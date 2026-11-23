# Shared path helpers. This file does not load tools, create directories, or
# change the caller's environment when dot-sourced.

function Resolve-Jm3Directory {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label not found: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Resolve-Jm3BackendCrate {
    param(
        [Parameter(Mandatory = $true)][string]$BuildRoot,
        [string]$RustBackendDir = ''
    )
    $selected = $RustBackendDir
    if ([string]::IsNullOrWhiteSpace($selected)) {
        $selected = $env:RUST_BACKEND_RUST_DIR
    }
    if (-not [string]::IsNullOrWhiteSpace($selected)) {
        if (-not [IO.Path]::IsPathRooted($selected)) {
            $selected = Join-Path $BuildRoot $selected
        }
        $candidates = @($selected)
    } else {
        $candidates = @(
            (Join-Path $BuildRoot 'rust-backend/rust'),
            (Join-Path $BuildRoot '../jmcomic3-rust-backend/rust')
        ) | Where-Object {
            Test-Path -LiteralPath (Join-Path $_ 'Cargo.toml') -PathType Leaf
        } | ForEach-Object { (Resolve-Path -LiteralPath $_).Path } | Select-Object -Unique
        if (@($candidates).Count -ne 1) {
            throw 'Expected one backend checkout. Set -RustBackendDir or RUST_BACKEND_RUST_DIR to its rust/ crate when neither or both nested and sibling checkouts exist.'
        }
    }
    $crate = Resolve-Jm3Directory -Path (@($candidates)[0]) -Label 'Rust backend crate'
    if (-not (Test-Path -LiteralPath (Join-Path $crate 'Cargo.toml') -PathType Leaf)) {
        throw "Rust crate manifest not found: $crate"
    }
    return $crate
}

function Get-Jm3OutputDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$BuildRoot,
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$')][string]$OutputName
    )
    $buildDirectory = [IO.Path]::GetFullPath((Join-Path $BuildRoot 'build'))
    $output = [IO.Path]::GetFullPath((Join-Path $buildDirectory $OutputName))
    if (-not $output.StartsWith(($buildDirectory + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) {
        throw "Build output must be inside $buildDirectory"
    }
    return $output
}

function Add-Jm3PathEntries {
    param([string[]]$Entries)
    $current = @($env:Path -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $env:Path = (@($Entries + $current) | Where-Object { $seen.Add($_) }) -join ';'
}
