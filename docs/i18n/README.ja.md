[简体中文](../../README.md) | [English](./README.en.md) | [繁體中文](./README.zh-TW.md) | [Русский](./README.ru.md) | **日本語** | [한국어](./README.ko.md)

# Codex オフラインデプロイ

[![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-Enabled-blue)](.github/workflows/download-codex-packages.yml)
[![Version](https://img.shields.io/badge/version-1.0-green)](setup-codex.sh)
[![License](https://img.shields.io/badge/license-MIT-yellow)](LICENSE)
[![Claude Code Offline](https://img.shields.io/badge/sister%20project-Claude%20Code%20Offline-blueviolet)](https://github.com/DeepTrial/claude-code-offline)

Codex CLI の自動オフラインデプロイ：npm から最新の Codex を毎日取得し、**Linux・Windows オフラインパッケージ**をビルドし、**自動インストールテスト**を実行した後、GitHub Releases に公開します。

## ✨ 特徴

- ✅ **毎日自動ビルド**：GitHub Actions が毎日 npm で新バージョンを確認し、自動でビルド・公開
- ✅ **デュアルプラットフォームパッケージ**：Linux x64（`tar.gz`）＋ Windows x64（`zip`、ネイティブ PowerShell インストーラー）
- ✅ **テストゲーティング**：各パッケージはクリーン環境（Node 未インストールの ubuntu コンテナ / Windows ランナー）でインストール＋起動検証を実施 — **テスト失敗時は公開しない**
- ✅ **Node.js 不要**：Codex はスタンドアロンのネイティブバイナリ（Rust コンパイル）で、シェルスクリプトから直接実行
- ✅ **サードパーティ API 対応**：`OPENAI_BASE_URL` を設定することで、任意の OpenAI 互換 API プロキシ/ゲートウェイを利用可能
- ✅ **ログインバイパス**：オンボーディングを自動スキップ、テレメトリを無効化
- ✅ **無人インストール**：スクリプト・CI 向けの `--yes` / `--non-interactive` モード
- ✅ **オフライン Skills/Plugins**：15 個のオフライン対応スキルを同梱（ドキュメント処理、デザイン、テスト等）
- ✅ **完全アンインストール**：設定バックアップ付きのクリーンアンインストール

---

## 🚀 クイックスタート

### Linux / macOS / WSL

**方法 1：ワンライナーインストール（ネットワーク必要）**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/DeepTrial/codex-offline/main/setup-codex.sh) --auto-download
```

**方法 2：オフラインパッケージインストール（ネットワーク不要）**

```bash
# Releases から codex-offline-packages-linux.tar.gz をダウンロード後：
tar -xzf codex-offline-packages-linux.tar.gz
cd codex-offline-packages
bash setup-codex.sh --yes
```

**方法 3：ローカルオフラインパッケージを使用**

```bash
bash setup-codex.sh --offline-path /path/to/codex-offline-packages
```

### Windows（ネイティブ）

1. [Releases](https://github.com/DeepTrial/codex-offline/releases) から `codex-offline-packages-windows.zip` をダウンロードして展開
2. `setup-codex.bat` をダブルクリック、または PowerShell で実行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-codex.ps1 -NonInteractive
```

インストーラーはネイティブ `codex.exe` を検証し、設定を生成し、`.bin` ディレクトリをユーザー PATH に追加します（冪等）。

---

## ⚠️ インストール後の設定（重要）

**Codex を使用するには、API キーの設定が必須です：**

```bash
# Linux/macOS/WSL
nano ~/.codex/config.toml

# Windows：%USERPROFILE%\.codex\config.toml をメモ帳で開く
```

プレースホルダーの値を置き換えます：

```toml
[api]
base_url = "https://your-api-endpoint.com"
api_key = "sk-your-api-key-here"

[telemetry]
enabled = false
```

または環境変数を直接設定：

```bash
export OPENAI_BASE_URL="https://your-api-endpoint.com"
export OPENAI_API_KEY="sk-your-api-key-here"
```

その後、**新しいターミナルを開く**（または `source ~/.bashrc` を実行）し、確認：

```bash
codex --version
```

> 💡 OpenAI API に直接アクセスできない地域では、`base_url` をプロキシ/リレーのアドレスに設定してください。Azure、DeepSeek、Moonshot など、すべての OpenAI API 互換インターフェースに対応しています。

---

## 📦 リリース内容

| ファイル | プラットフォーム | 説明 |
|------|----------|-------------|
| `codex-offline-packages-linux.tar.gz` | Linux x64 / WSL | 完全オフラインパッケージ（skills、jq 含む） |
| `codex-offline-packages-windows.zip` | Windows x64 | ネイティブ Windows パッケージ（skills、jq.exe、インストーラー含む） |
| `*.sha256` | - | チェックサムファイル：`sha256sum -c <file>.sha256` |

---

## 🔄 CI/CD パイプライン

```
check-version → build-linux-package ─┐
              → build-windows-package ┤→ test-release-package → create-release
                                        (ubuntu + windows デュアルプラットフォーム)
```

- **毎日のチェック**：UTC 00:00 に npm の最新版と既存の Release を比較し、新バージョンがある場合のみビルド
- **週次リビルド**：毎月曜日 UTC 01:00 にフルリビルド
- **手動トリガー**：Actions → `Download Codex Offline Packages` → Run workflow（バージョン指定/強制リビルド可能）
- **テストゲーティング**：テストジョブはクリーンな ubuntu:22.04 コンテナ（Node なし）と windows-latest で実行し、構成検証、`codex --version` アサーション、完全な非対話インストール、config.toml 検証を実施 — すべて合格しないと公開しない

ローカルの手動アップデートチェック：

```bash
bash check-update.sh              # インタラクティブ
bash check-update.sh --check-only # チェックのみ
bash check-update.sh --install    # ダウンロードしてインストール
```

---

## 🧩 同梱オフラインスキル（15 個）

ビルド時に `skills/skills-manifest.json` に従ってダウンロードされ、インストーラーによって `~/.codex/` にインストールされます：

| カテゴリ | スキル |
|----------|--------|
| **ドキュメント** | docx, pdf, pptx, xlsx |
| **デザイン** | frontend-design, algorithmic-art, canvas-design, theme-factory, web-artifacts-builder |
| **テスト** | webapp-testing (Playwright) |
| **ツール** | skill-creator |
| **エンタープライズ** | brand-guidelines, internal-comms, doc-coauthoring |
| **プラグイン** | superpowers (TDD/デバッグ/プランニングワークフローフレームワーク) |

---

## 🛠️ 高度な使い方

### インストーラースクリプトのパラメータ

| パラメータ | 説明 |
|-----------|-------------|
| `--offline-path PATH` | オフラインパッケージのパスを指定 |
| `--auto-download` | GitHub Release から自動ダウンロード |
| `--yes, -y` | すべてのプロンプトに自動で yes（完全無人） |
| `--non-interactive` | 非対話モード、デフォルト値を使用 |
| `--uninstall` | Codex と設定をアンインストール |
| `--help, -h` | ヘルプ |

### Windows インストーラーのパラメータ

| パラメータ | 説明 |
|-----------|-------------|
| `-OfflinePath <path>` | オフラインパッケージのパスを指定 |
| `-AutoDownload` | GitHub Release から自動ダウンロード |
| `-NonInteractive` | 非対話モード |
| `-Uninstall` | Codex をアンインストール |

---

## 🧪 パッケージのテスト

```bash
# Linux：構成検証 + バージョンアサーション + クリーンコンテナでのエンドツーエンドインストール
bash tests/test-linux-package.sh /path/to/codex-offline-packages 0.144.6
```

```powershell
# Windows：バイナリ検証 + インストーラー + config.toml + PATH レジストリアサーション
powershell -NoProfile -File tests\test-windows-package.ps1 `
  -PackageDir .\codex-offline-packages-windows -ExpectedVersion 0.144.6
```

---

## 🗑️ アンインストール

```bash
# Linux/macOS/WSL
bash setup-codex.sh --uninstall
```

```powershell
# Windows
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-codex.ps1 -Uninstall
```

アンインストール前に `~/.codex/` のバックアップが作成されます。

---

## 🔧 トラブルシューティング

### ネットワークに接続できない

インストーラーは各ネットワーク処理の前に 5 秒の事前チェックを行い、エラー時に即座に失敗します：
- ネットワーク/プロキシ（`HTTPS_PROXY`）を確認
- 完全オフライン：事前ダウンロード済みのオフラインパッケージを用意し、`--offline-path` を使用

### codex コマンドが見つからない

```bash
source ~/.bashrc   # または新しいターミナルを開く
```

### API 接続に失敗する

1. `~/.codex/config.toml` の `base_url` と `api_key` を確認
2. 設定した API エンドポイントへのネットワーク接続を確認
3. プロキシが必要かどうかを確認

### Node.js 環境がない

不要です。Codex は Rust でコンパイルされたスタンドアロンのネイティブバイナリ（約 280MB）で、シェルスクリプトから直接実行されます。Node.js は完全に不要です。

---

## ライセンス

元の Codex CLI のライセンスに準拠します。

---

**注**：Codex CLI は OpenAI の製品です。本プロジェクトは OpenAI と提携関係にありません。
