# Role Overview Max-Level Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a default-on max-level-only view to the own-character overview, with an opt-in setting to show non-max-level characters, without deleting or changing stored character data.

**Architecture:** Keep the rule in the pure role-overview projection so current-realm and all-realm views, counts, totals, stripes, and window size share one filter. Keep SavedVariables access and the checkbox in `RoleOverviewSettings.lua`; pass only the resolved boolean and existing actual client level cap `BG.fullLevel` into the projection provider. Do not use `BG.fullLevel_RoleOverview`, which is the legacy overview's lower display threshold rather than the level cap.

**Tech Stack:** Lua 5.1, WoW Frame API, existing plain-Lua test harness, PowerShell verification scripts.

---

### Task 1: Lock the projection rule with failing tests

**Files:**
- Modify: `tests/test_own_character_view.lua`

- [ ] **Step 1: Write the failing projection and setting tests**

Add mixed max-level and low-level snapshots and assert the default filter, opt-in behavior, safe missing-threshold fallback, cross-realm behavior, totals, source immutability, and boolean-only setting storage:

```lua
local levelSnapshots = {
    snapshot({ player = "Max", level = 80, money = 10000 }),
    snapshot({ player = "Alt", level = 1, money = 90000 }),
}
local maxOnly = View.project(input({ snapshots = levelSnapshots, maxLevel = 80 }))
test.eq(maxOnly.characterCount, 1, "non-max characters are hidden by default")
test.eq(maxOnly.resource.rows[1].player, "Max", "the max-level character remains visible")
test.eq(maxOnly.resource.totals.money, 10000, "totals exclude hidden characters")
test.eq(levelSnapshots[2].level, 1, "filtering never mutates snapshots")

local allLevels = View.project(input({
    snapshots = levelSnapshots, maxLevel = 80, showNonMaxLevel = true,
}))
test.eq(allLevels.characterCount, 2, "the opt-in setting restores non-max characters")

local noThreshold = View.project(input({ snapshots = levelSnapshots, maxLevel = nil }))
test.eq(noThreshold.characterCount, 2, "a missing client threshold fails open")

local preferenceRoot = {}
test.eq(Settings.showNonMaxLevel(preferenceRoot), false, "the setting defaults off")
Settings.setShowNonMaxLevel(preferenceRoot, true)
test.eq(Settings.showNonMaxLevel(preferenceRoot), true, "the setting stores explicit opt-in")
Settings.setShowNonMaxLevel(preferenceRoot, "yes")
test.eq(Settings.showNonMaxLevel(preferenceRoot), true, "invalid values do not overwrite the setting")
```

- [ ] **Step 2: Run the test suite and verify RED**

Run: `powershell -ExecutionPolicy Bypass -File tools/run-lua-tests.ps1`

Expected: failure because the low-level row is still projected and the new setting helpers do not exist.

- [ ] **Step 3: Commit the failing test**

```powershell
git add -- tests/test_own_character_view.lua
git commit -m "test: cover role overview level filter"
```

### Task 2: Implement the pure filter and settings UI

**Files:**
- Modify: `Core/BGNext/OwnCharactersView.lua`
- Modify: `Core/BGNext/RoleOverviewSettings.lua`
- Modify: `Core/BGNext/RoleOverviewEntry.lua`
- Modify: `Locales/enUS.lua`
- Modify: `Locales/zhCN.lua`
- Modify: `Locales/zhTW.lua`

- [ ] **Step 1: Add boolean-only preference helpers**

Add to `RoleOverviewSettings.lua`:

```lua
function M.showNonMaxLevel(root)
    local settings = type(root) == "table" and root.settings or nil
    return type(settings) == "table" and settings.roleOverviewShowNonMaxLevel == true
end

function M.setShowNonMaxLevel(root, value)
    if type(root) ~= "table" or type(value) ~= "boolean" then return end
    root.settings = type(root.settings) == "table" and root.settings or {}
    root.settings.roleOverviewShowNonMaxLevel = value
end
```

- [ ] **Step 2: Filter before sorting and row construction**

Extend `buildRows` with `maxLevel` and `showNonMaxLevel`. Preserve safe fallback when the client threshold is unavailable:

```lua
local function levelVisible(snapshot, maxLevel, showNonMaxLevel)
    if showNonMaxLevel == true then return true end
    if type(maxLevel) ~= "number" or maxLevel <= 0 then return true end
    return type(snapshot.level) == "number" and snapshot.level >= maxLevel
end
```

Require `levelVisible(...)` together with the existing realm condition before inserting an entry. Call it from `M.project` with `input.maxLevel` and `input.showNonMaxLevel` so counts, totals, stripes, ambiguous-name handling, and dimensions all consume the same filtered entries.

- [ ] **Step 3: Pass the existing client threshold and preference into the provider**

Add to the `view.project` input in `RoleOverviewEntry.lua`:

```lua
maxLevel = BG.fullLevel,
showNonMaxLevel = settings and settings.showNonMaxLevel(root) or false,
```

- [ ] **Step 4: Add the checkbox without changing module enablement**

In `RoleOverviewSettings.BuildPanel`, add a separate checkbox above `启用角色总览`:

```lua
local showNonMaxCheck = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
showNonMaxCheck:SetSize(30, 30)
showNonMaxCheck.Text:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
showNonMaxCheck.Text:SetText(L["显示非满级角色"])
showNonMaxCheck:SetScript("OnClick", function(self)
    M.setShowNonMaxLevel(root, self:GetChecked() and true or false)
    refresh()
end)
showNonMaxCheck:SetScript("OnShow", function(self)
    self:SetChecked(M.showNonMaxLevel(root))
end)
```

Include this control in `layoutLowerControls` and increase panel height so it cannot overlap the enable/clear controls.

Register the key in `Locales/zhCN.lua`, add `Show Non-Max-Level Characters` to `Locales/enUS.lua`, and add `顯示非滿級角色` to `Locales/zhTW.lua`; the locale suite requires every BGNext-owned static key in all locale files.

- [ ] **Step 5: Run focused and full tests and verify GREEN**

Run: `powershell -ExecutionPolicy Bypass -File tools/run-lua-tests.ps1`

Expected: every Lua suite passes, including the new default-hidden and opt-in cases.

- [ ] **Step 6: Commit the implementation**

```powershell
git add -- Core/BGNext/OwnCharactersView.lua Core/BGNext/RoleOverviewSettings.lua Core/BGNext/RoleOverviewEntry.lua Locales/enUS.lua Locales/zhCN.lua Locales/zhTW.lua tests/test_own_character_view.lua tests/test_role_overview_entry.lua
git commit -m "feat: hide non-max characters by default"
```

### Task 3: Document storage and run release-grade verification

**Files:**
- Modify: `docs/security/data-inventory.md`
- Modify: `docs/baseline/BGNext-overrides.sha256`

- [ ] **Step 1: Document the display-only field**

Add a data-inventory row:

```markdown
| `settings.roleOverviewShowNonMaxLevel` | Explicit user display choice, boolean only | Show locally stored non-max-level own characters in the role overview; absence/invalid values keep them hidden | Local until changed or all BGNext data is cleared; never deletes snapshots | None | Role overview settings checkbox | Low |
```

- [ ] **Step 2: Refresh only the three changed locale override hashes**

Run:

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath 'Locales/enUS.lua','Locales/zhCN.lua','Locales/zhTW.lua'
```

Replace only the `Locales/enUS.lua`, `Locales/zhCN.lua`, and `Locales/zhTW.lua` hashes in `docs/baseline/BGNext-overrides.sha256`. The three `Core/BGNext` runtime files are BGNext-only and must not be added to the upstream override manifest. `docs/baseline/BGLite-2.4.2.sha256` remains immutable.

- [ ] **Step 3: Run high-risk repository verification**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File tools/agent-verify.ps1 -Risk high -Base origin/main
```

Expected: Lua regression, baseline integrity, Lua 5.1 compilation, and diff checks all pass.

- [ ] **Step 4: Review the final diff for scope containment**

Run:

```powershell
git diff origin/main...HEAD -- Core/BGNext/OwnCharactersView.lua Core/BGNext/RoleOverviewSettings.lua Core/BGNext/RoleOverviewEntry.lua tests/test_own_character_view.lua docs/security/data-inventory.md
git diff --check
```

Expected: no collector, auction, trade, debt, bill, or character-deletion code changes; no whitespace errors.

- [ ] **Step 5: Commit documentation and verification metadata**

```powershell
git add -- docs/security/data-inventory.md docs/baseline/BGNext-overrides.sha256
git commit -m "docs: record role overview display preference"
```
