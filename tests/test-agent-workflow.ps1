$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'tools\AgentWorkflow.psm1') -Force
$powerShellExe = Get-BGNPowerShellExe

$script:failures = 0

function Assert-Equal {
    param($Expected, $Actual, [string]$Name)
    if ($Expected -ne $Actual) {
        Write-Host "FAIL $Name expected=[$Expected] actual=[$Actual]" -ForegroundColor Red
        $script:failures++
    }
}

function Assert-True {
    param($Actual, [string]$Name)
    Assert-Equal $true ([bool]$Actual) $Name
}

$rules = Read-BGNRiskRules (Join-Path $repo 'tools\agent-risk-rules.json')

Assert-True (Test-Path -LiteralPath $powerShellExe) 'PowerShell interpreter resolves to an existing executable'
Assert-True (($powerShellExe -match 'pwsh\.exe$') -or ($powerShellExe -match 'powershell\.exe$')) 'resolves pwsh.exe or powershell.exe'

Assert-Equal 'low' (Get-BGNMinimumRisk @('README.md') '' $rules) 'README is low'
Assert-Equal 'low' (Get-BGNMinimumRisk @('Locales/zhCN.lua') '' $rules) 'Locale is low'
Assert-Equal 'normal' (Get-BGNMinimumRisk @('Core/BGNext/UIStyle.lua') '' $rules) 'runtime is normal'
Assert-Equal 'normal' (Get-BGNMinimumRisk @('tests/test_example.lua') '' $rules) 'tests are normal'
Assert-Equal 'high' (Get-BGNMinimumRisk @('Core/Module/Trade.lua') '' $rules) 'trade is high'
Assert-Equal 'high' (Get-BGNMinimumRisk @('BGLite.toc') '' $rules) 'TOC is high'
Assert-Equal 'high' (Get-BGNMinimumRisk @('docs/security/data-inventory.md') '' $rules) 'data inventory is high'
Assert-Equal 'high' (Get-BGNMinimumRisk @('README.md') '+ SendAddonMessage(' $rules) 'sensitive token escalates'
Assert-Equal 'high' (Get-BGNMinimumRisk @('README.md', 'Core/Module/Trade.lua') '' $rules) 'highest risk wins'
Assert-Equal 'normal' (Get-BGNMinimumRisk @('unknown.file') '' $rules) 'unknown defaults to normal'

Assert-Equal $false (Test-BGNRiskAllowed 'low' 'normal') 'downgrade is refused'
Assert-Equal $true (Test-BGNRiskAllowed 'high' 'normal') 'upgrade is allowed'

$lowPlan = @(Get-BGNVerificationPlan 'low' $true)
$normalPlan = @(Get-BGNVerificationPlan 'normal' $true)
$highPlan = @(Get-BGNVerificationPlan 'high' $true)
Assert-Equal 'diff-check,luac' (($lowPlan | ForEach-Object name) -join ',') 'low command plan'
Assert-Equal 'lua-tests,baseline,diff-check,luac' (($normalPlan | ForEach-Object name) -join ',') 'normal command plan'
Assert-Equal 'lua-tests,baseline,diff-check,luac,high-review' (($highPlan | ForEach-Object name) -join ',') 'high command plan'

$shortContext = [pscustomobject]@{
    status = 'ready_for_codex_review'
    requestedRisk = 'normal'
    detectedRisk = 'normal'
    repository = 'D:\vibe coding\BGN'
    worktree = 'D:\vibe coding\BGN\.worktrees\example'
    branch = 'codex/example'
    base = 'abc123'
    head = 'def456'
    files = @('README.md')
    results = @([pscustomobject]@{ name = 'diff-check'; status = 'PASS' })
    unverified = @('real game client')
}
$shortHandoff = New-BGNHandoffText $shortContext
Assert-True ($shortHandoff.Contains('head: def456')) 'short handoff has exact head'
Assert-True ($shortHandoff.Contains('- diff-check: PASS')) 'short handoff has compact result'
Assert-True (-not $shortHandoff.Contains('high_risk_review:')) 'normal handoff omits high review block'

$highContext = $shortContext.PSObject.Copy()
$highContext.detectedRisk = 'high'
$highContext.requestedRisk = 'high'
$highHandoff = New-BGNHandoffText $highContext
Assert-True ($highHandoff.Contains('high_risk_review:')) 'high handoff includes high review block'
Assert-True ($highHandoff.Contains('security/privacy: unverified')) 'high handoff preserves manual uncertainty'

$sandboxParent = Join-Path ([System.IO.Path]::GetTempPath()) ("bgn-agent-workflow-" + [guid]::NewGuid().ToString('N'))
$sandboxRepo = Join-Path $sandboxParent 'BGN'
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $sandboxRepo 'tools') | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo 'tools\agent-verify.ps1') -Destination (Join-Path $sandboxRepo 'tools\agent-verify.ps1')
    Copy-Item -LiteralPath (Join-Path $repo 'tools\AgentWorkflow.psm1') -Destination (Join-Path $sandboxRepo 'tools\AgentWorkflow.psm1')
    Copy-Item -LiteralPath (Join-Path $repo 'tools\agent-risk-rules.json') -Destination (Join-Path $sandboxRepo 'tools\agent-risk-rules.json')
    Push-Location $sandboxRepo
    git init -q
    git config user.email 'agent-workflow-test@example.invalid'
    git config user.name 'Agent Workflow Test'
    git remote add origin 'https://github.com/pitcn/bgnext.git'
    Set-Content -LiteralPath 'README.md' -Value 'seed' -Encoding utf8
    git add README.md
    git commit -q -m 'seed'
    New-Item -ItemType Directory -Force -Path 'Core\Module' | Out-Null
    Set-Content -LiteralPath 'Core\Module\Trade.lua' -Value '-- high-risk fixture' -Encoding utf8

    $verifyScript = Join-Path $sandboxRepo 'tools\agent-verify.ps1'
    # Native stderr is wrapped as NativeCommandError in Windows PowerShell 5.1;
    # relax Stop so an expected non-zero child exit is observed via $LASTEXITCODE.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lowOutput = & $powerShellExe -NoProfile -File $verifyScript -Risk low -Base HEAD -PlanOnly 2>&1
        $lowExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    Assert-True ($lowExit -ne 0) 'CLI refuses an explicit downgrade'
    Assert-True (($lowOutput -join "`n").Contains('below detected minimum')) 'downgrade explains the detected minimum'

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $highOutput = & $powerShellExe -NoProfile -File $verifyScript -Risk high -Base HEAD -PlanOnly 2>&1
        $highExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    Assert-Equal 0 $highExit 'CLI permits an explicit upgrade'
    Assert-True (($highOutput -join "`n").Contains('PLAN lua-tests,baseline,diff-check,luac,high-review')) 'CLI prints a compact high-risk plan'
} finally {
    Pop-Location
    if (Test-Path -LiteralPath $sandboxParent) {
        $resolvedSandbox = (Resolve-Path -LiteralPath $sandboxParent).Path
        $resolvedTemp = (Resolve-Path -LiteralPath ([System.IO.Path]::GetTempPath())).Path
        if (-not $resolvedSandbox.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove test sandbox outside temp: $resolvedSandbox"
        }
        Remove-Item -LiteralPath $resolvedSandbox -Recurse -Force
    }
}

$agentRules = Get-Content -LiteralPath (Join-Path $repo 'AGENTS.md') -Raw
$claudeRules = Get-Content -LiteralPath (Join-Path $repo 'CLAUDE.md') -Raw
$safetySummaryPath = Join-Path $repo 'docs\agents\safety-summary.md'
Assert-True (Test-Path -LiteralPath $safetySummaryPath) 'normal-risk safety summary exists'
$safetySummary = if (Test-Path -LiteralPath $safetySummaryPath) {
    Get-Content -LiteralPath $safetySummaryPath -Raw
} else { '' }
foreach ($tier in @('Low risk', 'Normal risk', 'High risk')) {
    Assert-True ($agentRules.Contains($tier)) "AGENTS documents $tier"
}
Assert-True ($agentRules.Contains('may upgrade but must never downgrade')) 'AGENTS forbids risk downgrade'
Assert-True ($agentRules.Contains('tools/agent-verify.ps1')) 'AGENTS points to unified verifier'
Assert-True ($agentRules.Contains('Do not copy historical BiaoGe code or assets')) 'BiaoGe boundary remains'
Assert-True ($agentRules.Contains('Never create player profiles')) 'player-profile boundary remains'
Assert-True ($agentRules.Contains('No automatic external transmission')) 'external-transmission boundary remains'
Assert-True ($agentRules.Contains('Do not claim unverified compatibility')) 'compatibility boundary remains'
Assert-True ($claudeRules.Contains('tools/agent-verify.ps1')) 'CLAUDE points to unified verifier'
foreach ($requiredLink in @('SECURITY.md', 'docs/policies/PRIVACY.md', 'docs/security/data-inventory.md', 'docs/adr/')) {
    Assert-True ($safetySummary.Contains($requiredLink)) "safety summary links $requiredLink"
}

if ($script:failures -gt 0) {
    Write-Host "agent-workflow tests failed=$script:failures" -ForegroundColor Red
    exit 1
}

Write-Output 'agent-workflow tests passed'
