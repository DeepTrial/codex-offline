[简体中文](../../README.md) | [English](./README.en.md) | [繁體中文](./README.zh-TW.md) | [Русский](./README.ru.md) | [日本語](./README.ja.md) | **한국어**

# Codex 오프라인 배포

[![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-Enabled-blue)](.github/workflows/download-codex-packages.yml)
[![Version](https://img.shields.io/badge/version-1.0-green)](setup-codex.sh)
[![License](https://img.shields.io/badge/license-MIT-yellow)](LICENSE)

자동화된 Codex CLI 오프라인 배포: 매일 npm에서 최신 Codex를 가져와 **Linux 및 Windows 오프라인 패키지**를 빌드하고, **자동 설치 테스트**를 실행한 후 GitHub Releases에 게시합니다.

## ✨ 기능

- ✅ **매일 자동 빌드**: GitHub Actions가 매일 npm에서 새 버전을 확인하고, 자동으로 빌드 및 게시
- ✅ **듀얼 플랫폼 패키지**: Linux x64 (`tar.gz`) + Windows x64 (`zip`, 네이티브 PowerShell 설치 프로그램)
- ✅ **테스트 게이트**: 모든 패키지는 깨끗한 환경(Node가 없는 ubuntu 컨테이너 / Windows 러너)에서 전체 설치 + 시작 검증으로 테스트됩니다 — **테스트 실패 시 게시하지 않음**
- ✅ **Node.js 불필요**: Codex는 독립 실행형 네이티브 바이너리(Rust 컴파일)이며, 셸 스크립트를 통해 직접 호출됩니다
- ✅ **서드파티 API 지원**: `OPENAI_BASE_URL`을 구성하여 모든 OpenAI 호환 API 프록시/게이트웨이를 가리키도록 설정
- ✅ **로그인 우회**: 온보딩 자동 건너뛰기, 원격 분석 비활성화
- ✅ **무인 설치**: 스크립트 및 CI를 위한 `--yes` / `--non-interactive` 모드
- ✅ **오프라인 스킬/플러그인**: 15개의 오프라인 호환 스킬 포함 (문서 처리, 디자인, 테스트 등)
- ✅ **전체 제거**: 설정 백업과 함께 깨끗한 제거

---

## 🚀 빠른 시작

### Linux / macOS / WSL

**옵션 1: 원라인 설치 (네트워크 필요)**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/DeepTrial/codex-offline/main/setup-codex.sh) --auto-download
```

**옵션 2: 오프라인 패키지 설치 (네트워크 불필요)**

```bash
# Releases에서 codex-offline-packages-linux.tar.gz를 다운로드한 후:
tar -xzf codex-offline-packages-linux.tar.gz
cd codex-offline-packages
bash setup-codex.sh --yes
```

**옵션 3: 로컬 오프라인 패키지 사용**

```bash
bash setup-codex.sh --offline-path /path/to/codex-offline-packages
```

### Windows (네이티브)

1. [Releases](https://github.com/DeepTrial/codex-offline/releases)에서 `codex-offline-packages-windows.zip`을 다운로드하고 압축 해제
2. `setup-codex.bat`을 더블클릭하거나, PowerShell에서 실행:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-codex.ps1 -NonInteractive
```

설치 프로그램은 네이티브 `codex.exe`의 유효성을 검사하고, 설정을 생성하며, `.bin` 디렉터리를 사용자 PATH에 추가합니다(멱등성 유지).

---

## ⚠️ 설치 후 (중요)

**Codex를 사용하려면 자신의 API 키를 구성해야 합니다:**

```bash
# Linux/macOS/WSL
nano ~/.codex/config.toml

# Windows: 메모장에서 %USERPROFILE%\.codex\config.toml 열기
```

플레이스홀더 값을 교체하세요:

```toml
[api]
base_url = "https://your-api-endpoint.com"
api_key = "sk-your-api-key-here"

[telemetry]
enabled = false
```

또는 환경 변수를 직접 설정하세요:

```bash
export OPENAI_BASE_URL="https://your-api-endpoint.com"
export OPENAI_API_KEY="sk-your-api-key-here"
```

그런 다음 **새 터미널을 열고** (또는 `source ~/.bashrc` 실행), 확인하세요:

```bash
codex --version
```

> 💡 OpenAI API에 직접 접근할 수 없는 지역에서는 `base_url`을 프록시/릴레이 주소로 설정하세요. 모든 OpenAI API 호환 인터페이스(Azure, DeepSeek, Moonshot 등)를 지원합니다.

---

## 📦 릴리스 내용물

| 파일 | 플랫폼 | 설명 |
|------|----------|-------------|
| `codex-offline-packages-linux.tar.gz` | Linux x64 / WSL | 전체 오프라인 패키지 (스킬, jq 포함) |
| `codex-offline-packages-windows.zip` | Windows x64 | 네이티브 Windows 패키지 (스킬, jq.exe, 설치 프로그램 포함) |
| `*.sha256` | - | 체크섬 파일: `sha256sum -c <file>.sha256` |

---

## 🔄 CI/CD 파이프라인

```
check-version → build-linux-package ─┐
              → build-windows-package ┤→ test-release-package → create-release
                                        (ubuntu + windows 듀얼 플랫폼)
```

- **매일 확인**: UTC 00:00에 npm 최신 버전과 기존 릴리스를 비교하여, 새 버전이 있을 때만 빌드
- **주간 리빌드**: 매주 월요일 UTC 01:00 전체 리빌드
- **수동 트리거**: Actions → `Download Codex Offline Packages` → Run workflow (버전 지정/강제 리빌드 가능)
- **테스트 게이트**: 테스트 작업은 깨끗한 ubuntu:22.04 컨테이너(Node 없음) 및 windows-latest에서 실행되며, 구조 검증, `codex --version` 확인, 전체 무인 설치, config.toml 검증을 수행합니다 — 게시 전 모두 통과해야 함

로컬 수동 업데이트 확인:

```bash
bash check-update.sh              # 대화형
bash check-update.sh --check-only # 확인만
bash check-update.sh --install    # 다운로드 및 설치
```

---

## 🧩 번들 오프라인 스킬 (15개)

빌드 시 `skills/skills-manifest.json`에 따라 다운로드되고, 설치 프로그램에 의해 `~/.codex/`에 설치됩니다:

| 카테고리 | 스킬 |
|----------|--------|
| **문서** | docx, pdf, pptx, xlsx |
| **디자인** | frontend-design, algorithmic-art, canvas-design, theme-factory, web-artifacts-builder |
| **테스트** | webapp-testing (Playwright) |
| **도구** | skill-creator |
| **엔터프라이즈** | brand-guidelines, internal-comms, doc-coauthoring |
| **플러그인** | superpowers (TDD/디버깅/계획 워크플로우 프레임워크) |

---

## 🛠️ 고급 사용법

### 설치 프로그램 스크립트 매개변수

| 매개변수 | 설명 |
|-----------|-------------|
| `--offline-path PATH` | 오프라인 패키지 경로 지정 |
| `--auto-download` | GitHub Release에서 자동 다운로드 |
| `--yes, -y` | 모든 프롬프트에 자동 예 (완전 무인) |
| `--non-interactive` | 비대화형 모드, 기본값 사용 |
| `--uninstall` | Codex 및 설정 제거 |
| `--help, -h` | 도움말 |

### Windows 설치 프로그램 매개변수

| 매개변수 | 설명 |
|-----------|-------------|
| `-OfflinePath <path>` | 오프라인 패키지 경로 지정 |
| `-AutoDownload` | GitHub Release에서 자동 다운로드 |
| `-NonInteractive` | 비대화형 모드 |
| `-Uninstall` | Codex 제거 |

---

## 🧪 패키지 테스트

```bash
# Linux: 구조 검증 + 버전 확인 + 깨끗한 컨테이너 엔드투엔드 설치
bash tests/test-linux-package.sh /path/to/codex-offline-packages 0.144.6
```

```powershell
# Windows: 바이너리 검증 + 설치 프로그램 + config.toml + PATH 레지스트리 확인
powershell -NoProfile -File tests\test-windows-package.ps1 `
  -PackageDir .\codex-offline-packages-windows -ExpectedVersion 0.144.6
```

---

## 🗑️ 제거

```bash
# Linux/macOS/WSL
bash setup-codex.sh --uninstall
```

```powershell
# Windows
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-codex.ps1 -Uninstall
```

제거 전 `~/.codex/`의 백업이 생성됩니다.

---

## 🔧 문제 해결

### 네트워크 연결 불가

설치 프로그램은 모든 네트워크 단계 전에 5초 사전 확인을 수행하며, 오류 시 빠르게 실패합니다:
- 네트워크/프록시 확인 (`HTTPS_PROXY`)
- 완전 오프라인: 사전 다운로드한 오프라인 패키지가 있는지 확인하고, `--offline-path` 사용

### Codex 명령을 찾을 수 없음

```bash
source ~/.bashrc   # 또는 새 터미널 열기
```

### API 연결 실패

1. `~/.codex/config.toml`에서 `base_url` 및 `api_key` 확인
2. 구성된 API 엔드포인트에 대한 네트워크 연결 확인
3. 프록시가 필요한지 확인

### Node.js 환경 없음

필요하지 않습니다. Codex는 Rust로 컴파일된 독립 실행형 네이티브 바이너리(~280MB)이며, 셸 스크립트를 통해 직접 호출됩니다. Node.js는 완전히 불필요합니다.

---

## 라이선스

원본 Codex CLI 라이선스와 동일합니다.

---

**참고**: Codex CLI는 OpenAI 제품입니다. 이 프로젝트는 OpenAI와 관련이 없습니다.
