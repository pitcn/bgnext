param(
    [ValidateSet('low', 'normal', 'high')]
    [string]$Risk = 'normal',
    [string]$Base = 'origin/main',
    [switch]$PlanOnly,
    [switch]$WriteHandoff
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repo
Import-Module (Join-Path $PSScriptRoot 'AgentWorkflow.psm1') -Force

function Invoke-Checked {
    param([string]$Name, [scriptblock]$Action)
    $commandOutput = @(& $Action 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $detail = ($commandOutput | Select-Object -Last 20) -join "`n"
        throw "$Name failed with exit code $exitCode`n$detail"
    }
    Write-Host "PASS $Name"
    return [pscustomobject]@{ name = $Name; status = 'PASS' }
}

function Get-ChangedPaths {
    param([string]$DiffBase)
    $all = @()
    $all += @(git diff --name-only "$DiffBase...HEAD")
    $all += @(git diff --name-only)
    $all += @(git diff --cached --name-only)
    $all += @(git ls-files --others --exclude-standard)
    return @($all | Where-Object { $_ } | Sort-Object -Unique)
}

function Get-DiffText {
    param([string]$DiffBase, [string[]]$Paths)
    $chunks = @()
    $chunks += @(git diff --unified=0 "$DiffBase...HEAD")
    $chunks += @(git diff --unified=0)
    $chunks += @(git diff --cached --unified=0)
    $tracked = @(git ls-files)
    foreach ($path in $Paths) {
        if ($tracked -notcontains $path) {
            $absolute = Join-Path $repo $path
            if (Test-Path -LiteralPath $absolute -PathType Leaf) {
                $chunks += Get-Content -LiteralPath $absolute -Raw
            }
        }
    }
    return $chunks -join "`n"
}

function Find-Luac51 {
    $command = Get-Command luac5.1, luac -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    foreach ($path in @(
        'C:\Program Files (x86)\Lua\5.1\luac.exe',
        'C:\Program Files\Lua\5.1\luac.exe'
    )) {
        if (Test-Path -LiteralPath $path) { return $path }
    }
    throw 'Lua 5.1 luac is required when changed Lua files are present.'
}

$origin = (git remote get-url origin).Trim()
if ($origin -ne 'https://github.com/pitcn/bgnext.git') {
    throw "Unexpected origin: $origin"
}
$common = (git rev-parse --path-format=absolute --git-common-dir).Trim().Replace('\', '/')
if ($common -notmatch '/BGN/\.git$') {
    throw "Unexpected common git dir: $common"
}

git rev-parse --verify $Base *> $null
if ($LASTEXITCODE -ne 0) { throw "Base does not resolve: $Base" }

$rules = Read-BGNRiskRules (Join-Path $PSScriptRoot 'agent-risk-rules.json')
$paths = @(Get-ChangedPaths $Base)
$diffText = Get-DiffText $Base $paths
$minimum = Get-BGNMinimumRisk $paths $diffText $rules
if (-not (Test-BGNRiskAllowed $Risk $minimum)) {
    throw "Requested risk '$Risk' is below detected minimum '$minimum'."
}

$luaPaths = @($paths | Where-Object { $_ -like '*.lua' })
$plan = @(Get-BGNVerificationPlan $Risk ($luaPaths.Count -gt 0))
$planNames = ($plan | ForEach-Object name) -join ','
Write-Output "risk=requested:$Risk detected:$minimum files:$($paths.Count) lua:$($luaPaths.Count)"
if ($PlanOnly) {
    Write-Output "PLAN $planNames"
    exit 0
}

$results = @()
foreach ($step in $plan) {
    switch ($step.name) {
        'lua-tests' {
            $results += Invoke-Checked 'lua-tests' { pwsh -NoProfile -File tools/run-lua-tests.ps1 }
        }
        'baseline' {
            $results += Invoke-Checked 'baseline' { pwsh -NoProfile -File tools/verify-baseline.ps1 }
        }
        'diff-check' {
            $results += Invoke-Checked 'diff-check' {
                git diff --check "$Base...HEAD"
                if ($LASTEXITCODE -ne 0) { throw 'committed diff-check failed' }
                git diff --check
                if ($LASTEXITCODE -ne 0) { throw 'working-tree diff-check failed' }
                git diff --cached --check
            }
        }
        'luac' {
            $luac = Find-Luac51
            $results += Invoke-Checked 'luac' {
                foreach ($path in $luaPaths) {
                    $absolute = Join-Path $repo $path
                    if (Test-Path -LiteralPath $absolute -PathType Leaf) {
                        & $luac -p $absolute
                        if ($LASTEXITCODE -ne 0) { throw "luac failed: $path" }
                    }
                }
            }
        }
        'high-review' {
            Write-Output 'REVIEW_REQUIRED data/protocol/provenance/compatibility/game-install/SavedVariables/release'
            $results += [pscustomobject]@{ name = 'high-review'; status = 'REVIEW_REQUIRED' }
        }
    }
}

$head = (git rev-parse HEAD).Trim()
$baseSha = (git rev-parse $Base).Trim()
Write-Output "RESULT pass head:$head base:$baseSha"

if ($WriteHandoff) {
    $branch = (git branch --show-current).Trim()
    $repositoryHome = Split-Path -Parent $common
    $inbox = Join-Path $repositoryHome '.local\handoffs\inbox'
    New-Item -ItemType Directory -Force -Path $inbox | Out-Null
    $safeBranch = ($branch -replace '[^A-Za-z0-9._-]', '-')
    $name = "$(Get-Date -Format 'yyyyMMdd-HHmmss')--$safeBranch--agent-verify.md"
    $handoffPath = Join-Path $inbox $name
    $context = [pscustomobject]@{
        status = 'ready_for_codex_review'
        requestedRisk = $Risk
        detectedRisk = $minimum
        repository = $repositoryHome
        worktree = $repo
        branch = $branch
        base = $baseSha
        head = $head
        files = $paths
        results = $results
        unverified = @('real game client', 'game installation contents', 'SavedVariables instance')
    }
    New-BGNHandoffText $context | Set-Content -LiteralPath $handoffPath -Encoding utf8
    Write-Output "HANDOFF $handoffPath"
}
