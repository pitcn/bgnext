$script:RiskRank = @{ low = 1; normal = 2; high = 3 }

function Read-BGNRiskRules {
    param([Parameter(Mandatory)][string]$Path)
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Test-BGNGlob {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Pattern
    )
    $normalized = $Path.Replace('\', '/')
    $escaped = [regex]::Escape($Pattern.Replace('\', '/'))
    $regex = '^' + $escaped.Replace('\*\*', '.*').Replace('\*', '[^/]*') + '$'
    return $normalized -match $regex
}

function Get-BGNPathRisk {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Rules
    )
    foreach ($risk in @('high', 'normal', 'low')) {
        $property = "${risk}Paths"
        foreach ($pattern in $Rules.$property) {
            if (Test-BGNGlob -Path $Path -Pattern $pattern) {
                return $risk
            }
        }
    }
    return [string]$Rules.defaultRisk
}

function Get-BGNMinimumRisk {
    param(
        [string[]]$Paths = @(),
        [string]$DiffText = '',
        [Parameter(Mandatory)]$Rules
    )
    $minimum = 'low'
    foreach ($path in $Paths) {
        $candidate = Get-BGNPathRisk -Path $path -Rules $Rules
        if ($script:RiskRank[$candidate] -gt $script:RiskRank[$minimum]) {
            $minimum = $candidate
        }
    }
    foreach ($pattern in $Rules.sensitiveDiffPatterns) {
        if ($DiffText -match [regex]::Escape([string]$pattern)) {
            return 'high'
        }
    }
    return $minimum
}

function Test-BGNRiskAllowed {
    param(
        [Parameter(Mandatory)][ValidateSet('low', 'normal', 'high')][string]$Requested,
        [Parameter(Mandatory)][ValidateSet('low', 'normal', 'high')][string]$Minimum
    )
    return $script:RiskRank[$Requested] -ge $script:RiskRank[$Minimum]
}

function Get-BGNPowerShellExe {
    $exeName = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    $homeExe = Join-Path $PSHOME $exeName
    if (Test-Path -LiteralPath $homeExe -PathType Leaf) { return $homeExe }
    $fromPath = Get-Command $exeName -ErrorAction SilentlyContinue
    if ($fromPath) { return $fromPath.Source }
    throw "Cannot resolve the PowerShell interpreter '$exeName'. Install PowerShell 5.1 or PowerShell 7."
}

function Get-BGNVerificationPlan {
    param(
        [Parameter(Mandatory)][ValidateSet('low', 'normal', 'high')][string]$Risk,
        [Parameter(Mandatory)][bool]$HasLua
    )
    $plan = @()
    if ($Risk -ne 'low') {
        $plan += [pscustomobject]@{ name = 'lua-tests'; command = 'tools/run-lua-tests.ps1' }
        $plan += [pscustomobject]@{ name = 'baseline'; command = 'tools/verify-baseline.ps1' }
    }
    $plan += [pscustomobject]@{ name = 'diff-check'; command = 'git diff --check' }
    if ($HasLua) {
        $plan += [pscustomobject]@{ name = 'luac'; command = 'changed-lua' }
    }
    if ($Risk -eq 'high') {
        $plan += [pscustomobject]@{ name = 'high-review'; command = 'manual-checklist' }
    }
    return $plan
}

function New-BGNHandoffText {
    param([Parameter(Mandatory)]$Context)
    $lines = @(
        '# Agent handoff',
        '',
        "status: $($Context.status)",
        "risk: requested=$($Context.requestedRisk) detected=$($Context.detectedRisk)",
        "repository: $($Context.repository)",
        "worktree: $($Context.worktree)",
        "branch: $($Context.branch)",
        "base: $($Context.base)",
        "head: $($Context.head)",
        '',
        'changed_files:',
        (($Context.files | ForEach-Object { "- $_" }) -join "`n"),
        '',
        'verification:',
        (($Context.results | ForEach-Object { "- $($_.name): $($_.status)" }) -join "`n"),
        '',
        'unverified:',
        (($Context.unverified | ForEach-Object { "- $_" }) -join "`n")
    )
    if ($Context.detectedRisk -eq 'high') {
        $lines += @(
            '',
            'high_risk_review:',
            '- security/privacy: unverified',
            '- provenance: unverified',
            '- baseline: see verification',
            '- compatibility/game client: unverified'
        )
    }
    return $lines -join "`n"
}

Export-ModuleMember -Function @(
    'Read-BGNRiskRules',
    'Test-BGNGlob',
    'Get-BGNPathRisk',
    'Get-BGNMinimumRisk',
    'Test-BGNRiskAllowed',
    'Get-BGNPowerShellExe',
    'Get-BGNVerificationPlan',
    'New-BGNHandoffText'
)
