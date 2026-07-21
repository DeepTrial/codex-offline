<#
.SYNOPSIS
    Windows codex offline package end-to-end test.
.DESCRIPTION
    Verifies the built codex-offline-packages-windows directory:
      1. Structure: real native PE binary (>50MB), setup scripts present
      2. codex.exe --version prints expected version
      3. setup-codex.ps1 -OfflinePath <pkg> -NonInteractive succeeds
      4. %USERPROFILE%\.codex\config.toml exists afterward
      5. Package bin directory added to user PATH (registry)
.PARAMETER PackageDir
    Path to extracted codex-offline-packages-windows directory.
.PARAMETER ExpectedVersion
    Version string expected in codex.exe --version output.
.EXAMPLE
    powershell -NoProfile -File tests\test-windows-package.ps1 -PackageDir .\codex-offline-packages-windows -ExpectedVersion 0.144.6
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$PackageDir,
    [Parameter(Mandatory=$true)][string]$ExpectedVersion
)

$ErrorActionPreference = 'Stop'

function Fail([string]$M) { Write-Host "[FAIL] $M" -ForegroundColor Red; exit 1 }
function Ok([string]$M)   { Write-Host "  [OK] $M" -ForegroundColor Green }
function Info([string]$M) { Write-Host "[INFO] $M" -ForegroundColor Cyan }

$PackageDir = (Resolve-Path $PackageDir).Path

Write-Host '======================================================================'
Write-Host '  Windows Codex package test'
Write-Host "  Package: $PackageDir"
Write-Host "  Expect:  v$ExpectedVersion"
Write-Host '======================================================================'

# ---------------------------------------------------------------------------
# 1. Structure assertions
# ---------------------------------------------------------------------------
Info 'Checking package structure...'

$exe = Join-Path $PackageDir 'node_modules\@openai\codex\vendor\x86_64-pc-windows-msvc\bin\codex.exe'
if (-not (Test-Path $exe)) { Fail 'codex.exe missing' }
$size = (Get-Item $exe).Length
if ($size -le 50MB) { Fail "codex.exe is only $size bytes (<= 50MB) — looks like a stub" }
Ok "codex.exe is real ($size bytes)"

$ps1 = Join-Path $PackageDir 'setup-codex.ps1'
$bat = Join-Path $PackageDir 'setup-codex.bat'
if (-not (Test-Path $ps1)) { Fail 'setup-codex.ps1 missing' }
if (-not (Test-Path $bat)) { Fail 'setup-codex.bat missing' }
Ok 'setup scripts present'

$info = Join-Path $PackageDir 'package-info.json'
if (-not (Test-Path $info)) { Fail 'package-info.json missing' }
Ok 'package-info.json present'

# ---------------------------------------------------------------------------
# 2. Direct version check
# ---------------------------------------------------------------------------
Info 'Running codex.exe --version ...'
$out = & $exe --version 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Fail "codex.exe --version exited $LASTEXITCODE`: $out" }
Write-Host "    output: $($out.Trim())"
if ($out -notmatch [regex]::Escape($ExpectedVersion)) {
    Fail "version output does not contain expected version $ExpectedVersion"
}
Ok 'version check passed'

# ---------------------------------------------------------------------------
# 3. Non-interactive install
# ---------------------------------------------------------------------------
Info 'Running setup-codex.ps1 -OfflinePath <pkg> -NonInteractive ...'
& $ps1 -OfflinePath $PackageDir -NonInteractive
if ($LASTEXITCODE -ne 0) { Fail "setup-codex.ps1 exited $LASTEXITCODE" }
Ok 'installer completed (exit 0)'

# ---------------------------------------------------------------------------
# 4. config.toml exists
# ---------------------------------------------------------------------------
$toml = Join-Path $env:USERPROFILE '.codex\config.toml'
if (-not (Test-Path $toml)) { Fail "config.toml not found at $toml" }
Ok "config.toml exists: $toml"

# ---------------------------------------------------------------------------
# 5. User PATH (registry)
# ---------------------------------------------------------------------------
$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
$rawPath = ''
if ($null -ne $key) {
    $rawPath = [string]$key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    $key.Close()
}
$binDir = Join-Path $PackageDir 'node_modules\.bin'
$normalized = $binDir.TrimEnd('\').ToLowerInvariant()
$hit = @($rawPath -split ';' | Where-Object { $_.TrimEnd('\').ToLowerInvariant() -eq $normalized })
if ($hit.Count -eq 0) { Fail "user PATH does not contain: $binDir" }
Ok 'user PATH contains the package .bin directory'

Write-Host ''
Write-Host 'ALL WINDOWS CODEX PACKAGE TESTS PASSED'
exit 0
