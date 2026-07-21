# Codex 离线部署方案

[![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-Enabled-blue)](.github/workflows/download-codex-packages.yml)
[![Version](https://img.shields.io/badge/version-1.0-green)](setup-codex.sh)
[![License](https://img.shields.io/badge/license-MIT-yellow)](LICENSE)

自动化的 Codex CLI 离线部署方案：每天自动从 npm 拉取最新版 Codex，构建 **Linux 与 Windows 双平台离线包**，经过**自动化安装测试**后发布到 GitHub Releases。

## ✨ 特性

- ✅ **每日自动构建**：GitHub Actions 每天检查 npm 新版本，自动构建并发布
- ✅ **双平台安装包**：Linux x64 (`tar.gz`) + Windows x64 (`zip`，原生 PowerShell 安装器）
- ✅ **测试门禁**：每个包发布前都在干净环境（无 Node 的 ubuntu 容器 / Windows runner）中跑完整安装 + 启动验证，**测试不过不发版**
- ✅ **无需 Node.js**：Codex 是独立原生二进制（Rust 编译），通过 shell 脚本直接调用，完全不需要 Node.js
- ✅ **第三方 API 支持**：配置 `OPENAI_BASE_URL` 指向任意 OpenAI 兼容的 API 代理/网关
- ✅ **登录绕过**：自动跳过 onboarding，禁用遥测
- ✅ **无人值守安装**：`--yes` / `--non-interactive` 模式，适合脚本和 CI
- ✅ **离线 Skills/Plugins**：内置 15 个离线兼容 skills（文档处理、设计、测试等）
- ✅ **完整卸载功能**：支持配置备份的彻底卸载

---

## 🚀 快速开始

### Linux / macOS / WSL

**方式 1：一行命令安装（需要网络）**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/DeepTrial/codex-offline/main/setup-codex.sh) --auto-download
```

**方式 2：离线包安装（无需网络）**

```bash
# 从 Releases 下载 codex-offline-packages-linux.tar.gz 后：
tar -xzf codex-offline-packages-linux.tar.gz
cd codex-offline-packages
bash setup-codex.sh --yes
```

**方式 3：本地已有离线包**

```bash
bash setup-codex.sh --offline-path /path/to/codex-offline-packages
```

### Windows（原生）

1. 从 [Releases](https://github.com/DeepTrial/codex-offline/releases) 下载 `codex-offline-packages-windows.zip` 并解压
2. 双击 `setup-codex.bat`，或在 PowerShell 中运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-codex.ps1 -NonInteractive
```

安装器会校验原生 `codex.exe`、生成配置、并把 `.bin` 目录写入用户 PATH（幂等）。

---

## ⚠️ 安装后必做（关键步骤）

**必须配置自己的 API 密钥才能使用：**

```bash
# Linux/macOS/WSL
nano ~/.codex/config.toml

# Windows 用记事本打开 %USERPROFILE%\.codex\config.toml
```

替换占位值：

```toml
[api]
base_url = "https://your-api-endpoint.com"
api_key = "sk-your-api-key-here"

[telemetry]
enabled = false
```

或直接设置环境变量：

```bash
export OPENAI_BASE_URL="https://your-api-endpoint.com"
export OPENAI_API_KEY="sk-your-api-key-here"
```

然后**打开新终端**（或 `source ~/.bashrc`)，验证：

```bash
codex --version
```

> 💡 无法直连 OpenAI API 的地区，把 `base_url` 配置为你的代理/中转地址。支持所有 OpenAI API 兼容的接口（Azure、DeepSeek、Moonshot 等）。

---

## 📦 Release 内容

| 文件 | 平台 | 说明 |
|------|------|------|
| `codex-offline-packages-linux.tar.gz` | Linux x64 / WSL | 完整离线包（含 skills、jq） |
| `codex-offline-packages-windows.zip` | Windows x64 | 原生 Windows 包（含 skills、jq.exe、安装器） |
| `*.sha256` | - | 校验文件：`sha256sum -c <file>.sha256` |

---

## 🔄 自动化流水线

```
check-version → build-linux-package ─┐
              → build-windows-package ┤→ test-release-package → create-release
                                        (ubuntu + windows 双端)
```

- **每日检查**：UTC 00:00 对比 npm 最新版与现有 Release，有新版本才构建
- **每周重建**：每周一 UTC 01:00 完整重建
- **手动触发**：Actions → `Download Codex Offline Packages` → Run workflow（可指定版本/强制重建）
- **测试门禁**：测试 job 在干净的 ubuntu:22.04 容器（无 Node）和 windows-latest 上分别执行结构校验、`codex --version` 断言、完整非交互安装、config.toml 验证，全部通过才发布

本地手动检查更新：

```bash
bash check-update.sh              # 交互式
bash check-update.sh --check-only # 仅检查
bash check-update.sh --install    # 下载并安装
```

---

## 🧩 内置离线 Skills（15 个）

构建时按 `skills/skills-manifest.json` 自动下载，安装器运行后装入 `~/.codex/`:

| 分类 | 内容 |
|------|------|
| **文档处理** | docx、pdf、pptx、xlsx |
| **设计** | frontend-design、algorithmic-art、canvas-design、theme-factory、web-artifacts-builder |
| **测试** | webapp-testing (Playwright) |
| **工具** | skill-creator |
| **企业** | brand-guidelines、internal-comms、doc-coauthoring |
| **插件** | superpowers (TDD/调试/规划工作流框架） |

---

## 🛠️ 高级用法

### 安装脚本参数

| 参数 | 说明 |
|------|------|
| `--offline-path PATH` | 指定离线包路径 |
| `--auto-download` | 自动从 GitHub Release 下载 |
| `--yes, -y` | 所有提示自动 yes（完全无人值守） |
| `--non-interactive` | 非交互模式，自动采用默认答案 |
| `--uninstall` | 卸载 Codex 及配置 |
| `--help, -h` | 帮助 |

### Windows 安装器参数

| 参数 | 说明 |
|------|------|
| `-OfflinePath <path>` | 指定离线包路径 |
| `-AutoDownload` | 自动从 GitHub Release 下载 |
| `-NonInteractive` | 非交互模式 |
| `-Uninstall` | 卸载 Codex |

---

## 🧪 测试安装包

```bash
# Linux 包：结构校验 + 版本断言 + 无 Node 干净容器端到端安装
bash tests/test-linux-package.sh /path/to/codex-offline-packages 0.144.6
```

```powershell
# Windows 包：二进制校验 + 安装器 + config.toml + PATH 注册表断言
powershell -NoProfile -File tests\test-windows-package.ps1 `
  -PackageDir .\codex-offline-packages-windows -ExpectedVersion 0.144.6
```

---

## 🗑️ 卸载

```bash
# Linux/macOS/WSL
bash setup-codex.sh --uninstall
```

```powershell
# Windows
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-codex.ps1 -Uninstall
```

卸载前会自动备份 `~/.codex/` 目录。

---

## 🔧 故障排除

### Network unreachable

安装器在联网步骤前做 5 秒预检，失败立即报错：
- 检查网络/代理（`HTTPS_PROXY`）
- 纯离线：确保有预下载的离线包，用 `--offline-path` 指定

### Codex command not found

```bash
source ~/.bashrc   # 或打开新终端
```

### API 连接失败

1. 检查 `~/.codex/config.toml` 中 `base_url` 和 `api_key` 是否正确
2. 检查网络能否访问配置的 API 端点
3. 确认是否需要代理

### 无 Node.js 环境

不需要。Codex 是 Rust 编译的独立原生二进制（~280MB），通过 shell 脚本直接调用，完全不需要 Node.js。

---

## 许可证

与原 Codex CLI 许可证一致。

---

**注意**：Codex CLI 是 OpenAI 的产品。本项目与 OpenAI 无关。
