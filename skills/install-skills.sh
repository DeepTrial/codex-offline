#!/usr/bin/env bash
# =============================================================================
# Codex Skills/Plugins Installer for Offline Deployment
# =============================================================================
# Installs offline-compatible skills/plugins to local Codex configuration.
# Usage: bash install-skills.sh [skills_dir]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SOURCE="${1:-${SCRIPT_DIR}/offline-skills}"
CODEX_SKILLS_DIR="${HOME}/.codex/skills"
CODEX_PLUGINS_DIR="${HOME}/.codex/plugins"
MANIFEST_FILE="${SKILLS_SOURCE}/skills-manifest.json"

if [ -f "${SCRIPT_DIR}/lib/common.sh" ]; then
    source "${SCRIPT_DIR}/lib/common.sh"
fi

if ! type log_info >/dev/null 2>&1; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
    log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
    log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
    log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
fi

JQ_CMD=""

# jq init: system -> bundled
if ! type init_jq >/dev/null 2>&1; then
    init_jq() {
        if command -v jq &>/dev/null; then JQ_CMD="jq"; return 0; fi
        local os arch rel=""
        os="$(uname -s)"
        arch="$(uname -m)"
        case "$os" in
            Linux*)
                case "$arch" in
                    x86_64|amd64)   rel="linux-amd64/jq" ;;
                    aarch64|arm64)  rel="linux-arm64/jq" ;;
                esac ;;
            Darwin*)
                case "$arch" in
                    x86_64|amd64)   rel="macos-amd64/jq" ;;
                    arm64)          rel="macos-arm64/jq" ;;
                esac ;;
            CYGWIN*|MINGW*|MSYS*) rel="windows-amd64/jq.exe" ;;
        esac
        if [ -n "$rel" ] && [ -x "${SCRIPT_DIR}/bin/${rel}" ]; then
            JQ_CMD="${SCRIPT_DIR}/bin/${rel}"; return 0
        fi
        return 1
    }
fi

check_source() {
    if [ ! -d "$SKILLS_SOURCE" ]; then
        log_error "Skills source directory not found: ${SKILLS_SOURCE}"
        exit 1
    fi
}

install_skill() {
    local skill_name="$1" skill_type="${2:-skill}"
    local source_path="${SKILLS_SOURCE}/${skill_name}"

    if [ -z "$(find "$source_path" -type f -not -path '*/.git/*' 2>/dev/null | head -1)" ]; then
        log_warn "  Skipping '${skill_name}' — no bundled payload files"
        return 1
    fi

    if [ "$skill_type" = "plugin" ]; then
        local marketplace_name=""
        if [ -f "$MANIFEST_FILE" ]; then
            marketplace_name=$($JQ_CMD -r ".skills[\"${skill_name}\"].repo // empty" "$MANIFEST_FILE" 2>/dev/null)
        fi
        [ -z "$marketplace_name" ] && marketplace_name="$skill_name"
        marketplace_name="${marketplace_name##*/}"

        local cache_dir="${CODEX_PLUGINS_DIR}/marketplaces/${marketplace_name}/${skill_name}"
        mkdir -p "$cache_dir"

        if cp -r "$source_path"/. "$cache_dir/" 2>/dev/null; then
            log_ok "  Plugin installed to: ${cache_dir}"
        else
            log_warn "  Failed to copy plugin files"
            return 1
        fi

        # Copy rules if present
        if [ -d "$cache_dir/rules" ]; then
            log_info "  Copying rules..."
            for rule_dir in "$cache_dir/rules"/*/; do
                if [ -d "$rule_dir" ]; then
                    local rule_subdir; rule_subdir=$(basename "$rule_dir")
                    mkdir -p "${HOME}/.codex/rules/${rule_subdir}"
                    cp -r "$rule_dir"/* "${HOME}/.codex/rules/${rule_subdir}/" 2>/dev/null || true
                    log_ok "    Rules: ${rule_subdir}"
                fi
            done
        fi
    else
        local target_path="${CODEX_SKILLS_DIR}/${skill_name}"
        log_info "Installing skill: ${skill_name}"
        mkdir -p "$target_path"
        if cp -r "$source_path"/. "$target_path/" 2>/dev/null; then
            log_ok "  Installed to: ${target_path}"
        else
            log_warn "  Failed to copy some files"
            return 1
        fi
    fi
    return 0
}

install_all_skills() {
    local skills_installed=0 plugins_installed=0 failed=0
    log_info "Installing skills to: ${CODEX_SKILLS_DIR}"
    log_info "Installing plugins to: ${CODEX_PLUGINS_DIR}"

    mkdir -p "$CODEX_SKILLS_DIR" "$CODEX_PLUGINS_DIR"

    if [ -f "$MANIFEST_FILE" ]; then
        while IFS=$'\x1f' read -r skill_name skill_type offline_compatible; do
            if [ "$offline_compatible" = "false" ]; then
                log_warn "Skipping '${skill_name}' - offline_compatible=false"
                continue
            fi
            if [ -d "${SKILLS_SOURCE}/${skill_name}" ]; then
                if install_skill "$skill_name" "$skill_type"; then
                    if [ "$skill_type" = "plugin" ]; then
                        ((plugins_installed++)) || true
                    else
                        ((skills_installed++)) || true
                    fi
                else
                    ((failed++)) || true
                fi
            else
                log_warn "Skill directory not found: ${skill_name}"
                ((failed++)) || true
            fi
        done < <($JQ_CMD -r '.skills | to_entries[] | [.key, .value.type // "skill", (if .value.offline_compatible == null then "true" elif .value.offline_compatible == false then "false" else "true" end)] | join("")' "$MANIFEST_FILE")
    else
        for skill_dir in "$SKILLS_SOURCE"/*/; do
            if [ -d "$skill_dir" ] && [ -f "$skill_dir/SKILL.md" ]; then
                local skill_name; skill_name=$(basename "$skill_dir")
                if install_skill "$skill_name" "skill"; then
                    ((skills_installed++)) || true
                else
                    ((failed++)) || true
                fi
            fi
        done
    fi

    log_info "============================="
    log_ok "Installed: ${skills_installed} skills, ${plugins_installed} plugins"
    [ $failed -gt 0 ] && log_warn "Failed: ${failed} entries"
}

main() {
    log_info "Codex Skills & Plugins Installer"
    log_info "==================================="

    if ! init_jq; then
        log_error "jq not available. Install jq or run: bash download-jq.sh --all"
        exit 1
    fi

    check_source

    if [ -t 0 ]; then
        echo ""
        log_info "Will install offline skills to: ${CODEX_SKILLS_DIR}"
        log_info "Will install offline plugins to: ${CODEX_PLUGINS_DIR}"
        read -p "Continue? [Y/n]: " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]] && [ -n "$REPLY" ]; then
            log_info "Installation cancelled"
            exit 0
        fi
    fi

    install_all_skills

    log_info "==================================="
    log_ok "Installation complete!"
    echo ""
    log_info "Installed skills: ${CODEX_SKILLS_DIR}"
    log_info "Installed plugins: ${CODEX_PLUGINS_DIR}"
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Codex Skills & Plugins Installer"
    echo "Usage: bash install-skills.sh [skills_dir]"
    echo "  skills_dir  Directory containing offline skills (default: ./offline-skills/)"
    exit 0
fi

main "$@"
