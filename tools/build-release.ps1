[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$tocPath = Join-Path $repositoryRoot "BGLite.toc"
$version = (Get-Content -LiteralPath (Join-Path $repositoryRoot "addon_version.txt") -Raw).Trim()

if (-not $OutputPath) {
    $OutputPath = Join-Path $repositoryRoot ".local\packages\BGNext-$version.zip"
} elseif (-not [IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $repositoryRoot $OutputPath
}
$outputFullPath = [IO.Path]::GetFullPath($OutputPath)

$deniedPaths = @(
    "Core/Module/History.lua",
    "Core/Module/TradeHistory.lua",
    "Core/Module/MailHistory.lua",
    "Core/Module/Receive.lua",
    "Core/FBUI/ReceiveUIfunction.lua"
)
$denied = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$deniedPaths | ForEach-Object { [void]$denied.Add($_) }

$runtimeFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$xmlQueue = [Collections.Generic.Queue[string]]::new()

function Normalize-RelativePath([string]$Path) {
    return $Path.Replace("\", "/").TrimStart("/")
}

function Add-RuntimeFile([string]$Path, [string]$ParentXml = "") {
    $relativePath = Normalize-RelativePath $Path
    $rootCandidate = Join-Path $repositoryRoot $relativePath
    if (-not (Test-Path -LiteralPath $rootCandidate -PathType Leaf) -and $ParentXml) {
        $parentDirectory = Split-Path -Parent $ParentXml
        $relativePath = Normalize-RelativePath (Join-Path $parentDirectory $relativePath)
        $rootCandidate = Join-Path $repositoryRoot $relativePath
    }
    if (-not (Test-Path -LiteralPath $rootCandidate -PathType Leaf)) {
        throw "Runtime dependency not found: $Path (from $ParentXml)"
    }
    if ($denied.Contains($relativePath)) {
        throw "Denied legacy file is still reachable from the runtime graph: $relativePath"
    }
    if ($runtimeFiles.Add($relativePath) -and [IO.Path]::GetExtension($relativePath) -eq ".xml") {
        $xmlQueue.Enqueue($relativePath)
    }
}

Add-RuntimeFile "BGLite.toc"
Add-RuntimeFile "Bindings.xml"
Add-RuntimeFile "addon_version.txt"
foreach ($line in Get-Content -LiteralPath $tocPath) {
    $entry = $line.Trim()
    if ($entry -and -not $entry.StartsWith("#") -and $entry -match "\.(lua|xml)$") {
        Add-RuntimeFile $entry
    }
}

while ($xmlQueue.Count -gt 0) {
    $xmlPath = $xmlQueue.Dequeue()
    $xml = Get-Content -LiteralPath (Join-Path $repositoryRoot $xmlPath) -Raw
    foreach ($match in [regex]::Matches($xml, '<(?:Script|Include)\s+file="([^"]+)"', "IgnoreCase")) {
        Add-RuntimeFile $match.Groups[1].Value $xmlPath
    }
}

foreach ($document in @("README.md", "CHANGELOG.md", "COPYRIGHT.md", "PRIVACY.md", "SECURITY.md", "CONTRIBUTORS.md")) {
    Add-RuntimeFile $document
}

foreach ($asset in Get-ChildItem -LiteralPath (Join-Path $repositoryRoot "Media") -File -Recurse) {
    Add-RuntimeFile $asset.FullName.Substring($repositoryRoot.Length + 1)
}
foreach ($notice in Get-ChildItem -LiteralPath (Join-Path $repositoryRoot "Libs") -File -Recurse |
    Where-Object { $_.Name -match '^(LICENSE|COPYING|NOTICE)(\.|$)' }) {
    Add-RuntimeFile $notice.FullName.Substring($repositoryRoot.Length + 1)
}

foreach ($path in $runtimeFiles) {
    if ($denied.Contains($path)) {
        throw "Denied legacy file selected for release: $path"
    }
}

if (Test-Path -LiteralPath $outputFullPath) {
    if (-not $Force) {
        throw "Output already exists. Pass -Force to replace it: $outputFullPath"
    }
    Remove-Item -LiteralPath $outputFullPath -Force
}
$outputDirectory = Split-Path -Parent $outputFullPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ("bgnext-release-" + [guid]::NewGuid().ToString("N"))
$addonRoot = Join-Path $stagingRoot "BGLite"
try {
    New-Item -ItemType Directory -Path $addonRoot -Force | Out-Null
    foreach ($relativePath in $runtimeFiles) {
        $source = Join-Path $repositoryRoot $relativePath
        $destination = Join-Path $addonRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
    }
    Compress-Archive -LiteralPath $addonRoot -DestinationPath $outputFullPath -CompressionLevel Optimal
} finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}

$checksumPath = $outputFullPath + ".sha256"
$checksum = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputFullPath).Hash.ToLowerInvariant()
Set-Content -LiteralPath $checksumPath -Value "$checksum  $([IO.Path]::GetFileName($outputFullPath))" -NoNewline

Write-Output "package=$outputFullPath"
Write-Output "checksum=$checksumPath"
Write-Output "files=$($runtimeFiles.Count)"
