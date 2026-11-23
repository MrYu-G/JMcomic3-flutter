param(
    [string[]]$Abi = @("arm64-v8a", "armeabi-v7a"),
    [switch]$ApkOnly,
    [switch]$AabOnly,
    [switch]$NoPubGet,
    [string]$SplitDebugInfoDir = "symbols/android",
    [switch]$Obfuscate,
    [switch]$NoObfuscate,
    [switch]$DebugSign,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$')]
    [string]$OutputName = 'android-release-split'
)

$ErrorActionPreference = "Stop"

if ($ApkOnly -and $AabOnly) {
    throw "-ApkOnly and -AabOnly cannot be used together."
}

if ($Obfuscate -and $NoObfuscate) {
    throw "-Obfuscate and -NoObfuscate cannot be used together."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot 'build_common.ps1')
$outputRoot = Get-Jm3OutputDirectory -BuildRoot $repoRoot -OutputName $OutputName
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
if (-not [string]::IsNullOrWhiteSpace($SplitDebugInfoDir) -and -not [System.IO.Path]::IsPathRooted($SplitDebugInfoDir)) {
    $SplitDebugInfoDir = Join-Path $outputRoot $SplitDebugInfoDir
}
Write-Host "Release staging: $outputRoot"
$jniRoot = Join-Path $repoRoot "android/app/src/main/jniLibs"

$normalizedAbi = @()
$targetPlatformList = @()
foreach ($item in $Abi) {
    $abi = $item.Trim()
    if ([string]::IsNullOrWhiteSpace($abi)) {
        continue
    }
    $targetPlatform = switch ($abi) {
        "armeabi-v7a" { "android-arm"; break }
        "arm64-v8a" { "android-arm64"; break }
        default { $null }
    }
    if ([string]::IsNullOrWhiteSpace($targetPlatform)) {
        throw "Unsupported ABI: '$abi'. Supported values: arm64-v8a, armeabi-v7a"
    }
    if ($normalizedAbi -contains $abi) {
        continue
    }
    $normalizedAbi += $abi
    $targetPlatformList += $targetPlatform
}

if ($normalizedAbi.Count -eq 0) {
    throw "At least one ABI is required."
}

foreach ($abi in $normalizedAbi) {
    $soPath = Join-Path $jniRoot "$abi/librust.so"
    if (-not (Test-Path -LiteralPath $soPath -PathType Leaf)) {
        throw "Missing Rust so: $soPath`nRun scripts/build_android_rust_jnilibs.sh or scripts/sync_android_jnilibs.ps1 first."
    }
}

$targetPlatforms = $targetPlatformList -join ","
$sizeArgs = @()
if (-not [string]::IsNullOrWhiteSpace($SplitDebugInfoDir)) {
    $sizeArgs += "--split-debug-info=$SplitDebugInfoDir"
}
$shouldObfuscate = -not $NoObfuscate
if ($Obfuscate) {
    $shouldObfuscate = $true
}
if ($shouldObfuscate) {
    if ([string]::IsNullOrWhiteSpace($SplitDebugInfoDir)) {
        throw "Dart obfuscation requires -SplitDebugInfoDir so symbols can be archived separately."
    }
    # 默认混淆 Dart AOT 名称，进一步缩小 libapp.so；符号目录必须随版本保存用于崩溃还原。
    $sizeArgs += "--obfuscate"
}

function Resolve-ApkSigner {
    param([Parameter(Mandatory = $true)][string]$Root)

    $sdkRoots = @(
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT,
        (Join-Path $Root 'toolchains/android-sdk')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { [System.IO.Path]::GetFullPath($_) } |
        Select-Object -Unique
    foreach ($sdkRoot in $sdkRoots) {
        $buildToolsRoot = Join-Path $sdkRoot 'build-tools'
        if (-not (Test-Path -LiteralPath $buildToolsRoot -PathType Container)) {
            continue
        }
        $signer = Get-ChildItem -LiteralPath $buildToolsRoot -Directory |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'lib/apksigner.jar' } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            Select-Object -First 1
        if ($signer) {
            return $signer
        }
    }
    throw 'Android build-tools apksigner.jar was not found.'
}

function Sign-AndVerifyDebugApks {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][System.IO.FileInfo[]]$ApkFiles
    )

    $debugKeystore = Join-Path $env:USERPROFILE '.android/debug.keystore'
    if (-not (Test-Path -LiteralPath $debugKeystore -PathType Leaf)) {
        throw "Debug keystore not found: $debugKeystore"
    }
    $signer = Resolve-ApkSigner -Root $Root
    foreach ($apk in $ApkFiles) {
        & java -jar $signer sign `
            --ks $debugKeystore `
            --ks-key-alias androiddebugkey `
            --ks-pass pass:android `
            --key-pass pass:android `
            $apk.FullName
        if ($LASTEXITCODE -ne 0) {
            throw "Debug signing failed: $($apk.FullName)"
        }
    }
    foreach ($apk in $ApkFiles) {
        & java -jar $signer verify --verbose $apk.FullName
        if ($LASTEXITCODE -ne 0) {
            throw "APK signature verification failed: $($apk.FullName)"
        }
    }
}

Push-Location $repoRoot
try {
    if (-not $NoPubGet) {
        & flutter pub get --enforce-lockfile
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed with exit code $LASTEXITCODE" }
    }

    # Split APK per ABI to reduce single-package size.
    if (-not $AabOnly) {
        & flutter build apk --release --target-platform $targetPlatforms --split-per-abi @sizeArgs
        if ($LASTEXITCODE -ne 0) { throw "APK build failed with exit code $LASTEXITCODE" }
    }

    # AAB for app store distribution.
    if (-not $ApkOnly) {
        & flutter build appbundle --release --target-platform $targetPlatforms @sizeArgs
        if ($LASTEXITCODE -ne 0) { throw "AAB build failed with exit code $LASTEXITCODE" }
    }
}
finally {
    Pop-Location
}

if (-not $AabOnly) {
    # Flutter uses its configured build directory, not FLUTTER_BUILD_DIR.
    # This project and its Gradle runner use the default repo-local build/.
    $apkOutputRoot = Join-Path $repoRoot 'build/app/outputs/flutter-apk'
    # Only touch packages produced for this invocation's requested ABI set.
    # Old packages from a prior build must not be signed or reported as current.
    $apkFiles = @($normalizedAbi | ForEach-Object {
        $apkPath = Join-Path $apkOutputRoot "app-$_-release.apk"
        & (Join-Path $PSScriptRoot 'verify_android_package.ps1') -PackagePath $apkPath -ExpectedAbi @($_) | Out-Host
        Get-Item -LiteralPath $apkPath
    })
    if ($DebugSign) {
        Sign-AndVerifyDebugApks -Root $repoRoot -ApkFiles $apkFiles
        Write-Host 'APK signing: Android debug keystore (test install only)' -ForegroundColor Yellow
    } else {
        $signer = Resolve-ApkSigner -Root $repoRoot
        foreach ($apk in $apkFiles) {
            & java -jar $signer verify $apk.FullName *> $null
            if ($LASTEXITCODE -ne 0) {
                throw "Release APK is unsigned or invalid: $($apk.FullName). Configure android/key.properties for release signing, or rerun with -DebugSign for a test-install package."
            }
        }
        Write-Host 'APK signing: configured release key' -ForegroundColor Green
    }
}
if (-not $ApkOnly) {
    & (Join-Path $PSScriptRoot 'verify_android_package.ps1') -PackagePath (Join-Path $repoRoot 'build/app/outputs/bundle/release/app-release.aab') -ExpectedAbi $normalizedAbi
}

Write-Host "Done. ABI: $($normalizedAbi -join ', '), target-platform: $targetPlatforms"
if (-not [string]::IsNullOrWhiteSpace($SplitDebugInfoDir)) {
    Write-Host "Dart debug symbols: $SplitDebugInfoDir"
}
Write-Host "Dart obfuscation: $shouldObfuscate"
