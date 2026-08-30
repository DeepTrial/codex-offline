<#
.SYNOPSIS
    Codex CLI offline installer for Windows.
.DESCRIPTION
    Sets up Codex CLI from codex-offline-packages-windows (standalone native
    binary — Node.js is NOT required). Creates .codex directory, writes
    config.toml (official Codex CLI format), manages user PATH.
.PARAMETER OfflinePath
    Path to extracted codex-offline-packages-windows directory.
.PARAMETER AutoDownload
    Download latest Windows package from GitHub Releases.
.PARAMETER NonInteractive
    Never prompt; auto-take default answers.
.PARAMETER Uninstall
    Remove Codex configuration and PATH entry.
.PARAMETER ConfigOnly
    Only (re)generate configuration files; skip binary/PATH setup.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-codex.ps1 -OfflinePath .\codex-offline-packages-windows -NonInteractive
#>
[CmdletBinding()]
param(
    [string]$OfflinePath,
    [switch]$AutoDownload,
    [switch]$NonInteractive,
    [switch]$Uninstall,
    [switch]$ConfigOnly
)

$ErrorActionPreference = 'Stop'
$script:ExitCode = 0

# GitHub Release configuration
$script:GitHubRepo   = 'DeepTrial/codex-offline'
$script:GitHubApiUrl = "https://api.github.com/repos/$($script:GitHubRepo)/releases/latest"
$script:AssetName    = 'codex-offline-packages-windows.zip'

# Paths
$script:UserCodexDir = Join-Path $env:USERPROFILE '.codex'
$script:CodexToml    = Join-Path $script:UserCodexDir 'config.toml'

# Force TLS 1.2 for Windows PowerShell 5.1 (GitHub requires it)
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch { }

# ---------------------------------------------------------------------------
# Logging helpers (colored)
# ---------------------------------------------------------------------------
function Write-Info  { param([string]$Msg) Write-Host "[INFO] $Msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$Msg) Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-Warn  { param([string]$Msg) Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }
function Write-Err   { param([string]$Msg) Write-Host "  [ERROR] $Msg" -ForegroundColor Red }

# Write UTF-8 WITHOUT BOM (byte-level parity with the bash installer)
function Write-Utf8File {
    param([string]$Path, [string]$Content)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

# ---------------------------------------------------------------------------
# Confirmation helper: -NonInteractive takes the default and prints it
# ---------------------------------------------------------------------------
function Confirm-Action {
    param(
        [string]$Prompt,
        [string]$Default = 'n'
    )
    $hint = if ($Default -eq 'y') { '[Y/n]' } else { '[y/N]' }
    if ($NonInteractive) {
        Write-Host "$Prompt ${hint}: $Default (auto)"
        return ($Default -eq 'y')
    }
    $answer = Read-Host "$Prompt $hint"
    if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }
    return ($answer -match '^(?i)y(es)?$')
}

# ---------------------------------------------------------------------------
# Network helpers
# ---------------------------------------------------------------------------
function Test-Url {
    param(
        [string]$Url,
        [int]$TimeoutSec = 5
    )
    try {
        $response = Invoke-WebRequest -Uri $Url -Method Head -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop
        return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500)
    } catch {
        return $false
    }
}

function Assert-Network {
    param([string]$What)
    Write-Info "Checking network connectivity (5s timeout)..."
    $npmOk = Test-Url -Url 'https://registry.npmjs.org/' -TimeoutSec 5
    $ghOk  = Test-Url -Url 'https://api.github.com'      -TimeoutSec 5
    if ($npmOk) { Write-Ok 'npm registry reachable' } else { Write-Warn 'npm registry UNREACHABLE' }
    if ($ghOk)  { Write-Ok 'GitHub reachable' }       else { Write-Warn 'GitHub UNREACHABLE' }
    if (-not ($npmOk -or $ghOk)) {
        Write-Err "Cannot ${What}: network is unreachable."
        Write-Host ''
        Write-Host 'Troubleshooting suggestions:'
        Write-Host '  - Check your internet connection / proxy / firewall settings'
        Write-Host '  - Behind a proxy? set HTTPS_PROXY env var or configure system proxy'
        Write-Host '  - Fully offline? use a pre-downloaded package:'
        Write-Host '      .\setup-codex.ps1 -OfflinePath <path\to\codex-offline-packages-windows>'
        return $false
    }
    Write-Ok 'Network available'
    return $true
}

# ---------------------------------------------------------------------------
# Existing installation detection
# ---------------------------------------------------------------------------
function Get-ExistingInstallation {
    $found = @()
    $codexCmd = Get-Command codex -ErrorAction SilentlyContinue
    if ($codexCmd) { $found += "  - codex command: $($codexCmd.Source)" }
    if (Test-Path $script:UserCodexDir) { $found += "  - Config directory: $($script:UserCodexDir)" }
    if (Test-Path $script:CodexToml)    { $found += "  - Config file: $($script:CodexToml)" }
    return $found
}

# ---------------------------------------------------------------------------
# Package location & validation
# ---------------------------------------------------------------------------
function Find-Package {
    $candidates = @()
    if ($OfflinePath) { $candidates += $OfflinePath }
    $candidates += @(
        $PSScriptRoot,
        (Join-Path $PSScriptRoot 'codex-offline-packages-windows'),
        (Join-Path (Split-Path $PSScriptRoot -Parent) 'codex-offline-packages-windows'),
        (Join-Path $env:USERPROFILE 'codex-offline-packages-windows'),
        (Join-Path $script:UserCodexDir 'offline-packages-windows')
    )
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $exe = Join-Path $candidate 'node_modules\@openai\codex\vendor\x86_64-pc-windows-msvc\bin\codex.exe'
        if (Test-Path $exe) {
            return (Resolve-Path $candidate).Path
        }
    }
    return $null
}

function Test-NativeBinary {
    param([string]$PackageDir)
    $exe = Join-Path $PackageDir 'node_modules\@openai\codex\vendor\x86_64-pc-windows-msvc\bin\codex.exe'
    if (-not (Test-Path $exe)) {
        Write-Err "Native binary not found: $exe"
        return $false
    }
    $size = (Get-Item $exe).Length
    if ($size -lt 50MB) {
        Write-Err "codex.exe is a stub ($size bytes), not a real Windows binary."
        return $false
    }
    try {
        $versionOutput = & $exe --version 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "exit code $LASTEXITCODE" }
        Write-Ok "Native binary verified: $($versionOutput.Trim()) ($([math]::Round($size/1MB)) MB)"
        return $true
    } catch {
        Write-Err "codex.exe exists but failed to run: $_"
        return $false
    }
}

# ---------------------------------------------------------------------------
# Auto-download from GitHub Releases
# ---------------------------------------------------------------------------
function Get-PackageFromGitHub {
    param([string]$DestinationDir)

    if (-not (Assert-Network 'download the offline package')) { return $null }

    Write-Info "Fetching latest release info from $($script:GitHubApiUrl)..."
    try {
        $release = Invoke-RestMethod -Uri $script:GitHubApiUrl -TimeoutSec 30 -Headers @{ 'User-Agent' = 'codex-offline-setup' }
    } catch {
        Write-Err "Failed to fetch release info: $_"
        return $null
    }

    $asset = $release.assets | Where-Object { $_.name -eq $script:AssetName } | Select-Object -First 1
    if (-not $asset) {
        Write-Err "Asset '$($script:AssetName)' not found in the latest release ($($release.tag_name))."
        return $null
    }

    $zipPath = Join-Path $env:TEMP $script:AssetName
    Write-Info "Downloading $($asset.browser_download_url) ..."
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -TimeoutSec 600 -UseBasicParsing
    } catch {
        Write-Err "Download failed: $_"
        return $null
    }
    Write-Ok "Downloaded: $zipPath"

    Write-Info "Extracting to $DestinationDir ..."
    if (Test-Path $DestinationDir) { Remove-Item $DestinationDir -Recurse -Force }
    New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    try {
        Expand-Archive -Path $zipPath -DestinationPath $DestinationDir -Force
    } catch {
        Write-Err "Extraction failed: $_"
        return $null
    }
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

    $nested = Join-Path $DestinationDir 'codex-offline-packages-windows'
    if (Test-Path (Join-Path $nested 'node_modules\@openai\codex\vendor\x86_64-pc-windows-msvc\bin\codex.exe')) {
        return $nested
    }
    return $DestinationDir
}

# ---------------------------------------------------------------------------
# Directory structure
# ---------------------------------------------------------------------------
function New-CodexDirectories {
    foreach ($sub in @('', 'tmp', 'backups')) {
        $dir = if ($sub) { Join-Path $script:UserCodexDir $sub } else { $script:UserCodexDir }
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }
    Write-Ok "Directories created: $($script:UserCodexDir)\{tmp,backups}"
}

# ---------------------------------------------------------------------------
# Configuration file generators (official Codex CLI format)
# ---------------------------------------------------------------------------
function Backup-IfExists {
    param([string]$FilePath)
    if (Test-Path $FilePath) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $backupName = "$(Split-Path $FilePath -Leaf).backup.$stamp"
        $backupPath = Join-Path (Join-Path $script:UserCodexDir 'backups') $backupName
        Copy-Item $FilePath $backupPath -Force
        Write-Warn "$(Split-Path $FilePath -Leaf) already exists. Backed up to backups\$backupName"
        return $true
    }
    return $false
}

function Write-CodexToml {
    $file = $script:CodexToml
    if (Backup-IfExists $file) { return }
    $content = @'
#:schema https://developers.openai.com/codex/config-schema.json
# Codex configuration (generated by setup-codex.ps1)
# Official Codex CLI config format — edit with your API credentials.

# Default model (change to your provider's model ID)
model = "gpt-5"

# Provider ID — must match a [model_providers.XXX] table name below
model_provider = "custom"

# Approval policy: never / on-request / suggest
approval_policy = "on-request"

# Sandbox mode for file operations
sandbox_mode = "workspace-write"

# Store credentials in file (required for auth.json to work)
cli_auth_credentials_store = "file"

[model_providers.custom]
name = "Custom API Provider"
# Your OpenAI-compatible API base URL (proxy / gateway / third-party)
base_url = "YOUR_BASE_URL_HERE"
# Protocol: "responses" for OpenAI Responses API, "chat_completions" for Chat Completions API
wire_api = "responses"

# --- API Key configuration (choose ONE method) ---

# Method A (RECOMMENDED): Read API key from environment variable.
# Set the environment variable before running codex, e.g.:
#   $env:OPENAI_API_KEY = "sk-..."
requires_openai_auth = false
env_key = "OPENAI_API_KEY"

# Method B: Use auth.json for key storage (see .codex\auth.json).
# Uncomment the line below and comment out the two lines above:
# requires_openai_auth = true

# Method C (NOT RECOMMENDED): Hard-code key in this file.
# Only for fully automated / air-gapped deployments:
# experimental_bearer_token = "YOUR_API_KEY_HERE"
'@
    Write-Utf8File -Path $file -Content $content
    Write-Ok 'Created config.toml with placeholder values (official Codex CLI format)'
}

function Write-AuthJson {
    $file = Join-Path $script:UserCodexDir 'auth.json'
    if (Backup-IfExists $file) { return }
    $content = @'
{
  "OPENAI_API_KEY": "YOUR_API_KEY_HERE"
}
'@
    Write-Utf8File -Path $file -Content $content
    Write-Ok 'Created auth.json with placeholder key (Method B: file-based auth)'
}

function Write-CodexEnv {
    $file = Join-Path $script:UserCodexDir 'env.cmd'
    $content = @'
@echo off
REM Codex environment overrides — disable telemetry
set CODEX_TELEMETRY_DISABLED=1
set DISABLE_TELEMETRY=1
'@
    Write-Utf8File -Path $file -Content $content
    Write-Ok 'Created env.cmd'
}

# ---------------------------------------------------------------------------
# User PATH management (registry, idempotent)
# ---------------------------------------------------------------------------
function Get-RawUserPath {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    if ($null -eq $key) { return '' }
    $value = $key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    $key.Close()
    if ($null -eq $value) { return '' }
    return [string]$value
}

function Set-RawUserPath {
    param([string]$NewPath)
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    if ($null -eq $key) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
    }
    $key.SetValue('Path', $NewPath, 'ExpandString')
    $key.Close()
}

function Add-UserPath {
    param([string]$BinDir)
    $userPath = Get-RawUserPath
    $entries = @($userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $normalizedTarget = $BinDir.TrimEnd('\').ToLowerInvariant()
    $exists = $entries | Where-Object { $_.TrimEnd('\').ToLowerInvariant() -eq $normalizedTarget }
    if ($exists) {
        Write-Ok "PATH already contains: $BinDir"
    } else {
        $newPath = (@($entries) + $BinDir) -join ';'
        Set-RawUserPath -NewPath $newPath
        Write-Ok "Added to user PATH: $BinDir"
    }
    if (($env:Path -split ';') -notcontains $BinDir) {
        $env:Path = "$BinDir;$env:Path"
    }
}

function Remove-UserPath {
    param([string]$BinDir)
    $userPath = Get-RawUserPath
    if ([string]::IsNullOrWhiteSpace($userPath)) { return }
    $normalizedTarget = $BinDir.TrimEnd('\').ToLowerInvariant()
    $entries = @($userPath -split ';' | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and $_.TrimEnd('\').ToLowerInvariant() -ne $normalizedTarget
    })
    $newPath = $entries -join ';'
    if ($newPath -ne $userPath) {
        Set-RawUserPath -NewPath $newPath
        Write-Ok "Removed from user PATH: $BinDir"
    }
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------
function Invoke-Uninstall {
    Write-Host '============================================================================='
    Write-Host '  Codex Uninstaller (Windows)'
    Write-Host '============================================================================='
    Write-Host ''

    $existing = Get-ExistingInstallation
    if ($existing.Count -eq 0) {
        Write-Warn 'No existing Codex installation detected.'
        return
    }
    Write-Host 'Detected existing installation at:'
    $existing | ForEach-Object { Write-Host $_ }
    Write-Host ''

    if (-not $NonInteractive) {
        if (-not (Confirm-Action 'Are you sure you want to uninstall Codex?' 'n')) {
            Write-Info 'Uninstall cancelled.'
            return
        }
    } else {
        Write-Host 'Are you sure you want to uninstall Codex? [y/N]: y (auto, -NonInteractive)'
    }

    # Backup configuration first
    if (Test-Path $script:UserCodexDir) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $backupDir = Join-Path $env:USERPROFILE ".codex-backup-$stamp"
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Copy-Item $script:UserCodexDir (Join-Path $backupDir '.codex') -Recurse -Force
        Write-Ok "Configuration backed up to: $backupDir"
    }

    # Remove PATH entries pointing into any offline package
    $userPath = Get-RawUserPath
    if (-not [string]::IsNullOrWhiteSpace($userPath)) {
        $kept = @($userPath -split ';' | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch '@openai[\\/]codex[\\/]vendor'
        })
        if (($kept -join ';') -ne $userPath) {
            Set-RawUserPath -NewPath ($kept -join ';')
            Write-Ok 'Removed Codex entries from user PATH'
        }
    }

    # Remove configuration
    if (Test-Path $script:UserCodexDir) { Remove-Item $script:UserCodexDir -Recurse -Force; Write-Ok 'Removed .codex directory' }

    Write-Host ''
    Write-Host '============================================================================='
    Write-Host '  Uninstallation Complete'
    Write-Host '============================================================================='
    Write-Host ''
    Write-Host 'Open a NEW terminal for the PATH change to take effect.'
}

# ---------------------------------------------------------------------------
# Config-only mode
# ---------------------------------------------------------------------------
function Invoke-ConfigOnly {
    Write-Host '============================================================================='
    Write-Host '  Configuration Only Mode'
    Write-Host '============================================================================='
    Write-Host ''

    New-CodexDirectories
    Write-CodexToml
    Write-AuthJson
    Write-CodexEnv

    Write-Host ''
    Write-Host '  Generated files:'
    Write-Host '    - .codex\config.toml  (official Codex CLI format)'
    Write-Host '    - .codex\auth.json    (Method B: file-based API key)'
    Write-Host '    - .codex\env.cmd      (telemetry disable)'
    Write-Host ''
    Write-Host "  IMPORTANT: Edit $($script:UserCodexDir)\config.toml with your API endpoint."
    Write-Host ''
    Write-Host '  Three ways to provide your API key:'
    Write-Host ''
    Write-Host '  Method A (Recommended) — Environment variable:'
    Write-Host '    $env:OPENAI_API_KEY = "sk-..."'
    Write-Host ''
    Write-Host '  Method B — File-based (auth.json):'
    Write-Host '    Edit .codex\auth.json with your key, then set requires_openai_auth=true in config.toml'
    Write-Host ''
    Write-Host '  Method C — Inline (not recommended for shared systems):'
    Write-Host '    Set experimental_bearer_token in config.toml'
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
function Invoke-Install {
    Write-Host '============================================================================='
    Write-Host '  Codex Offline Deployment Script v2.0 (Windows)'
    Write-Host '============================================================================='
    Write-Host ''

    $existing = Get-ExistingInstallation
    if ($existing.Count -gt 0) {
        Write-Warn 'Detected existing Codex installation:'
        $existing | ForEach-Object { Write-Host $_ }
        Write-Host ''
        if (-not (Confirm-Action 'Continue and update the existing installation?' 'y')) {
            Write-Info 'Exiting. No changes made.'
            return
        }
        Write-Host ''
    }

    # Step 1: locate / download the package
    Write-Host 'Step 1/4: Locating Codex package...'
    $packageDir = $null
    if ($AutoDownload) {
        $dest = Join-Path $script:UserCodexDir 'offline-packages-windows'
        $packageDir = Get-PackageFromGitHub -DestinationDir $dest
        if (-not $packageDir) {
            throw 'Failed to download the offline package.'
        }
    } else {
        $packageDir = Find-Package
        if (-not $packageDir) {
            Write-Err 'Could not find a valid codex-offline-packages-windows package.'
            Write-Host ''
            Write-Host 'Searched: -OfflinePath argument, script directory, and user profile.'
            Write-Host 'Run one of:'
            Write-Host '  .\setup-codex.ps1 -OfflinePath <path\to\codex-offline-packages-windows>'
            Write-Host '  .\setup-codex.ps1 -AutoDownload'
            throw 'Package not found.'
        }
    }
    Write-Ok "Using package: $packageDir"

    # Step 2: validate the native binary
    Write-Host 'Step 2/4: Verifying native binary (Node.js not required)...'
    if (-not (Test-NativeBinary -PackageDir $packageDir)) {
        throw 'Native binary validation failed.'
    }

    # Also verify codex-code-mode-host exists
    $hostBin = Join-Path $packageDir 'node_modules\@openai\codex\vendor\x86_64-pc-windows-msvc\bin\codex-code-mode-host.exe'
    if (Test-Path $hostBin) {
        Write-Ok "codex-code-mode-host present ($([math]::Round((Get-Item $hostBin).Length/1MB)) MB)"
    } else {
        Write-Warn "codex-code-mode-host not found (some features may be unavailable)"
    }

    # Step 3: directory structure + config
    Write-Host 'Step 3/4: Creating .codex directory and config...'
    New-CodexDirectories
    Write-CodexToml
    Write-AuthJson
    Write-CodexEnv

    # Step 4: PATH
    Write-Host 'Step 4/4: Updating user PATH...'
    $binDir = Join-Path $packageDir 'node_modules\.bin'
    # Create .bin launcher directory with a batch wrapper
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    $nativeExe = Join-Path $packageDir 'node_modules\@openai\codex\vendor\x86_64-pc-windows-msvc\bin\codex.exe'
    # Batch wrapper: calls native codex.exe directly (no Node.js)
    $wrapperBatch = Join-Path $binDir 'codex.bat'
    @"
@echo off
REM Codex batch wrapper — calls native binary directly. No Node.js.
"$nativeExe" %*
"@ | Out-File -FilePath $wrapperBatch -Encoding ascii
    Write-Ok "Created batch wrapper: $wrapperBatch"

    Add-UserPath -BinDir $binDir

    Write-Host ''
    Write-Host '============================================================================='
    Write-Host '  SETUP COMPLETE'
    Write-Host '============================================================================='
    Write-Host ''
    Write-Host '  Configured:'
    Write-Host '    - Native codex binary (standalone, Node.js NOT required)'
    Write-Host "    - Package at: $packageDir"
    Write-Host '    - .codex directory (config.toml, auth.json, env.cmd)'
    Write-Host '    - User PATH updated (registry)'
    Write-Host ''
    Write-Host '============================================================================='
    Write-Host '  !!! ACTION REQUIRED !!!'
    Write-Host '============================================================================='
    Write-Host ''
    Write-Host "  Edit $($script:UserCodexDir)\config.toml with your API endpoint:"
    Write-Host ''
    Write-Host '    notepad %USERPROFILE%\.codex\config.toml'
    Write-Host ''
    Write-Host '  Replace YOUR_BASE_URL_HERE with your provider'"'"'s base URL, e.g.:'
    Write-Host '    base_url = "https://api.example.com/v1"'
    Write-Host ''
    Write-Host '  Then provide your API key using ONE of these methods:'
    Write-Host ''
    Write-Host '  Method A (Recommended) — Environment variable:'
    Write-Host '    $env:OPENAI_API_KEY = "sk-..."'
    Write-Host ''
    Write-Host '  Method B — File-based (auth.json):'
    Write-Host '    Edit .codex\auth.json with your key, then set requires_openai_auth=true in config.toml'
    Write-Host ''
    Write-Host '  Method C — Inline (not recommended for shared systems):'
    Write-Host '    Set experimental_bearer_token in config.toml'
    Write-Host ''
    Write-Host '============================================================================='
    Write-Host '  NEXT STEPS'
    Write-Host '============================================================================='
    Write-Host ''
    Write-Host '  1. Edit .codex\config.toml with your API endpoint and key'
    Write-Host '  2. Open a NEW terminal (so the updated PATH is loaded)'
    Write-Host '  3. Verify: codex --version'
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
try {
    if ($Uninstall) {
        Invoke-Uninstall
    } elseif ($ConfigOnly) {
        Invoke-ConfigOnly
    } else {
        Invoke-Install
    }
    exit 0
} catch {
    Write-Host ''
    Write-Err "Setup failed: $($_.Exception.Message)"
    exit 1
}
