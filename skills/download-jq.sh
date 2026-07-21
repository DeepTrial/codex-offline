#!/usr/bin/env bash
# =============================================================================
# jq Downloader for Offline Deployment
# =============================================================================
# Downloads jq 1.7.1 binaries for all supported platforms.
# Usage: bash download-jq.sh [--all] [output_dir]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || {
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
    log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
    log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
    log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
}

DOWNLOAD_ALL=false
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --all) DOWNLOAD_ALL=true; shift ;;
        *)     OUTPUT_DIR="${1:-}"; shift ;;
    esac
done

OUTPUT_DIR="${OUTPUT_DIR:-${SCRIPT_DIR}/bin}"
JQ_VERSION="1.7.1"
JQ_BASE="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}"

# Platform -> (asset_name, output_subpath)
declare -A JQ_ASSETS=(
    ["linux-amd64"]="jq-linux-amd64"
    ["linux-arm64"]="jq-linux-arm64"
    ["linux-armhf"]="jq-linux-armhf"
    ["macos-amd64"]="jq-macos-amd64"
    ["macos-arm64"]="jq-macos-arm64"
    ["windows-amd64"]="jq-windows-amd64.exe"
)

download_jq_platform() {
    local platform="$1"
    local asset="${JQ_ASSETS[$platform]:-}"
    if [ -z "$asset" ]; then
        log_warn "Unknown platform: $platform"
        return 1
    fi

    local dest_dir="${OUTPUT_DIR}/${platform}"
    local dest_file
    if [[ "$platform" == windows-* ]]; then
        dest_file="jq.exe"
    else
        dest_file="jq"
    fi

    mkdir -p "$dest_dir"
    local dest_path="${dest_dir}/${dest_file}"

    if [ -f "$dest_path" ] && [ -s "$dest_path" ]; then
        log_ok "jq for ${platform} already exists"
        return 0
    fi

    local url="${JQ_BASE}/${asset}"
    log_info "Downloading jq for ${platform}..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 60 -o "$dest_path" "$url" || { log_error "Failed: $url"; return 1; }
    elif command -v wget >/dev/null 2>&1; then
        wget --timeout=60 -q -O "$dest_path" "$url" || { log_error "Failed: $url"; return 1; }
    else
        log_error "curl or wget required"
        return 1
    fi
    chmod +x "$dest_path"
    local fsize
    fsize=$(file_size "$dest_path")
    log_ok "Downloaded jq for ${platform} (${fsize} bytes)"
}

# Detect current platform for default single-platform download
detect_current_platform() {
    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"
    case "$os" in
        Linux*)
            case "$arch" in
                x86_64|amd64)   echo "linux-amd64" ;;
                aarch64|arm64)  echo "linux-arm64" ;;
                armv7l|armhf)   echo "linux-armhf" ;;
            esac ;;
        Darwin*)
            case "$arch" in
                x86_64|amd64)   echo "macos-amd64" ;;
                arm64)          echo "macos-arm64" ;;
            esac ;;
        CYGWIN*|MINGW*|MSYS*)
            echo "windows-amd64" ;;
    esac
}

mkdir -p "$OUTPUT_DIR"

if [ "$DOWNLOAD_ALL" = true ]; then
    log_info "Downloading jq ${JQ_VERSION} for all platforms..."
    for platform in "${!JQ_ASSETS[@]}"; do
        download_jq_platform "$platform" || log_warn "Failed to download jq for $platform"
    done
else
    local current
    current=$(detect_current_platform)
    if [ -n "$current" ]; then
        log_info "Downloading jq ${JQ_VERSION} for current platform: $current"
        download_jq_platform "$current"
    else
        log_error "Could not detect current platform"
        exit 1
    fi
fi

log_ok "jq download complete"
