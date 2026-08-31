# Specialization Equipment Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace class-wide equipment-filter defaults with client-aware specialization defaults, add an explicit follow-current-specialization mode, and preserve every existing/custom profile safely.

**Architecture:** A pure specialization adapter converts Blizzard APIs into a stable BGNext `specKey`; a pure specialization catalog composes class capabilities with independently authored role rules; the existing equipment-filter model owns migration and follow/manual selection semantics; a small runtime module coalesces specialization events; the UI only renders model state. Unknown, zero-point, tied, missing-API, and unverified-client cases keep the current profile instead of guessing.

**Tech Stack:** Lua 5.1, World of Warcraft addon APIs, BGNext SavedVariables under `BiaoGe.BGNext`, repository Lua test harness, PowerShell baseline verification.

---

## File map

- Create `Core/BGNext/SpecializationAdapter.lua`: pure client-family detection and current-character specialization resolution.
- Create `Core/BGNext/EquipmentFilterSpecializations.lua`: versioned specialization declarations and deterministic rule composition.
- Create `Core/BGNext/EquipmentFilterRuntime.lua`: current-character-only event registration and one-second refresh coalescing.
- Modify `Core/BGNext/EquipmentFilterProfiles.lua`: expose shared rule catalogs/class capabilities and delegate specialization defaults.
- Modify `Core/BGNext/EquipmentFilter.lua`: migrate old state, implement `follow-spec`/`manual`, reconcile built-ins without deleting custom profiles.
- Modify `Core/BGNext/EquipmentFilterUI.lua`: add the follow entry/status and ensure custom interactions enter manual mode.
- Modify `BGLite.toc`: load adapter/catalog before model, runtime after model, UI last.
- Create `tests/test_specialization_adapter.lua` and `tests/test_equipment_filter_specializations.lua`.
- Modify `tests/test_equipment_filter.lua`, `tests/test_equipment_filter_profiles.lua`, `tests/test_equipment_filter_ui.lua`, and `tests/run.lua`.
- Modify `docs/security/data-inventory.md`, `docs/compatibility.md`, and `docs/baseline/BGNext-overrides.sha256`.

## Supported specialization declarations

The first implementation declares only the five currently targeted families. `wrath` and `cata` resolve API facts but have no automatic catalog until their clients are validated, so follow mode reports unknown and preserves the active profile.

- `vanilla` and `tbc`: tree keys for Warrior Arms/Fury/Protection; Paladin Holy/Protection/Retribution; Hunter Beast Mastery/Marksmanship/Survival; Rogue Assassination/Combat/Subtlety; Priest Discipline/Holy/Shadow; Shaman Elemental/Enhancement/Restoration; Mage Arcane/Fire/Frost; Warlock Affliction/Demonology/Destruction; Druid Balance/Feral/Restoration.
- `titan`: the same tree keys plus Death Knight Blood/Frost/Unholy. Druid remains a three-tree client; Feral uses one shared manual/default rule because cat versus bear cannot be inferred safely from tree points.
- `mop`: stable specialization IDs 62/63/64 Mage, 65/66/70 Paladin, 71/72/73 Warrior, 102/103/104/105 Druid, 250/251/252 Death Knight, 253/254/255 Hunter, 256/257/258 Priest, 259/260/261 Rogue, 262/263/264 Shaman, 265/266/267 Warlock, and 268/269/270 Monk.
- `retail`: the same stable IDs that still exist, plus Demon Hunter 577/581 and Evoker 1467/1468/1473. Any additional live specialization ID, including an unverified new Demon Hunter specialization, remains unknown until its Blizzard ID and equipment rules are recorded.

Role rule families are independently authored and client-scoped: `strength-melee`, `agility-melee`, `agility-ranged`, `intellect-damage`, `intellect-healing`, `strength-tank`, `agility-tank`, and `feral-ambiguous`. Physical rules filter spell-power/healing-only affixes; caster/healer rules filter attack-power/armor-penetration/expertise-only affixes; healer rules preserve spirit/mana regeneration; tank rules set `tankOnly`; weapon/armor overrides narrow class capabilities only where the specialization truly differs.

### Task 1: Pure specialization adapter

**Files:**
- Create: `Core/BGNext/SpecializationAdapter.lua`
- Create: `tests/test_specialization_adapter.lua`
- Modify: `tests/run.lua`
- Modify: `BGLite.toc`

- [ ] **Step 1: Write the failing adapter tests**

```lua
return function(test)
    BG = { BGNext = {} }
    local M = dofile("Core/BGNext/SpecializationAdapter.lua")

    test.eq(M.familyFromFlags({ IsTitan = true, IsWLK = true }), "titan", "Titan wins ordered flags")
    test.eq(M.familyFromFlags({ IsMOP = true }), "mop", "MoP family detected")
    test.eq(M.familyFromFlags({ IsRetail = true }), "retail", "Retail family detected")

    local modern = M.resolve("retail", {
        GetSpecialization = function() return 2 end,
        GetSpecializationInfo = function(index) return index == 2 and 72 or nil end,
    }, "WARRIOR")
    test.eq(modern.specKey, "spec:72", "modern client stores stable spec ID")

    local old = M.resolve("titan", {
        GetActiveTalentGroup = function() return 1 end,
        GetTalentTabInfo = function(index) return nil, nil, nil, nil, ({ 8, 31, 2 })[index] end,
    }, "WARRIOR")
    test.eq(old.specKey, "tree:WARRIOR:2", "old client resolves dominant tree")

    local tied = M.resolve("titan", {
        GetActiveTalentGroup = function() return 1 end,
        GetTalentTabInfo = function(index) return nil, nil, nil, nil, ({ 20, 20, 0 })[index] end,
    }, "WARRIOR")
    test.eq(tied.specKey, nil, "tied trees are unknown")
    test.eq(tied.reason, "tie", "tie reason is explicit")

    local zero = M.resolve("tbc", {
        GetActiveTalentGroup = function() return 1 end,
        GetTalentTabInfo = function() return nil, nil, nil, nil, 0 end,
    }, "MAGE")
    test.eq(zero.reason, "zero", "zero-point trees are unknown")
    test.eq(M.resolve("retail", {}, "MAGE").reason, "api-unavailable", "missing API is safe")
end
```

- [ ] **Step 2: Register the test and run it to verify RED**

Add `tests/test_specialization_adapter.lua` immediately before equipment-filter suites in `tests/run.lua`.

Run: `lua tests/run.lua`

Expected: failure opening `Core/BGNext/SpecializationAdapter.lua`.

- [ ] **Step 3: Implement the minimal adapter**

Expose exactly:

```lua
M.familyFromFlags(flags) -> family|nil
M.detect(globals) -> family|nil
M.resolve(family, api, classToken) -> { family=..., classToken=..., specKey=...|nil, reason=...|nil }
```

Use ordered family flags from `OwnCharactersAdapters.lua`. For `mop`/`retail`, safely call `GetSpecialization`, then `GetSpecializationInfo` and store `spec:<numericId>`. For `vanilla`/`tbc`/`wrath`/`titan`, safely read exactly three current talent trees and require one unique positive maximum. For `cata`, use the modern API path but return only the stable ID; catalog support is decided separately. Wrap every optional API with `pcall`, accept no unit/name argument, and store no values.

- [ ] **Step 4: Load the adapter and verify GREEN**

Place `Core\BGNext\SpecializationAdapter.lua` immediately before `EquipmentFilterProfiles.lua` in `BGLite.toc`.

Run: `lua tests/run.lua`

Expected: all suites pass, including the new adapter suite.

- [ ] **Step 5: Commit the adapter slice**

Run the mandatory runtime gates, update only the `BGLite.toc` override hash, then commit:

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
pwsh -NoProfile -File tools/verify-baseline.ps1
git diff --check
git add BGLite.toc Core/BGNext/SpecializationAdapter.lua tests/test_specialization_adapter.lua tests/run.lua docs/baseline/BGNext-overrides.sha256
git commit -m "feat: resolve current equipment specialization safely"
```

### Task 2: Versioned specialization defaults

**Files:**
- Create: `Core/BGNext/EquipmentFilterSpecializations.lua`
- Create: `tests/test_equipment_filter_specializations.lua`
- Modify: `Core/BGNext/EquipmentFilterProfiles.lua`
- Modify: `tests/test_equipment_filter_profiles.lua`
- Modify: `tests/run.lua`
- Modify: `BGLite.toc`

- [ ] **Step 1: Write failing catalog tests**

The new suite must assert these concrete behaviors:

```lua
local arms = catalog.getDefault("titan", "WARRIOR", "tree:WARRIOR:1")
test.eq(arms.affix.SPELL_POWER, true, "physical profile filters spell power")
test.eq(arms.affix.ATTACK_POWER, nil, "physical profile keeps attack power")

local elemental = catalog.getDefault("titan", "SHAMAN", "tree:SHAMAN:1")
test.eq(elemental.affix.ATTACK_POWER, true, "caster profile filters attack power")
test.eq(elemental.affix.SPELL_POWER, nil, "caster profile keeps spell power")

local restoration = catalog.getDefault("titan", "SHAMAN", "tree:SHAMAN:3")
test.eq(restoration.affix.MANA_REGEN, nil, "healer keeps mana regeneration")

local protection = catalog.getDefault("titan", "WARRIOR", "tree:WARRIOR:3")
test.eq(protection.tankOnly, true, "tank profile enables tank-only rule")

local feral = catalog.getDefault("titan", "DRUID", "tree:DRUID:2")
test.eq(feral.builtInKey, "titan:DRUID:tree:DRUID:2", "ambiguous feral has stable key")

test.eq(catalog.getDefault("retail", "WARRIOR", "spec:72").primaryStat.STRENGTH, true,
    "retail Fury selects strength")
test.eq(catalog.getDefault("retail", "WARRIOR", "spec:999999"), nil,
    "unverified spec is absent")
```

Also iterate every declared profile and assert unique ID, non-empty name, icon, every rule table, explicit booleans, stable `builtInKey`, and defensive copies.

- [ ] **Step 2: Run the suite to verify RED**

Run: `lua tests/run.lua`

Expected: failure opening `EquipmentFilterSpecializations.lua`.

- [ ] **Step 3: Implement independent role-rule composition**

Move reusable rule catalogs and class weapon/armor capabilities out of file-local scope in `EquipmentFilterProfiles.lua` through read-only clone-returning helpers:

```lua
Profiles.getRuleCatalog(client)
Profiles.getClassBase(family, classToken)
Profiles.getClassFallback(family, classToken)
```

Implement in the new module:

```lua
Specializations.list(family, classToken) -> ordered defensive copy
Specializations.getDefault(family, classToken, specKey) -> profile|nil
Specializations.getFallback(family, classToken) -> conservative class profile|nil
```

Build filter tables from allowed attributes using BGNext-owned `complement` logic. Do not paste the researched BiaoGe table, names, icon list, ordering, or identifiers. Resolve player-visible names/icons from `GetSpecializationInfo` in the UI/runtime when available; the catalog carries independently selected fallback names and Blizzard public spell texture IDs/paths only.

- [ ] **Step 4: Verify every declared family and rule family**

Run: `lua tests/run.lua`

Expected: all suites pass, with physical/caster/healer/tank and unknown-spec assertions green.

- [ ] **Step 5: Commit the catalog slice**

Run all three mandatory gates, update the `BGLite.toc` override hash, and commit:

```powershell
git add BGLite.toc Core/BGNext/EquipmentFilterProfiles.lua Core/BGNext/EquipmentFilterSpecializations.lua tests/test_equipment_filter_profiles.lua tests/test_equipment_filter_specializations.lua tests/run.lua docs/baseline/BGNext-overrides.sha256
git commit -m "feat: add client-specific specialization filter defaults"
```

### Task 3: Safe migration and selection semantics

**Files:**
- Modify: `Core/BGNext/EquipmentFilter.lua`
- Modify: `tests/test_equipment_filter.lua`
- Modify: `docs/security/data-inventory.md`

- [ ] **Step 1: Write failing state-model tests**

Add focused cases proving:

```lua
local old = { selectedId = "MAGE", order = { "MAGE", "custom-1" }, profiles = existingProfiles }
model.ensureCharacter(root, "realm", "Mage", defaults, { specKey = "spec:63" })
test.eq(old.selectionMode, "manual", "existing state migrates without silent switching")
test.eq(old.selectedId, "MAGE", "migration preserves selection")
test.eq(old.profiles["custom-1"].name, "自定义", "migration preserves custom profile")

local fresh = model.ensureCharacter({ equipmentFilters = {} }, "realm", "Mage", defaults,
    { specKey = "spec:63", builtInId = "retail:MAGE:spec:63" })
test.eq(fresh.selectionMode, "follow-spec", "new state follows specialization")
test.eq(fresh.selectedId, "retail:MAGE:spec:63", "new state selects resolved specialization")

model.selectProfile(fresh, "custom-1")
test.eq(fresh.selectionMode, "manual", "custom selection pauses following")
model.followSpecialization(fresh, "retail:MAGE:spec:64")
test.eq(fresh.selectionMode, "follow-spec", "explicit follow resumes following")
test.eq(fresh.selectedId, "retail:MAGE:spec:64", "follow selects new built-in")

model.applyResolvedSpecialization(fresh, nil)
test.eq(fresh.selectedId, "retail:MAGE:spec:64", "unknown specialization preserves selection")
```

Test reset separately: it rebuilds built-ins, preserves all `custom-*` profiles, switches to `follow-spec`, and selects the resolved built-in or conservative fallback.

- [ ] **Step 2: Run tests to verify RED**

Run: `lua tests/run.lua`

Expected: assertions fail because `selectionMode`, `followSpecialization`, and reconciliation do not exist.

- [ ] **Step 3: Implement the model transition API**

Extend normalized persistent state with only:

```lua
selectionMode = "follow-spec" | "manual"
selectedId = string|nil
profiles = map
order = array
```

Expose:

```lua
M.reconcileBuiltIns(state, defaults)
M.applyResolvedSpecialization(state, builtInId)
M.followSpecialization(state, builtInId)
M.selectProfile(state, id) -- always enters manual mode
M.resetDefaults(state, defaults, builtInId) -- preserves customs, enters follow mode
```

Determine legacy state before adding defaults: a valid pre-feature state without `selectionMode` becomes `manual`; a newly created state becomes `follow-spec`. Never read `BiaoGe.FilterClassItemDB`. Never delete a custom profile or replace its table. Built-ins are identified only by BGNext `builtInKey`; stale built-ins may be replaced, but their IDs must not collide with `custom-*`.

- [ ] **Step 4: Update the data inventory and verify GREEN**

Change the equipment-filter inventory row to document `selectionMode`, `selectedId`, profiles/order, current-character specialization as a transient source, and the fact that no talent points/history are persisted.

Run: `lua tests/run.lua`

Expected: all state migration, custom preservation, follow/manual, reset, and unknown fallback tests pass.

- [ ] **Step 5: Commit the model slice**

Run the mandatory gates and commit:

```powershell
git add Core/BGNext/EquipmentFilter.lua tests/test_equipment_filter.lua docs/security/data-inventory.md
git commit -m "feat: follow specialization without overwriting custom filters"
```

### Task 4: Current-character runtime and event coalescing

**Files:**
- Create: `Core/BGNext/EquipmentFilterRuntime.lua`
- Create: `tests/test_equipment_filter_runtime.lua`
- Modify: `tests/run.lua`
- Modify: `BGLite.toc`

- [ ] **Step 1: Write failing runtime tests**

Test a pure controller constructor with injected adapter/model/catalog/refresh callbacks. Assert initial login resolve, duplicate event coalescing, no refresh when `specKey` is unchanged, one refresh when it changes, unknown preserving selection, manual mode preserving selection, and no registration of inspection/chat/addon-message APIs.

```lua
local controller = Runtime.new(deps)
controller:onEvent("PLAYER_TALENT_UPDATE")
controller:onEvent("PLAYER_SPECIALIZATION_CHANGED")
controller:flush()
test.eq(resolveCount, 1, "duplicate events coalesce")
test.eq(refreshCount, 1, "changed specialization refreshes once")
```

- [ ] **Step 2: Run tests to verify RED**

Run: `lua tests/run.lua`

Expected: failure opening `EquipmentFilterRuntime.lua`.

- [ ] **Step 3: Implement the controller and thin WoW binding**

Expose `M.new(deps)` with `onEvent` and `flush`. The live binding registers `PLAYER_ENTERING_WORLD`, `PLAYER_TALENT_UPDATE`, and only where available `PLAYER_SPECIALIZATION_CHANGED`; an `OnUpdate` accumulator calls `flush` after one second. It reads only `UnitClass("player")` and current-character specialization APIs. It calls the model only when the stable key changes, then invokes existing local filter refresh functions. It sends no messages, inspects no unit, and writes no talent points.

- [ ] **Step 4: Verify GREEN and source safety assertions**

Run: `lua tests/run.lua`

Expected: all runtime tests pass and source assertions find none of `NotifyInspect`, `SendChatMessage`, `SendAddonMessage`, or `BiaoGe.FilterClassItemDB`.

- [ ] **Step 5: Commit the runtime slice**

Run the mandatory gates, update the `BGLite.toc` override hash, and commit:

```powershell
git add BGLite.toc Core/BGNext/EquipmentFilterRuntime.lua tests/test_equipment_filter_runtime.lua tests/run.lua docs/baseline/BGNext-overrides.sha256
git commit -m "feat: refresh equipment filters on specialization changes"
```

### Task 5: Follow-specialization UI

**Files:**
- Modify: `Core/BGNext/EquipmentFilterUI.lua`
- Modify: `tests/test_equipment_filter_ui.lua`

- [ ] **Step 1: Write failing UI source/behavior assertions**

Assert that the selector creates one dedicated follow button before profile buttons, uses model functions rather than setting `selectionMode` directly, shows the resolved Blizzard name/icon when present, shows an explicit unknown status, and custom create/select/edit/reorder paths remain available. Assert reset passes the current resolved built-in ID and no forbidden communication/legacy DB strings appear.

- [ ] **Step 2: Run tests to verify RED**

Run: `lua tests/run.lua`

Expected: failure because no follow selector or unknown status exists.

- [ ] **Step 3: Implement the UI as a model consumer**

Add a 25x25 follow button at the start of the profile row. Its click calls `followSpecialization`; its tooltip/status communicates either the current specialization or that recognition failed and the current scheme is retained. Built-in profile clicks enter manual mode just like custom clicks, because only the dedicated follow entry enables automatic switching. Creating a profile clones the active profile rules before applying the new name/icon, then selects it in manual mode. Reset preserves custom profiles and returns to follow mode.

- [ ] **Step 4: Run UI and full tests to verify GREEN**

Run: `lua tests/run.lua`

Expected: all UI assertions and all existing equipment-filter interaction tests pass.

- [ ] **Step 5: Commit the UI slice**

Run the mandatory gates and commit:

```powershell
git add Core/BGNext/EquipmentFilterUI.lua tests/test_equipment_filter_ui.lua
git commit -m "feat: add follow-specialization filter selection"
```

### Task 6: Compatibility evidence, package verification, and handoff

**Files:**
- Modify: `docs/compatibility.md`
- Modify: `docs/design/2026-08-31-specialization-equipment-filter-design.md`
- Create: shared gitignored `.local/handoffs/inbox/<timestamp>--codex-spec-equipment-by-specialization--specialization-filters.md`

- [ ] **Step 1: Record evidence without overstating support**

Add an equipment-filter section to `docs/compatibility.md` with `vanilla`, `tbc`, `titan`, `mop`, and `retail` marked code-covered/automatically tested and awaiting in-game verification. Mark `wrath`, `cata`, unverified new Retail specs, and Titan cat-versus-bear auto-detection as unverified limitations. Change the design status to implemented only after all automated gates pass.

- [ ] **Step 2: Run complete verification freshly**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
pwsh -NoProfile -File tools/verify-baseline.ps1
pwsh -NoProfile -File tools/build-release.ps1
git diff --check
git status --short
```

Expected: Lua reports zero failures; baseline verification reports all approved files; release build exits zero and contains the three new runtime modules; diff check is silent; status lists only intended changes before the final docs commit.

- [ ] **Step 3: Review requirements and provenance**

Confirm line by line: no BiaoGe code/data/assets copied; research disclosure remains linked; no legacy DB access; no other-player inspection; no communication; no talent history; old/custom profiles preserved; follow/manual semantics tested; unknown never guesses; every modified baseline file has one reviewed override hash.

- [ ] **Step 4: Commit verification documentation**

```powershell
git add docs/compatibility.md docs/design/2026-08-31-specialization-equipment-filter-design.md
git commit -m "docs: record specialization filter compatibility evidence"
```

- [ ] **Step 5: Write the mandatory local handoff**

Create the inbox from `git rev-parse --path-format=absolute --git-common-dir` as required by `CLAUDE.md`. Record worktree, branch, HEAD, base/range, changed files, exact observed verification output, no game/SavedVariables modification, provenance disclosure, privacy/security review, unverified clients, and requested Codex review checks. Set status `needs_game_validation`; never commit `.local/`.
