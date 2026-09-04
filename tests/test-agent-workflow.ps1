$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'tools\AgentWorkflow.psm1') -Force

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

$verifyScript = Join-Path $repo 'tools\agent-verify.ps1'
$lowOutput = & pwsh -NoProfile -File $verifyScript -Risk low -Base origin/main -PlanOnly 2>&1
$lowExit = $LASTEXITCODE
Assert-True ($lowExit -ne 0) 'CLI refuses an explicit downgrade'
Assert-True (($lowOutput -join "`n").Contains('below detected minimum')) 'downgrade explains the detected minimum'

$highOutput = & pwsh -NoProfile -File $verifyScript -Risk high -Base origin/main -PlanOnly 2>&1
$highExit = $LASTEXITCODE
Assert-Equal 0 $highExit 'CLI permits an explicit upgrade'
Assert-True (($highOutput -join "`n").Contains('PLAN lua-tests,baseline,diff-check,high-review')) 'CLI prints a compact high-risk plan'

if ($script:failures -gt 0) {
    Write-Host "agent-workflow tests failed=$script:failures" -ForegroundColor Red
    exit 1
}

Write-Output 'agent-workflow tests passed'
