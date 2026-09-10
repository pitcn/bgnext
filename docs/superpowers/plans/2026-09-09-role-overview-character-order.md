# Role Overview Character Order Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add persistent per-client character ordering to the role overview, controlled only by Up, Down, and Restore Default buttons in the existing settings page.

**Architecture:** Keep snapshots unchanged in `OwnCharacters`; store a separate validated identity array under `BiaoGe.BGNext.roleOverviewCharacterOrder[clientFamily]`. The model owns validation and mutations, the projection consumes an order rank without touching SavedVariables, and the settings page renders buttons that call the model and refresh the existing overview.

**Tech Stack:** WoW Lua 5.1, existing BGNext SavedVariables and frame helpers, plain-Lua regression suite, PowerShell baseline/release checks.

---

### Task 1: Add the character-order model and lifecycle safety

**Files:**
- Modify: `tests/test_data_lifecycle.lua`
- Modify: `tests/test_own_characters.lua`
- Modify: `Core/BGNext/DataLifecycle.lua`
- Modify: `Core/BGNext/OwnCharacters.lua`

- [ ] **Step 1: Write failing lifecycle tests**

Extend `tests/test_data_lifecycle.lua` to assert that `ensureRoot` creates `roleOverviewCharacterOrder`, preserves an existing table, and replaces a scalar/string with an empty table without touching `ownCharacters`.

```lua
test.eq(type(root.roleOverviewCharacterOrder), "table", "character order storage is initialized")
local preserved = { titan = { { realmId = 123, player = "Piti" } } }
test.eq(life.ensureRoot({ BGNext = { roleOverviewCharacterOrder = preserved } })
    .roleOverviewCharacterOrder, preserved, "valid character order storage is preserved")
test.eq(type(life.ensureRoot({ BGNext = { roleOverviewCharacterOrder = 1 } })
    .roleOverviewCharacterOrder), "table", "invalid character order storage is repaired")
```

- [ ] **Step 2: Write failing model tests**

In `tests/test_own_characters.lua`, add three characters across two realms plus another client family. Assert:

- missing order returns the current deterministic default;
- moving a middle character up/down persists `{ realmId, player }` only;
- first-up and last-down return `false` without mutation;
- duplicate, malformed, missing-character, and wrong-family entries are ignored;
- new characters append after valid custom entries in default order;
- Titan and MoP orders are independent;
- deleting one character removes only its order entry;
- `clearFamily` and `clearAll` clear matching order data;
- reset removes only the selected family's order and preserves snapshots.

Use public functions with the following contract:

```lua
M.characterOrder(root, clientFamily)                 -- sanitized identity array
M.listOrdered(root, clientFamily)                    -- snapshots in effective order
M.moveCharacter(root, clientFamily, realmId, player, delta) -- delta is -1 or 1
M.resetCharacterOrder(root, clientFamily)
```

- [ ] **Step 3: Run the suite to verify RED**

Run: `lua tests/run.lua`

Expected: failures for the missing order root and missing model functions.

- [ ] **Step 4: Initialize the optional storage root**

In `DataLifecycle.ensureRoot`, add a type guard beside `ownCharacters`:

```lua
root.roleOverviewCharacterOrder = type(root.roleOverviewCharacterOrder) == "table"
    and root.roleOverviewCharacterOrder or {}
```

Do not change `schemaVersion`; absence remains the backward-compatible default.

- [ ] **Step 5: Implement pure validated ordering in the model**

In `OwnCharacters.lua`:

- use the existing numeric `realmId` and non-empty `player` identity rules;
- rebuild effective order from currently stored snapshots on every read;
- accept each stored identity at most once;
- append missing snapshots in the existing `M.list` order;
- write a fresh array containing only `{ realmId, player }` after a successful move;
- reject deltas other than `-1` and `1`;
- make boundary moves no-ops;
- remove stale entries during successful writes;
- extend `delete`, `clearFamily`, and `clearAll` to remove only matching order records.

The implementation must never add ordering fields to a snapshot.

- [ ] **Step 6: Run the suite to verify GREEN**

Run: `lua tests/run.lua`

Expected: all suites pass with the new model tests.

- [ ] **Step 7: Commit the model slice**

```powershell
git add Core/BGNext/DataLifecycle.lua Core/BGNext/OwnCharacters.lua tests/test_data_lifecycle.lua tests/test_own_characters.lua
git commit -m "feat: add safe role overview character order"
```

### Task 2: Apply custom order in the role-overview projection

**Files:**
- Modify: `tests/test_own_character_view.lua`
- Modify: `tests/test_role_overview_entry.lua`
- Modify: `Core/BGNext/OwnCharactersView.lua`
- Modify: `Core/BGNext/RoleOverviewEntry.lua`

- [ ] **Step 1: Write failing projection tests**

Extend `tests/test_own_character_view.lua` with an input `characterOrder` containing full identities. Assert:

- custom order overrides the current-realm/name comparator;
- current-realm-only mode filters rows without changing the remaining relative order;
- all-realms mode preserves cross-realm custom order;
- unranked new characters appear after ranked characters using the existing default comparator;
- malformed and duplicate order entries cannot hide or duplicate rows;
- missing `characterOrder` preserves every existing ordering assertion unchanged.

Example input:

```lua
characterOrder = {
    { realmId = 456, player = "Piti" },
    { realmId = 123, player = "Alpha" },
}
```

- [ ] **Step 2: Write a failing provider wiring test**

Extend `tests/test_role_overview_entry.lua` source/runtime assertions so the provider obtains the model's sanitized character order and passes it to `OwnCharactersView.project`. Do not let the UI read `root.roleOverviewCharacterOrder` directly.

- [ ] **Step 3: Run the suite to verify RED**

Run: `lua tests/run.lua`

Expected: custom-order projection assertions fail because `buildRows` still applies only the default comparator.

- [ ] **Step 4: Add order ranks to the projection**

Update `buildRows` to accept the order array and build a local rank map keyed by the unambiguous pair `realmId + player`. Sorting rules:

1. two ranked rows compare by rank;
2. one ranked row comes before one unranked row;
3. two unranked rows use the existing current-realm, realm ID, and player-name comparator.

Filtering for `showAllRealms` happens before sorting. Do not mutate snapshots or the caller's order array.

- [ ] **Step 5: Wire the provider**

In `RoleOverviewEntry.provider`, pass:

```lua
characterOrder = Model and Model.characterOrder(root, family) or nil,
```

The provider remains read-only and sends no messages.

- [ ] **Step 6: Run the suite to verify GREEN**

Run: `lua tests/run.lua`

Expected: all suites pass, including all old default-order tests.

- [ ] **Step 7: Commit the projection slice**

```powershell
git add Core/BGNext/OwnCharactersView.lua Core/BGNext/RoleOverviewEntry.lua tests/test_own_character_view.lua tests/test_role_overview_entry.lua
git commit -m "feat: apply custom order to role overview rows"
```

### Task 3: Add Up, Down, and Restore Default controls to settings

**Files:**
- Modify: `tests/test_own_character_view.lua`
- Modify: `Core/BGNext/RoleOverviewSettings.lua`
- Modify: `Locales/zhCN.lua`
- Modify: `Locales/zhTW.lua`
- Modify: `Locales/enUS.lua`

- [ ] **Step 1: Write failing settings-model tests**

Add pure helper tests to `tests/test_own_character_view.lua` for a new `RoleOverviewSettings.characterOrderRows(root, family, model)` function. Assert each row contains only UI-safe values:

```lua
{
    realmId = 123,
    player = "Piti",
    label = "Piti" or "时光II-Piti",
    canMoveUp = false,
    canMoveDown = true,
}
```

Two same-name cross-realm characters must include a realm label; unique names remain compact. The helper must use `model.listOrdered` and never inspect arbitrary SavedVariables fields.

- [ ] **Step 2: Add failing source/UI boundary assertions**

Assert the settings source contains localized “角色顺序”, “上移”, “下移”, and “恢复默认排序” controls, calls `Model.moveCharacter`/`Model.resetCharacterOrder`, and does not register drag handlers or new events. Assert the existing column and clear controls remain present.

- [ ] **Step 3: Run the suite to verify RED**

Run: `lua tests/run.lua`

Expected: failures for the missing helper and controls.

- [ ] **Step 4: Implement the pure row projection**

In `RoleOverviewSettings.lua`, add `characterOrderRows`. Build a collision count by player name, then label only colliding names with `realmName` (falling back to `realmId`). Compute button enablement from the effective list index.

- [ ] **Step 5: Build pooled settings rows**

Inside `BuildPanel`, after the column-reset control and before the module enable/clear controls:

- add the “角色顺序” heading;
- create one label plus “上移” and “下移” buttons per current row;
- disable the first Up and last Down button;
- on click call `Model.moveCharacter`, rebuild only this row section, refresh the open overview, and play the existing click sound;
- add “恢复默认排序”, calling `Model.resetCharacterOrder`, rebuilding rows, and refreshing;
- show a localized “暂无角色数据” line when empty;
- rebuild rows when the settings page is shown so newly observed characters appear without a reload;
- reuse or hide previously created controls instead of accumulating frames after each move.

Do not add drag scripts, timers, events, tooltips, confirmation dialogs, or a second settings window.

- [ ] **Step 6: Add three-locale strings**

Add natural translations for:

- `角色顺序`
- `上移`
- `下移`
- `恢复默认排序`
- `暂无角色数据`

Use Chinese source keys, `true` values in `zhCN`, Traditional Chinese translations in `zhTW`, and concise English in `enUS`.

- [ ] **Step 7: Run the suite to verify GREEN**

Run: `lua tests/run.lua`

Expected: all suites pass and old settings controls remain detectable.

- [ ] **Step 8: Commit the settings slice**

```powershell
git add Core/BGNext/RoleOverviewSettings.lua Locales/zhCN.lua Locales/zhTW.lua Locales/enUS.lua tests/test_own_character_view.lua
git commit -m "feat: add role overview order buttons"
```

### Task 4: Document the data field and run release-grade verification

**Files:**
- Modify: `docs/security/data-inventory.md`
- Modify: `docs/testing/own-character-overview-clean-room.md`
- Modify: `docs/baseline/BGNext-overrides.sha256` only if an approved baseline runtime file changed; otherwise leave untouched

- [ ] **Step 1: Update the data inventory**

Add one row for `roleOverviewCharacterOrder[clientFamily][*]` documenting that it contains only the local user's existing own-character `realmId` and `player`, exists solely to order the local overview, is stored until reset/deletion/clear, has no recipients, and is low risk.

- [ ] **Step 2: Update the manual test checklist**

Add a concise scenario:

1. open role-overview settings;
2. move a character up and down;
3. verify the overview updates immediately;
4. reload and verify persistence;
5. switch current/all-realm view and verify relative order;
6. restore default and verify no character data was deleted.

- [ ] **Step 3: Run focused and full verification**

Run:

```powershell
lua tests/run.lua
pwsh -NoProfile -File tools/verify-baseline.ps1
git diff --check origin/main...HEAD
```

Expected: zero Lua failures, verified official BGLite 2.4.2 baseline, and no whitespace errors.

- [ ] **Step 4: Inspect runtime scope**

Run:

```powershell
git diff --stat origin/main...HEAD
git diff origin/main...HEAD -- Core/BGNext/OwnCharacters.lua Core/BGNext/OwnCharactersView.lua Core/BGNext/RoleOverviewEntry.lua Core/BGNext/RoleOverviewSettings.lua Core/BGNext/DataLifecycle.lua
rg -n "SendAddonMessage|SendChatMessage|RegisterEvent|RegisterForDrag|OnDrag" Core/BGNext/OwnCharacters.lua Core/BGNext/OwnCharactersView.lua Core/BGNext/RoleOverviewSettings.lua
```

Expected: changes stay inside ordering/storage/settings concerns; no communication, new event, or drag behavior appears.

- [ ] **Step 5: Commit documentation**

```powershell
git add docs/security/data-inventory.md docs/testing/own-character-overview-clean-room.md
git commit -m "docs: document role overview character order"
```

- [ ] **Step 6: Perform the game check before release**

On one supported client, verify the settings buttons, immediate refresh, reload persistence, current/all-realm projection, and restore default behavior. Record that this is one-client evidence only; do not claim every game version was tested in game.
