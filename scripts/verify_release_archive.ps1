[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PackagePath
)

$ErrorActionPreference = 'Stop'

function Get-Jm3ReleaseEntryViolation {
    param([Parameter(Mandatory = $true)][string]$EntryName)

    # Match both ZIP separators so Windows-style paths cannot bypass the same
    # policy used for Android entries. Nothing is extracted or read as text.
    $name = $EntryName.Replace('\', '/')
    $parts = @($name.TrimEnd('/').Split('/'))
    if ($name.StartsWith('/') -or $name -match '[:\x00-\x1f\x7f]' -or
        (@($parts | Where-Object { $_ -in @('', '.', '..') -or $_ -match '[. ]$' }).Count -gt 0)) {
        return 'unsafe archive path'
    }
    if ($name -match '(^|/)(rust|rust-backend|jmcomic3-rust-backend|rust_builder|backend-source|\.git|\.hg|\.svn)(/|$)|(^|/)lib/(src/rust|basic/backend)/|(^|/)(Cargo\.(toml|lock)|flutter_rust_bridge\.ya?ml|gen_frb\.ps1|frb_generated(?:\.[^/]*)?\.dart)$|\.rs$') {
        return 'backend source or bridge-generation files'
    }
    if ($name -match '(^|/)(secrets?|credentials?|signing|\.ssh|\.aws|\.azure|frb_store_parts)(/|$)|(^|/)(\.env(?:\.[^/]*)?|key\.properties(?:\.[^/]*)?|id_(rsa|ed25519|ecdsa|dsa)(?:\.pub)?|(?:credentials?|passwords?|cookies?|tokens?)\.(?:json|ya?ml|txt|toml|ini)|service[-_]account[^/]*\.json|client_secret[^/]*\.json|frb_store\.json)$|\.(jks|keystore|p12|pfx|pem|key|p8|kdbx|(?:db|sqlite3?)(?:-(?:wal|shm|journal))?)$') {
        return 'signing credentials or private application state'
    }
    # AGP writes its own version marker under a path containing "build".
    if ($name -ceq 'META-INF/com/android/build/gradle/app-metadata.properties') { return $null }
    if ($name -match '(^|/)(test|tests|integration_test|test_driver|screenshots?|captures?|acceptance|verification|test-output|test-results|coverage|checks|build|dist|target|\.dart_tool|\.smoke-data|_cache|_flutter|_android-sdk|toolchains)(/|$)|\.(log|bak)$') {
        return 'test evidence or local build output'
    }
    if ($name -match '(^|/)(symbols|debug-symbols|native-debug-symbols|com\.android\.tools\.build\.debugsymbols)(/|$)|\.(symbols|pdb|debug|sym|dbg)(/|$)|\.dSYM(/|$)') {
        return 'debug symbols'
    }
    # Release packages have no nested archives. Flutter's compressed NOTICES.Z
    # and public APK/JAR signature metadata (.RSA/.DSA/.EC/.SF) remain valid.
    if ($name -match '\.(zip|7z|rar|tar|tgz|tbz2|txz|gz|bz2|xz|lz|lzma|zst|zstd|crate|apk|aab|aar|jar)$') {
        return 'nested archive'
    }
    return $null
}

$package = Get-Item -LiteralPath $PackagePath
if ($package.PSIsContainer -or $package.Extension.ToLowerInvariant() -notin @('.apk', '.aab', '.zip')) {
    throw 'Expected an APK, AAB, or Windows ZIP archive.'
}
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($package.FullName)
try {
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $fileCount = 0
    foreach ($entry in $archive.Entries) {
        $displayName = $entry.FullName -replace '[\x00-\x1f\x7f]', '?'
        $violation = Get-Jm3ReleaseEntryViolation -EntryName $entry.FullName
        if ($violation) { throw "Release archive entry rejected ($violation): $displayName" }
        $name = $entry.FullName.Replace('\', '/')
        if (-not $seen.Add($name.TrimEnd('/'))) { throw "Duplicate archive entry: $displayName" }
        if (-not $name.EndsWith('/')) { $fileCount++ }
    }
    if ($fileCount -eq 0) { throw 'Release archive contains no files.' }
    # Emit a single report only after every entry has passed. The Android
    # checker consumes this silently to retain its existing ABI/size report.
    [pscustomobject]@{
        Package = $package.FullName
        ArchiveBytes = $package.Length
        CheckedFiles = $fileCount
    }
} finally { $archive.Dispose() }
