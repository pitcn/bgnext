# Equipment Filter Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore BGNext's local equipment-filter configuration and visible workflow so it matches the original BiaoGe user experience while reusing the reviewed BGLite filtering engine and respecting BGNext's privacy and licensing boundaries.

**Architecture:** Add a pure profile/catalog module and a local per-character state module under `Core/BGNext/`, then adapt BGLite's existing filter engine to consume the active BGNext profile through a narrow accessor. Build the settings frame separately after the main BGLite UI loads. No new addon messages, exports, history, other-player data, or external assets are introduced.

**Tech Stack:** World of Warcraft Lua 5.1 API, existing BGLite UI helpers, SavedVariables under `BiaoGe.BGNext.equipmentFilters`, repository Lua test runner and baseline verifier.

---

## Behavioral reference and boundaries

- Reference only the visible workflow and layout of BiaoGe 2.3.5 `FilterClassItem`: bottom profile icons and settings button; `< 装备过滤 >` frame; profile selection; add/edit/delete/reorder; reset; weapon, armor, affix, class restriction, Battle.net-bound, tank and primary-stat sections.
- Use only BGLite code already present in this repository and independently written BGNext code. Do not copy BiaoGe source, algorithms, artwork, sounds, fonts, long text, or static databases.
- Filtering concerns only the logged-in player's local display. It never evaluates another player's suitability and never sends a chat/addon message.
- An active rule makes unsuitable equipment semi-transparent using the existing BGLite alpha behavior. Missing item metadata or unsupported client APIs must leave the item fully visible.
- Save profiles under `BiaoGe.BGNext.equipmentFilters[realmId][player]`. Do not create or update legacy `BiaoGe.FilterClassItemDB` records.

### Task 1: Lock the public contract with failing tests

**Files:**
- Create: `tests/test_equipment_filter_profiles.lua`
- Create: `tests/test_equipment_filter.lua`
- Modify: `tests/run.lua`

- [ ] **Step 1: Add the profile-catalog test before production files exist**

Test that the future catalog module returns deterministic, independent profile tables with `id`, `name`, `icon`, `weapon`, `armor`, `affix`, `classRestriction`, `ignoreBattleNetBound`, `tankOnly`, and `primaryStat` fields. Cover at least warrior, mage, hunter and druid; verify that mutating one returned profile cannot change a later result.

- [ ] **Step 2: Add the state-module test before production files exist**

Test this API:

```lua
local model = dofile("Core/BGNext/EquipmentFilter.lua")
local state = model.ensureCharacter(root, "realm", "player", defaults)
model.selectProfile(state, profileId)
model.createProfile(state, profile)
model.updateProfile(state, profileId, patch)
model.moveProfile(state, profileId, -1)
model.deleteProfile(state, profileId)
model.resetDefaults(state, defaults)
local active = model.getActiveProfile(root, "realm", "player")
```

Assert per-character isolation, stable profile IDs, no aliasing, selection toggle-off behavior, validation of empty names and unknown rule IDs, deletion fallback, default reset, and nil-safe lookup.

- [ ] **Step 3: Register both suites and run RED**

Run:

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
```

Expected: FAIL because `EquipmentFilterProfiles.lua` and `EquipmentFilter.lua` do not exist.

- [ ] **Step 4: Commit the red tests**

```powershell
git add tests/test_equipment_filter_profiles.lua tests/test_equipment_filter.lua tests/run.lua
git commit -m "test: define equipment filter contract"
```

### Task 2: Implement independent profile catalog

**Files:**
- Create: `Core/BGNext/EquipmentFilterProfiles.lua`
- Modify: `BGLite.toc`

- [ ] **Step 1: Define normalized rule identifiers**

Use game-stable identifiers rather than localized tooltip sentences: weapon subclass numbers, armor subclass numbers, `STRENGTH`/`AGILITY`/`INTELLECT`, and named capability flags. Keep client availability checks at catalog construction time.

- [ ] **Step 2: Build class and specialization defaults independently**

Construct defaults from documented class equipment capabilities. Include only profiles meaningful to the running client; unsupported classes/specs are omitted. Every profile uses Blizzard icon paths or file IDs already exposed by the client, not BiaoGe media.

- [ ] **Step 3: Return defensive copies**

Expose `getDefaults(client, classToken)` and `getRuleCatalog(client)`; both return new tables so callers cannot mutate module constants.

- [ ] **Step 4: Run GREEN for the catalog tests**

Run `pwsh -NoProfile -File tools/run-lua-tests.ps1` and expect only state-module tests to remain red.

- [ ] **Step 5: Commit**

```powershell
git add Core/BGNext/EquipmentFilterProfiles.lua BGLite.toc tests/test_equipment_filter_profiles.lua
git commit -m "feat: add local equipment filter profiles"
```

### Task 3: Implement per-character profile state

**Files:**
- Create: `Core/BGNext/EquipmentFilter.lua`
- Modify: `BGLite.toc`
- Modify: `docs/data-inventory.md`

- [ ] **Step 1: Implement validation and cloning helpers**

Accept only known rule identifiers from the catalog, trim profile names, cap names at 24 UTF-8 bytes without splitting a continuation byte, and ignore unknown patch fields. Never persist functions, frames or localized tooltip text.

- [ ] **Step 2: Implement the tested state API**

Store this shape:

```lua
equipmentFilters[realmId][player] = {
    selectedId = "profile-id-or-nil",
    order = { "profile-id" },
    profiles = {
        ["profile-id"] = {
            name = "法师",
            icon = 135846,
            weapon = {}, armor = {}, affix = {},
            classRestriction = true,
            ignoreBattleNetBound = false,
            tankOnly = false,
            primaryStat = { INTELLECT = true },
            builtInKey = "MAGE",
        },
    },
}
```

`resetDefaults` replaces only the logged-in character's filter state. It must not touch wishlist, settlement, other characters, or legacy BGLite data.

- [ ] **Step 3: Initialize on `BG.Init`**

Use `BG.BGNext.DB`, `BG.realmID` and `BG.playerName`; install defaults only when that character has no filter state. Publish `BG.BGNext.EquipmentFilter` and a nil-safe `BG.BGNext.GetActiveEquipmentFilterProfile` accessor.

- [ ] **Step 4: Run GREEN**

Run the complete Lua suite and expect all model tests to pass.

- [ ] **Step 5: Update the data inventory precisely**

Document the per-character keys, local source, local-only recipient, retention until delete/reset/all-data clear, and low risk. State explicitly that no legacy profile database is read or migrated.

- [ ] **Step 6: Commit**

```powershell
git add Core/BGNext/EquipmentFilter.lua BGLite.toc docs/data-inventory.md tests/test_equipment_filter.lua
git commit -m "feat: store private equipment filter profiles"
```

### Task 4: Adapt the BGLite filter engine to the BGNext accessor

**Files:**
- Modify: `Core/function2.lua`
- Modify: `tests/test_equipment_filter.lua`
- Modify: `tools/baseline-overrides.sha256`

- [ ] **Step 1: Add failing engine-adapter assertions**

Add source and behavior tests proving that the engine obtains its active profile from `BG.BGNext.GetActiveEquipmentFilterProfile`, does not write `BiaoGe.FilterClassItemDB`, and returns “not filtered” when the profile or item metadata is unavailable.

- [ ] **Step 2: Run RED**

Run the suite and confirm failure points at the current legacy state access.

- [ ] **Step 3: Replace legacy reads with a narrow runtime accessor**

Remove the Lite stub's persistent legacy profile creation. Inside the filtering block, call a local `GetActiveProfile()` wrapper on every evaluation/refresh so profile changes take effect immediately. Translate normalized BGNext fields to the existing armor, weapon, affix, class, tank and primary-stat checks without adding a second filtering implementation.

- [ ] **Step 4: Harden optional UI consumers**

Make `BG.UpdateAllFilter()` update only frames that exist. Do not recreate deleted ItemLib, history or third-party aura functionality. `BG.LootFilterClassItem()` returns an empty marker when inactive or undecidable.

- [ ] **Step 5: Run GREEN and baseline verification**

Run:

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
pwsh -NoProfile -File tools/verify-baseline.ps1
```

Review only `Core/function2.lua`, then update its single explicit override hash. Run the verifier again and expect success.

- [ ] **Step 6: Commit**

```powershell
git add Core/function2.lua tests/test_equipment_filter.lua tools/baseline-overrides.sha256
git commit -m "refactor: connect filters to BGNext profiles"
```

### Task 5: Rebuild the original-equivalent configuration UI

**Files:**
- Create: `Core/BGNext/EquipmentFilterUI.lua`
- Create: `tests/test_equipment_filter_ui.lua`
- Modify: `tests/run.lua`
- Modify: `BGLite.toc`

- [ ] **Step 1: Write failing UI structure tests**

Assert that the module creates: bottom profile buttons parented to `BG.FBMainFrame`; a settings button immediately after them; a centered settings frame offset 100 pixels right; title, close, reset and profile-selection controls; add/edit panel; and the seven rule sections in original order. Assert no `SendChatMessage`, `C_ChatInfo.SendAddonMessage`, version query, export or other-player API appears.

- [ ] **Step 2: Run RED**

Run the suite and confirm failure because `EquipmentFilterUI.lua` is absent.

- [ ] **Step 3: Implement bottom shortcuts and selection behavior**

Create 25x25 profile buttons with Blizzard icons, 10-pixel spacing and selected highlight. Clicking the selected profile disables filtering; clicking another profile activates it and calls `BG.UpdateAllFilter()`. Right-click opens the same local edit/delete/reorder actions as the original workflow.

- [ ] **Step 4: Implement the settings frame**

Use existing BGLite frame/button/font helpers. Preserve the original control relationships and sizes: title at top, profile row, scrollable rule area, reset at upper left, close at lower right, and add/edit overlay with name, icon grid, confirm and back. Do not use copied textures or custom media.

- [ ] **Step 5: Implement rule controls and feedback**

Render sections in this order: weapon type, armor type, affix, class restriction, Battle.net-bound, tank-only when available, primary stat when available. A click updates only the current character profile, refreshes all item alpha states immediately and visibly updates the selected state. Unsupported rules are omitted; ambiguous item results remain full alpha.

- [ ] **Step 6: Run GREEN and commit**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
git add Core/BGNext/EquipmentFilterUI.lua tests/test_equipment_filter_ui.lua tests/run.lua BGLite.toc
git commit -m "feat: restore equipment filter interface"
```

### Task 6: Verify existing current-raid purchase view instead of duplicating it

**Files:**
- Create: `tests/test_current_purchases.lua`
- Modify: `tests/run.lua`
- Modify: `docs/superpowers/specs/2026-08-26-first-release-design.md`

- [ ] **Step 1: Add regression assertions for the retained BGLite path**

Verify `Core/Module/AuctionLog.lua` retains the `我买的`/`I bought` filter and selects successful records only when `IsMyPlayer(v.maijia)` is true. Verify the view belongs to the current table's `auctionLog` and does not read `BiaoGe.History` in BGLite.

- [ ] **Step 2: Run the test and record whether it is already GREEN**

This is a characterization test for retained BGLite behavior, not a new implementation test. If it passes immediately, record that the feature already exists in the clean baseline and do not add a duplicate `CurrentShopping.lua` window.

- [ ] **Step 3: Correct the first-release terminology**

Document “当前团本个人购物清单” as the existing `拍卖记录 → 我买的` view, with the same item rows, amount and total behavior. Explicitly exclude BiaoGe's unrelated merchant-shopping module and any cross-raid summary.

- [ ] **Step 4: Commit**

```powershell
git add tests/test_current_purchases.lua tests/run.lua docs/superpowers/specs/2026-08-26-first-release-design.md
git commit -m "docs: map current purchases to retained auction view"
```

### Task 7: Documentation, changelog and compliance review

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/COMPLIANCE.md` only if clarification is needed

- [ ] **Step 1: Document user operation**

Describe the bottom profile buttons, settings entry, profile management, alpha meaning, immediate refresh and “无法判断则不隐藏” fallback. State that filters are private, local and per logged-in character.

- [ ] **Step 2: Document what was not added**

State that the feature does not broadcast suitability, inspect teammates, build equipment profiles of other players, export data, or preserve raid history.

- [ ] **Step 3: Complete the runtime PR compliance answers**

Record: player problem, local item metadata read, per-character profile fields saved, no messages, no export, no automated player action, no third-party assets, tests/failure paths, baseline file reason, and platform re-review requirement.

- [ ] **Step 4: Commit**

```powershell
git add README.md CHANGELOG.md docs/COMPLIANCE.md
git commit -m "docs: explain private equipment filtering"
```

### Task 8: Full verification and game acceptance package

**Files:**
- Modify only if verification finds a defect; every fix starts with a failing regression test.

- [ ] **Step 1: Run mandatory gates**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
pwsh -NoProfile -File tools/verify-baseline.ps1
git diff --check
```

Expected: all Lua suites pass, baseline inventory passes with only reviewed overrides, and no whitespace errors.

- [ ] **Step 2: Run Lua 5.1 syntax checks**

Compile every changed `.lua` file with the repository's bundled Lua 5.1 interpreter. Expected: no syntax errors.

- [ ] **Step 3: Scan changed lines for communication and prohibited data**

Search the diff for addon/chat send APIs, HTTP/socket/file APIs, history/profile/ranking fields, mail subject/body, GUID/account/device identifiers and legacy `BiaoGe.FilterClassItemDB` writes. Expected: no new prohibited behavior.

- [ ] **Step 4: Build a clean staging package**

Package only files referenced by `BGLite.toc` plus required media/libs. Exclude `.git`, `.github`, docs, tests, tools, `.superpowers`, backups and SavedVariables. Compare every staged runtime file hash with the worktree.

- [ ] **Step 5: Install only after WoW fully exits**

Confirm both `WowClassic` and `WowVoiceProxy` are stopped. Move the current `AddOns\BGLite` folder to a timestamped backup outside `AddOns`, install the staged package, and verify all installed hashes. Never alter SavedVariables.

- [ ] **Step 6: Perform the in-game parity matrix**

For each available client, verify: bottom profile row; active/off state; settings position and sizing; add/edit/delete/reorder/reset; every rule section; current bill, loot list and auction-log alpha refresh; missing metadata fallback; reload persistence; no messages sent; and `拍卖记录 → 我买的` current-purchase view. Capture same-state original/BGNext screenshots where the original client can safely be run separately.

- [ ] **Step 7: Push the reviewed branch**

Push `codex/v0.1.0` only after automated gates pass. Keep the PR in draft until the in-game matrix and visual comparison are complete.

