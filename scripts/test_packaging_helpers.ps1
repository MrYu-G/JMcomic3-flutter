$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'build_common.ps1')
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$fixtures = Join-Path $repoRoot ("build/checks/packaging-maintenance/fixtures-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtures | Out-Null
$oldBackend = $env:RUST_BACKEND_RUST_DIR
$checks = 0

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) { throw "$Message (expected $Expected; got $Actual)" }
    $script:checks++
}
function Assert-Rejected([scriptblock]$Action, [string]$Message, [string]$Reason = '') {
    $rejected = $false
    $received = [System.Collections.Generic.List[object]]::new()
    $failure = ''
    try { & $Action | ForEach-Object { $received.Add($_) } } catch {
        $rejected = $true
        $failure = $_.Exception.Message
    }
    if (-not $rejected) { throw "Expected rejection: $Message" }
    if ($Reason -and $failure -notmatch [regex]::Escape($Reason)) {
        throw "Unexpected rejection for ${Message}: $failure"
    }
    if ($received.Count) { throw "Rejected check emitted a success report: $Message" }
    $script:checks++
}
function New-Crate([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    [IO.File]::WriteAllText((Join-Path $Path 'Cargo.toml'), "[package]`nname = 'synthetic_fixture'`n")
    return (Resolve-Path -LiteralPath $Path).Path
}
function New-Package([string]$Name, [string[]]$Entries) {
    $path = Join-Path $fixtures $Name
    $archive = [IO.Compression.ZipFile]::Open($path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in $Entries) {
            $stream = $archive.CreateEntry($name).Open()
            try { $stream.WriteByte(1) } finally { $stream.Dispose() }
        }
    } finally { $archive.Dispose() }
    return $path
}

try {
    $env:RUST_BACKEND_RUST_DIR = $null
    $nestedApp = Join-Path $fixtures 'nested/app'
    $nested = New-Crate (Join-Path $nestedApp 'rust-backend/rust')
    Assert-Equal (Resolve-Jm3BackendCrate -BuildRoot $nestedApp) $nested 'Nested checkout'

    $siblingApp = Join-Path $fixtures 'sibling/app'
    New-Item -ItemType Directory -Path $siblingApp | Out-Null
    $sibling = New-Crate (Join-Path $fixtures 'sibling/jmcomic3-rust-backend/rust')
    Assert-Equal (Resolve-Jm3BackendCrate -BuildRoot $siblingApp) $sibling 'Sibling checkout'
    $second = New-Crate (Join-Path $siblingApp 'rust-backend/rust')
    Assert-Rejected { Resolve-Jm3BackendCrate -BuildRoot $siblingApp } 'Ambiguous checkouts'
    Assert-Equal (Resolve-Jm3BackendCrate -BuildRoot $siblingApp -RustBackendDir 'rust-backend/rust') $second 'Explicit relative crate'
    $env:RUST_BACKEND_RUST_DIR = $sibling
    Assert-Equal (Resolve-Jm3BackendCrate -BuildRoot $siblingApp) $sibling 'Environment crate'
    Assert-Equal (Resolve-Jm3BackendCrate -BuildRoot $siblingApp -RustBackendDir $nested) $nested 'Parameter overrides environment'
    Assert-Rejected { Resolve-Jm3BackendCrate -BuildRoot $siblingApp -RustBackendDir 'missing' } 'Missing explicit crate must not fall back'
    $env:RUST_BACKEND_RUST_DIR = $null
    Assert-Rejected { Resolve-Jm3BackendCrate -BuildRoot (Join-Path $fixtures 'missing-app') } 'Missing implicit checkout'
    Assert-Rejected { Get-Jm3OutputDirectory -BuildRoot $nestedApp -OutputName '../outside' } 'Output traversal'
    Assert-Equal (Get-Jm3OutputDirectory -BuildRoot $nestedApp -OutputName 'release-test') (Join-Path $nestedApp 'build/release-test') 'Scoped output'

    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $iconAsset = 'assets/flutter_assets/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png'
    $apkEntries = @('lib/arm64-v8a/librust.so', 'lib/arm64-v8a/libflutter.so', 'lib/arm64-v8a/libapp.so', 'assets/flutter_assets/lib/assets/version.txt', $iconAsset)
    $verify = Join-Path $PSScriptRoot 'verify_android_package.ps1'
    $apk = New-Package 'valid.apk' $apkEntries
    $report = & $verify -PackagePath $apk -ExpectedAbi @('arm64-v8a')
    Assert-Equal $report.NativeFiles 3 'APK native count'
    Assert-Equal $report.NativeUncompressedBytes 3 'APK measured native bytes'
    Assert-Equal $report.AppAssetFiles 2 'APK exact app asset count'
    Assert-Equal $report.AppAssetBytes 2 'APK measured asset bytes'
    $aab = New-Package 'valid.aab' @($apkEntries | ForEach-Object { "base/$_" })
    $bundleReport = & $verify -PackagePath $aab -ExpectedAbi @('arm64-v8a')
    Assert-Equal $bundleReport.NativeFiles 3 'AAB base module'
    Assert-Equal $bundleReport.AppAssetFiles 2 'AAB exact app asset count'
    Assert-Equal $bundleReport.AppAssetBytes 2 'AAB measured asset bytes'
    Assert-Rejected { & $verify -PackagePath $apk -ExpectedAbi @('armeabi-v7a') } 'Wrong ABI'
    $extraAbi = New-Package 'extra-abi.apk' ($apkEntries + 'lib/x86_64/librust.so')
    Assert-Rejected { & $verify -PackagePath $extraAbi -ExpectedAbi @('arm64-v8a') } 'Unexpected emulator ABI'
    $duplicateRust = New-Package 'duplicate-rust.apk' ($apkEntries + 'lib/arm64-v8a/librust_lib_jasmine.so')
    Assert-Rejected { & $verify -PackagePath $duplicateRust -ExpectedAbi @('arm64-v8a') } 'Duplicate Rust filename'
    $duplicateEntry = New-Package 'duplicate-entry.apk' ($apkEntries + $apkEntries[0])
    Assert-Rejected { & $verify -PackagePath $duplicateEntry -ExpectedAbi @('arm64-v8a') } 'Duplicate ZIP entry'
    foreach ($format in @('apk', 'aab')) {
        $assetCases = @(
            @{ Name = 'missing-icon'; Entries = @($apkEntries | Where-Object { $_ -cne $iconAsset }) },
            @{ Name = 'extra-lib-asset'; Entries = $apkEntries + 'assets/flutter_assets/lib/assets/unused.bin' },
            @{ Name = 'extra-android-asset'; Entries = $apkEntries + 'assets/flutter_assets/android/app/src/main/res/mipmap-xxxhdpi/unused.png' },
            @{ Name = 'extra-android-subtree'; Entries = $apkEntries + 'assets/flutter_assets/android/unused.bin' },
            @{ Name = 'wrong-icon-case'; Entries = @($apkEntries | ForEach-Object { if ($_ -ceq $iconAsset) { $_.Replace('ic_launcher.png', 'IC_LAUNCHER.png') } else { $_ } }) }
        )
        foreach ($assetCase in $assetCases) {
            $fixtureEntries = if ($format -eq 'aab') { @($assetCase.Entries | ForEach-Object { "base/$_" }) } else { $assetCase.Entries }
            $badAssets = New-Package ("$($assetCase.Name).$format") $fixtureEntries
            Assert-Rejected { & $verify -PackagePath $badAssets -ExpectedAbi @('arm64-v8a') } "$format $($assetCase.Name)" 'App assets must contain exactly'
        }
    }
    $missingLib = New-Package 'missing-lib.apk' ($apkEntries | Where-Object { $_ -notlike '*libapp.so' })
    Assert-Rejected { & $verify -PackagePath $missingLib -ExpectedAbi @('arm64-v8a') } 'Missing AOT library'

    $verifyArchive = Join-Path $PSScriptRoot 'verify_release_archive.ps1'
    $publicMetadata = @('META-INF/MANIFEST.MF', 'META-INF/CERT.SF', 'META-INF/CERT.RSA', 'META-INF/CERT.DSA', 'META-INF/CERT.EC')
    $flutterAssets = @('assets/flutter_assets/NOTICES.Z', 'assets/flutter_assets/AssetManifest.bin', 'assets/flutter_assets/fonts/MaterialIcons-Regular.otf', 'assets/flutter_assets/shaders/ink_sparkle.frag', 'assets/flutter_assets/packages/synthetic_plugin/icon.png')
    $signedApk = New-Package 'signed-metadata.apk' ($apkEntries + $publicMetadata + $flutterAssets + 'assets/native_assets/android_arm64/plugin.so')
    $signedHash = (Get-FileHash -LiteralPath $signedApk -Algorithm SHA256).Hash
    $signedReport = @(& $verify -PackagePath $signedApk -ExpectedAbi @('arm64-v8a'))
    Assert-Equal $signedReport.Count 1 'Android checker retains one report'
    Assert-Equal $signedReport[0].NativeFiles 3 'Public signatures and plugin assets preserve native libraries'
    Assert-Equal $signedReport[0].AppAssetFiles 2 'Framework and plugin assets excluded from APK app asset count'
    Assert-Equal $signedReport[0].AppAssetBytes 2 'Framework and plugin assets excluded from APK app asset bytes'
    Assert-Equal ($signedReport[0].PSObject.Properties.Name -join ',') 'Package,ArchiveBytes,Abi,NativeFiles,NativeUncompressedBytes,NativeCompressedBytes,AppAssetFiles,AppAssetBytes' 'Android report shape'
    Assert-Equal (Get-FileHash -LiteralPath $signedApk -Algorithm SHA256).Hash $signedHash 'Archive verification is read-only'
    $bundleEntries = @($apkEntries + $flutterAssets | ForEach-Object { "base/$_" }) + $publicMetadata + @('BundleConfig.pb', 'BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map', 'base/manifest/AndroidManifest.xml')
    $signedBundle = New-Package 'signed-metadata.aab' $bundleEntries
    $signedBundleReport = & $verify -PackagePath $signedBundle -ExpectedAbi @('arm64-v8a')
    Assert-Equal $signedBundleReport.NativeFiles 3 'Signed AAB with standard metadata'
    Assert-Equal $signedBundleReport.AppAssetFiles 2 'Framework and plugin assets excluded from AAB app asset count'
    Assert-Equal $signedBundleReport.AppAssetBytes 2 'Framework and plugin assets excluded from AAB app asset bytes'
    $windowsEntries = @('Jmcomic3/jmcomic3.exe', 'Jmcomic3/flutter_windows.dll', 'Jmcomic3/nativeapi.dll', 'Jmcomic3/rust.dll', 'Jmcomic3/data/icudtl.dat', 'Jmcomic3/data/app.so', 'Jmcomic3/data/flutter_assets/lib/assets/version.txt', 'Jmcomic3/data/flutter_assets/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png', 'Jmcomic3/data/flutter_assets/NOTICES.Z', 'Jmcomic3/data/flutter_assets/fonts/MaterialIcons-Regular.otf', 'Jmcomic3/LICENSE', 'Jmcomic3/build-info.json')
    $windows = New-Package 'valid-windows.zip' $windowsEntries
    $windowsReport = @(& $verifyArchive -PackagePath $windows)
    Assert-Equal $windowsReport.Count 1 'Windows checker emits one report'
    Assert-Equal $windowsReport[0].CheckedFiles $windowsEntries.Count 'Windows runtime files and licenses are retained'

    $forbiddenEntries = @(
        @{ Path = 'assets/hidden/invoke.rs'; Reason = 'backend source' },
        @{ Path = 'assets/Cargo.toml'; Reason = 'backend source' },
        @{ Path = 'assets/Cargo.lock'; Reason = 'backend source' },
        @{ Path = 'assets/rust-backend/README.md'; Reason = 'backend source' },
        @{ Path = 'assets/jmcomic3-rust-backend/README.md'; Reason = 'backend source' },
        @{ Path = 'assets/lib/basic/backend/invoke.dart'; Reason = 'backend source' },
        @{ Path = 'assets/lib/src/rust/api.dart'; Reason = 'backend source' },
        @{ Path = 'assets/frb_generated.io.dart'; Reason = 'backend source' },
        @{ Path = 'assets/flutter_rust_bridge.yaml'; Reason = 'backend source' },
        @{ Path = 'assets/.git/objects/private-object'; Reason = 'backend source' },
        @{ Path = 'assets/SECRETS/private.txt'; Reason = 'signing credentials' },
        @{ Path = 'assets/key.properties'; Reason = 'signing credentials' },
        @{ Path = 'assets/release.keystore'; Reason = 'signing credentials' },
        @{ Path = 'assets/release.jks'; Reason = 'signing credentials' },
        @{ Path = 'assets/key.pem'; Reason = 'signing credentials' },
        @{ Path = 'assets/signing-key.pfx'; Reason = 'signing credentials' },
        @{ Path = 'assets/.env.local'; Reason = 'signing credentials' },
        @{ Path = 'assets/credentials.json'; Reason = 'signing credentials' },
        @{ Path = 'assets/passwords.yaml'; Reason = 'signing credentials' },
        @{ Path = 'assets/.ssh/id_ed25519'; Reason = 'signing credentials' },
        @{ Path = 'data/frb_store.json'; Reason = 'private application state' },
        @{ Path = 'data/frb_store_parts/settings.json'; Reason = 'private application state' },
        @{ Path = 'data/cookies.txt'; Reason = 'private application state' },
        @{ Path = 'data/token.json'; Reason = 'private application state' },
        @{ Path = 'data/history.sqlite'; Reason = 'private application state' },
        @{ Path = 'data/history.db-wal'; Reason = 'private application state' },
        @{ Path = 'assets/test/synthetic.png'; Reason = 'test evidence' },
        @{ Path = 'assets/screenshots/reader.png'; Reason = 'test evidence' },
        @{ Path = 'assets/build/checks/report.txt'; Reason = 'test evidence' },
        @{ Path = 'assets\captures\reader.png'; Reason = 'test evidence' },
        @{ Path = 'symbols/app.android-arm64.symbols'; Reason = 'debug symbols' },
        @{ Path = 'Jmcomic3/jmcomic3.pdb'; Reason = 'debug symbols' },
        @{ Path = 'Jmcomic3/rust.debug'; Reason = 'debug symbols' },
        @{ Path = 'BUNDLE-METADATA/com.android.tools.build.debugsymbols/arm64-v8a/librust.so.sym'; Reason = 'debug symbols' },
        @{ Path = 'assets/backend-source.zip'; Reason = 'nested archive' },
        @{ Path = 'assets/backend.tar.gz'; Reason = 'nested archive' },
        @{ Path = 'assets/backend.tar.zst'; Reason = 'nested archive' },
        @{ Path = 'assets/backend.crate'; Reason = 'nested archive' },
        @{ Path = 'assets/sources.jar'; Reason = 'nested archive' },
        @{ Path = 'assets/../private.txt'; Reason = 'unsafe archive path' },
        @{ Path = '/private.txt'; Reason = 'unsafe archive path' },
        @{ Path = 'C:\private.txt'; Reason = 'unsafe archive path' }
    )
    foreach ($forbidden in $forbiddenEntries) {
        $badArchive = New-Package ("forbidden-$checks.zip") ($windowsEntries + $forbidden.Path)
        Assert-Rejected { & $verifyArchive -PackagePath $badArchive } $forbidden.Path $forbidden.Reason
    }
    $privateApk = New-Package 'private-state.apk' ($apkEntries + 'assets/frb_store.json')
    Assert-Rejected { & $verify -PackagePath $privateApk -ExpectedAbi @('arm64-v8a') } 'Android rejects private state before emitting its ABI report' 'private application state'
    $symbolBundle = New-Package 'debug-symbols.aab' ($bundleEntries + 'BUNDLE-METADATA/com.android.tools.build.debugsymbols/arm64-v8a/librust.so.dbg')
    Assert-Rejected { & $verify -PackagePath $symbolBundle -ExpectedAbi @('arm64-v8a') } 'AAB rejects embedded debug symbols' 'debug symbols'
    $duplicateWindows = New-Package 'duplicate-windows.zip' ($windowsEntries + 'JMCOMIC3\flutter_windows.dll')
    Assert-Rejected { & $verifyArchive -PackagePath $duplicateWindows } 'Windows separator/case duplicate' 'Duplicate archive entry'
    Write-Host "$checks packaging checks passed. Synthetic fixtures: $fixtures"
} finally {
    $env:RUST_BACKEND_RUST_DIR = $oldBackend
}
