[CmdletBinding()]
param(
    [string]$ManifestPath = "docs/baseline/BGLite-2.4.1.sha256",
    [string]$OverrideManifestPath = "docs/baseline/BGNext-overrides.sha256",
    [string]$ExclusionPath = "docs/baseline/BGLite-2.4.1-exclusions.txt"
)

$ErrorActionPreference = "Stop"
$baselineCommit = "31b4942e3251d8bba5c6e6be56fc427da2ae045f"
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$manifestFullPath = [IO.Path]::GetFullPath((Join-Path $repositoryRoot $ManifestPath))
$overrideManifestFullPath = [IO.Path]::GetFullPath((Join-Path $repositoryRoot $OverrideManifestPath))
$exclusionFullPath = [IO.Path]::GetFullPath((Join-Path $repositoryRoot $ExclusionPath))

if (-not (Test-Path -LiteralPath $manifestFullPath -PathType Leaf)) {
    throw "Baseline manifest not found: $ManifestPath"
}

$expectedPaths = @(
    git -C $repositoryRoot ls-tree -r --name-only $baselineCommit |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ } |
        Sort-Object
)

if ($LASTEXITCODE -ne 0) {
    throw "Unable to read baseline commit $baselineCommit."
}

$manifestEntries = @{}
$lineNumber = 0

foreach ($line in Get-Content -LiteralPath $manifestFullPath) {
    $lineNumber++
    if (-not $line) {
        continue
    }
    if ($line -notmatch "^([0-9a-fA-F]{64})  (.+)$") {
        throw "Invalid manifest entry at line $lineNumber."
    }

    $hash = $Matches[1].ToLowerInvariant()
    $relativePath = $Matches[2].Replace("\", "/")
    if ($manifestEntries.ContainsKey($relativePath)) {
        throw "Duplicate manifest path: $relativePath"
    }
    $manifestEntries[$relativePath] = $hash
}

$overrideEntries = @{}
if (Test-Path -LiteralPath $overrideManifestFullPath -PathType Leaf) {
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $overrideManifestFullPath) {
        $lineNumber++
        if (-not $line -or $line.StartsWith("#")) {
            continue
        }
        if ($line -notmatch "^([0-9a-fA-F]{64})  (.+)$") {
            throw "Invalid override manifest entry at line $lineNumber."
        }

        $hash = $Matches[1].ToLowerInvariant()
        $relativePath = $Matches[2].Replace("\", "/")
        if ($overrideEntries.ContainsKey($relativePath)) {
            throw "Duplicate override path: $relativePath"
        }
        $overrideEntries[$relativePath] = $hash
    }
}

$manifestPaths = @($manifestEntries.Keys | Sort-Object)
$missingFromManifest = @($expectedPaths | Where-Object { -not $manifestEntries.ContainsKey($_) })
$extraInManifest = @($manifestPaths | Where-Object { $_ -notin $expectedPaths })

if ($missingFromManifest.Count -gt 0 -or $extraInManifest.Count -gt 0) {
    foreach ($path in $missingFromManifest) {
        Write-Error "Missing from manifest: $path"
    }
    foreach ($path in $extraInManifest) {
        Write-Error "Unexpected manifest entry: $path"
    }
    throw "Baseline manifest does not match commit $baselineCommit."
}

$unknownOverrides = @($overrideEntries.Keys | Where-Object { -not $manifestEntries.ContainsKey($_) })
if ($unknownOverrides.Count -gt 0) {
    foreach ($path in $unknownOverrides) {
        Write-Error "Override is not an upstream baseline file: $path"
    }
    throw "Override manifest contains unknown paths."
}

$excludedPaths = @{}
if (Test-Path -LiteralPath $exclusionFullPath -PathType Leaf) {
    foreach ($line in Get-Content -LiteralPath $exclusionFullPath) {
        $relativePath = $line.Trim().Replace("\", "/")
        if ($relativePath -and -not $relativePath.StartsWith("#")) {
            if (-not $manifestEntries.ContainsKey($relativePath)) {
                throw "Baseline exclusion is not an upstream file: $relativePath"
            }
            $excludedPaths[$relativePath] = $true
        }
    }
}

$failures = 0
$rootPrefix = $repositoryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar

foreach ($relativePath in $expectedPaths) {
    if ($excludedPaths.ContainsKey($relativePath)) {
        continue
    }
    $nativeRelativePath = $relativePath.Replace("/", [IO.Path]::DirectorySeparatorChar)
    $fullPath = [IO.Path]::GetFullPath((Join-Path $repositoryRoot $nativeRelativePath))

    if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Error "Unsafe manifest path: $relativePath"
        $failures++
        continue
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        Write-Error "Baseline file missing: $relativePath"
        $failures++
        continue
    }

    $actualHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = if ($overrideEntries.ContainsKey($relativePath)) {
        $overrideEntries[$relativePath]
    } else {
        $manifestEntries[$relativePath]
    }
    if ($actualHash -ne $expectedHash) {
        Write-Error "Baseline file changed: $relativePath"
        $failures++
    }
}

if ($failures -gt 0) {
    throw "Baseline integrity check failed for $failures file(s)."
}

Write-Output "Baseline integrity verified: $($expectedPaths.Count) upstream files, $($excludedPaths.Count) explicit repository exclusion(s), and $($overrideEntries.Count) BGNext override(s)."
