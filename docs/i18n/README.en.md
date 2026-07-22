[简体中文](../../README.md) | **English** | [繁體中文](./README.zh-TW.md) | [Русский](./README.ru.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md)

# Codex Offline Deployment

[![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-Enabled-blue)](.github/workflows/download-codex-packages.yml)
[![Version](https://img.shields.io/npm/v/@openai/codex?label=version&color=green)](https://www.npmjs.com/package/@openai/codex)
[![License](https://img.shields.io/badge/license-MIT-yellow)](LICENSE)
[![Claude Code Offline](https://img.shields.io/badge/sister%20project-Claude%20Code%20Offline-blueviolet)](https://github.com/DeepTrial/claude-code-offline)

Automated Codex CLI offline deployment: pulls the latest Codex from npm daily, builds **Linux and Windows offline packages**, runs **automated install tests**, then publishes to GitHub Releases.

## ✨ Features

- ✅ **Daily auto-build**: GitHub Actions checks npm for new versions every day, builds and publishes automatically
- ✅ **Dual-platform packages**: Linux x64 (`tar.gz`) + Windows x64 (`zip`, native PowerShell installer)
- ✅ **Test gating**: Every package is tested in a clean environment (Node-free ubuntu container / Windows runner) with full install + startup verification — **no publish if tests fail**
- ✅ **No Node.js required**: Codex is a standalone native binary (Rust-compiled), invoked directly via shell script
- ✅ **Third-party API support**: Configure `OPENAI_BASE_URL` to point to any OpenAI-compatible API proxy/gateway
- ✅ **Login bypass**: Auto-skips onboarding, disables telemetry
- ✅ **Unattended install**: `--yes` / `--non-interactive` mode for scripts and CI
- ✅ **Offline Skills/Plugins**: 15 offline-compatible skills bundled (document processing, design, testing, etc.)
- ✅ **Full uninstall**: Clean uninstall with config backup

---

## 🚀 Quick Start

### Linux / macOS / WSL

**Option 1: One-liner install (requires network)**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/DeepTrial/codex-offline/main/setup-codex.sh) --auto-download
```

**Option 2: Offline package install (no network needed)**

```bash
# After downloading codex-offline-packages-linux.tar.gz from Releases:
tar -xzf codex-offline-packages-linux.tar.gz
cd codex-offline-packages
bash setup-codex.sh --yes
```

**Option 3: Use a local offline package**

```bash
bash setup-codex.sh --offline-path /path/to/codex-offline-packages
```

### Windows (Native)

1. Download `codex-offline-packages-windows.zip` from [Releases](https://github.com/DeepTrial/codex-offline/releases) and extract
2. Double-click `setup-codex.bat`, or run in PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-codex.ps1 -NonInteractive
```

The installer validates the native `codex.exe`, generates config, and adds the `.bin` directory to user PATH (idempotent).

---

## ⚠️ Post-Install (Critical)

**You must configure your own API key to use Codex:**

```bash
# Linux/macOS/WSL
nano ~/.codex/config.toml

# Windows: open %USERPROFILE%\.codex\config.toml in Notepad
```

Replace placeholder values:

```toml
[api]
base_url = "https://your-api-endpoint.com"
api_key = "sk-your-api-key-here"

[telemetry]
enabled = false
```

Or set environment variables directly:

```bash
export OPENAI_BASE_URL="https://your-api-endpoint.com"
export OPENAI_API_KEY="sk-your-api-key-here"
```

Then **open a new terminal** (or `source ~/.bashrc`), and verify:

```bash
codex --version
```

> 💡 In regions where direct OpenAI API access is unavailable, set `base_url` to your proxy/relay address. Supports all OpenAI API-compatible interfaces (Azure, DeepSeek, Moonshot, etc.).

---

## 📦 Release Contents

| File | Platform | Description |
|------|----------|-------------|
| `codex-offline-packages-linux.tar.gz` | Linux x64 / WSL | Full offline package (includes skills, jq) |
| `codex-offline-packages-windows.zip` | Windows x64 | Native Windows package (includes skills, jq.exe, installer) |
| `*.sha256` | - | Checksum files: `sha256sum -c <file>.sha256` |

---

## 🔄 CI/CD Pipeline

```
check-version → build-linux-package ─┐
              → build-windows-package ┤→ test-release-package → create-release
                                        (ubuntu + windows dual-platform)
```

- **Daily check**: UTC 00:00 compares npm latest with existing Release, only builds on new versions
- **Weekly rebuild**: Every Monday UTC 01:00 full rebuild
- **Manual trigger**: Actions → `Download Codex Offline Packages` → Run workflow (can specify version/force rebuild)
- **Test gating**: Test jobs run on clean ubuntu:22.04 containers (no Node) and windows-latest, performing structure validation, `codex --version` assertion, full non-interactive install, config.toml verification — all must pass before publish

Local manual update check:

```bash
bash check-update.sh              # Interactive
bash check-update.sh --check-only # Check only
bash check-update.sh --install    # Download and install
```

---

## 🧩 Bundled Offline Skills (15)

Downloaded at build time per `skills/skills-manifest.json`, installed to `~/.codex/` by the installer:

| Category | Skills |
|----------|--------|
| **Documents** | docx, pdf, pptx, xlsx |
| **Design** | frontend-design, algorithmic-art, canvas-design, theme-factory, web-artifacts-builder |
| **Testing** | webapp-testing (Playwright) |
| **Tools** | skill-creator |
| **Enterprise** | brand-guidelines, internal-comms, doc-coauthoring |
| **Plugins** | superpowers (TDD/debugging/planning workflow framework) |

---

## 🛠️ Advanced Usage

### Installer Script Parameters

| Parameter | Description |
|-----------|-------------|
| `--offline-path PATH` | Specify offline package path |
| `--auto-download` | Auto-download from GitHub Release |
| `--yes, -y` | Auto-yes all prompts (fully unattended) |
| `--non-interactive` | Non-interactive mode, use defaults |
| `--uninstall` | Uninstall Codex and config |
| `--help, -h` | Help |

### Windows Installer Parameters

| Parameter | Description |
|-----------|-------------|
| `-OfflinePath <path>` | Specify offline package path |
| `-AutoDownload` | Auto-download from GitHub Release |
| `-NonInteractive` | Non-interactive mode |
| `-Uninstall` | Uninstall Codex |

---

## 🧪 Testing Packages

```bash
# Linux: structure validation + version assertion + clean container end-to-end install
bash tests/test-linux-package.sh /path/to/codex-offline-packages 0.144.6
```

```powershell
# Windows: binary validation + installer + config.toml + PATH registry assertion
powershell -NoProfile -File tests\test-windows-package.ps1 `
  -PackageDir .\codex-offline-packages-windows -ExpectedVersion 0.144.6
```

---

## 🗑️ Uninstall

```bash
# Linux/macOS/WSL
bash setup-codex.sh --uninstall
```

```powershell
# Windows
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-codex.ps1 -Uninstall
```

A backup of `~/.codex/` is created before uninstall.

---

## 🔧 Troubleshooting

### Network unreachable

The installer does a 5-second pre-check before any network step, failing fast on errors:
- Check network/proxy (`HTTPS_PROXY`)
- Pure offline: ensure a pre-downloaded offline package is available, use `--offline-path`

### Codex command not found

```bash
source ~/.bashrc   # or open a new terminal
```

### API connection failed

1. Verify `base_url` and `api_key` in `~/.codex/config.toml`
2. Check network connectivity to the configured API endpoint
3. Confirm whether a proxy is needed

### No Node.js environment

Not needed. Codex is a standalone native binary compiled from Rust (~280MB), invoked directly via shell script. Node.js is completely unnecessary.

---

## License

Same as the original Codex CLI license.

---

**Note**: Codex CLI is an OpenAI product. This project is not affiliated with OpenAI.
