[CmdletBinding()]
param(
    [string]$ManifestPath = "docs/baseline/BGLite-2.4.0.sha256"
)

$ErrorActionPreference = "Stop"
$baselineCommit = "9e0b119c66a644cce0083b5ffe4e59c6c946d0f1"
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$manifestFullPath = [IO.Path]::GetFullPath((Join-Path $repositoryRoot $ManifestPath))

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

$failures = 0
$rootPrefix = $repositoryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar

foreach ($relativePath in $expectedPaths) {
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
    if ($actualHash -ne $manifestEntries[$relativePath]) {
        Write-Error "Baseline file changed: $relativePath"
        $failures++
    }
}

if ($failures -gt 0) {
    throw "Baseline integrity check failed for $failures file(s)."
}

Write-Output "Baseline integrity verified: $($expectedPaths.Count) files."
