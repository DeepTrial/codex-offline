#!/usr/bin/env bash
# =============================================================================
# Linux codex offline package end-to-end test
# =============================================================================
# Verifies the built codex-offline-packages directory:
#   1. Structure: real native binary (>50MB), launcher script
#   2. codex --version prints expected version
#   3. Clean-room install in node-less ubuntu:22.04 container:
#      bash setup-codex.sh --offline-path <pkg> --yes must succeed
#
# Usage: bash tests/test-linux-package.sh <package_dir> <expected_version>
# =============================================================================

set -euo pipefail

PKG_DIR="${1:?Usage: $0 <package_dir> <expected_version>}"
EXPECTED_VERSION="${2:?Usage: $0 <package_dir> <expected_version>}"

info() { echo "[INFO] $*"; }
ok()   { echo "  [OK] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

PKG_DIR="$(cd "$PKG_DIR" && pwd)"

echo "======================================================================"
echo "  Linux Codex package test"
echo "  Package: $PKG_DIR"
echo "  Expect:  v$EXPECTED_VERSION"
echo "======================================================================"

# Detect platform triple
detect_triple() {
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
    esac
}
TRIPLE=$(detect_triple)
[ -n "$TRIPLE" ] || fail "Could not detect platform triple"

# ---------------------------------------------------------------------------
# 1. Structure assertions
# ---------------------------------------------------------------------------
info "Checking package structure..."

MAIN_BIN="$PKG_DIR/node_modules/@openai/codex/vendor/${TRIPLE}/bin/codex"
[ -f "$MAIN_BIN" ] || fail "Native binary missing: $MAIN_BIN"
BIN_SIZE=$(stat -c%s "$MAIN_BIN" 2>/dev/null || echo 0)
[ "$BIN_SIZE" -gt 52428800 ] || fail "Native binary is only $BIN_SIZE bytes (<= 50MB) — looks like a stub"
ok "Native binary is real ($BIN_SIZE bytes)"

LAUNCHER="$PKG_DIR/node_modules/.bin/codex"
[ -e "$LAUNCHER" ] || fail ".bin/codex launcher missing"
[ -x "$LAUNCHER" ] || fail ".bin/codex not executable"
[ ! -L "$LAUNCHER" ] || fail ".bin/codex is a symlink (must be a real script)"
ok ".bin/codex is real, executable launcher (not a symlink)"

[ -f "$PKG_DIR/setup-codex.sh" ] || fail "setup-codex.sh missing"
ok "setup-codex.sh present"

# ---------------------------------------------------------------------------
# 2. Direct version check
# ---------------------------------------------------------------------------
info "Running codex --version ..."
VERSION_OUT="$("$LAUNCHER" --version 2>&1)" || fail "codex --version failed: $VERSION_OUT"
echo "    output: $VERSION_OUT"
echo "$VERSION_OUT" | grep -q "$EXPECTED_VERSION" \
    || fail "version output does not contain expected version $EXPECTED_VERSION"
ok "version check passed"

# ---------------------------------------------------------------------------
# 3. Clean-room install test (docker, no Node.js, fake HOME)
# ---------------------------------------------------------------------------
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    info "Running clean-room install test in ubuntu:22.04 (no Node.js, fake HOME)..."
    chmod -R a+rwX "$PKG_DIR" 2>/dev/null || true
    docker run --rm \
        -v "$PKG_DIR:/pkg" \
        -e EXPECTED_VERSION="$EXPECTED_VERSION" \
        ubuntu:22.04 bash -c '
            set -e
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq bash >/dev/null
            useradd -m tester
            mkdir -p /tmp/fakehome && chown tester:tester /tmp/fakehome

            if ! su tester -c "HOME=/tmp/fakehome bash /pkg/setup-codex.sh --offline-path /pkg --yes < /dev/null" > /tmp/install.log 2>&1; then
                echo "[FAIL] setup-codex.sh exited non-zero. Last log lines:"
                tail -40 /tmp/install.log
                exit 1
            fi
            echo "  [OK] setup-codex.sh --yes completed (exit 0, no Node.js)"

            VER=$(su tester -c "HOME=/tmp/fakehome bash -c \"source ~/.bashrc && codex --version\"")
            echo "    codex --version: $VER"
            echo "$VER" | grep -q "$EXPECTED_VERSION" || { echo "[FAIL] unexpected version"; exit 1; }

            # Verify config.toml was created
            if [ -f /tmp/fakehome/.codex/config.toml ]; then
                echo "  [OK] config.toml created"
            else
                echo "[FAIL] config.toml missing"
                exit 1
            fi
        ' || fail "docker clean-room install test failed"
    ok "clean-room install + codex --version passed (no Node.js)"
else
    info "docker not available; skipping clean-room container test"
fi

echo ""
echo "ALL LINUX CODEX PACKAGE TESTS PASSED"
