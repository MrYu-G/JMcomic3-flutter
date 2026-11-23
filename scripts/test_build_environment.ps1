$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$fixtures = Join-Path $repository ('build/checks/build-environment/fixtures-' + [Guid]::NewGuid().ToString('N'))
$savedLocation = Get-Location
$environmentNames = @('Path', 'JM3_BUILD_ROOT', 'FLUTTER_ROOT', 'CARGO_HOME', 'RUSTUP_HOME', 'PUB_CACHE', 'CARGO_TARGET_DIR', 'RUST_BACKEND_RUST_DIR', 'CARGO_HTTP_CHECK_REVOKE', 'CARGO_NET_GIT_FETCH_WITH_CLI', 'ANDROID_HOME', 'ANDROID_SDK_ROOT', 'ANDROID_NDK_HOME', 'JAVA_HOME', 'GRADLE_USER_HOME', 'RUST_ANDROID_JNILIBS_SOURCE', 'RUST_ANDROID_SOURCE_LIB_NAME')
$savedEnvironment = @{}
foreach ($name in $environmentNames) { $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$checks = 0

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) { throw "$Message (expected $Expected; got $Actual)" }
    $script:checks++
}
function Assert-Rejected([scriptblock]$Action, [string]$Reason) {
    $failure = ''
    try { & $Action | Out-Null } catch { $failure = $_.Exception.Message }
    if (-not $failure.Contains($Reason)) { throw "Expected rejection containing '$Reason'; got '$failure'" }
    $script:checks++
}
function New-FixtureFile([string]$Path, [string]$Contents = 'fixture') {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, $Contents)
}
function New-FixtureApp([string]$Name, [bool]$IncludeTools = $true) {
    $app = Join-Path $fixtures $Name
    foreach ($directory in @('scripts', '_flutter/flutter', 'toolchains/cargo', 'toolchains/rustup')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $app $directory) | Out-Null
    }
    foreach ($scriptFile in @('enter_build_env.ps1', 'build_common.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $scriptFile) -Destination (Join-Path $app 'scripts')
    }
    New-FixtureFile (Join-Path $app 'rust-backend/rust/Cargo.toml') "[package]`nname = 'fixture'`n"
    if ($IncludeTools) {
        New-FixtureFile (Join-Path $app 'toolchains/vs2022/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe')
        New-FixtureFile (Join-Path $app 'toolchains/vs2022/Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja/ninja.exe')
    }
    return $app
}
function Invoke-FixtureEnvironment([string]$App, [string]$RequestedTarget = '') {
    $parameters = @{ SkipVisualStudio = $true; RustBackendDir = 'rust-backend/rust' }
    if ($RequestedTarget) { $parameters.Target = $RequestedTarget }
    # The synthetic executables are never launched. Only environment resolution
    # runs, with MSVC loading disabled and output kept local to this test.
    . (Join-Path $App 'scripts/enter_build_env.ps1') @parameters 6> $null
    return [pscustomobject]@{ CMake = $CMakeBin; Ninja = $NinjaRoot; SelectedTarget = $Target }
}

try {
    $app = New-FixtureApp 'app'
    $androidVariables = @('ANDROID_HOME', 'ANDROID_SDK_ROOT', 'ANDROID_NDK_HOME', 'JAVA_HOME', 'GRADLE_USER_HOME', 'RUST_ANDROID_JNILIBS_SOURCE', 'RUST_ANDROID_SOURCE_LIB_NAME')
    foreach ($name in $androidVariables) { [Environment]::SetEnvironmentVariable($name, "fixture-existing-$name", 'Process') }
    $windows = Invoke-FixtureEnvironment $app 'Windows'
    Assert-Equal $windows.SelectedTarget 'Windows' 'Windows target selected'
    Assert-Equal $windows.CMake (Join-Path $app 'toolchains/vs2022/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin') 'VS bundled CMake fallback'
    Assert-Equal $windows.Ninja (Join-Path $app 'toolchains/vs2022/Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja') 'VS bundled Ninja fallback'
    Assert-Equal $env:RUST_BACKEND_RUST_DIR (Join-Path $app 'rust-backend/rust') 'Explicit backend resolution preserved'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $app '_cache/gradle')) $false 'Windows does not create Gradle cache'
    foreach ($name in $androidVariables) {
        Assert-Equal ([Environment]::GetEnvironmentVariable($name, 'Process')) "fixture-existing-$name" "Windows leaves $name unchanged"
    }
    Assert-Rejected { Invoke-FixtureEnvironment $app } 'Android SDK not found'
    Assert-Rejected { Invoke-FixtureEnvironment $app 'Android' } 'Android SDK not found'

    foreach ($directory in @('toolchains/cmake/bin', 'toolchains/ninja')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $app $directory) | Out-Null
    }
    $emptyDedicated = Invoke-FixtureEnvironment $app 'Windows'
    Assert-Equal $emptyDedicated.CMake $windows.CMake 'Empty CMake directory does not hide bundled executable'
    Assert-Equal $emptyDedicated.Ninja $windows.Ninja 'Empty Ninja directory does not hide bundled executable'
    New-FixtureFile (Join-Path $app 'toolchains/cmake/bin/cmake.exe')
    New-FixtureFile (Join-Path $app 'toolchains/ninja/ninja.exe')
    $dedicated = Invoke-FixtureEnvironment $app 'Windows'
    Assert-Equal $dedicated.CMake (Join-Path $app 'toolchains/cmake/bin') 'Dedicated CMake takes precedence'
    Assert-Equal $dedicated.Ninja (Join-Path $app 'toolchains/ninja') 'Dedicated Ninja takes precedence'

    New-Item -ItemType Directory -Force -Path (Join-Path $app 'toolchains/android-sdk/ndk/25.2.9519653') | Out-Null
    New-FixtureFile (Join-Path $app 'toolchains/jdk-21/bin/java.exe')
    $env:JAVA_HOME = Join-Path $app 'missing-explicit-java'
    $android = Invoke-FixtureEnvironment $app 'Android'
    Assert-Equal $android.SelectedTarget 'Android' 'Android target selected'
    Assert-Equal $env:JAVA_HOME (Join-Path $app 'toolchains/jdk-21') 'Local Java fallback'
    Assert-Equal $env:ANDROID_HOME (Join-Path $app 'toolchains/android-sdk') 'Android SDK selection'
    Assert-Equal $env:ANDROID_NDK_HOME (Join-Path $app 'toolchains/android-sdk/ndk/25.2.9519653') 'Pinned NDK selection'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $app '_cache/gradle')) $true 'Android creates Gradle cache'
    New-FixtureFile (Join-Path $app 'explicit-java/bin/java.exe')
    $env:JAVA_HOME = Join-Path $app 'explicit-java'
    $combined = Invoke-FixtureEnvironment $app
    Assert-Equal $combined.SelectedTarget 'All' 'Default retains combined environment'
    Assert-Equal $env:JAVA_HOME (Join-Path $app 'explicit-java') 'Explicit Java takes precedence'

    $missingTools = New-FixtureApp 'missing-tools' $false
    Assert-Rejected { Invoke-FixtureEnvironment $missingTools 'Windows' } 'cmake.exe was not found'
    New-FixtureFile (Join-Path $missingTools 'toolchains/cmake/bin/cmake.exe')
    Assert-Rejected { Invoke-FixtureEnvironment $missingTools 'Windows' } 'ninja.exe was not found'
    Write-Host "$checks environment checks passed. Synthetic fixtures: $fixtures"
} finally {
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
    Set-Location -LiteralPath $savedLocation.Path
}
