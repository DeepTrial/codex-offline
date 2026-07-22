[简体中文](../../README.md) | [English](./README.en.md) | **繁體中文** | [Русский](./README.ru.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md)

# Codex 離線部署

[![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-Enabled-blue)](.github/workflows/download-codex-packages.yml)
[![Version](https://img.shields.io/npm/v/@openai/codex?label=version&color=green)](https://www.npmjs.com/package/@openai/codex)
[![License](https://img.shields.io/badge/license-MIT-yellow)](LICENSE)
[![Claude Code Offline](https://img.shields.io/badge/sister%20project-Claude%20Code%20Offline-blueviolet)](https://github.com/DeepTrial/claude-code-offline)

自動化 Codex CLI 離線部署：每日從 npm 拉取最新 Codex，建置 **Linux 與 Windows 離線套件**，執行**自動化安裝測試**，然後發布至 GitHub Releases。

## ✨ 功能特色

- ✅ **每日自動建置**：GitHub Actions 每天檢查 npm 上的新版本，自動建置並發布
- ✅ **雙平台套件**：Linux x64（`tar.gz`）+ Windows x64（`zip`，原生 PowerShell 安裝程式）
- ✅ **測試把關**：每個套件都在乾淨環境中測試（無 Node 的 ubuntu 容器 / Windows runner），包含完整安裝 + 啟動驗證 — **測試失敗則不發布**
- ✅ **無需 Node.js**：Codex 是獨立的原生二進位檔案（Rust 編譯），透過 shell 腳本直接呼叫
- ✅ **第三方 API 支援**：設定 `OPENAI_BASE_URL` 指向任何 OpenAI 相容的 API 代理/閘道
- ✅ **跳過登入**：自動跳過新手引導，停用遙測
- ✅ **無人值守安裝**：`--yes` / `--non-interactive` 模式，適用於腳本和 CI
- ✅ **離線 Skills/Plugins**：內建 15 個離線相容的 skills（文件處理、設計、測試等）
- ✅ **完整解除安裝**：乾淨解除安裝並備份設定

---

## 🚀 快速開始

### Linux / macOS / WSL

**選項一：一行指令安裝（需網路）**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/DeepTrial/codex-offline/main/setup-codex.sh) --auto-download
```

**選項二：離線套件安裝（無需網路）**

```bash
# 從 Releases 下載 codex-offline-packages-linux.tar.gz 後：
tar -xzf codex-offline-packages-linux.tar.gz
cd codex-offline-packages
bash setup-codex.sh --yes
```

**選項三：使用本地離線套件**

```bash
bash setup-codex.sh --offline-path /path/to/codex-offline-packages
```

### Windows（原生）

1. 從 [Releases](https://github.com/DeepTrial/codex-offline/releases) 下載 `codex-offline-packages-windows.zip` 並解壓縮
2. 雙擊 `setup-codex.bat`，或在 PowerShell 中執行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-codex.ps1 -NonInteractive
```

安裝程式會驗證原生 `codex.exe`，生成設定，並將 `.bin` 目錄加入使用者 PATH（冪等操作）。

---

## ⚠️ 安裝後（重要）

**您必須設定自己的 API 金鑰才能使用 Codex：**

```bash
# Linux/macOS/WSL
nano ~/.codex/config.toml

# Windows：用記事本開啟 %USERPROFILE%\.codex\config.toml
```

替換佔位值：

```toml
[api]
base_url = "https://your-api-endpoint.com"
api_key = "sk-your-api-key-here"

[telemetry]
enabled = false
```

或直接設定環境變數：

```bash
export OPENAI_BASE_URL="https://your-api-endpoint.com"
export OPENAI_API_KEY="sk-your-api-key-here"
```

然後**開啟新的終端機**（或執行 `source ~/.bashrc`），並驗證：

```bash
codex --version
```

> 💡 在無法直接存取 OpenAI API 的地區，可將 `base_url` 設為您的代理/中轉地址。支援所有 OpenAI API 相容介面（Azure、DeepSeek、Moonshot 等）。

---

## 📦 發布內容

| 檔案 | 平台 | 說明 |
|------|------|------|
| `codex-offline-packages-linux.tar.gz` | Linux x64 / WSL | 完整離線套件（含 skills、jq） |
| `codex-offline-packages-windows.zip` | Windows x64 | 原生 Windows 套件（含 skills、jq.exe、安裝程式） |
| `*.sha256` | - | 校驗碼檔案：`sha256sum -c <file>.sha256` |

---

## 🔄 CI/CD 流程

```
check-version → build-linux-package ─┐
              → build-windows-package ┤→ test-release-package → create-release
                                        (ubuntu + windows 雙平台)
```

- **每日檢查**：UTC 00:00 比較 npm 最新版與現有 Release，僅在新版本時建置
- **每週重建**：每週一 UTC 01:00 完整重建
- **手動觸發**：Actions → `Download Codex Offline Packages` → Run workflow（可指定版本/強制重建）
- **測試把關**：測試作業在乾淨的 ubuntu:22.04 容器（無 Node）和 windows-latest 上執行，進行結構驗證、`codex --version` 斷言、完整無人值守安裝、config.toml 驗證 — 全部通過後才發布

本地手動更新檢查：

```bash
bash check-update.sh              # 互動式
bash check-update.sh --check-only # 僅檢查
bash check-update.sh --install    # 下載並安裝
```

---

## 🧩 內建離線 Skills（15 個）

在建置時根據 `skills/skills-manifest.json` 下載，由安裝程式安裝至 `~/.codex/`：

| 分類 | Skills |
|------|--------|
| **文件** | docx, pdf, pptx, xlsx |
| **設計** | frontend-design, algorithmic-art, canvas-design, theme-factory, web-artifacts-builder |
| **測試** | webapp-testing（Playwright） |
| **工具** | skill-creator |
| **企業** | brand-guidelines, internal-comms, doc-coauthoring |
| **插件** | superpowers（TDD/除錯/規劃工作流程框架） |

---

## 🛠️ 進階用法

### 安裝腳本參數

| 參數 | 說明 |
|------|------|
| `--offline-path PATH` | 指定離線套件路徑 |
| `--auto-download` | 自動從 GitHub Release 下載 |
| `--yes, -y` | 自動確認所有提示（完全無人值守） |
| `--non-interactive` | 非互動模式，使用預設值 |
| `--uninstall` | 解除安裝 Codex 及設定 |
| `--help, -h` | 說明 |

### Windows 安裝程式參數

| 參數 | 說明 |
|------|------|
| `-OfflinePath <path>` | 指定離線套件路徑 |
| `-AutoDownload` | 自動從 GitHub Release 下載 |
| `-NonInteractive` | 非互動模式 |
| `-Uninstall` | 解除安裝 Codex |

---

## 🧪 測試套件

```bash
# Linux：結構驗證 + 版本斷言 + 乾淨容器端對端安裝
bash tests/test-linux-package.sh /path/to/codex-offline-packages 0.144.6
```

```powershell
# Windows：二進位檔案驗證 + 安裝程式 + config.toml + PATH 登錄斷言
powershell -NoProfile -File tests\test-windows-package.ps1 `
  -PackageDir .\codex-offline-packages-windows -ExpectedVersion 0.144.6
```

---

## 🗑️ 解除安裝

```bash
# Linux/macOS/WSL
bash setup-codex.sh --uninstall
```

```powershell
# Windows
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-codex.ps1 -Uninstall
```

解除安裝前會建立 `~/.codex/` 的備份。

---

## 🔧 疑難排解

### 網路無法連線

安裝程式在每個網路步驟前會進行 5 秒預檢，遇到錯誤時快速失敗：
- 檢查網路/代理（`HTTPS_PROXY`）
- 純離線：確保已備妥預先下載的離線套件，使用 `--offline-path`

### 找不到 codex 指令

```bash
source ~/.bashrc   # 或開啟新的終端機
```

### API 連線失敗

1. 驗證 `~/.codex/config.toml` 中的 `base_url` 和 `api_key`
2. 檢查與所設定 API 端點的網路連線
3. 確認是否需要代理

### 無 Node.js 環境

不需要。Codex 是由 Rust 編譯的獨立原生二進位檔案（約 280MB），透過 shell 腳本直接呼叫，完全不需要 Node.js。

---

## 授權

與原始 Codex CLI 授權相同。

---

**注意**：Codex CLI 是 OpenAI 的產品。本專案與 OpenAI 無關。
