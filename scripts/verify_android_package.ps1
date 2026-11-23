[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [Parameter(Mandatory = $true)]
    [ValidateSet('arm64-v8a', 'armeabi-v7a', 'x86_64')][string[]]$ExpectedAbi
)

$ErrorActionPreference = 'Stop'
$package = Get-Item -LiteralPath $PackagePath
$extension = $package.Extension.ToLowerInvariant()
if ($extension -notin @('.apk', '.aab')) { throw 'Expected an APK or AAB archive.' }
& (Join-Path $PSScriptRoot 'verify_release_archive.ps1') -PackagePath $package.FullName | Out-Null
$prefix = if ($extension -eq '.aab') { 'base/' } else { '' }
$nativePrefix = $prefix + 'lib/'
$assetPrefix = $prefix + 'assets/flutter_assets/'
$expectedAssets = @(
    $assetPrefix + 'lib/assets/version.txt'
    $assetPrefix + 'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png'
)
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($package.FullName)
try {
    $entries = @($archive.Entries | Where-Object { -not $_.FullName.EndsWith('/') })
    $names = @($entries.FullName)
    $duplicates = @($names | Group-Object | Where-Object { $_.Count -gt 1 })
    if ($duplicates.Count) { throw "Duplicate package entry: $($duplicates[0].Name)" }
    $native = @($entries | Where-Object { $_.FullName.StartsWith($nativePrefix) })
    $actualAbi = @($native | ForEach-Object { $_.FullName.Substring($nativePrefix.Length).Split('/')[0] } | Sort-Object -Unique)
    $expected = @($ExpectedAbi | Sort-Object -Unique)
    if (@(Compare-Object -ReferenceObject $expected -DifferenceObject $actualAbi).Count) {
        throw "Package ABI mismatch: expected $($expected -join ', '); found $($actualAbi -join ', ')"
    }
    foreach ($abi in $expected) {
        foreach ($library in @('librust.so', 'libflutter.so', 'libapp.so')) {
            if ($names -cnotcontains "$nativePrefix$abi/$library") {
                throw "Package is missing $abi/$library"
            }
        }
    }
    if ($native | Where-Object { $_.Name -eq 'librust_lib_jasmine.so' }) {
        throw 'Package contains a duplicate cargo-named Rust library.'
    }
    # Audit app-owned source trees while allowing Flutter and package assets.
    # Match the trees broadly, then require the manifest's exact archive paths.
    $assets = @($entries | Where-Object {
        $assetName = $_.FullName.Replace('\', '/')
        $assetName.StartsWith(($assetPrefix + 'lib/assets/'), [StringComparison]::OrdinalIgnoreCase) -or
            $assetName.StartsWith(($assetPrefix + 'android/'), [StringComparison]::OrdinalIgnoreCase)
    })
    if ($assets.Count -ne $expectedAssets.Count -or @($assets | Where-Object { $expectedAssets -cnotcontains $_.FullName }).Count) {
        throw 'App assets must contain exactly lib/assets/version.txt and android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png; update the explicit manifest and audit if adding assets.'
    }
    [pscustomobject]@{
        Package = $package.FullName
        ArchiveBytes = $package.Length
        Abi = $actualAbi -join ', '
        NativeFiles = $native.Count
        NativeUncompressedBytes = ($native | Measure-Object -Property Length -Sum).Sum
        NativeCompressedBytes = ($native | Measure-Object -Property CompressedLength -Sum).Sum
        AppAssetFiles = $assets.Count
        AppAssetBytes = ($assets | Measure-Object -Property Length -Sum).Sum
    }
} finally { $archive.Dispose() }
