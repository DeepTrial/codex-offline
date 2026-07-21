#!/usr/bin/env bash
# =============================================================================
# Common utility functions shared across all codex-offline scripts.
# =============================================================================

set -euo pipefail

# --- Logging ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# --- Command checks ---
command_exists() { command -v "$1" >/dev/null 2>&1; }

# --- URL reachability ---
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

# --- Mirror download ---
download_with_mirrors() {
    local output_file="$1"; shift; local mirrors=("$@"); local success=false
    for mirror in "${mirrors[@]}"; do
        log_info "Trying mirror: $mirror"
        if command_exists curl; then
            curl -fsSL --max-time 10 --retry 2 -o "$output_file" "$mirror" 2>/dev/null && { success=true; log_ok "Downloaded from: $mirror"; break; }
        elif command_exists wget; then
            wget --timeout=10 --tries=2 -q -O "$output_file" "$mirror" 2>/dev/null && { success=true; log_ok "Downloaded from: $mirror"; break; }
        fi
        log_warn "Failed to download from: $mirror"
    done
    [ "$success" = true ]
}

# --- jq initializer (system -> bundled -> package manager) ---
init_jq() {
    if command -v jq &>/dev/null; then
        JQ_CMD="jq"
        return 0
    fi
    local os arch rel=""
    os="$(uname -s)"
    arch="$(uname -m)"
    case "$os" in
        Linux*)
            case "$arch" in
                x86_64|amd64)   rel="linux-amd64/jq" ;;
                aarch64|arm64)  rel="linux-arm64/jq" ;;
                armv7l|armhf)   rel="linux-armhf/jq" ;;
            esac ;;
        Darwin*)
            case "$arch" in
                x86_64|amd64)   rel="macos-amd64/jq" ;;
                arm64)          rel="macos-arm64/jq" ;;
            esac ;;
        CYGWIN*|MINGW*|MSYS*)
            rel="windows-amd64/jq.exe" ;;
    esac
    if [ -n "$rel" ] && [ -x "${SCRIPT_DIR}/bin/${rel}" ]; then
        JQ_CMD="${SCRIPT_DIR}/bin/${rel}"
        return 0
    fi
    return 1
}

# --- Platform triple for codex native binary ---
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
                     aarch64|arm64)  echo "aarch64-pc-windows-msvc" ;;
                 esac ;;
    esac
}

# --- File size (portable GNU/BSD) ---
file_size() {
    stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo 0
}
