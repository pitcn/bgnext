# BGNext Own Character Overview Clean-Room Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Independently implement the BGNext own-character overview on the verified BGLite 2.4.0 baseline, matching the approved BiaoGe-visible table workflow without reading or copying BiaoGe/community source or assets.

**Architecture:** Store only last-seen snapshots of the locally logged-in player under `BiaoGe.BGNext.ownCharacters`. Isolate client differences behind adapters, project snapshots into a pure table view model, and render the approved two-section horizontal table from that projection. Entry/settings modules own interaction state; collectors never create frames and renderers never traverse SavedVariables directly.

**Tech Stack:** World of Warcraft Lua 5.1, BGLite framework helpers, Blizzard public addon APIs, local SavedVariables, repository Lua test harness, PowerShell baseline verification.

---

## Mandatory clean-room rules

During this implementation, do not open, search, hash, summarize, or otherwise read any file under:

- `C:\Users\hyk06\Downloads\BiaoGe-v2.3.5`
- `C:\Users\hyk06\Downloads\biaoge审核`
- `D:\vibe coding\BGN\archives`
- `D:\vibe coding\BGN\backups`
- `C:\World of Warcraft1\_classic_titan_\Interface\AddOns\BGLite` as an implementation source

Do not recover discarded role-overview commits from reflog, bundles, remote objects, other worktrees, or the game installation. Use only the current worktree, the approved design, existing BGLite code in the current worktree, Blizzard APIs, and user-provided screenshots.

Stop and report if an exact visible behavior cannot be specified without opening forbidden source. Do not substitute a card UI or a vertical equipment wall.

## Locked file structure

Create these focused runtime modules:

- `Core/BGNext/OwnCharacters.lua` — snapshot validation, storage, expiry, delete, clear.
- `Core/BGNext/OwnCharactersAdapters.lua` — client-family detection, safe API wrappers, adapter registry.
- `Core/BGNext/OwnCharactersCatalog.lua` — per-family column definitions and defaults.
- `Core/BGNext/OwnCharactersCollector.lua` — current-player-only event collection.
- `Core/BGNext/OwnCharactersView.lua` — pure projection, sorting, labels, totals, dynamic width model.
- `Core/BGNext/OwnCharactersUI.lua` — two-section horizontal table renderer.
- `Core/BGNext/RoleOverviewSettings.lua` — per-client column visibility and reset.
- `Core/BGNext/RoleOverviewEntry.lua` — main-frame entry, hover/pin/drag/commands.

Create matching test suites:

- `tests/test_own_characters.lua`
- `tests/test_own_character_adapters.lua`
- `tests/test_own_character_collector.lua`
- `tests/test_own_character_view.lua`
- `tests/test_own_character_ui.lua`
- `tests/test_role_overview_entry.lua`

Modify only when required:

- `tests/run.lua`
- `BGLite.toc`
- `Core/function2.lua` — replace only the existing Lite stubs/integration hooks needed by the new module.
- `Core/BiaoGe.lua` — only if the current BGLite main-frame lifecycle has no stable hook; prefer `RoleOverviewEntry.lua` hooking an existing frame/event.
- `Core/Options.lua` — only if the existing settings framework requires explicit registration.
- `Bindings.xml` and `Core/DB/Init2.lua` — preserve the existing RoleOverview binding identifier rather than inventing a second binding.
- `Locales/zhCN.lua`, `Locales/zhTW.lua`, `Locales/enUS.lua`
- `docs/security/data-inventory.md`
- `docs/baseline/BGNext-overrides.sha256`

Never create a single replacement file containing model, collector, adapters, view, and renderer together.

### Task 1: Snapshot model and retention

**Files:**
- Create: `Core/BGNext/OwnCharacters.lua`
- Create: `tests/test_own_characters.lua`
- Modify: `tests/run.lua`

- [ ] **Step 1: Add the failing model suite to the runner**

Append `tests/test_own_characters.lua` to the suite list in `tests/run.lua` and define tests using this public contract:

```lua
local M = dofile("Core/BGNext/OwnCharacters.lua")
local root = {}

local saved = M.upsert(root, "titan", {
    realmId = 123,
    realmName = "时光II",
    player = "Piti",
    class = "HUNTER",
    level = 80,
    itemLevel = 230.75,
    updatedAt = 1000,
    money = 50000,
    raidStates = { SWtitan = { completed = true, resetsAt = 2000 } },
    unknownField = "must not persist",
})

test.eq(saved.player, "Piti", "stores current character")
test.eq(saved.unknownField, nil, "drops non-whitelisted fields")
test.eq(M.get(root, "titan", 123, "Piti").itemLevel, 230.75, "reads snapshot")
M.expireRaidStates(root, 2001)
test.eq(next(M.get(root, "titan", 123, "Piti").raidStates), nil, "expires weekly state")
```

Also test same-name cross-realm isolation, overwrite-without-history, invalid input rejection, delete-one, clear-family, and clear-all.

- [ ] **Step 2: Run the suite and observe the expected failure**

Run:

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
```

Expected: failure naming `tests/test_own_characters.lua` because the module or functions do not exist.

- [ ] **Step 3: Implement the minimal pure model**

Expose exactly these functions from `OwnCharacters.lua`:

```lua
M.ensureRoot(root)
M.upsert(root, clientFamily, snapshot)
M.get(root, clientFamily, realmId, player)
M.list(root, clientFamily)
M.expireRaidStates(root, now)
M.delete(root, clientFamily, realmId, player)
M.clearFamily(root, clientFamily)
M.clearAll(root)
```

Whitelist only fields documented in the approved design. Deep-copy accepted nested tables. Store snapshots at `root.ownCharacters[clientFamily][realmId][player]`. Never create a history array, previous-value field, player score, account identifier, GUID, note, or communication field.

- [ ] **Step 4: Run the complete suite**

Expected: all suites report `failed=0`.

- [ ] **Step 5: Commit the model slice**

```powershell
git add Core/BGNext/OwnCharacters.lua tests/test_own_characters.lua tests/run.lua
git commit -m "feat: add private own-character snapshots"
```

### Task 2: Client adapters and column catalogs

**Files:**
- Create: `Core/BGNext/OwnCharactersAdapters.lua`
- Create: `Core/BGNext/OwnCharactersCatalog.lua`
- Create: `tests/test_own_character_adapters.lua`
- Modify: `tests/run.lua`

- [ ] **Step 1: Write failing adapter/catalog tests**

Require these contracts:

```lua
local Adapters = dofile("Core/BGNext/OwnCharactersAdapters.lua")
local Catalog = dofile("Core/BGNext/OwnCharactersCatalog.lua")

test.eq(Adapters.familyFromFlags({ IsTitan = true }), "titan", "detects titan")
test.eq(Adapters.familyFromFlags({ IsMOP = true }), "mop", "detects mop")
test.eq(Adapters.safeCall(nil), nil, "missing API is safe")

local titan = Catalog.forFamily("titan")
test.eq(type(titan.raidColumns), "table", "titan raid columns exist")
test.eq(type(titan.resourceColumns), "table", "titan resource columns exist")
test.eq(Catalog.defaultVisible("titan", "raid", "MCtitan"), true, "default is explicit")
```

Test unique stable column IDs, deterministic order, a title and width category for every column, and absence of unsupported columns for each family.

- [ ] **Step 2: Run tests and observe failure**

Expected: the new suite fails before production files exist.

- [ ] **Step 3: Implement adapters using only current BGLite metadata and Blizzard APIs**

Supported families: `vanilla`, `tbc`, `wrath`, `titan`, `cata`, `mop`, `retail`. `safeCall(fn, ...)` must return `nil` rather than throw when the API is missing or protected. Catalog entries are declarative data only; they may identify BGLite raid keys already present in the current repository but must not contain copied external implementation code.

Each column descriptor must use this shape:

```lua
{
    id = "stable-id",
    section = "raid" or "resource",
    title = "localized key",
    kind = "status" or "progress" or "number" or "money" or "items" or "profession",
    width = "narrow" or "normal" or "wide" or "dynamic-items",
    defaultVisible = true or false,
    total = true or false,
}
```

- [ ] **Step 4: Run complete tests and commit**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
git add Core/BGNext/OwnCharactersAdapters.lua Core/BGNext/OwnCharactersCatalog.lua tests/test_own_character_adapters.lua tests/run.lua
git commit -m "feat: add own-character client adapters"
```

### Task 3: Current-player-only collector

**Files:**
- Create: `Core/BGNext/OwnCharactersCollector.lua`
- Create: `tests/test_own_character_collector.lua`
- Modify: `tests/run.lua`

- [ ] **Step 1: Write failing collector tests with injected APIs**

The collector must accept an injected environment so Lua 5.1 tests do not require WoW globals:

```lua
local Collector = dofile("Core/BGNext/OwnCharactersCollector.lua")
local snapshot = Collector.collect({
    family = "titan",
    now = function() return 1000 end,
    playerName = function() return "Piti" end,
    realmId = function() return 123 end,
    realmName = function() return "时光II" end,
    class = function() return "HUNTER" end,
    level = function() return 80 end,
    money = function() return 50000 end,
    equipment = function() return {} end,
    raidStates = function() return {} end,
    resources = function() return {} end,
    professions = function() return {} end,
})

test.eq(snapshot.player, "Piti", "collects logged-in player")
test.eq(snapshot.realmId, 123, "collects own realm")
```

Test that missing APIs return a partial snapshot, secret/protected values are discarded, and no function accepts another player name or unit token.

- [ ] **Step 2: Observe failure, implement, then rerun**

Expose `collect(env)` and `installEvents(env, onSnapshot)`. Runtime events may include `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`, `PLAYER_EQUIPMENT_CHANGED`, `UPDATE_INSTANCE_INFO`, `PLAYER_MONEY`, `BAG_UPDATE_DELAYED`, `CURRENCY_DISPLAY_UPDATE`, and profession updates only when supported. Debounce bursts locally. Never register chat, combat-log, group-roster, trade, mail, inspect, addon-message, or target events.

- [ ] **Step 3: Run privacy scan and commit**

```powershell
rg -n "SendAddonMessage|SendChatMessage|C_ChatInfo|INSPECT_READY|COMBAT_LOG_EVENT|CHAT_MSG" Core/BGNext/OwnCharacters*.lua
pwsh -NoProfile -File tools/run-lua-tests.ps1
git add Core/BGNext/OwnCharactersCollector.lua tests/test_own_character_collector.lua tests/run.lua
git commit -m "feat: collect logged-in character snapshots"
```

Expected scan: no communication/inspection matches in the new collector.

### Task 4: Pure horizontal-table projection

**Files:**
- Create: `Core/BGNext/OwnCharactersView.lua`
- Create: `tests/test_own_character_view.lua`
- Modify: `tests/run.lua`

- [ ] **Step 1: Write failing projection tests**

Define `View.project(input)` where input contains snapshots, catalog, visibility settings, current realm ID, `showAllRealms`, and `now`. Assert:

- characters are rows;
- raid/resource descriptors are columns;
- current realm appears first;
- same-name cross-realm rows remain distinct;
- short realm prefix appears only when needed/all realms are shown;
- hidden columns are absent while source snapshots remain untouched;
- expired raid states render blank;
- alternating row style is deterministic;
- totals include only descriptors with `total=true`;
- computed width shrinks after hiding `MCtitan` or a resource column.

Use this output shape:

```lua
{
    raid = { title = "...", hint = "...", columns = {}, rows = {} },
    resource = { title = "...", hint = "...", columns = {}, rows = {}, totals = {} },
    width = 0,
    height = 0,
}
```

- [ ] **Step 2: Observe failure and implement without WoW globals**

The projection file must be loadable with plain Lua 5.1 and may not call `CreateFrame`, SavedVariables, item APIs, or time APIs directly.

- [ ] **Step 3: Run tests and commit**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
git add Core/BGNext/OwnCharactersView.lua tests/test_own_character_view.lua tests/run.lua
git commit -m "feat: project own characters into original table flow"
```

### Task 5: Column settings

**Files:**
- Create: `Core/BGNext/RoleOverviewSettings.lua`
- Add settings assertions to: `tests/test_own_character_view.lua`
- Modify only if required: `Core/Options.lua`
- Modify: `Locales/zhCN.lua`, `Locales/zhTW.lua`, `Locales/enUS.lua`

- [ ] **Step 1: Test per-family visibility state**

Require these pure helpers:

```lua
Settings.ensure(root, family, catalog)
Settings.isVisible(root, family, section, columnId, catalog)
Settings.setVisible(root, family, section, columnId, visible)
Settings.resetFamily(root, family)
```

Assert Titan settings do not affect MoP settings, reset removes only the selected family's overrides, and hiding affects projection but not snapshots.

- [ ] **Step 2: Implement the settings panel**

Register a “角色总览” subsection through the existing BGLite settings framework. Show separate checkbox groups for raid and resource columns plus “恢复当前版本默认列”. Changes rebuild the visible overview immediately.

- [ ] **Step 3: Run tests and commit**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
git add Core/BGNext/RoleOverviewSettings.lua Core/Options.lua Locales/zhCN.lua Locales/zhTW.lua Locales/enUS.lua tests/test_own_character_view.lua
git commit -m "feat: add role overview column settings"
```

Omit `Core/Options.lua` from `git add` if it was not needed.

### Task 6: High-fidelity renderer

**Files:**
- Create: `Core/BGNext/OwnCharactersUI.lua`
- Create: `tests/test_own_character_ui.lua`
- Modify: `tests/run.lua`

- [ ] **Step 1: Write structural UI contract tests**

Because plain Lua cannot render frames, test source-level invariants and extracted geometry helpers:

- renderer consumes a projection argument rather than SavedVariables;
- two section titles exist;
- rows are horizontal and cells follow projected column order;
- dynamic width/height uses projection values;
- item cells are 19px content icons unless in-game screenshot calibration changes this documented constant;
- alternating row backgrounds and green completion markers are present;
- settings, refresh, and close controls exist;
- no card/grid-by-character layout helper exists;
- no communication calls exist.

- [ ] **Step 2: Implement the renderer from the approved specification**

Use BGLite font/color/frame helpers when they are part of the current verified baseline. Use Blizzard built-in textures for buttons and item icons. Do not create or import new visual assets. Render:

1. `< 角色团本完成总览 >` with reset hint;
2. raid header and alternating character rows;
3. `< 角色货币总览 >` with interaction hint;
4. resource header, alternating character rows, and totals.

The renderer must rebuild safely when columns, snapshots, Shift state, item cache, or scale changes. Empty data shows a compact local-only message instead of an empty equipment wall.

- [ ] **Step 3: Run tests and commit**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
git add Core/BGNext/OwnCharactersUI.lua tests/test_own_character_ui.lua tests/run.lua
git commit -m "feat: render original-flow character overview"
```

### Task 7: Entry, pinning, commands, and deletion

**Files:**
- Create: `Core/BGNext/RoleOverviewEntry.lua`
- Create: `tests/test_role_overview_entry.lua`
- Modify: `tests/run.lua`
- Modify: `Core/function2.lua`
- Modify if required: `Core/BiaoGe.lua`
- Modify if required: `Bindings.xml`, `Core/DB/Init2.lua`

- [ ] **Step 1: Write failing interaction tests**

Extract pure interaction decisions and test:

```lua
Entry.intent("hover", {}) == "preview"
Entry.intent("leave", { pinned = false }) == "hide"
Entry.intent("middle-click", {}) == "pin"
Entry.intent("left-click", { ctrl = true }) == "pin"
Entry.intent("slash-role", {}) == "toggle-pinned"
```

Test default current-realm filtering, Shift all-realm filtering, full-key deletion, and refusal to delete without confirmation.

- [ ] **Step 2: Implement the existing-habit entry**

Create the bottom-right “角色总览” entry on the BGLite main frame. Wire hover preview, leave-to-hide, middle-click/Ctrl-left pin, drag/save position, settings, refresh, close, Shift display, `/bgn role`, and `/bgnext role`. Reuse the existing `BINDING_NAME_RoleOverview` identifier rather than creating a conflicting binding.

Replace only the relevant Lite stubs in `Core/function2.lua`; do not import legacy role code. If `Core/BiaoGe.lua` needs a hook, keep the change minimal and explain it in the commit body.

- [ ] **Step 3: Run tests and commit**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
git add Core/BGNext/RoleOverviewEntry.lua tests/test_role_overview_entry.lua tests/run.lua Core/function2.lua Core/BiaoGe.lua Bindings.xml Core/DB/Init2.lua
git commit -m "feat: add original-habit role overview entry"
```

Before committing, unstage unchanged optional files with `git restore --staged <path>`; never discard unrelated user changes.

### Task 8: Load order, data inventory, and full verification

**Files:**
- Modify: `BGLite.toc`
- Modify: `docs/security/data-inventory.md`
- Modify: `docs/baseline/BGNext-overrides.sha256`
- Create: `docs/verification/own-character-overview-clean-room.md`

- [ ] **Step 1: Add modules in dependency order**

Insert after BGNext initialization and before UI consumers:

```text
Core\BGNext\OwnCharacters.lua
Core\BGNext\OwnCharactersAdapters.lua
Core\BGNext\OwnCharactersCatalog.lua
Core\BGNext\OwnCharactersCollector.lua
Core\BGNext\OwnCharactersView.lua
Core\BGNext\RoleOverviewSettings.lua
Core\BGNext\OwnCharactersUI.lua
Core\BGNext\RoleOverviewEntry.lua
```

- [ ] **Step 2: Update the data inventory**

Document `ownCharacters[clientFamily][realmId][player]`, allowed snapshot fields, last-seen overwrite semantics, weekly reset expiry, local-only recipients, delete/clear controls, and medium privacy risk. State explicitly that no other-player, cross-account, historical, communication, or migration data is accepted.

- [ ] **Step 3: Review and update explicit overrides**

Run baseline verification first. For every modified upstream file, inspect its diff and update only that path in `docs/baseline/BGNext-overrides.sha256`. Do not bulk-refresh hashes and do not change the 188-file upstream manifest.

- [ ] **Step 4: Run all automated gates**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
pwsh -NoProfile -File tools/verify-baseline.ps1
git diff --check
rg -n -g "OwnCharacters*.lua" -g "RoleOverview*.lua" "SendAddonMessage|SendChatMessage|C_ChatInfo|INSPECT_READY|COMBAT_LOG_EVENT|CHAT_MSG" Core/BGNext
```

Expected: Lua `failed=0`; baseline verifies 188 files and the new explicit override count; `git diff --check` is silent; communication/inspection scan has no matches.

- [ ] **Step 5: Record honest compatibility status**

In `docs/verification/own-character-overview-clean-room.md`, mark Anniversary/Titan as code-covered and awaiting or completed in-game evidence as applicable. Mark other client families as code-covered/simulated/unverified based on actual evidence. Never label them “supported” solely because a catalog exists.

- [ ] **Step 6: Commit verification metadata**

```powershell
git add BGLite.toc docs/security/data-inventory.md docs/baseline/BGNext-overrides.sha256 docs/verification/own-character-overview-clean-room.md
git commit -m "docs: verify clean-room character overview"
```

### Task 9: Review checkpoint and PR update

**Files:** No runtime changes.

- [ ] **Step 1: Review branch scope**

```powershell
git status --short --branch
git log --oneline 295b1b9..HEAD
git diff --stat 295b1b9..HEAD
git diff --check 295b1b9..HEAD
```

Confirm only the design, plan, role-overview modules, tests, necessary integrations, localization, inventory, TOC, and reviewed override hashes changed.

- [ ] **Step 2: Run final clean-room checks**

Do not run similarity comparison by opening forbidden directories. Stop and hand control back to Codex/maintainer for the independent provenance audit. Report the exact new commit range and files so the independent reviewer can compare them without exposing reference source to the implementation session.

- [ ] **Step 3: Push without merging**

After all gates pass:

```powershell
git push origin codex/v0.1.0
```

Do not force-push, merge PR #1, create a tag, publish a Release, or modify `main`.

- [ ] **Step 4: Stop for game validation**

Provide the maintainer with the exact HEAD SHA and an installation file list. Do not read or overwrite the current game addon directory until the maintainer explicitly asks for installation. Required in-game screenshots: default current realm, Shift all realms with same-name characters, hidden `MCtitan`, hidden Titan-shard/resource column, pinned window, and settings panel.

## Completion standard

The task is complete only when all automated gates pass, the implementation session reports no access to forbidden source paths, the independent provenance audit passes, the branch is pushed without merging, and the feature remains explicitly “awaiting game validation” until screenshots are approved.
