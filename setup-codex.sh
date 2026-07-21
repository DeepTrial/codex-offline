#!/usr/bin/env bash
# =============================================================================
# Codex Offline Deployment Script for Linux / macOS / WSL
# =============================================================================
# Purpose: Set up Codex CLI from offline packages or auto-download.
#          No Node.js required — uses the standalone native binary.
#
# Usage:  bash setup-codex.sh [--offline-path PATH] [--auto-download] [--yes]
#
# Version: 1.0
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
# Config generators
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
# Codex configuration (generated by setup-codex.sh)
# Edit these values with your API credentials.

[api]
# Your OpenAI-compatible API base URL (proxy/gateway)
base_url = "YOUR_BASE_URL_HERE"
# Your API key
api_key = "YOUR_API_KEY_HERE"

# Optional: model overrides
# model = "your-model-name"

[telemetry]
enabled = false

[updates]
auto_check = false
CODEXTOML
        log_ok "Created config.toml with placeholder values"
    fi
}

generate_codex_env() {
    # Write environment variables that bypass login/onboarding
    local env_file="$USER_CODEX_DIR/env"
    cat > "$env_file" << 'ENVFILE'
# Codex environment overrides (bypass login, disable telemetry)
CODEX_SKIP_ONBOARDING=1
CODEX_TELEMETRY_DISABLED=1
DISABLE_TELEMETRY=1
ENVFILE
    log_ok "Created env config"
}

generate_codex_wrapper() {
    local native_bin="$1"
    local wrapper="$USER_CODEX_DIR/codex-wrapper.sh"
    cat > "$wrapper" << WRAPPER
#!/usr/bin/env bash
# Codex Wrapper — sets env vars and executes the native binary.
# Generated by setup-codex.sh

# Skip onboarding
export CODEX_SKIP_ONBOARDING=1

# Disable telemetry
export CODEX_TELEMETRY_DISABLED=1
export DISABLE_TELEMETRY=1

# Load API configuration from config.toml if available
if [ -f "\$HOME/.codex/config.toml" ]; then
    BASE_URL=\$(grep -E '^\s*base_url\s*=' "\$HOME/.codex/config.toml" 2>/dev/null | head -1 | sed 's/.*=\s*"\\(.*\\)".*/\\1/' | sed "s/.*=\s*'\\(.*\\)'.*/\\1/")
    API_KEY=\$(grep -E '^\s*api_key\s*=' "\$HOME/.codex/config.toml" 2>/dev/null | head -1 | sed 's/.*=\s*"\\(.*\\)".*/\\1/' | sed "s/.*=\s*'\\(.*\\)'.*/\\1/")
    [ -n "\$BASE_URL" ] && [ "\$BASE_URL" != "YOUR_BASE_URL_HERE" ] && export OPENAI_BASE_URL="\$BASE_URL"
    [ -n "\$API_KEY" ] && [ "\$API_KEY" != "YOUR_API_KEY_HERE" ] && export OPENAI_API_KEY="\$API_KEY"
fi

# Execute native binary directly (no PATH dependency)
exec ${native_bin} "\$@"
WRAPPER
    chmod +x "$wrapper"
    log_ok "Created codex-wrapper.sh"
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
# Main setup
# =============================================================================
setup_codex() {
    echo "============================================================================="
    echo "  Codex Offline Deployment Script v1.0"
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
        if ! is_valid_package_path "$OFFLINE_PACKAGES"; then
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
    generate_codex_env
    generate_codex_wrapper "$native_bin"

    # Add wrapper alias to bashrc
    local wrapper_path="$USER_CODEX_DIR/codex-wrapper.sh"
    if ! grep -q "codex-wrapper" "$BASHRC" 2>/dev/null; then
        cat >> "$BASHRC" << WRAPPER_ALIAS

# Codex wrapper — sets env vars for offline/third-party API mode
alias codex='bash $wrapper_path'
WRAPPER_ALIAS
        log_ok "Added codex wrapper alias to .bashrc"
    fi

    # Add PATH to bashrc
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
    echo "    - ~/.codex/config.toml (with placeholder values)"
    echo "    - PATH in .bashrc"
    echo ""
    echo "============================================================================="
    echo "  !!! ACTION REQUIRED !!!"
    echo "============================================================================="
    echo ""
    echo "  Edit ~/.codex/config.toml with your API credentials:"
    echo ""
    echo "    nano ~/.codex/config.toml"
    echo ""
    echo "  Replace the placeholder values:"
    echo "    base_url = \"YOUR_BASE_URL_HERE\"   -> your API endpoint"
    echo "    api_key  = \"YOUR_API_KEY_HERE\"    -> your API key"
    echo ""
    echo "  Or set environment variables directly:"
    echo "    export OPENAI_BASE_URL=\"https://your-api.example.com\""
    echo "    export OPENAI_API_KEY=\"sk-...\""
    echo ""
    echo "============================================================================="
    echo "  LOGIN/ONBOARDING BYPASS"
    echo "============================================================================="
    echo ""
    echo "  This script configured Codex to skip onboarding and disable telemetry."
    echo "  The wrapper script (~/.codex/codex-wrapper.sh) sets these automatically."
    echo ""
    echo "============================================================================="
    echo "  NEXT STEPS"
    echo "============================================================================="
    echo ""
    echo "  1. Edit ~/.codex/config.toml with your API key and base URL"
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

while [[ $# -gt 0 ]]; do
    case $1 in
        --offline-path)    OFFLINE_PATH="$2"; shift 2 ;;
        --auto-download)   AUTO_DOWNLOAD=true; shift ;;
        --yes|-y)          ASSUME_YES=true; shift ;;
        --non-interactive) NON_INTERACTIVE=true; shift ;;
        --uninstall)       DO_UNINSTALL=true; shift ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --offline-path PATH   Specify path to offline packages"
            echo "  --auto-download       Auto-download from GitHub Releases"
            echo "  --yes, -y             Assume yes for all prompts"
            echo "  --non-interactive      Never prompt, use defaults"
            echo "  --uninstall           Uninstall Codex"
            echo "  --help, -h            Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Auto-detect or interactive"
            echo "  $0 --offline-path ./pkg --yes         # Unattended offline install"
            echo "  $0 --auto-download                    # Auto-download from GitHub"
            echo "  $0 --uninstall                        # Remove Codex"
            exit 0
            ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# Handle uninstall before setup (after all args parsed, so --yes is honored)
if [ "$DO_UNINSTALL" = true ]; then
    uninstall_codex
    exit 0
fi

# Run
setup_codex
