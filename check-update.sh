#!/usr/bin/env bash
# =============================================================================
# Codex Version Checker and Update Script
# =============================================================================
# Checks for new Codex versions and optionally downloads from GitHub Releases.
# Usage: bash check-update.sh [--check-only] [--download] [--install]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_REPO="DeepTrial/codex-offline"
NPM_PACKAGE="@openai/codex"

# Source shared utilities
if [ -f "${SCRIPT_DIR}/skills/lib/common.sh" ]; then
    source "${SCRIPT_DIR}/skills/lib/common.sh"
else
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
    log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
    log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
    log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
fi

get_current_version() {
    if command -v codex >/dev/null 2>&1; then
        codex --version 2>/dev/null | head -1 | sed 's/codex version //i' || echo "unknown"
    else
        echo "not_installed"
    fi
}

get_npm_version() {
    local response
    if ! response=$(curl -s --max-time 15 "https://registry.npmjs.org/${NPM_PACKAGE}" 2>/dev/null); then
        log_warn "Network unreachable" >&2
        echo ""
        return 0
    fi
    echo "$response" | (command -v jq >/dev/null 2>&1 && jq -r '.["dist-tags"].latest // empty' || grep -o '"latest":"[^"]*"' | head -1 | cut -d'"' -f4)
}

get_github_version() {
    local response
    if ! response=$(curl -s --max-time 15 "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null); then
        log_warn "GitHub unreachable" >&2
        echo ""
        return 0
    fi
    echo "$response" | (command -v jq >/dev/null 2>&1 && jq -r '.tag_name // empty' | sed 's/^v//' || grep -o '"tag_name":"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/^v//')
}

download_latest() {
    local version="$1"
    local asset_name="codex-offline-packages-linux.tar.gz"
    local download_url="https://github.com/${GITHUB_REPO}/releases/download/v${version}/${asset_name}"
    local output_file="codex-offline-packages-v${version}.tar.gz"

    log_info "Downloading Codex v${version}..."
    if command -v wget >/dev/null 2>&1; then
        wget --progress=bar:force --timeout=60 -O "$output_file" "$download_url" && return 0
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL --progress-bar --max-time 300 -o "$output_file" "$download_url"
    fi
    [ -f "$output_file" ] && [ -s "$output_file" ] && { log_ok "Downloaded: $output_file"; echo "$output_file"; return 0; }
    log_error "Download failed"
    return 1
}

check_updates() {
    echo "============================================================================="
    echo "  Codex Version Checker"
    echo "============================================================================="
    echo ""

    local current_version npm_version github_version
    current_version=$(get_current_version)
    npm_version=$(get_npm_version)
    github_version=$(get_github_version)

    echo "Version Information:"
    echo "  Current:  ${current_version}"
    echo "  npm:      ${npm_version:-Unable to check}"
    echo "  GitHub:   ${github_version:-Unable to check}"
    echo ""

    if [ "$current_version" = "not_installed" ]; then
        log_warn "Codex not installed"
        if [ -n "$github_version" ]; then
            read -p "Download and install latest (v${github_version})? [Y/n]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                local f; f=$(download_latest "$github_version")
                [ -n "$f" ] && { tar -xzf "$f"; bash codex-offline-packages/setup-codex.sh; }
            fi
        fi
        return
    fi

    if [ -n "$npm_version" ] && [ "$npm_version" != "$current_version" ]; then
        log_warn "New version available: v${npm_version} (current: v${current_version})"
        echo ""
        echo "Options:"
        echo "  1) Download from GitHub Releases"
        echo "  2) Skip"
        echo ""
        read -p "Select [1-2]: " -r choice
        case $choice in
            1) local f; f=$(download_latest "$npm_version")
               if [ -n "$f" ]; then
                   read -p "Install now? [Y/n]: " -n 1 -r
                   echo
                   if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                       tar -xzf "$f"
                       bash codex-offline-packages/setup-codex.sh --offline-path codex-offline-packages
                   fi
               fi ;;
            *) log_info "Skipped" ;;
        esac
    else
        log_ok "You have the latest version (v${current_version})"
    fi
}

# Parse args
CHECK_ONLY=false; AUTO_DOWNLOAD=false; AUTO_INSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --check-only) CHECK_ONLY=true; shift ;;
        --download)   AUTO_DOWNLOAD=true; shift ;;
        --install)    AUTO_DOWNLOAD=true; AUTO_INSTALL=true; shift ;;
        --help|-h)
            echo "Usage: $0 [--check-only|--download|--install]"
            echo "  --check-only  Only check for updates"
            echo "  --download    Download if update available"
            echo "  --install     Download and install if update available"
            exit 0 ;;
        *) log_error "Unknown: $1"; exit 1 ;;
    esac
done

check_updates
