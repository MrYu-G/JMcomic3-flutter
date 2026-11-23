[CmdletBinding()]
param(
    [ValidateSet('both', 'arm64-v8a', 'armeabi-v7a')]
    [string]$Abi = 'both',
    [switch]$SkipRust,
    [switch]$AppBundle,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$')]
    [string]$OutputName = 'android',
    [string]$RustBackendDir = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'enter_build_env.ps1') -RustBackendDir $RustBackendDir
Set-Location -LiteralPath $env:JM3_BUILD_ROOT
$outputRoot = Get-Jm3OutputDirectory -BuildRoot $env:JM3_BUILD_ROOT -OutputName $OutputName
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
Write-Host "Build reports: $outputRoot"
$abis = if ($Abi -eq 'both') { @('arm64-v8a', 'armeabi-v7a') } else { @($Abi) }

if (-not $SkipRust) {
    # Use the same PowerShell toolchain and validated sync path as emulator
    # builds; no second shell can reset the selected backend or host linker.
    Push-Location -LiteralPath $env:RUST_BACKEND_RUST_DIR
    try {
        foreach ($abiName in $abis) {
            & cargo ndk -t $abiName -o $env:RUST_ANDROID_JNILIBS_SOURCE build --release --locked --lib
            if ($LASTEXITCODE -ne 0) { throw "Rust Android build failed: $abiName ($LASTEXITCODE)" }
        }
    } finally { Pop-Location }
    & (Join-Path $PSScriptRoot 'sync_android_jnilibs.ps1') -Source $env:RUST_ANDROID_JNILIBS_SOURCE -Abi $abis
}

# Share release flags, external symbols, ABI/package checks, and signature
# verification with the package-only workflow instead of keeping two variants.
if ($AppBundle) {
    & (Join-Path $PSScriptRoot 'build_android_release_split.ps1') -Abi $abis -AabOnly -OutputName $OutputName
} else {
    & (Join-Path $PSScriptRoot 'build_android_release_split.ps1') -Abi $abis -ApkOnly -OutputName $OutputName
}
Write-Host 'Android package build completed.' -ForegroundColor Green
