[CmdletBinding()]
param([string]$RustBackendDir = '')

$ErrorActionPreference = 'Stop'
# The native wrapper loads the Windows environment once for both build stages;
# Android SDK/NDK and Java are not prerequisites for this target.
& (Join-Path $PSScriptRoot 'build_windows_rust.ps1') -RustBackendDir $RustBackendDir
if ($LASTEXITCODE -ne 0) { throw "Rust Windows build failed with exit code $LASTEXITCODE" }
Set-Location -LiteralPath $env:JM3_BUILD_ROOT
Write-Host "Flutter output: $(Join-Path $env:JM3_BUILD_ROOT 'build/windows')"

& flutter pub get --enforce-lockfile
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed with exit code $LASTEXITCODE" }
& flutter build windows --release --no-pub
if ($LASTEXITCODE -ne 0) { throw "Flutter Windows build failed with exit code $LASTEXITCODE" }
Write-Host 'Windows package build completed.' -ForegroundColor Green
