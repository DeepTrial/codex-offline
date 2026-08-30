#!/usr/bin/env bash
# =============================================================================
# Codex Offline Deployment Script for Linux / macOS / WSL
# =============================================================================
# Purpose: Set up Codex CLI from offline packages or auto-download.
#          No Node.js required — uses the standalone native binary.
#
# Usage:  bash setup-codex.sh [OPTIONS]
#
# Version: 2.0
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd)"

# Source shared utilities
if [ -f "${SCRIPT_DIR}/skills/lib/common.sh" ]; then
    source "${SCRIPT_DIR}/skills/lib/common.sh"
fi

# Fallback logging
if ! type log_info >/dev/null 2>&1; then
    log_info()  { echo "[INFO] $1"; }
    log_ok()    { echo "  [OK] $1"; }
    log_warn()  { echo "  [WARN] $1"; }
    log_error() { echo "  [ERROR] $1" >&2; }
fi
if ! type command_exists >/dev/null 2>&1; then
    command_exists() { command -v "$1" >/dev/null 2>&1; }
fi
if ! type test_url_accessible >/dev/null 2>&1; then
    test_url_accessible() {
        local url="$1" timeout="${2:-10}"
        if command_exists curl; then
            curl -fsSL --max-time "$timeout" --retry 2 -I "$url" >/dev/null 2>&1
        elif command_exists wget; then
            wget --timeout="$timeout" --tries=2 -q --spider "$url" 2>/dev/null
        else
            return 1
        fi
    }
fi
if ! type file_size >/dev/null 2>&1; then
    file_size() {
        stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo 0
    }
fi

# --- Paths ---
USER_CODEX_DIR="$HOME/.codex"
CODEX_TOML="$HOME/.codex/config.toml"
BASHRC="$HOME/.bashrc"

# --- GitHub Release Config ---
GITHUB_REPO="DeepTrial/codex-offline"
GITHUB_API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"

# --- Offline package default path ---
DEFAULT_OFFLINE_PATH="${SCRIPT_DIR}/codex-offline-packages"

# --- Shell config markers ---
SETUP_START="# >>> CODEX_SETUP >>>"
SETUP_END="# <<< CODEX_SETUP <<<"

# --- Network ---
NETWORK_TIMEOUT=10

# --- Flags ---
ASSUME_YES=false
NON_INTERACTIVE=false
NETWORK_AVAILABLE="unknown"

# --- Mirror sources ---
NPM_MIRRORS=(
    "https://registry.npmjs.org/"
    "https://registry.npmmirror.com"
)
GITHUB_MIRRORS=(
    "https://api.github.com"
    "https://hub.gitmirror.com/https://api.github.com"
    "https://ghproxy.com/https://api.github.com"
)

# =============================================================================
# Platform triple detection for codex native binaries
# =============================================================================
detect_codex_triple() {
    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"
    case "$os" in
        Linux*)  case "$arch" in
                     x86_64|amd64)   echo "x86_64-unknown-linux-musl" ;;
                     aarch64|arm64)  echo "aarch64-unknown-linux-musl" ;;
                 esac ;;
        Darwin*) case "$arch" in
                     x86_64|amd64)   echo "x86_64-apple-darwin" ;;
                     arm64)          echo "aarch64-apple-darwin" ;;
                 esac ;;
        CYGWIN*|MINGW*|MSYS*)
                 case "$arch" in
                     x86_64|amd64)   echo "x86_64-pc-windows-msvc" ;;
                     arm64|aarch64)  echo "aarch64-pc-windows-msvc" ;;
                 esac ;;
    esac
}

# Find native codex binary inside the package
find_codex_native_binary() {
    local pkg_dir="$1"
    local triple bin_name="codex"
    triple=$(detect_codex_triple)
    [ -z "$triple" ] && return 1

    case "$(uname -s)" in
        CYGWIN*|MINGW*|MSYS*) bin_name="codex.exe" ;;
    esac

    local candidate="${pkg_dir}/node_modules/@openai/codex/vendor/${triple}/bin/${bin_name}"
    if [ -f "$candidate" ]; then
        echo "$candidate"
        return 0
    fi
    return 1
}

# Check if native binary is real ( > 10MB, not stub)
is_real_native_binary() {
    local bin="$1"
    local size
    size=$(file_size "$bin")
    [ "$size" -gt 10485760 ]  # > 10MB
}

# =============================================================================
# Network helpers
# =============================================================================
check_network_status() {
    local npm_ok=false gh_ok=false
    log_info "Checking network connectivity (5s timeout per probe)..."
    test_url_accessible "${NPM_MIRRORS[0]}" 5 && npm_ok=true && log_ok "npm registry reachable" || log_warn "npm registry UNREACHABLE"
    test_url_accessible "${GITHUB_MIRRORS[0]}" 5 && gh_ok=true && log_ok "GitHub reachable" || log_warn "GitHub UNREACHABLE"
    if [ "$npm_ok" = true ] || [ "$gh_ok" = true ]; then
        NETWORK_AVAILABLE=true; log_ok "Network available"
    else
        NETWORK_AVAILABLE=false; log_warn "Network appears UNAVAILABLE"
    fi
    return 0
}

require_network_or_fail() {
    local what="$1"
    if [ "$NETWORK_AVAILABLE" = "unknown" ]; then check_network_status; fi
    if [ "$NETWORK_AVAILABLE" != true ]; then
        log_error "Cannot $what: network is unreachable."
        echo ""
        echo "Troubleshooting:"
        echo "  - Check internet / proxy / firewall"
        echo "  - Behind proxy? export HTTPS_PROXY=http://proxy:port"
        echo "  - Fully offline? bash $0 --offline-path /path/to/codex-offline-packages"
        return 1
    fi
    return 0
}

# =============================================================================
# Confirmation helper
# =============================================================================
confirm() {
    local prompt="$1" default="${2:-n}" answer yn_hint
    if [ "$default" = y ]; then yn_hint="[Y/n]"; else yn_hint="[y/N]"; fi
    if [ "$ASSUME_YES" = true ] || [ "$NON_INTERACTIVE" = true ] || [ ! -t 0 ]; then
        echo "$prompt $yn_hint: $default (auto)"
        [ "$default" = y ] && return 0 || return 1
    fi
    read -p "$prompt $yn_hint: " -n 1 -r answer || answer=""
    echo
    [ -z "$answer" ] && answer="$default"
    [[ "$answer" =~ ^[Yy]$ ]]
}

# Uninstall always requires explicit confirmation; --yes overrides for automation
confirm_uninstall() {
    if [ "$ASSUME_YES" = true ]; then
        echo "Are you sure you want to uninstall Codex? [y/N]: y (auto, --yes)"
        return 0
    fi
    confirm "Are you sure you want to uninstall Codex?" n
}

# =============================================================================
# Config generators (official Codex CLI format)
# =============================================================================
generate_config_toml() {
    local config_file="$CODEX_TOML"
    if [ -f "$config_file" ]; then
        local backup_name="config.toml.backup.$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$USER_CODEX_DIR/backups"
        cp "$config_file" "$USER_CODEX_DIR/backups/$backup_name"
        log_warn "config.toml already exists. Backed up to backups/$backup_name"
    else
        cat > "$config_file" << 'CODEXTOML'
#:schema https://developers.openai.com/codex/config-schema.json
# Codex configuration (generated by setup-codex.sh)
# Official Codex CLI config format — edit with your API credentials.

# Default model (change to your provider's model ID)
model = "gpt-5"

# Provider ID — must match a [model_providers.XXX] table name below
model_provider = "custom"

# Approval policy: never / on-request / suggest
approval_policy = "on-request"

# Sandbox mode for file operations
sandbox_mode = "workspace-write"

# Store credentials in file (required for auth.json to work)
cli_auth_credentials_store = "file"

[model_providers.custom]
name = "Custom API Provider"
# Your OpenAI-compatible API base URL (proxy / gateway / third-party)
base_url = "YOUR_BASE_URL_HERE"
# Protocol: "responses" for OpenAI Responses API, "chat_completions" for Chat Completions API
wire_api = "responses"

# --- API Key configuration (choose ONE method) ---

# Method A (RECOMMENDED): Read API key from environment variable.
# Set the environment variable before running codex, e.g.:
#   export OPENAI_API_KEY="sk-..."
requires_openai_auth = false
env_key = "OPENAI_API_KEY"

# Method B: Use auth.json for key storage (see ~/.codex/auth.json).
# Uncomment the line below and comment out the two lines above:
# requires_openai_auth = true

# Method C (NOT RECOMMENDED): Hard-code key in this file.
# Only for fully automated / air-gapped deployments:
# experimental_bearer_token = "YOUR_API_KEY_HERE"
CODEXTOML
        log_ok "Created config.toml with placeholder values (official Codex CLI format)"
    fi
}

generate_auth_json() {
    # Generate auth.json for Method B key storage (optional fallback)
    local auth_file="$USER_CODEX_DIR/auth.json"
    if [ -f "$auth_file" ]; then
        local backup_name="auth.json.backup.$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$USER_CODEX_DIR/backups"
        cp "$auth_file" "$USER_CODEX_DIR/backups/$backup_name"
        log_warn "auth.json already exists. Backed up to backups/$backup_name"
    else
        cat > "$auth_file" << 'AUTHJSON'
{
  "OPENAI_API_KEY": "YOUR_API_KEY_HERE"
}
AUTHJSON
        chmod 600 "$auth_file"
        log_ok "Created auth.json with placeholder key (Method B: file-based auth)"
        log_info "To use Method B, edit auth.json with your key and set requires_openai_auth=true in config.toml"
    fi
}

generate_codex_env() {
    # Write environment variables that bypass login/onboarding
    local env_file="$USER_CODEX_DIR/env"
    cat > "$env_file" << 'ENVFILE'
# Codex environment overrides (disable telemetry)
CODEX_TELEMETRY_DISABLED=1
DISABLE_TELEMETRY=1
ENVFILE
    log_ok "Created env config"
}

# =============================================================================
# Package validation & launcher
# =============================================================================
is_valid_package_path() {
    local path="$1"
    # Check for native binary in vendor dir
    local triple native_bin
    triple=$(detect_codex_triple)
    [ -z "$triple" ] && return 1
    native_bin="${path}/node_modules/@openai/codex/vendor/${triple}/bin/codex"
    if [ "$(uname -s | cut -c1-6)" = "CYGWIN" ] || [ "$(uname -s | cut -c1-5)" = "MINGW" ] || [ "$(uname -s | cut -c1-4)" = "MSYS" ]; then
        native_bin="${native_bin}.exe"
    fi
    [ -f "$native_bin" ] && return 0

    # Also check for package.json format
    [ -f "$path/package.json" ] && ls "$path"/*.tgz >/dev/null 2>&1 && return 0

    return 1
}

rebuild_codex_launcher() {
    # Create a real shell script that calls the native codex binary directly.
    # No symlinks — survives extraction with Windows tools.
    local pkg_dir="$1"
    local bin_dir="$pkg_dir/node_modules/.bin"
    local launcher="$bin_dir/codex"
    local native_bin
    native_bin=$(find_codex_native_binary "$pkg_dir")

    mkdir -p "$bin_dir"
    rm -f "$launcher" 2>/dev/null || true

    if [ -n "$native_bin" ] && [ -f "$native_bin" ]; then
        # Native binary exists — create shell exec wrapper (NO Node.js needed!)
        cat > "$launcher" << LAUNCHER
#!/usr/bin/env bash
# Codex launcher — execs native binary directly. No Node.js required.
NATIVE_BIN="$native_bin"
exec "\$NATIVE_BIN" "\$@"
LAUNCHER
        chmod +x "$launcher"
        log_ok "Rebuilt codex launcher (execs native binary, no Node.js)"
        return 0
    fi

    log_error "Could not create codex launcher: no native binary found"
    return 1
}

# =============================================================================
# Package location
# =============================================================================
find_offline_packages() {
    local paths=(
        "${SCRIPT_DIR}/codex-offline-packages"
        "${SCRIPT_DIR}/../codex-offline-packages"
        "$HOME/codex-offline-packages"
        "/opt/codex-offline-packages"
    )
    for path in "${paths[@]}"; do
        if is_valid_package_path "$path"; then
            echo "$path"
            return 0
        fi
    done
    return 1
}

# =============================================================================
# Download
# =============================================================================
download_offline_packages() {
    local download_dir="$1"
    mkdir -p "$download_dir"

    require_network_or_fail "download offline packages" || return 1

    log_info "Fetching latest release info..."
    local release_info download_url
    release_info=$(curl -fsSL --max-time "$NETWORK_TIMEOUT" "$GITHUB_API_URL" 2>/dev/null) || {
        log_error "Failed to fetch release info"
        return 1
    }

    download_url=$(echo "$release_info" | grep "browser_download_url.*codex-offline-packages-linux.tar.gz" | head -1 | cut -d '"' -f 4)
    if [ -z "$download_url" ]; then
        download_url=$(echo "$release_info" | grep "browser_download_url.*codex-offline-packages.tar.gz" | head -1 | cut -d '"' -f 4)
    fi

    if [ -z "$download_url" ]; then
        log_error "Could not find offline packages in latest release"
        log_info "Falling back to direct npm download..."
        return 1
    fi

    log_info "Downloading: $download_url"
    local temp_file="$download_dir/codex-offline-packages.tar.gz"
    if command_exists wget; then
        wget -q --show-progress --timeout=300 -O "$temp_file" "$download_url"
    else
        curl -fsSL --progress-bar --max-time 300 -o "$temp_file" "$download_url"
    fi

    [ ! -f "$temp_file" ] || [ ! -s "$temp_file" ] && { log_error "Download failed"; return 1; }

    log_info "Extracting..."
    tar -xzf "$temp_file" -C "$download_dir" --strip-components=1
    rm -f "$temp_file"
    log_ok "Offline packages downloaded and extracted"
    return 0
}

# =============================================================================
# Existing installation detection
# =============================================================================
detect_existing_installation() {
    local found=false
    local install_paths=""

    if type codex >/dev/null 2>&1; then
        found=true
        install_paths="  - codex binary: $(type -P codex 2>/dev/null || echo 'in PATH')"
    fi
    if [ -d "$USER_CODEX_DIR" ]; then
        found=true
        install_paths="$install_paths
  - Config directory: $USER_CODEX_DIR"
    fi
    if [ -f "$CODEX_TOML" ]; then
        found=true
        install_paths="$install_paths
  - Config file: $CODEX_TOML"
    fi
    if [ -f "$BASHRC" ] && grep -q "$SETUP_START" "$BASHRC" 2>/dev/null; then
        found=true
        install_paths="$install_paths
  - Shell config: $BASHRC"
    fi

    if [ "$found" = true ]; then
        echo "$install_paths"
        return 0
    fi
    return 1
}

# =============================================================================
# Uninstall
# =============================================================================
uninstall_codex() {
    echo "============================================================================="
    echo "  Codex Uninstaller"
    echo "============================================================================="
    echo ""

    local existing
    existing=$(detect_existing_installation 2>/dev/null || true)

    if [ -z "$existing" ]; then
        log_warn "No existing Codex installation detected."
        return 0
    fi

    echo "Detected existing installation:"
    echo "$existing"
    echo ""

    if ! confirm_uninstall; then
        log_info "Uninstall cancelled."
        return 0
    fi

    # Backup
    if [ -d "$USER_CODEX_DIR" ]; then
        if confirm "Create backup of ~/.codex before removal?" y; then
            local backup_dir="$HOME/.codex-backup-$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$backup_dir"
            cp -r "$USER_CODEX_DIR" "$backup_dir/"
            log_ok "Backed up to: $backup_dir"
        fi
        rm -rf "$USER_CODEX_DIR"
        log_ok "Removed ~/.codex directory"
    fi

    # Clean bashrc
    if [ -f "$BASHRC" ]; then
        if grep -q "$SETUP_START" "$BASHRC" 2>/dev/null; then
            sed -i "/$SETUP_START/,/$SETUP_END/d" "$BASHRC"
            log_ok "Removed shell config from .bashrc"
        fi
        if grep -q "codex-wrapper" "$BASHRC" 2>/dev/null; then
            sed -i '/# Codex wrapper/d' "$BASHRC"
            sed -i "/alias codex='bash/d" "$BASHRC" 2>/dev/null || true
        fi
    fi

    echo ""
    echo "============================================================================="
    echo "  Uninstall Complete"
    echo "============================================================================="
    echo ""
    echo "Restart your terminal to fully clear the environment."
}

# =============================================================================
# Config-only mode
# =============================================================================
config_only() {
    echo "============================================================================="
    echo "  Codex Configuration Only Mode"
    echo "============================================================================="
    echo ""
    echo "Generating / updating config files without installing binary or modifying PATH."
    echo ""

    mkdir -p "$USER_CODEX_DIR"
    mkdir -p "$USER_CODEX_DIR/tmp"
    mkdir -p "$USER_CODEX_DIR/backups"

    generate_config_toml
    generate_auth_json
    generate_codex_env

    echo ""
    echo "============================================================================="
    echo "  CONFIGURATION COMPLETE"
    echo "============================================================================="
    echo ""
    echo "  Generated / updated:"
    echo "    - ~/.codex/config.toml  (official Codex CLI format)"
    echo "    - ~/.codex/auth.json    (Method B: file-based API key)"
    echo "    - ~/.codex/env          (telemetry disable)"
    echo ""
    echo "  !!! ACTION REQUIRED !!!"
    echo ""
    echo "  Edit ~/.codex/config.toml with your API endpoint:"
    echo "    nano ~/.codex/config.toml"
    echo ""
    echo "  Three ways to provide your API key:"
    echo ""
    echo "  Method A (Recommended) — Environment variable:"
    echo "    export OPENAI_API_KEY=\"sk-...\""
    echo ""
    echo "  Method B — File-based (auth.json):"
    echo "    Edit ~/.codex/auth.json with your key, then set requires_openai_auth=true in config.toml"
    echo ""
    echo "  Method C — Inline (not recommended for shared systems):"
    echo "    Set experimental_bearer_token in config.toml"
    echo ""
}

# =============================================================================
# Skills-only mode
# =============================================================================
skills_only() {
    echo "============================================================================="
    echo "  Codex Skills Only Mode"
    echo "============================================================================="
    echo ""

    local pkg_dir="${OFFLINE_PATH:-${SCRIPT_DIR}/codex-offline-packages}"
    if ! is_valid_package_path "$pkg_dir"; then
        pkg_dir=$(find_offline_packages || true)
    fi
    if [ -z "$pkg_dir" ] || [ ! -d "$pkg_dir/skills" ]; then
        log_error "Could not find offline skills package"
        echo "Run with --offline-path to specify the package directory"
        exit 1
    fi

    local skills_dir="$pkg_dir/skills"
    if [ -f "$skills_dir/install-skills.sh" ]; then
        if command -v jq >/dev/null 2>&1; then
            bash "$skills_dir/install-skills.sh" "$skills_dir/offline-skills" && \
                log_ok "Skills installed" || log_warn "Skills installation may have issues"
        else
            log_warn "jq not available, skipping skills install"
            log_info "Install jq first, then run: bash $skills_dir/install-skills.sh $skills_dir/offline-skills"
        fi
    else
        log_error "Skills installer not found at $skills_dir/install-skills.sh"
        exit 1
    fi
}

# =============================================================================
# Main setup
# =============================================================================
setup_codex() {
    echo "============================================================================="
    echo "  Codex Offline Deployment Script v2.0"
    echo "============================================================================="
    echo ""
    echo "Sets up Codex CLI from offline packages with third-party API support."
    echo "No Node.js required — uses standalone native binary."
    echo ""

    # Check existing installation
    set +e
    local existing; existing=$(detect_existing_installation 2>&1); local detect_exit=$?
    set -e
    if [ -n "$existing" ] && [ "$detect_exit" -eq 0 ]; then
        echo ""
        log_warn "Detected existing Codex installation:"
        echo "$existing"
        echo ""
        echo "Options:"
        echo "  1) Reinstall / Update"
        echo "  2) Uninstall"
        echo "  3) Continue anyway"
        echo "  4) Exit"
        echo ""
        if [ "$ASSUME_YES" = true ] || [ "$NON_INTERACTIVE" = true ] || [ ! -t 0 ]; then
            choice="1"
            echo "Select option [1-4]: 1 (auto)"
        else
            read -p "Select option [1-4]: " -r choice
        fi

        case $choice in
            1) log_info "Proceeding with reinstall..." ;;
            2) uninstall_codex; exit 0 ;;
            3) log_warn "Continuing with existing installation..." ;;
            4|*) log_info "Exiting."; exit 0 ;;
        esac
        echo ""
    fi

    # Step 1: Locate packages
    echo "Step 1/5: Locating Codex packages..."
    if [ -n "$OFFLINE_PATH" ]; then
        OFFLINE_PACKAGES="$OFFLINE_PATH"
        if ! is_valid_package_path "$OFFLINE_PACKAGES"; then
            log_error "No valid Codex packages at: $OFFLINE_PACKAGES"
            exit 1
        fi
        log_ok "Using specified offline packages: $OFFLINE_PACKAGES"
    elif [ "$AUTO_DOWNLOAD" = true ]; then
        OFFLINE_PACKAGES="$USER_CODEX_DIR/offline-packages"
        if [ "$FORCE_DOWNLOAD" = true ] || ! is_valid_package_path "$OFFLINE_PACKAGES"; then
            rm -rf "$OFFLINE_PACKAGES"
            download_offline_packages "$OFFLINE_PACKAGES" || {
                log_error "Failed to download offline packages"
                exit 1
            }
        else
            log_ok "Using existing downloaded packages"
        fi
    else
        OFFLINE_PACKAGES=$(find_offline_packages || true)
        if [ -z "$OFFLINE_PACKAGES" ]; then
            log_warn "Offline packages not found in default locations"
            if [ "$ASSUME_YES" = true ] || [ "$NON_INTERACTIVE" = true ] || [ ! -t 0 ]; then
                log_error "No packages found, interactive disabled."
                echo "Run: bash $0 --auto-download --yes"
                exit 1
            fi
            echo ""
            echo "Options:"
            echo "  1) Download from GitHub Release automatically"
            echo "  2) Specify offline package path"
            echo "  3) Exit"
            echo ""
            read -p "Select option [1-3]: " -r choice
            case $choice in
                1) OFFLINE_PACKAGES="$USER_CODEX_DIR/offline-packages"
                   download_offline_packages "$OFFLINE_PACKAGES" || { log_error "Download failed"; exit 1; } ;;
                2) read -p "Enter path: " -r OFFLINE_PACKAGES
                   is_valid_package_path "$OFFLINE_PACKAGES" || { log_error "Invalid path"; exit 1; } ;;
                3|*) log_info "Exiting."; exit 0 ;;
            esac
        else
            log_ok "Found offline packages at: $OFFLINE_PACKAGES"
        fi
    fi

    OFFLINE_PACKAGES="$(cd "$OFFLINE_PACKAGES" && pwd)"
    echo ""

    # Step 2: Verify native binary & build launcher
    echo "Step 2/5: Verifying native binary..."
    local native_bin
    native_bin=$(find_codex_native_binary "$OFFLINE_PACKAGES" || true)
    if [ -z "$native_bin" ] || [ ! -f "$native_bin" ]; then
        log_error "Native codex binary not found in package"
        log_info "Tried: ${OFFLINE_PACKAGES}/node_modules/@openai/codex/vendor/.../bin/codex"
        exit 1
    fi

    if ! is_real_native_binary "$native_bin"; then
        local sz; sz=$(file_size "$native_bin")
        log_error "Native binary appears to be a stub ($sz bytes)"
        exit 1
    fi
    log_ok "Native binary found ($(file_size "$native_bin") bytes)"

    rebuild_codex_launcher "$OFFLINE_PACKAGES" || exit 1

    # Test native binary
    if timeout 30 "$native_bin" --version >/dev/null 2>&1; then
        local ver; ver=$("$native_bin" --version 2>&1 | head -1 || echo "ok")
        log_ok "Native binary runs: $ver"
    else
        log_warn "Native binary did not return version cleanly (may still work)"
    fi

    # Set codex bin path
    CODEX_BIN="$OFFLINE_PACKAGES/node_modules/.bin/codex"
    export PATH="$OFFLINE_PACKAGES/node_modules/.bin:$PATH"
    echo ""

    # Step 3: Directory structure
    echo "Step 3/5: Creating ~/.codex/ directory structure..."
    mkdir -p "$USER_CODEX_DIR"
    mkdir -p "$USER_CODEX_DIR/tmp"
    mkdir -p "$USER_CODEX_DIR/backups"
    log_ok "Directories created"
    echo ""

    # Step 4: Config
    echo "Step 4/5: Generating configuration files..."
    generate_config_toml
    generate_auth_json
    generate_codex_env

    # Add PATH to bashrc (no wrapper alias — use direct PATH)
    if grep -q "$SETUP_START" "$BASHRC" 2>/dev/null; then
        sed -i "/$SETUP_START/,/$SETUP_END/d" "$BASHRC"
    fi
    cat >> "$BASHRC" << PATHBLOCK

# >>> CODEX_SETUP >>>
export PATH="${OFFLINE_PACKAGES}/node_modules/.bin:\$PATH"
# <<< CODEX_SETUP <<<
PATHBLOCK
    log_ok "PATH added to .bashrc"
    echo ""

    # Step 5: Verify + skills
    echo "Step 5/5: Verifying setup..."

    if command -v codex >/dev/null 2>&1; then
        log_ok "codex command available in PATH"
    else
        log_warn "codex not yet in PATH. Open a new terminal and try again."
    fi

    # Skills installation
    local skills_dir="${OFFLINE_PACKAGES}/skills"
    if [ -d "$skills_dir" ] && [ -f "$skills_dir/install-skills.sh" ]; then
        echo ""
        log_info "Found offline skills package"
        if confirm "Install offline skills?" y; then
            if command -v jq >/dev/null 2>&1; then
                bash "$skills_dir/install-skills.sh" "$skills_dir/offline-skills" && \
                    log_ok "Skills installed" || log_warn "Skills installation may have issues"
            else
                log_warn "jq not available, skipping skills install"
                log_info "Install jq first, then run: bash $skills_dir/install-skills.sh $skills_dir/offline-skills"
            fi
        else
            log_info "Skills skipped. Install later: bash $skills_dir/install-skills.sh $skills_dir/offline-skills"
        fi
    fi

    echo ""
    echo "============================================================================="
    echo "  SETUP COMPLETE"
    echo "============================================================================="
    echo ""
    echo "  Configured:"
    echo "    - Native codex binary (standalone, NO Node.js required)"
    echo "    - Offline packages at: $OFFLINE_PACKAGES"
    echo "    - ~/.codex/ directory structure"
    echo "    - ~/.codex/config.toml (official Codex CLI format)"
    echo "    - ~/.codex/auth.json (Method B key storage)"
    echo "    - PATH in .bashrc"
    echo ""
    echo "============================================================================="
    echo "  !!! ACTION REQUIRED !!!"
    echo "============================================================================="
    echo ""
    echo "  Edit ~/.codex/config.toml with your API endpoint:"
    echo ""
    echo "    nano ~/.codex/config.toml"
    echo ""
    echo "  Replace YOUR_BASE_URL_HERE with your provider's base URL, e.g.:"
    echo "    base_url = \"https://api.example.com/v1\""
    echo ""
    echo "  Then provide your API key using ONE of these methods:"
    echo ""
    echo "  Method A (Recommended) — Environment variable:"
    echo "    export OPENAI_API_KEY=\"sk-...\""
    echo ""
    echo "  Method B — File-based (auth.json):"
    echo "    Edit ~/.codex/auth.json with your key, then set requires_openai_auth=true in config.toml"
    echo ""
    echo "  Method C — Inline (not recommended for shared systems):"
    echo "    Set experimental_bearer_token in config.toml"
    echo ""
    echo "============================================================================="
    echo "  TELEMETRY"
    echo "============================================================================="
    echo ""
    echo "  Telemetry is disabled by default. The env file (~/.codex/env) sets:"
    echo "    CODEX_TELEMETRY_DISABLED=1"
    echo ""
    echo "============================================================================="
    echo "  NEXT STEPS"
    echo "============================================================================="
    echo ""
    echo "  1. Edit ~/.codex/config.toml with your API endpoint and key"
    echo "  2. Open a new terminal (or run: source ~/.bashrc)"
    echo "  3. Verify: codex --version"
    echo ""
}

# =============================================================================
# Parse args
# =============================================================================
OFFLINE_PATH=""
AUTO_DOWNLOAD=false
DO_UNINSTALL=false
CONFIG_ONLY=false
SKILLS_ONLY=false
FORCE_DOWNLOAD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --offline-path)    OFFLINE_PATH="$2"; shift 2 ;;
        --auto-download)   AUTO_DOWNLOAD=true; shift ;;
        --force-download)  FORCE_DOWNLOAD=true; shift ;;
        --yes|-y)          ASSUME_YES=true; shift ;;
        --non-interactive) NON_INTERACTIVE=true; shift ;;
        --config-only)     CONFIG_ONLY=true; shift ;;
        --skills-only)     SKILLS_ONLY=true; shift ;;
        --uninstall)       DO_UNINSTALL=true; shift ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --offline-path PATH   Specify path to offline packages"
            echo "  --auto-download       Auto-download from GitHub Releases"
            echo "  --force-download      Force re-download even if package exists"
            echo "  --yes, -y             Assume yes for all prompts"
            echo "  --non-interactive     Never prompt, use defaults"
            echo "  --config-only         Only (re)generate config files; skip binary/PATH"
            echo "  --skills-only         Only install offline skills"
            echo "  --uninstall           Uninstall Codex"
            echo "  --help, -h            Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Auto-detect or interactive"
            echo "  $0 --offline-path ./pkg --yes         # Unattended offline install"
            echo "  $0 --auto-download                    # Auto-download from GitHub"
            echo "  $0 --config-only                      # Regenerate config files only"
            echo "  $0 --skills-only                      # Install skills only"
            echo "  $0 --uninstall                        # Remove Codex"
            exit 0
            ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# Handle mode switches before main setup
if [ "$DO_UNINSTALL" = true ]; then
    uninstall_codex
    exit 0
fi

if [ "$CONFIG_ONLY" = true ]; then
    config_only
    exit 0
fi

if [ "$SKILLS_ONLY" = true ]; then
    skills_only
    exit 0
fi

# Run main setup
setup_codex
