[CmdletBinding()]
param(
    [string]$RepositoryPath = '',
    [switch]$IndexOnly
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryPath)) {
    $RepositoryPath = Join-Path $PSScriptRoot '..'
}
$repository = (Resolve-Path -LiteralPath $RepositoryPath).Path
$gitArgs = @('-C', $repository, 'ls-files', '-z', '--cached')
if (-not $IndexOnly) {
    $gitArgs += @('--others', '--exclude-standard')
}
$listing = & git @gitArgs
if ($LASTEXITCODE -ne 0) { throw 'Could not read the Git file inventory.' }
$files = (($listing -join "`n") -split "`0") | Where-Object { $_ } | Sort-Object -Unique

# Keep only product icons in source control. Tests generate their own fixtures.
$productIcons = @('windows/runner/resources/app_icon.ico')
foreach ($density in @('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi')) {
    foreach ($suffix in @('', '_background', '_foreground', '_round')) {
        $productIcons += "android/app/src/main/res/mipmap-$density/ic_launcher$suffix.png"
    }
}
# Determine the repository type from the inspected snapshot, not a local file
# that could have been deleted while a different copy remains in the index.
$isApp = $files -contains 'lib/main.dart'
$rejected = @()
$checked = 0
$credentialPath = '(^|/)(secrets|credentials|\.ssh|frb_store_parts)(/|$)|(^|/)(\.env(?:\.[^/]*)?|key\.properties|id_rsa|id_ed25519|credentials\.(?:json|ya?ml)|service-account[^/]*\.json|client_secret[^/]*\.json|cookies?\.(?:json|txt)|tokens?\.(?:json|txt)|frb_store\.json)$|\.(jks|keystore|p12|pfx|pem|key)$'
$backendPath = '(^|/)(rust|rust-backend|jmcomic3-rust-backend|rust_builder|backend-source)(/|$)|^lib/(src/rust|basic/backend)/|(^|/)(Cargo\.(toml|lock)|flutter_rust_bridge\.yaml|gen_frb\.ps1)$|\.rs$'
$secretRules = @{
    'private key material' = '-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----'
    'GitHub access token' = '\b(?:gh[pousr]_[A-Za-z0-9]{36,255}|github_pat_[A-Za-z0-9_]{60,})\b'
    'AWS access key ID' = '\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'
    'Slack access token' = '\bxox[baprs]-[A-Za-z0-9-]{20,}\b'
}
foreach ($path in $files) {
    # Local review includes pending deletions. IndexOnly checks the exact staged
    # snapshot, including an unwanted file deleted locally but not yet staged.
    if (-not $IndexOnly -and -not (Test-Path -LiteralPath (Join-Path $repository $path))) {
        continue
    }
    $checked++
    $image = $path -match '\.(png|jpe?g|gif|webp|bmp|avif|tiff?|ico|svg|heic|heif)$'
    $productIcon = $isApp -and $productIcons -ccontains $path
    $output = $path -match '(^|/)(build|dist|target|screenshots|acceptance|verification|test-output|coverage|\.dart_tool|\.smoke-data|_cache|_flutter|_android-sdk|toolchains)(/|$)'
    $taskEvidence = $path -match '^docs/[^/]+-plan\.md$|^tmp_method_inventory\.txt$|\.(log|bak)$'
    $template = $path -match '\.(example|sample|template)$'
    $credential = $path -match $credentialPath -and -not $template
    $archiveOrSymbols = $path -match '\.(zip|7z|rar|tar|tgz|tbz2|txz|gz|bz2|xz|lz|lzma|zst|zstd|crate|apk|aab|symbols|pdb|debug|sym|dbg)$'
    if (($image -and -not $productIcon) -or $output -or $taskEvidence -or $credential -or $archiveOrSymbols -or ($isApp -and $path -match $backendPath)) {
        $rejected += $path
        # Do not open protected files or binary outputs to report their values.
        continue
    }
    if ($path -match '\.(dart|rs|md|txt|json|ya?ml|toml|lock|properties|gradle|ps1|sh|cpp|cc|c|h|xml|example|sample|template)$') {
        if ($IndexOnly) {
            $content = (& git -C $repository show ":$path") -join "`n"
            if ($LASTEXITCODE -ne 0) { throw "Could not read staged text: $path" }
        } else {
            $content = [IO.File]::ReadAllText((Join-Path $repository $path))
        }
        foreach ($rule in $secretRules.GetEnumerator()) {
            if ($content -cmatch $rule.Value) {
                $rejected += "$path (possible $($rule.Key); value redacted)"
            }
        }
        if ($path -ceq 'android/key.properties.example') {
            foreach ($field in @('storePassword', 'keyPassword')) {
                $value = [regex]::Match($content, "(?m)^$field\s*=\s*([^\r\n]*)").Groups[1].Value.Trim()
                if ($value -cne 'CHANGE_ME') {
                    $rejected += "$path (signing template must retain placeholder values)"
                }
            }
        }
    }
}
if ($rejected.Count -gt 0) {
    throw ("Files must not be uploaded:`n" + ($rejected -join "`n"))
}
Write-Host "Repository file policy passed ($checked files checked)."
