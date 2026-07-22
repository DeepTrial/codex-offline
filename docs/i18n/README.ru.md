[简体中文](../../README.md) | [English](./README.en.md) | [繁體中文](./README.zh-TW.md) | **Русский** | [日本語](./README.ja.md) | [한국어](./README.ko.md)

# Автономное развёртывание Codex

[![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-Enabled-blue)](.github/workflows/download-codex-packages.yml)
[![Version](https://img.shields.io/badge/version-1.0-green)](setup-codex.sh)
[![License](https://img.shields.io/badge/license-MIT-yellow)](LICENSE)

Автоматизированное автономное развёртывание Codex CLI: ежедневно извлекает последнюю версию Codex из npm, собирает **автономные пакеты для Linux и Windows**, запускает **автоматизированные тесты установки**, затем публикует в GitHub Releases.

## ✨ Возможности

- ✅ **Ежедневная автосборка**: GitHub Actions ежедневно проверяет npm на наличие новых версий, автоматически собирает и публикует
- ✅ **Двухплатформенные пакеты**: Linux x64 (`tar.gz`) + Windows x64 (`zip`, собственный установщик PowerShell)
- ✅ **Тестовый рубеж**: Каждый пакет тестируется в чистой среде (контейнер ubuntu без Node / Windows runner) с полной проверкой установки и запуска — **публикация только при успешных тестах**
- ✅ **Node.js не требуется**: Codex — самодостаточный нативный бинарник (скомпилирован на Rust), вызывается напрямую через shell-скрипт
- ✅ **Поддержка сторонних API**: Настройте `OPENAI_BASE_URL` для подключения к любому OpenAI-совместимому прокси/шлюзу API
- ✅ **Обход входа в систему**: Автоматический пропуск онбординга, отключение телеметрии
- ✅ **Автоматическая установка**: Режим `--yes` / `--non-interactive` для скриптов и CI
- ✅ **Автономные навыки/плагины**: 15 автономно совместимых навыков в комплекте (обработка документов, дизайн, тестирование и т.д.)
- ✅ **Полное удаление**: Чистое удаление с резервным копированием конфигурации

---

## 🚀 Быстрый старт

### Linux / macOS / WSL

**Вариант 1: Установка одной командой (требуется сеть)**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/DeepTrial/codex-offline/main/setup-codex.sh) --auto-download
```

**Вариант 2: Установка из автономного пакета (сеть не нужна)**

```bash
# После загрузки codex-offline-packages-linux.tar.gz из Releases:
tar -xzf codex-offline-packages-linux.tar.gz
cd codex-offline-packages
bash setup-codex.sh --yes
```

**Вариант 3: Использование локального автономного пакета**

```bash
bash setup-codex.sh --offline-path /path/to/codex-offline-packages
```

### Windows (Нативная)

1. Загрузите `codex-offline-packages-windows.zip` из [Releases](https://github.com/DeepTrial/codex-offline/releases) и распакуйте
2. Дважды щёлкните `setup-codex.bat` или выполните в PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-codex.ps1 -NonInteractive
```

Установщик проверяет нативный `codex.exe`, генерирует конфигурацию и добавляет каталог `.bin` в пользовательский PATH (идемпотентно).

---

## ⚠️ После установки (Важно)

**Для использования Codex необходимо настроить собственный API-ключ:**

```bash
# Linux/macOS/WSL
nano ~/.codex/config.toml

# Windows: откройте %USERPROFILE%\.codex\config.toml в Блокноте
```

Замените значения-заполнители:

```toml
[api]
base_url = "https://your-api-endpoint.com"
api_key = "sk-your-api-key-here"

[telemetry]
enabled = false
```

Или задайте переменные окружения напрямую:

```bash
export OPENAI_BASE_URL="https://your-api-endpoint.com"
export OPENAI_API_KEY="sk-your-api-key-here"
```

Затем **откройте новый терминал** (или выполните `source ~/.bashrc`) и проверьте:

```bash
codex --version
```

> 💡 В регионах, где прямой доступ к OpenAI API недоступен, укажите в `base_url` адрес вашего прокси/ретранслятора. Поддерживаются все OpenAI API-совместимые интерфейсы (Azure, DeepSeek, Moonshot и т.д.).

---

## 📦 Содержание релиза

| Файл | Платформа | Описание |
|------|-----------|----------|
| `codex-offline-packages-linux.tar.gz` | Linux x64 / WSL | Полный автономный пакет (включает навыки, jq) |
| `codex-offline-packages-windows.zip` | Windows x64 | Нативный пакет Windows (включает навыки, jq.exe, установщик) |
| `*.sha256` | - | Файлы контрольных сумм: `sha256sum -c <file>.sha256` |

---

## 🔄 Конвейер CI/CD

```
check-version → build-linux-package ─┐
              → build-windows-package ┤→ test-release-package → create-release
                                        (ubuntu + windows двухплатформенный)
```

- **Ежедневная проверка**: UTC 00:00 сравнивает последнюю версию npm с существующим релизом, сборка только при новой версии
- **Еженедельная пересборка**: Каждый понедельник UTC 01:00 полная пересборка
- **Ручной запуск**: Actions → `Download Codex Offline Packages` → Run workflow (можно указать версию/принудительную пересборку)
- **Тестовый рубеж**: Тестовые задания выполняются в чистых контейнерах ubuntu:22.04 (без Node) и windows-latest, выполняя проверку структуры, утверждение `codex --version`, полную неинтерактивную установку, проверку config.toml — всё должно пройти перед публикацией

Локальная ручная проверка обновлений:

```bash
bash check-update.sh              # Интерактивный режим
bash check-update.sh --check-only # Только проверка
bash check-update.sh --install    # Загрузить и установить
```

---

## 🧩 Встроенные автономные навыки (15)

Загружаются при сборке согласно `skills/skills-manifest.json`, устанавливаются в `~/.codex/` установщиком:

| Категория | Навыки |
|-----------|--------|
| **Документы** | docx, pdf, pptx, xlsx |
| **Дизайн** | frontend-design, algorithmic-art, canvas-design, theme-factory, web-artifacts-builder |
| **Тестирование** | webapp-testing (Playwright) |
| **Инструменты** | skill-creator |
| **Предприятие** | brand-guidelines, internal-comms, doc-coauthoring |
| **Плагины** | superpowers (фреймворк рабочего процесса TDD/отладки/планирования) |

---

## 🛠️ Расширенное использование

### Параметры скрипта установки

| Параметр | Описание |
|----------|----------|
| `--offline-path PATH` | Указать путь к автономному пакету |
| `--auto-download` | Автоматическая загрузка из GitHub Release |
| `--yes, -y` | Автоматический ответ «да» на все запросы (полностью автоматический режим) |
| `--non-interactive` | Неинтерактивный режим, используются значения по умолчанию |
| `--uninstall` | Удалить Codex и конфигурацию |
| `--help, -h` | Справка |

### Параметры установщика Windows

| Параметр | Описание |
|----------|----------|
| `-OfflinePath <path>` | Указать путь к автономному пакету |
| `-AutoDownload` | Автоматическая загрузка из GitHub Release |
| `-NonInteractive` | Неинтерактивный режим |
| `-Uninstall` | Удалить Codex |

---

## 🧪 Тестирование пакетов

```bash
# Linux: проверка структуры + утверждение версии + сквозная установка в чистом контейнере
bash tests/test-linux-package.sh /path/to/codex-offline-packages 0.144.6
```

```powershell
# Windows: проверка бинарника + установщик + config.toml + утверждение PATH в реестре
powershell -NoProfile -File tests\test-windows-package.ps1 `
  -PackageDir .\codex-offline-packages-windows -ExpectedVersion 0.144.6
```

---

## 🗑️ Удаление

```bash
# Linux/macOS/WSL
bash setup-codex.sh --uninstall
```

```powershell
# Windows
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-codex.ps1 -Uninstall
```

Перед удалением создаётся резервная копия `~/.codex/`.

---

## 🔧 Устранение неполадок

### Сеть недоступна

Установщик выполняет 5-секундную предварительную проверку перед любым сетевым шагом, быстро завершаясь с ошибкой:
- Проверьте сеть/прокси (`HTTPS_PROXY`)
- Полностью автономный режим: убедитесь, что предварительно загруженный автономный пакет доступен, используйте `--offline-path`

### Команда codex не найдена

```bash
source ~/.bashrc   # или откройте новый терминал
```

### Ошибка подключения к API

1. Проверьте `base_url` и `api_key` в `~/.codex/config.toml`
2. Проверьте сетевую доступность настроенной конечной точки API
3. Уточните, нужен ли прокси

### Нет среды Node.js

Не требуется. Codex — самодостаточный нативный бинарник, скомпилированный на Rust (~280 МБ), вызываемый напрямую через shell-скрипт. Node.js совершенно не нужен.

---

## Лицензия

Совпадает с лицензией оригинального Codex CLI.

---

**Примечание**: Codex CLI — продукт OpenAI. Этот проект не связан с OpenAI.
