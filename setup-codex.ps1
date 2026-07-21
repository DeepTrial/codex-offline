<#
.SYNOPSIS
    Codex CLI offline installer for Windows.
.DESCRIPTION
    Sets up Codex CLI from codex-offline-packages-windows (standalone native
    binary — Node.js is NOT required). Creates .codex directory, writes
    config.toml, manages user PATH.
.PARAMETER OfflinePath
    Path to extracted codex-offline-packages-windows directory.
.PARAMETER AutoDownload
    Download latest Windows package from GitHub Releases.
.PARAMETER NonInteractive
    Never prompt; auto-take default answers.
.PARAMETER Uninstall
    Remove Codex configuration and PATH entry.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-codex.ps1 -OfflinePath .\codex-offline-packages-windows -NonInteractive
#>
[CmdletBinding()]
param(
    [string]$OfflinePath,
    [switch]$AutoDownload,
    [switch]$NonInteractive,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

# GitHub config
$script:GitHubRepo   = 'DeepTrial/codex-offline'
$script:GitHubApiUrl = "https://api.github.com/repos/$($script:GitHubRepo)/releases/latest"
$script:AssetName    = 'codex-offline-packages-windows.zip'

# Paths
$script:UserCodexDir = Join-Path $env:USERPROFILE '.codex'
$script:CodexToml    = Join-Path $script:UserCodexDir 'config.toml'

# Force TLS 1.2
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

# --- Logging ---
function Write-Info  { param([string]$Msg) Write-Host "[INFO] $Msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$Msg) Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-Warn  { param([string]$Msg) Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }
function Write-Err   { param([string]$Msg) Write-Host "  [ERROR] $Msg" -ForegroundColor Red }

function Write-Utf8File {
    param([string]$Path, [string]$Content)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

# --- Confirmation ---
function Confirm-Action {
    param([string]$Prompt, [string]$Default = 'n')
    $hint = if ($Default -eq 'y') { '[Y/n]' } else { '[y/N]' }
    if ($NonInteractive) {
        Write-Host "$Prompt ${hint}: $Default (auto)"
        return ($Default -eq 'y')
    }
    $answer = Read-Host "$Prompt $hint"
    if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }
    return ($answer -match '^(?i)y(es)?$')
}

# --- Network ---
function Test-Url {
    param([string]$Url, [int]$TimeoutSec = 5)
    try {
        $r = Invoke-WebRequest -Uri $Url -Method Head -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop
        return ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500)
    } catch { return $false }
}

function Assert-Network {
    param([string]$What)
    Write-Info "Checking network (5s timeout)..."
    $npmOk = Test-Url 'https://registry.npmjs.org/' 5
    $ghOk  = Test-Url 'https://api.github.com' 5
    if ($npmOk) { Write-Ok 'npm registry reachable' } else { Write-Warn 'npm registry UNREACHABLE' }
    if ($ghOk)  { Write-Ok 'GitHub reachable' }       else { Write-Warn 'GitHub UNREACHABLE' }
    if (-not ($npmOk -or $ghOk)) {
        Write-Err "Cannot ${What}: network unreachable."
        Write-Host ''
        Write-Host '  Check internet/proxy/firewall.'
        Write-Host '  Offline: .\setup-codex.ps1 -OfflinePath <path>'
        return $false
    }
    return $true
}

# --- Existing detection ---
function Get-ExistingInstallation {
    $found = @()
    $cmd = Get-Command codex -ErrorAction SilentlyContinue
    if ($cmd) { $found += "  - codex command: $($cmd.Source)" }
    if (Test-Path $script:UserCodexDir) { $found += "  - Config dir: $($script:UserCodexDir)" }
    if (Test-Path $script:CodexToml)    { $found += "  - Config file: $($script:CodexToml)" }
    return $found
}

# --- Package location ---
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
    foreach ($c in $candidates) {
        if ([string]::IsNullOrWhiteSpace($c)) { continue }
        $exe = Join-Path $c 'node_modules\@openai\codex\vendor\x86_64-pc-windows-msvc\bin\codex.exe'
        if (Test-Path $exe) { return (Resolve-Path $c).Path }
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
        $ver = & $exe --version 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "exit code $LASTEXITCODE" }
        Write-Ok "Native binary verified: $($ver.Trim()) ($([math]::Round($size/1MB)) MB)"
        return $true
    } catch {
        Write-Err "codex.exe exists but failed to run: $_"
        return $false
    }
}

# --- Auto-download ---
function Get-PackageFromGitHub {
    param([string]$DestDir)
    if (-not (Assert-Network 'download package')) { return $null }
    Write-Info "Fetching latest release from $($script:GitHubApiUrl)..."
    try {
        $release = Invoke-RestMethod -Uri $script:GitHubApiUrl -TimeoutSec 30 -Headers @{'User-Agent'='codex-offline-setup'}
    } catch {
        Write-Err "Failed to fetch release: $_"
        return $null
    }
    $asset = $release.assets | Where-Object { $_.name -eq $script:AssetName } | Select-Object -First 1
    if (-not $asset) {
        Write-Err "Asset '$($script:AssetName)' not found."
        return $null
    }
    $zipPath = Join-Path $env:TEMP $script:AssetName
    Write-Info "Downloading $($asset.browser_download_url) ..."
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -TimeoutSec 600 -UseBasicParsing
    } catch { Write-Err "Download failed: $_"; return $null }
    Write-Ok "Downloaded: $zipPath"
    Write-Info "Extracting to $DestDir ..."
    if (Test-Path $DestDir) { Remove-Item $DestDir -Recurse -Force }
    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    Expand-Archive -Path $zipPath -DestinationPath $DestDir -Force
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    $nested = Join-Path $DestDir 'codex-offline-packages-windows'
    if (Test-Path (Join-Path $nested 'node_modules\@openai\codex\vendor\x86_64-pc-windows-msvc\bin\codex.exe')) {
        return $nested
    }
    return $DestDir
}

# --- Directory ---
function New-CodexDirectories {
    foreach ($sub in @('', 'tmp', 'backups')) {
        $dir = if ($sub) { Join-Path $script:UserCodexDir $sub } else { $script:UserCodexDir }
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }
    Write-Ok "Directories created: $($script:UserCodexDir)\{tmp,backups}"
}

# --- Config ---
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
# Codex configuration (generated by setup-codex.ps1)
# Edit these values with your API credentials.

[api]
# Your OpenAI-compatible API base URL (proxy/gateway)
base_url = "YOUR_BASE_URL_HERE"
# Your API key
api_key = "YOUR_API_KEY_HERE"

# Optional: model overrides
# model = "your-model-name"

[telemetry]
enabled = false

[updates]
auto_check = false
'@
    Write-Utf8File -Path $file -Content $content
    Write-Ok 'Created config.toml with placeholder values'
}

function Write-CodexEnv {
    $file = Join-Path $script:UserCodexDir 'env.cmd'
    $content = @'
@echo off
REM Codex environment overrides — bypass onboarding, disable telemetry
set CODEX_SKIP_ONBOARDING=1
set CODEX_TELEMETRY_DISABLED=1
set DISABLE_TELEMETRY=1
'@
    Write-Utf8File -Path $file -Content $content
    Write-Ok 'Created env.cmd'
}

# --- PATH management (registry) ---
function Get-RawUserPath {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    if ($null -eq $key) { return '' }
    $val = $key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    $key.Close()
    return [string]$val
}

function Set-RawUserPath {
    param([string]$NewPath)
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    if ($null -eq $key) { $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment') }
    $key.SetValue('Path', $NewPath, 'ExpandString')
    $key.Close()
}

function Add-UserPath {
    param([string]$BinDir)
    $userPath = Get-RawUserPath
    $entries = @($userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $normalized = $BinDir.TrimEnd('\').ToLowerInvariant()
    $exists = $entries | Where-Object { $_.TrimEnd('\').ToLowerInvariant() -eq $normalized }
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
    $normalized = $BinDir.TrimEnd('\').ToLowerInvariant()
    $entries = @($userPath -split ';' | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and $_.TrimEnd('\').ToLowerInvariant() -ne $normalized
    })
    $newPath = $entries -join ';'
    if ($newPath -ne $userPath) {
        Set-RawUserPath -NewPath $newPath
        Write-Ok "Removed from user PATH: $BinDir"
    }
}

# --- Uninstall ---
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
    Write-Host 'Detected:'
    $existing | ForEach-Object { Write-Host $_ }
    Write-Host ''
    if (-not $NonInteractive) {
        if (-not (Confirm-Action 'Uninstall Codex?' 'n')) { Write-Info 'Cancelled.'; return }
    }
    if (Test-Path $script:UserCodexDir) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $backupDir = Join-Path $env:USERPROFILE ".codex-backup-$stamp"
        Copy-Item $script:UserCodexDir $backupDir -Recurse -Force
        Write-Ok "Backed up to: $backupDir"
        Remove-Item $script:UserCodexDir -Recurse -Force
        Write-Ok 'Removed .codex directory'
    }
    $userPath = Get-RawUserPath
    if ($userPath -match '@openai[\\/]codex[\\/]vendor') {
        $kept = @($userPath -split ';' | Where-Object { $_ -notmatch '@openai[\\/]codex[\\/]vendor' })
        Set-RawUserPath -NewPath ($kept -join ';')
        Write-Ok 'Removed Codex entries from PATH'
    }
    Write-Host ''
    Write-Host 'Uninstall complete. Open a NEW terminal for PATH changes.'
}

# --- Install ---
function Invoke-Install {
    Write-Host '============================================================================='
    Write-Host '  Codex Offline Deployment Script v1.0 (Windows)'
    Write-Host '============================================================================='
    Write-Host ''

    $existing = Get-ExistingInstallation
    if ($existing.Count -gt 0) {
        Write-Warn 'Detected existing Codex installation:'
        $existing | ForEach-Object { Write-Host $_ }
        Write-Host ''
        if (-not (Confirm-Action 'Continue and update?' 'y')) { Write-Info 'Exiting.'; return }
        Write-Host ''
    }

    # Step 1: Locate package
    Write-Host 'Step 1/4: Locating Codex package...'
    $packageDir = $null
    if ($AutoDownload) {
        $dest = Join-Path $script:UserCodexDir 'offline-packages-windows'
        $packageDir = Get-PackageFromGitHub -DestDir $dest
        if (-not $packageDir) { throw 'Failed to download package.' }
    } else {
        $packageDir = Find-Package
        if (-not $packageDir) {
            Write-Err 'Could not find codex-offline-packages-windows.'
            Write-Host ''
            Write-Host 'Run: .\setup-codex.ps1 -AutoDownload'
            Write-Host '  Or: .\setup-codex.ps1 -OfflinePath <path>'
            throw 'Package not found.'
        }
    }
    Write-Ok "Using package: $packageDir"

    # Step 2: Verify binary
    Write-Host 'Step 2/4: Verifying native binary (no Node.js needed)...'
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

    # Step 3: Directory + config
    Write-Host 'Step 3/4: Creating .codex directory and config...'
    New-CodexDirectories
    Write-CodexToml
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
    Write-Host '    - .codex directory (config.toml, env.cmd)'
    Write-Host '    - User PATH updated (registry)'
    Write-Host ''
    Write-Host '============================================================================='
    Write-Host '  !!! ACTION REQUIRED !!!'
    Write-Host '============================================================================='
    Write-Host ''
    Write-Host "  Edit $($script:CodexToml) with your API credentials:"
    Write-Host ''
    Write-Host '    notepad %USERPROFILE%\.codex\config.toml'
    Write-Host ''
    Write-Host '  Or set environment variables:'
    Write-Host '    set OPENAI_BASE_URL=https://your-api.example.com'
    Write-Host '    set OPENAI_API_KEY=sk-...'
    Write-Host ''
    Write-Host '============================================================================='
    Write-Host '  NEXT STEPS'
    Write-Host '============================================================================='
    Write-Host ''
    Write-Host '  1. Edit .codex\config.toml with your API key and base URL'
    Write-Host '  2. Open a NEW terminal (updated PATH)'
    Write-Host '  3. Verify: codex --version'
}

# --- Entry ---
try {
    if ($Uninstall) { Invoke-Uninstall }
    else { Invoke-Install }
    exit 0
} catch {
    Write-Host ''
    Write-Err "Setup failed: $($_.Exception.Message)"
    exit 1
}
