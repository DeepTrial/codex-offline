#!/usr/bin/env bash
# =============================================================================
# Codex Skills/Plugins Downloader for Offline Deployment
# =============================================================================
# Reads skills-manifest.json, git-clones each offline entry, copies files.
# Usage: bash download-skills.sh [output_dir]
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${1:-${SCRIPT_DIR}/offline-skills}"
MANIFEST_FILE="${SCRIPT_DIR}/skills-manifest.json"

source "${SCRIPT_DIR}/lib/common.sh"

JQ_CMD=""

check_deps() {
    if ! init_jq; then
        log_error "jq not available. Install jq or run: bash download-jq.sh --all"
        exit 1
    fi
    for dep in curl git; do
        if ! command -v "$dep" &>/dev/null; then
            log_error "$dep is required but not installed"
            exit 1
        fi
    done
}

download_entry() {
    local entry_name="$1" entry_repo="$2" entry_path="$3" entry_files="$4" entry_type="${5:-skill}"
    local output_path="${OUTPUT_DIR}/${entry_name}"

    log_info "Downloading ${entry_type}: ${entry_name} (from ${entry_repo})"
    mkdir -p "$output_path"

    local clone_dir="/tmp/cdx-${entry_name}-clone-$$"
    local repo_url="https://github.com/${entry_repo}"

    if ! git clone --depth 1 "$repo_url" "$clone_dir" 2>&1; then
        log_error "  Failed to clone: ${repo_url}"
        rm -rf "$clone_dir"
        return 1
    fi

    local src_base="$clone_dir"
    if [ -n "$entry_path" ]; then
        src_base="$clone_dir/${entry_path}"
        if [ ! -d "$src_base" ]; then
            log_warn "  Path ${entry_path} not found in repo, using root"
            src_base="$clone_dir"
        fi
    fi

    for file in $entry_files; do
        local src="$src_base/$file"
        local dst="$output_path/$file"
        if [ -e "$src" ]; then
            mkdir -p "$(dirname "$dst")"
            cp -r "$src" "$dst" 2>/dev/null || log_warn "  Failed to copy: ${file}"
        else
            log_warn "  Not found in repo: ${file}"
        fi
    done

    local copied
    copied=$(find "$output_path" -type f -not -path '*/.git/*' 2>/dev/null | wc -l)
    if [ "$copied" -eq 0 ]; then
        log_error "  No payload files for ${entry_name} — refusing empty bundle"
        rm -rf "$clone_dir"
        return 1
    fi

    if [ "$entry_type" = "plugin" ] && [ -d "$clone_dir/.git" ]; then
        git -C "$clone_dir" rev-parse HEAD > "$output_path/.git-sha" 2>/dev/null || true
    fi

    rm -rf "$clone_dir"
    log_ok "${entry_type} '${entry_name}' downloaded (${copied} files)"
    return 0
}

create_index() {
    local index_file="${OUTPUT_DIR}/SKILLS-INDEX.md"
    log_info "Creating skills index..."
    cat > "$index_file" << 'EOF'
# Codex Offline Skills Index

This directory contains offline-compatible skills for Codex CLI.

## Installation

To install these skills, run:
```bash
bash install-skills.sh
```

Or manually copy to:
- Linux/macOS: `~/.codex/skills/`
- Windows: `%USERPROFILE%\.codex\skills\`

## Available Skills

EOF
    for skill_dir in "$OUTPUT_DIR"/*/; do
        if [ -d "$skill_dir" ] && [ -f "$skill_dir/SKILL.md" ]; then
            local skill_name description
            skill_name=$(basename "$skill_dir")
            description=$(grep -m1 "^description:" "$skill_dir/SKILL.md" 2>/dev/null | cut -d'"' -f2 || echo "No description")
            echo "- **${skill_name}**: ${description}" >> "$index_file"
        fi
    done
    log_ok "Index created: ${index_file}"
}

main() {
    log_info "Codex Skills & Plugins Downloader"
    log_info "==================================="
    check_deps

    if [ ! -f "$MANIFEST_FILE" ]; then
        log_error "Manifest file not found: ${MANIFEST_FILE}"
        exit 1
    fi

    mkdir -p "$OUTPUT_DIR"

    local skills_count succeeded=0 failed=0 skipped=0
    skills_count=$($JQ_CMD -r '.skills | length' "$MANIFEST_FILE")
    log_info "Found ${skills_count} entries in manifest"

    local tmp_results
    tmp_results=$(mktemp)

    while IFS=$'\x1f' read -r entry_name entry_type entry_repo entry_path entry_files offline_compatible; do
        if [ "$offline_compatible" = "false" ]; then
            log_warn "Skipping '${entry_name}' - offline_compatible=false"
            echo "skipped" >> "$tmp_results"
            continue
        fi
        (
            if download_entry "$entry_name" "$entry_repo" "$entry_path" "$entry_files" "$entry_type"; then
                echo "ok" >> "$tmp_results"
            else
                echo "fail" >> "$tmp_results"
            fi
        ) &
    done < <($JQ_CMD -r '.skills | to_entries[] | [.key, .value.type // "skill", .value.repo, .value.path // "", (.value.files | join(" ")), (if .value.offline_compatible == null then "true" elif .value.offline_compatible == false then "false" else "true" end)] | join("")' "$MANIFEST_FILE")
    wait

    succeeded=$(grep -c "^ok$" "$tmp_results" 2>/dev/null || true)
    failed=$(grep -c "^fail$" "$tmp_results" 2>/dev/null || true)
    skipped=$(grep -c "^skipped$" "$tmp_results" 2>/dev/null || true)
    succeeded=${succeeded:-0}; failed=${failed:-0}; skipped=${skipped:-0}
    rm -f "$tmp_results"

    create_index
    cp "$MANIFEST_FILE" "$OUTPUT_DIR/"

    log_info "==================================="
    log_ok "Download completed: ${succeeded} succeeded, ${failed} failed, ${skipped} skipped"
    log_info "Output: ${OUTPUT_DIR}"
    log_info "Total size: $(du -sh "$OUTPUT_DIR" | cut -f1)"

    if [ "$failed" -gt 0 ]; then
        log_error "${failed} entries failed — aborting with error"
        exit 1
    fi
}

main "$@"
