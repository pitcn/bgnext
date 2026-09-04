# Agent Workflow Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace BGNext's one-size-fits-all Agent ceremony with enforceable low/normal/high risk tiers, one compact verification command, and automatically generated handoffs.

**Architecture:** A small PowerShell module owns deterministic risk classification and compact handoff formatting. A thin `agent-verify.ps1` entry point composes existing test and baseline scripts without duplicating them, rejects attempted risk downgrades, and leaves full security/release review mandatory for sensitive changes. Repository instructions reference a short safety summary for normal work and the complete governance set for high-risk work.

**Tech Stack:** PowerShell 7/Windows PowerShell-compatible scripts, JSON risk rules, Git, existing Lua 5.1 test and baseline tools, Markdown documentation.

---

## File map

- Create `tools/agent-risk-rules.json`: ordered path rules and sensitive diff tokens that define the minimum risk.
- Create `tools/AgentWorkflow.psm1`: pure classification, command-result, changed-Lua, and handoff helpers.
- Create `tools/agent-verify.ps1`: CLI orchestration over existing verification commands.
- Create `tests/test-agent-workflow.ps1`: isolated PowerShell tests for classification, downgrade refusal, command selection, and handoff shape.
- Create `docs/agents/safety-summary.md`: concise normal-risk context with links to authoritative documents.
- Modify `AGENTS.md`: replace the universal runtime workflow with risk-tiered requirements.
- Modify `CLAUDE.md`: keep Claude instructions aligned if it restates workflow requirements.

### Task 1: Deterministic risk classification

**Files:**
- Create: `tools/agent-risk-rules.json`
- Create: `tools/AgentWorkflow.psm1`
- Create: `tests/test-agent-workflow.ps1`

- [ ] **Step 1: Write failing classification tests**

Create `tests/test-agent-workflow.ps1` with a temporary rules file and assertions covering low documentation/Locale paths, normal runtime/tests, high trade/auction/data/release paths, sensitive-token escalation, highest-risk-wins, and unknown-path escalation to normal:

```powershell
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\AgentWorkflow.psm1') -Force

$failures = 0
function Assert-Equal($Expected, $Actual, [string]$Name) {
    if ($Expected -ne $Actual) {
        Write-Error "$Name expected=$Expected actual=$Actual" -ErrorAction Continue
        $script:failures++
    }
}

$rules = Read-BGNRiskRules (Join-Path $PSScriptRoot '..\tools\agent-risk-rules.json')
Assert-Equal low (Get-BGNMinimumRisk @('README.md') '' $rules) 'readme is low'
Assert-Equal low (Get-BGNMinimumRisk @('Locales/zhCN.lua') '' $rules) 'locale is low'
Assert-Equal normal (Get-BGNMinimumRisk @('Core/BGNext/UIStyle.lua') '' $rules) 'runtime is normal'
Assert-Equal normal (Get-BGNMinimumRisk @('tests/test_example.lua') '' $rules) 'tests are normal'
Assert-Equal high (Get-BGNMinimumRisk @('Core/Module/Trade.lua') '' $rules) 'trade is high'
Assert-Equal high (Get-BGNMinimumRisk @('BGLite.toc') '' $rules) 'toc is high'
Assert-Equal high (Get-BGNMinimumRisk @('README.md') '+ SendAddonMessage(' $rules) 'sensitive token escalates'
Assert-Equal high (Get-BGNMinimumRisk @('README.md','Core/Module/Trade.lua') '' $rules) 'highest risk wins'
Assert-Equal normal (Get-BGNMinimumRisk @('unknown.file') '' $rules) 'unknown defaults normal'

if ($failures -gt 0) { exit 1 }
Write-Output 'agent-workflow tests passed'
```

- [ ] **Step 2: Run the test and observe RED**

Run:

```powershell
pwsh -NoProfile -File tests/test-agent-workflow.ps1
```

Expected: failure because `AgentWorkflow.psm1` and the risk rules do not exist.

- [ ] **Step 3: Add explicit JSON rules**

Create `tools/agent-risk-rules.json` with this structure and conservative ordering:

```json
{
  "defaultRisk": "normal",
  "lowPaths": [
    "README.md",
    "CHANGELOG.md",
    "docs/**",
    "Locales/**"
  ],
  "normalPaths": [
    "tests/**",
    "Core/**"
  ],
  "highPaths": [
    "AGENTS.md",
    "CLAUDE.md",
    "SECURITY.md",
    "BGLite.toc",
    ".github/workflows/**",
    "docs/adr/**",
    "docs/policies/**",
    "docs/security/**",
    "docs/baseline/**",
    "tools/build-release.ps1",
    "Core/Module/Trade.lua",
    "Core/Module/Auction.lua",
    "Core/BGNext/CurrentTrade.lua",
    "Core/BGNext/DataLifecycle.lua",
    "Core/BGNext/AuctionSender.lua"
  ],
  "sensitiveDiffPatterns": [
    "SavedVariables",
    "schemaVersion",
    "SendAddonMessage",
    "SendChatMessage",
    "C_ChatInfo.SendAddonMessage",
    "currentSettlement",
    "BG.trade",
    "BG.SendStartAuctionMsg"
  ]
}
```

High rules override normal rules, and normal rules override low rules. Governance documents under `docs/**` are therefore high despite the broad low documentation rule.

- [ ] **Step 4: Implement the pure classifier module**

Create `tools/AgentWorkflow.psm1` with exported functions:

```powershell
$script:RiskRank = @{ low = 1; normal = 2; high = 3 }

function Read-BGNRiskRules([string]$Path) {
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Test-BGNGlob([string]$Path, [string]$Pattern) {
    $normalized = $Path.Replace('\', '/')
    $escaped = [regex]::Escape($Pattern.Replace('\', '/'))
    $regex = '^' + $escaped.Replace('\*\*', '.*').Replace('\*', '[^/]*') + '$'
    return $normalized -match $regex
}

function Get-BGNPathRisk([string]$Path, $Rules) {
    foreach ($risk in @('high','normal','low')) {
        $property = "${risk}Paths"
        foreach ($pattern in $Rules.$property) {
            if (Test-BGNGlob $Path $pattern) { return $risk }
        }
    }
    return [string]$Rules.defaultRisk
}

function Get-BGNMinimumRisk([string[]]$Paths, [string]$DiffText, $Rules) {
    $minimum = 'low'
    foreach ($path in $Paths) {
        $candidate = Get-BGNPathRisk $path $Rules
        if ($script:RiskRank[$candidate] -gt $script:RiskRank[$minimum]) { $minimum = $candidate }
    }
    foreach ($pattern in $Rules.sensitiveDiffPatterns) {
        if ($DiffText -match [regex]::Escape([string]$pattern)) { return 'high' }
    }
    return $minimum
}

function Test-BGNRiskAllowed([string]$Requested, [string]$Minimum) {
    return $script:RiskRank[$Requested] -ge $script:RiskRank[$Minimum]
}

Export-ModuleMember -Function Read-BGNRiskRules,Test-BGNGlob,Get-BGNPathRisk,Get-BGNMinimumRisk,Test-BGNRiskAllowed
```

- [ ] **Step 5: Run the classifier test and observe GREEN**

Run:

```powershell
pwsh -NoProfile -File tests/test-agent-workflow.ps1
```

Expected: `agent-workflow tests passed` and exit code 0.

- [ ] **Step 6: Commit classifier and tests**

```powershell
git add tools/agent-risk-rules.json tools/AgentWorkflow.psm1 tests/test-agent-workflow.ps1
git commit -m "feat: classify agent workflow risk"
```

### Task 2: One-command verification orchestration

**Files:**
- Modify: `tools/AgentWorkflow.psm1`
- Create: `tools/agent-verify.ps1`
- Modify: `tests/test-agent-workflow.ps1`

- [ ] **Step 1: Add failing command-plan and downgrade tests**

Extend `tests/test-agent-workflow.ps1` with assertions for `Get-BGNVerificationPlan`:

```powershell
Assert-Equal 'diff-check,luac' ((Get-BGNVerificationPlan low $false).name -join ',') 'low command plan'
Assert-Equal 'lua-tests,baseline,diff-check,luac' ((Get-BGNVerificationPlan normal $true).name -join ',') 'normal command plan'
Assert-Equal 'lua-tests,baseline,diff-check,luac,high-review' ((Get-BGNVerificationPlan high $true).name -join ',') 'high command plan'
Assert-Equal $false (Test-BGNRiskAllowed low normal) 'downgrade refused'
Assert-Equal $true (Test-BGNRiskAllowed high normal) 'upgrade allowed'
```

- [ ] **Step 2: Run and observe RED for missing planning function**

Run `pwsh -NoProfile -File tests/test-agent-workflow.ps1`.

Expected: failure naming `Get-BGNVerificationPlan`.

- [ ] **Step 3: Implement the command planner**

Add to `tools/AgentWorkflow.psm1` and export it:

```powershell
function Get-BGNVerificationPlan([string]$Risk, [bool]$HasLua) {
    $plan = @()
    if ($Risk -ne 'low') {
        $plan += @{ name = 'lua-tests'; command = 'pwsh -NoProfile -File tools/run-lua-tests.ps1' }
        $plan += @{ name = 'baseline'; command = 'pwsh -NoProfile -File tools/verify-baseline.ps1' }
    }
    $plan += @{ name = 'diff-check'; command = 'git diff --check' }
    if ($HasLua) { $plan += @{ name = 'luac'; command = 'changed-lua' } }
    if ($Risk -eq 'high') { $plan += @{ name = 'high-review'; command = 'manual-checklist' } }
    return $plan
}
```

For low with no Lua, omit `luac`; update the low assertion to pass `$true` so it expects `diff-check,luac`.

- [ ] **Step 4: Implement `tools/agent-verify.ps1`**

The entry point must:

```powershell
param(
    [ValidateSet('low','normal','high')][string]$Risk = 'normal',
    [string]$Base = 'origin/main',
    [switch]$WriteHandoff
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repo
Import-Module (Join-Path $PSScriptRoot 'AgentWorkflow.psm1') -Force
$rules = Read-BGNRiskRules (Join-Path $PSScriptRoot 'agent-risk-rules.json')

$origin = (git remote get-url origin).Trim()
if ($origin -ne 'https://github.com/pitcn/bgnext.git') { throw "Unexpected origin: $origin" }
$common = (git rev-parse --path-format=absolute --git-common-dir).Trim().Replace('\','/')
if ($common -notmatch '/BGN/\.git$') { throw "Unexpected common git dir: $common" }

$paths = @(git diff --name-only "$Base...HEAD")
$diffText = (git diff --unified=0 "$Base...HEAD") -join "`n"
$minimum = Get-BGNMinimumRisk $paths $diffText $rules
if (-not (Test-BGNRiskAllowed $Risk $minimum)) {
    throw "Requested risk '$Risk' is below detected minimum '$minimum'."
}

$luaPaths = @($paths | Where-Object { $_ -like '*.lua' })
$plan = Get-BGNVerificationPlan $Risk ($luaPaths.Count -gt 0)
$results = @()
```

Execute the plan sequentially. `lua-tests` and `baseline` call the existing scripts; `diff-check` runs `git diff --check "$Base...HEAD"`; `luac` resolves the repository's configured Lua 5.1 compiler and parses only changed Lua files; `high-review` prints a compact checklist for data, protocol, provenance, compatibility, game install, SavedVariables, and release status without marking those items passed. Stop on the first failed command and exit nonzero.

Successful output must remain compact:

```text
risk=requested:normal detected:normal files:4 lua:2
PASS lua-tests
PASS baseline
PASS diff-check
PASS luac
RESULT pass head:<sha> base:<sha>
```

- [ ] **Step 5: Test downgrade refusal and command selection through the CLI**

Add a `-PlanOnly` switch used only for deterministic tests. It performs repository/risk detection and prints planned command names without running them. Test a temporary commit containing a sensitive token and assert that `-Risk low -PlanOnly` exits nonzero while `-Risk high -PlanOnly` succeeds.

- [ ] **Step 6: Run tests and a normal dry run**

```powershell
pwsh -NoProfile -File tests/test-agent-workflow.ps1
pwsh -NoProfile -File tools/agent-verify.ps1 -Risk high -Base origin/main
```

Expected: test exit 0; the design/plan change is detected high because it changes governance process, and all automated commands pass while the high-risk checklist remains explicitly unverified.

- [ ] **Step 7: Commit verification orchestration**

```powershell
git add tools/AgentWorkflow.psm1 tools/agent-verify.ps1 tests/test-agent-workflow.ps1
git commit -m "feat: add risk-aware agent verification"
```

### Task 3: Compact automatic handoffs

**Files:**
- Modify: `tools/AgentWorkflow.psm1`
- Modify: `tools/agent-verify.ps1`
- Modify: `tests/test-agent-workflow.ps1`

- [ ] **Step 1: Add failing handoff-shape tests**

Add tests for `New-BGNHandoffText` asserting that a short handoff contains repository, worktree, branch, exact head/base, detected/requested risk, changed files, compact command status and unverified items, while omitting full command logs. Assert that high risk adds the full security/privacy/provenance/baseline/compatibility headings.

- [ ] **Step 2: Run and observe RED**

Run `pwsh -NoProfile -File tests/test-agent-workflow.ps1`.

Expected: failure naming `New-BGNHandoffText`.

- [ ] **Step 3: Implement deterministic handoff rendering**

Add and export:

```powershell
function New-BGNHandoffText($Context) {
    $lines = @(
        "# Agent handoff",
        "",
        "status: $($Context.status)",
        "risk: requested=$($Context.requestedRisk) detected=$($Context.detectedRisk)",
        "repository: $($Context.repository)",
        "worktree: $($Context.worktree)",
        "branch: $($Context.branch)",
        "base: $($Context.base)",
        "head: $($Context.head)",
        "",
        "changed_files:",
        (($Context.files | ForEach-Object { "- $_" }) -join "`n"),
        "",
        "verification:",
        (($Context.results | ForEach-Object { "- $($_.name): $($_.status)" }) -join "`n"),
        "",
        "unverified:",
        (($Context.unverified | ForEach-Object { "- $_" }) -join "`n")
    )
    if ($Context.detectedRisk -eq 'high') {
        $lines += @('', 'high_risk_review:', '- security/privacy: unverified', '- provenance: unverified', '- baseline: see verification', '- compatibility/game client: unverified')
    }
    return $lines -join "`n"
}
```

- [ ] **Step 4: Wire `-WriteHandoff`**

After successful verification, resolve the common Git directory exactly as required by repository policy, create `.local/handoffs/inbox`, sanitize the branch, and write `yyyyMMdd-HHmmss--<branch>--agent-verify.md` with UTF-8. Do not commit `.local` and do not include full logs, environment secrets, usernames, player data, screenshots or SavedVariables content.

- [ ] **Step 5: Run tests and inspect one generated handoff**

```powershell
pwsh -NoProfile -File tests/test-agent-workflow.ps1
pwsh -NoProfile -File tools/agent-verify.ps1 -Risk high -Base origin/main -WriteHandoff
```

Expected: tests pass; one new local handoff exists under the canonical repository `.local/handoffs/inbox`; it contains exact SHAs and compact PASS/unverified entries but no full logs.

- [ ] **Step 6: Commit handoff automation**

```powershell
git add tools/AgentWorkflow.psm1 tools/agent-verify.ps1 tests/test-agent-workflow.ps1
git commit -m "feat: generate compact agent handoffs"
```

### Task 4: Risk-tiered repository instructions

**Files:**
- Create: `docs/agents/safety-summary.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Write the concise safety summary**

The summary must state, without weakening the originals:

- No BiaoGe code/assets copying; behavior study only under ADR-0003.
- No player profiles, telemetry, hidden communication or automatic external transmission.
- Current settlement is one raid/seven days; personal features stay local.
- Uncertain provenance/privacy/data/protocol work escalates high and reads full authoritative documents.
- Links to `SECURITY.md`, `docs/policies/PRIVACY.md`, `docs/policies/COMPLIANCE.md`, `docs/security/data-inventory.md`, and `docs/adr/`.

- [ ] **Step 2: Replace universal ceremony in `AGENTS.md` with the approved tiers**

Keep all “Non-negotiable boundaries” unchanged. Replace “Required workflow before runtime changes” and “Local completion handoff” with:

- low: `AGENTS.md` + direct context, no mandatory full-document reread or RED test for non-behavior changes, `agent-verify -Risk low` before completion.
- normal: `AGENTS.md` + safety summary + relevant ADR/module, RED test for behavior fixes, one full `agent-verify -Risk normal` before completion, short automatic handoff.
- high: complete current reading/audit/TDD/full handoff, `agent-verify -Risk high`, plus release-only checks when applicable.
- explicit statement that the rules file supplies a minimum; Agents may upgrade but may not downgrade.
- issue/PR comments only for blockers, decisions and completion; do not paste full logs when a compact result and CI link suffice.

- [ ] **Step 3: Align `CLAUDE.md` without duplicating policy**

Make `CLAUDE.md` point to `AGENTS.md`, the detected risk command, and the safety summary. Remove any contradictory universal reread/handoff wording, but retain Claude-specific operating instructions.

- [ ] **Step 4: Add documentation assertions**

Extend `tests/test-agent-workflow.ps1` to assert that `AGENTS.md` contains all three tier names, the no-downgrade rule, the unified command, and unchanged phrases for baseline verification, BiaoGe copying, player profiles, external transmission and unverified compatibility.

- [ ] **Step 5: Run the documentation tests**

```powershell
pwsh -NoProfile -File tests/test-agent-workflow.ps1
```

Expected: `agent-workflow tests passed`.

- [ ] **Step 6: Commit documentation**

```powershell
git add AGENTS.md CLAUDE.md docs/agents/safety-summary.md tests/test-agent-workflow.ps1
git commit -m "docs: adopt risk-tiered agent workflow"
```

### Task 5: End-to-end verification and PR

**Files:**
- Modify only if verification reveals a defect in the files above.

- [ ] **Step 1: Run the workflow's own tests**

```powershell
pwsh -NoProfile -File tests/test-agent-workflow.ps1
```

Expected: `agent-workflow tests passed`.

- [ ] **Step 2: Run the new high-risk gate with automatic handoff**

```powershell
pwsh -NoProfile -File tools/agent-verify.ps1 -Risk high -Base origin/main -WriteHandoff
```

Expected: Lua suite and baseline pass, changed PowerShell/JSON/docs checks pass, diff-check passes, high-risk manual items remain explicitly listed as unverified, and a compact handoff is written.

- [ ] **Step 3: Run PowerShell syntax checks**

```powershell
$files = 'tools/AgentWorkflow.psm1','tools/agent-verify.ps1','tests/test-agent-workflow.ps1'
foreach ($file in $files) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { $errors | ForEach-Object { Write-Error $_ }; exit 1 }
}
```

Expected: exit code 0 with no parser errors.

- [ ] **Step 4: Verify scope and working tree**

```powershell
git diff --check origin/main...HEAD
git status --short
git log --oneline origin/main..HEAD
```

Expected: only the design, plan, workflow scripts/tests and approved instruction documents differ; no addon runtime, SavedVariables, protocol, package or game-install file changes.

- [ ] **Step 5: Create the GitHub Issue and PR**

Create one maintenance Issue describing token/time reduction, non-negotiable safety preservation and acceptance criteria. Capture the number returned by `gh issue create` in `$issueNumber`, then create a PR from `codex/agent-workflow-optimization` to `main` whose body contains `Closes #$issueNumber`; summarize risk rules, downgrade protection, command outputs and unverified manual checks. Do not merge it automatically.

- [ ] **Step 6: Final review handoff**

Report the Issue URL, PR URL, exact head/base, fresh verification output, generated handoff path, and any high-risk items requiring human review. Do not claim the workflow reduces token use by a measured percentage unless actual before/after measurements exist.
