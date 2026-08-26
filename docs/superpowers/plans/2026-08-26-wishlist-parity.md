# BGNext Original-Equivalent Wishlist Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the temporary flat BGNext wishlist with an independently implemented, local-only wishlist whose permitted UI and behavior match BiaoGe v2.3.5 while excluding wish broadcasts and team-competition queries.

**Architecture:** Keep persistent validation and import/export logic in `Core/BGNext/Wishlist.lua`, keep frame construction and input behavior in `Core/BGNext/WishlistUI.lua`, and isolate event-to-reminder matching in a new pure `Core/BGNext/WishlistReminder.lua`. Reuse reviewed BGLite raid, boss, loot, item-tooltip and auction hooks, but do not copy historical BiaoGe code or assets.

**Tech Stack:** World of Warcraft Lua 5.1, BGLite 2.4.0 frame helpers and local loot database, SavedVariables under `BiaoGe.BGNext`, PowerShell verification scripts, Lua 5.1 unit tests.

---

## Locked file structure

- Modify `Core/BGNext/Wishlist.lua`: slot-based local data, validation, placement, migration, import/export.
- Modify `Core/BGNext/WishlistUI.lua`: original-equivalent grid, keyboard/mouse behavior, import/export panels and clear confirmation.
- Create `Core/BGNext/WishlistReminder.lua`: pure deduplication and local reminder adapter.
- Modify `Core/Module/Auction.lua`: call the local reminder adapter from the existing current-auction hook only.
- Modify `Core/Module/Loot.lua`: call the local reminder adapter from the two existing loot paths only.
- Modify `BGLite.toc`: load the reminder module after `Wishlist.lua` and before runtime consumers.
- Modify `tests/test_wishlist.lua`: slot model, validation, migration and codec coverage.
- Replace `tests/test_wishlist_ui.lua`: navigation, shortcut and forbidden-path assertions.
- Create `tests/test_wishlist_reminder.lua`: event deduplication and local-only behavior.
- Modify `tests/run.lua`: register the new reminder suite.
- Modify `docs/security/data-inventory.md`: slot data, isolated legacy BGNext test data and manual import/export.
- Create `docs/reviews/wishlist-parity-matrix.md`: same-state visual and behavior acceptance record.
- Modify `docs/baseline/BGNext-overrides.sha256`: only hashes for reviewed runtime overrides.
- Modify `CHANGELOG.md`: describe the user-visible replacement and privacy exclusions.

### Task 1: Lock the data and communication contract

**Files:**
- Modify: `docs/security/data-inventory.md`
- Create: `docs/reviews/wishlist-parity-matrix.md`

- [ ] **Step 1: Replace the generic wishlist inventory row**

Use these rows:

```markdown
| `wishlist[realmId][player][raidId][difficultyIndex][bossIndex][slotIndex]` | Item IDs explicitly selected by the current player for their own logged-in character | Reproduce the original boss-and-slot wishlist and local reminders | Local until the user removes a slot, clears the raid, or clears BGNext data | Current player UI only | Edit slot/right-click remove/clear/import | Medium |
| `wishlistUnplaced[realmId][player][raidId][itemId]` | Items from the temporary BGNext flat wishlist that cannot be mapped reliably to one boss | Preserve user-entered test data without guessing a boss | Local until manually cleared or successfully placed | Current player UI only | Review and clear locally | Medium |
| Manual wishlist import/export text | Raid, difficulty, boss position and item IDs selected by the current player | User-directed backup and restore | Visible edit box only; BGNext does not write it outside SavedVariables or send it | Recipient chosen manually by the user after copying | Explicit click, full preview, cancel available | Medium |
```

State beneath the table that wishlist import/export never calls `SendChatMessage`, `C_ChatInfo.SendAddonMessage`, clipboard APIs, HTTP, telemetry or file APIs.

- [ ] **Step 2: Create the parity matrix with fixed rows**

Create `docs/reviews/wishlist-parity-matrix.md` with columns `State`, `BiaoGe evidence`, `BGNext evidence`, `Result`, `Allowed difference`. Include rows for: tab, each client’s difficulty arrangement, boss rows, empty slot, filled slot, hovered slot, focused slot, looted marker, right-click delete, cursor drop, item picker, Tab, four arrow keys, Enter, Shift-click, Ctrl-click, full-boss rejection, invalid-drop rejection, clear confirmation, import panel, export panel, successful import, empty export, loot reminder and auction reminder. Add three explicit absent rows: broadcast buttons, channel selector and competition query.

- [ ] **Step 3: Verify and commit the contract**

Run `git diff --check`. Expected: no output.

```powershell
git add docs/security/data-inventory.md docs/reviews/wishlist-parity-matrix.md
git commit -m "docs: lock wishlist data and parity contract"
```

### Task 2: Replace the flat map with a validated slot model

**Files:**
- Modify: `Core/BGNext/Wishlist.lua`
- Modify: `tests/test_wishlist.lua`

- [ ] **Step 1: Write failing slot-model tests**

Replace the old flat-list assertions with fixtures shaped as follows:

```lua
local root = { wishlist = {}, wishlistUnplaced = {} }
local limits = { difficulties = 2, bosses = 3, slots = 2 }

test.eq(wish.setSlot(root, "realm", "A", "ICC", limits, 1, 2, 1, 5001), true, "valid slot stored")
test.eq(wish.getSlot(root, "realm", "A", "ICC", 1, 2, 1), 5001, "slot returns item")
test.eq(wish.getSlot(root, "realm", "B", "ICC", 1, 2, 1), nil, "other character isolated")
test.eq(wish.getSlot(root, "realm", "A", "TOC", 1, 2, 1), nil, "other raid isolated")
test.eq(wish.setSlot(root, "realm", "A", "ICC", limits, 3, 1, 1, 5002), false, "difficulty out of range")
test.eq(wish.setSlot(root, "realm", "A", "ICC", limits, 1, 4, 1, 5002), false, "boss out of range")
test.eq(wish.setSlot(root, "realm", "A", "ICC", limits, 1, 1, 3, 5002), false, "slot out of range")
test.eq(wish.clearSlot(root, "realm", "A", "ICC", 1, 2, 1), true, "right-click removal clears one slot")
test.eq(wish.clearRaid(root, "realm", "A", "ICC"), true, "clear removes only current raid")
```

Also assert `findItem` returns every matching slot, `contains` is true when at least one slot matches, and two slots may intentionally hold the same item while an event match is logically one item.

- [ ] **Step 2: Run the suite and verify RED**

Run `pwsh -NoProfile -File tools/run-lua-tests.ps1`.

Expected: `tests/test_wishlist.lua` fails because `setSlot`, `getSlot`, `clearSlot`, `clearRaid` and `findItem` do not exist.

- [ ] **Step 3: Implement the minimal validated slot API**

In `Core/BGNext/Wishlist.lua`, retain `itemIdFromValue` and replace flat-map helpers with these public operations:

```lua
function M.setSlot(root, realmId, player, raidId, limits, difficultyIndex, bossIndex, slotIndex, itemId)
    if not validItemId(itemId) or not validLimits(limits, difficultyIndex, bossIndex, slotIndex) then
        return false
    end
    local raid = getRaid(root, realmId, player, raidId, true)
    if not raid then return false end
    raid[difficultyIndex] = raid[difficultyIndex] or {}
    raid[difficultyIndex][bossIndex] = raid[difficultyIndex][bossIndex] or {}
    raid[difficultyIndex][bossIndex][slotIndex] = itemId
    return true
end

function M.getSlot(root, realmId, player, raidId, difficultyIndex, bossIndex, slotIndex)
    local raid = getRaid(root, realmId, player, raidId, false)
    return raid and raid[difficultyIndex] and raid[difficultyIndex][bossIndex]
        and raid[difficultyIndex][bossIndex][slotIndex] or nil
end

function M.clearSlot(root, realmId, player, raidId, difficultyIndex, bossIndex, slotIndex)
    local slots = getBossSlots(root, realmId, player, raidId, difficultyIndex, bossIndex)
    if not slots or slots[slotIndex] == nil then return false end
    slots[slotIndex] = nil
    return true
end

function M.contains(root, realmId, player, raidId, itemId)
    return #M.findItem(root, realmId, player, raidId, itemId) > 0
end
```

`findItem` iterates numeric difficulty, boss and slot keys, returning `{ difficultyIndex, bossIndex, slotIndex }` records sorted in that order. `clearRaid` replaces only the selected raid table with `{}` and does not touch another character or raid.

- [ ] **Step 4: Run GREEN and commit**

Run the full Lua suite. Expected: every suite passes.

```powershell
git add Core/BGNext/Wishlist.lua tests/test_wishlist.lua
git commit -m "feat: model wishlists by difficulty boss and slot"
```

### Task 3: Add safe placement and temporary-data migration

**Files:**
- Modify: `Core/BGNext/Wishlist.lua`
- Modify: `tests/test_wishlist.lua`

- [ ] **Step 1: Write failing placement and migration tests**

Add tests using a resolver that returns `{ difficultyIndex = 1, bossIndex = 2 }` for item `6001` and `nil` for item `6999`:

```lua
local placed = wish.placeItem(root, "realm", "A", "ICC", limits, 6001, resolver)
test.eq(placed.ok, true, "normal boss drop placed")
test.eq(placed.slotIndex, 1, "first free original-order slot used")

wish.setSlot(root, "realm", "A", "ICC", limits, 1, 2, 2, 6002)
local full = wish.placeItem(root, "realm", "A", "ICC", limits, 6003, resolver)
test.eq(full.reason, "boss-full", "full boss rejected")
test.eq(wish.placeItem(root, "realm", "A", "ICC", limits, 6999, resolver).reason, "unknown-drop", "unknown drop rejected")

local legacy = { wishlist = { realm = { A = { ICC = { [6001] = true, [6999] = true } } } }, wishlistUnplaced = {} }
local result = wish.migrateFlatRaid(legacy, "realm", "A", "ICC", limits, resolver)
test.eq(result.placed, 1, "known legacy item placed")
test.eq(result.quarantined, 1, "unknown legacy item quarantined")
test.eq(legacy.wishlistUnplaced.realm.A.ICC[6999], true, "unknown item preserved")
```

- [ ] **Step 2: Run RED**

Run the full suite. Expected: failure because `placeItem` and `migrateFlatRaid` are missing.

- [ ] **Step 3: Implement deterministic placement**

`placeItem` must call the injected resolver, reject unknown or out-of-range positions, scan slots `1..limits.slots`, and write to the first empty slot. Return `{ ok = false, reason = "unknown-drop" }` or `{ ok = false, reason = "boss-full" }` without changing data.

`migrateFlatRaid` must first detect the old boolean-key form, build a sorted item-ID list, place each resolvable item, put unresolved/full items under `wishlistUnplaced`, and only then replace the old raid table with the new slot table. Running it twice must return `{ placed = 0, quarantined = 0, changed = false }`.

- [ ] **Step 4: Run GREEN and commit**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
git add Core/BGNext/Wishlist.lua tests/test_wishlist.lua
git commit -m "feat: place wishlist items using verified boss drops"
```

### Task 4: Implement the original wishlist text codec safely

**Files:**
- Modify: `Core/BGNext/Wishlist.lua`
- Modify: `tests/test_wishlist.lua`

- [ ] **Step 1: Write failing codec tests**

Use the historical visible text structure without importing historical SavedVariables:

```lua
wish.setSlot(root, "realm", "A", "ICC", limits, 1, 2, 1, 7001)
wish.setSlot(root, "realm", "A", "ICC", limits, 1, 2, 2, 7002)
test.eq(wish.exportRaid(root, "realm", "A", "ICC", limits), "ICC:n1b2-7001-7002", "stable original text format")
test.eq(wish.exportRaid({ wishlist = {} }, "realm", "A", "ICC", limits), nil, "empty raid has no payload")

local imported = wish.parseImport("ICC:n1b2-7001-7002,n2b1-7100", { ICC = limits })
test.eq(imported.ok, true, "valid import parsed")
test.eq(imported.raids.ICC[1][2][1], 7001, "first imported slot")
test.eq(wish.parseImport("ICC:n9b2-7001", { ICC = limits }).ok, false, "out-of-range import rejected")
test.eq(wish.parseImport("ICC:n1b2-doSomething()", { ICC = limits }).ok, false, "non-numeric payload rejected")
```

Add a replacement test proving `applyImport` leaves existing data untouched when parsing fails and replaces only each successfully parsed raid when parsing succeeds.

- [ ] **Step 2: Run RED**

Expected failure: `exportRaid`, `parseImport` and `applyImport` are missing.

- [ ] **Step 3: Implement a non-executable parser**

Implement with only `string.match`, `string.gmatch`, `tonumber`, table construction and numeric bounds. Do not call `loadstring`, `load`, `RunScript`, chat APIs or addon-message APIs. Sort exported difficulty and boss numbers; preserve slot order. Cap the input at 32 KiB and the total accepted item count at the sum of declared slots. Return structured errors: `empty`, `too-large`, `unknown-raid`, `invalid-section`, `out-of-range`, `invalid-item`, or `too-many-items`.

- [ ] **Step 4: Run GREEN and commit**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
rg -n 'loadstring|RunScript|SendChatMessage|SendAddonMessage' Core/BGNext/Wishlist.lua
git add Core/BGNext/Wishlist.lua tests/test_wishlist.lua
git commit -m "feat: add manual wishlist import and export"
```

Expected scan: no matches.

### Task 5: Replace the simplified page with the original grid

**Files:**
- Modify: `Core/BGNext/WishlistUI.lua`
- Replace: `tests/test_wishlist_ui.lua`

- [ ] **Step 1: Write failing pure UI-contract tests**

Expose only pure helpers on the module table and test them:

```lua
test.eq(ui.tabNumber, 3, "wishlist uses original third tab")
test.eq(ui.nextCell(1, 1, 1, "RIGHT", 2, 3, 2).slotIndex, 2, "right moves one slot")
test.eq(ui.nextCell(1, 1, 2, "RIGHT", 2, 3, 2).bossIndex, 2, "right wraps to next boss")
test.eq(ui.nextCell(1, 3, 2, "DOWN", 2, 3, 2).difficultyIndex, 2, "down wraps to next difficulty")
test.eq(ui.nextCell(2, 3, 2, "TAB", 2, 3, 2).difficultyIndex, 1, "tab wraps whole grid")
test.eq(ui.shortcutAction(false, "LeftButton", true), "wishlist", "alt-left sets wish")
test.eq(ui.shortcutAction(true, "RightButton", true), "auction", "alt-right keeps auction")
test.eq(ui.shortcutAction(false, "LeftButton", false), nil, "no modifier does not set wish")
```

Read the file as text and assert the old strings `个人心愿清单`, `输入物品 ID` and `已记录 %d 件装备` are absent. Assert `SendChatMessage`, `SendAddonMessage`, `通报心愿` and `查询心愿竞争` are absent.

- [ ] **Step 2: Run RED**

Expected: the tab and navigation tests fail, and the old simplified-page text assertions fail.

- [ ] **Step 3: Build the grid using BGLite primitives**

Set `M.tabNumber = 3`. Build `BG.HopeMainFrame` and `BG.HopeFrame[raidId]["n"..difficulty]["boss"..boss]["slot"..slot]`. Use the BGLite values `ns.HopeMaxn[raidId]`, `ns.HopeMaxb[raidId]`, `ns.HopeMaxi`, `BG.difficultyTable`, and `BG.Boss` for dimensions and labels. Match the original constants discovered during reference review: item edit width `115`, boss title width `100`, secondary gap `20`, item height `20`, title font size `15`, and original difficulty ordering. Use `BG.editTemplate`, `BG.LootedText`, `BG.SetListzhuangbei`, `BG.AddHText`, `BG.BindOnEquip`, `BG.LevelText`, `BG.IsHave`, `BG.UpdateFilter` and item tooltips rather than creating substitute widgets.

Each slot’s `OnTextChanged` converts the displayed link to an item ID and writes only through `Wishlist.setSlot`; an empty field calls `clearSlot`. A rejected item restores the prior slot value and shows the mapped local error. The frame `OnShow` compacts holes within each boss from left to right and refreshes looted markers.

- [ ] **Step 4: Add original mouse and keyboard behavior**

Implement these exact handlers:

- RightButton without Alt: clear one slot.
- Cursor item on mouse-up: validate and place in that slot.
- Shift click on a filled slot: insert its link into chat through existing `BG.InsertLink` only after the user gesture.
- Ctrl click/hover: use existing dress-up/item-library behavior when supported.
- Tab and arrow keys: call the tested `nextCell` and focus the returned existing slot.
- Enter: clear focus and hide the item picker.
- Focus gained: select text, record `BG.lastfocuszhuangbei`, open the existing boss-drop picker.
- Focus lost: clear selection and focus marker.

Do not create a free-form item-ID input or scroll-list rows.

- [ ] **Step 5: Run GREEN and commit**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
git add Core/BGNext/WishlistUI.lua tests/test_wishlist_ui.lua
git commit -m "feat: rebuild wishlist in the original boss grid"
```

### Task 6: Restore clear, import and export panels

**Files:**
- Modify: `Core/BGNext/WishlistUI.lua`
- Modify: `tests/test_wishlist_ui.lua`

- [ ] **Step 1: Write failing source-contract tests**

Assert the UI contains named local handlers `showImportPanel`, `showExportPanel`, and `confirmClearRaid`; assert it calls `Wishlist.parseImport`, `Wishlist.applyImport`, and `Wishlist.exportRaid`. Assert the import/export buttons are parented to `BG.HopeMainFrame` and anchored at the original top-right area. Assert there is no automatic clipboard or chat call.

- [ ] **Step 2: Run RED**

Expected: missing-handler assertions fail.

- [ ] **Step 3: Implement original-equivalent panels**

Create the two `250 x 250` bordered panels at the main frame’s top-right, with a multiline edit box, original-style title, OK/Cancel buttons for import, and Cancel-only plus selected read-only text for export. Only one panel can be visible. Escape closes either panel. Import performs no mutation until OK or Enter; parse failure keeps the panel open and preserves stored data. Successful import refreshes only affected raids and reports the actual count.

Create the original-position current-wishlist clear button and a static confirmation dialog. Acceptance calls `Wishlist.clearRaid` for the current realm, character and raid; cancellation changes nothing.

- [ ] **Step 4: Run GREEN and commit**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
git add Core/BGNext/WishlistUI.lua tests/test_wishlist_ui.lua
git commit -m "feat: restore wishlist clear import and export controls"
```

### Task 7: Centralize local-only loot and auction reminders

**Files:**
- Create: `Core/BGNext/WishlistReminder.lua`
- Create: `tests/test_wishlist_reminder.lua`
- Modify: `tests/run.lua`
- Modify: `BGLite.toc`
- Modify: `Core/Module/Loot.lua`
- Modify: `Core/Module/Auction.lua`

- [ ] **Step 1: Write failing reminder tests**

Test a pure `matchEvent` function:

```lua
local event = reminder.matchEvent({ 8001, 8001, 8002 }, 8001, "ICC", "loot:42")
test.eq(event.matched, true, "matching wish reminds")
test.eq(event.key, "loot:42:8001", "event key is deterministic")
test.eq(reminder.shouldNotify({}, event.key), true, "first event notifies")
local seen = {}; reminder.markNotified(seen, event.key)
test.eq(reminder.shouldNotify(seen, event.key), false, "duplicate slot/event notifies once")
test.eq(reminder.matchEvent({ 8001 }, 8999, "ICC", "auction:7").matched, false, "unmatched item silent")
```

Read the new module as text and assert it contains no SavedVariables writes, `SendChatMessage`, `SendAddonMessage`, network or timer-driven background send path.

- [ ] **Step 2: Run RED**

Expected: failure because `WishlistReminder.lua` is absent.

- [ ] **Step 3: Implement the pure adapter and runtime notifier**

The module stores seen event keys in a local in-memory table only. Its runtime `notify(kind, itemId, raidId, eventId, itemLink, level)` first queries the current player’s wishlist, deduplicates by `kind:eventId:itemId`, then calls the existing local `BG.FrameLootMsg:AddMessage` and `BG.PlaySound("hope")`. It returns `true` only when a new local notification was displayed.

Load it after `Wishlist.lua`. Replace the duplicated direct `BG.IsHope` reminder branches in the two loot paths and the existing auction wish branch with calls to this adapter, while preserving BGLite’s current auction frame `<心愿>` marker and auto-expand behavior. Do not add a protocol message or new event listener.

- [ ] **Step 4: Run GREEN and commit**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
git add BGLite.toc Core/BGNext/WishlistReminder.lua Core/Module/Loot.lua Core/Module/Auction.lua tests/run.lua tests/test_wishlist_reminder.lua
git commit -m "feat: add local-only wishlist reminders"
```

### Task 8: Review baseline overrides and perform offline gates

**Files:**
- Modify: `docs/baseline/BGNext-overrides.sha256`
- Modify: `CHANGELOG.md`
- Verify: all files changed by Tasks 1–7

- [ ] **Step 1: Review every runtime difference**

Run:

```powershell
git diff 57af73b...HEAD -- BGLite.toc Core/BGNext/Wishlist.lua Core/BGNext/WishlistUI.lua Core/BGNext/WishlistReminder.lua Core/Module/Loot.lua Core/Module/Auction.lua
```

Expected: only slot-model, original-equivalent UI, manual codec and local reminder changes. No team-wish communication, player aggregation, telemetry, historical SavedVariables import or unrelated auction behavior.

- [ ] **Step 2: Update only reviewed override hashes**

Calculate SHA-256 for the changed BGLite baseline files and replace only their exact lines in `docs/baseline/BGNext-overrides.sha256`. Add hashes for new BGNext runtime modules. Do not bulk-regenerate the file.

- [ ] **Step 3: Record the changelog**

Add under `0.1.0`:

```markdown
- 以独立实现恢复原版 BiaoGe 的个人心愿清单布局与操作习惯。
- 恢复本人主动触发、内容可见的心愿导入与导出。
- 心愿掉落和当前拍卖提醒仅在本地显示；不恢复通报心愿和团队心愿竞争查询。
```

- [ ] **Step 4: Run all offline gates**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
pwsh -NoProfile -File tools/verify-baseline.ps1
git diff --check
& 'C:\Program Files (x86)\Lua\5.1\luac.exe' -p Core\BGNext\Wishlist.lua
& 'C:\Program Files (x86)\Lua\5.1\luac.exe' -p Core\BGNext\WishlistUI.lua
& 'C:\Program Files (x86)\Lua\5.1\luac.exe' -p Core\BGNext\WishlistReminder.lua
```

Expected: all suites pass, baseline integrity passes, diff check is empty and all three files compile under Lua 5.1.

- [ ] **Step 5: Commit verified metadata**

```powershell
git add CHANGELOG.md docs/baseline/BGNext-overrides.sha256
git commit -m "chore: verify original-equivalent wishlist"
```

### Task 9: Install and complete the same-state game acceptance matrix

**Files:**
- Modify: `docs/reviews/wishlist-parity-matrix.md`
- Verify package: `C:\World of Warcraft1\_classic_titan_\Interface\AddOns\BGLite`

- [ ] **Step 1: Build a runtime-only package**

Include only `BGLite.toc`, `Bindings.xml`, `Templates.xml`, `addon_version.txt`, and tracked files under `Core/`, `Libs/`, `Locales/`, and `Media/`. Verify every staged file hash against the worktree before installation.

- [ ] **Step 2: Back up and install safely**

Confirm no `Wow*` process is running. Resolve the exact target and generate the backup name with:

```powershell
$short = (git rev-parse --short HEAD).Trim()
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$target = (Resolve-Path 'C:\World of Warcraft1\_classic_titan_\Interface\AddOns\BGLite').Path
$backup = Join-Path 'D:\vibe coding\BGN\backups' "BGLite-before-$short-$stamp"
```

Move the exact existing addon directory to `$backup`, then move the verified staged `BGLite` directory to `$target`. Verify every installed runtime hash. Do not delete the backup or SavedVariables.

- [ ] **Step 3: Run the original/BGNext matrix**

At identical resolution and UI scale, capture paired screenshots for every row in `docs/reviews/wishlist-parity-matrix.md`. Mark `PASS` only where layout, behavior and feedback match. Mark the three prohibited controls `PASS` only when absent and no corresponding send/query handler exists. Record unavoidable client/API or rights-related differences in `Allowed difference`.

- [ ] **Step 4: Verify privacy and compatibility in game**

Confirm wishlist changes produce no raid/party/guild/whisper/addon messages; reload preserves only the current character’s slots; another own character is isolated; another player cannot inspect the list; BGLite basic auctions still work when the BGNext player has no wish, has a matching wish, and has a nonmatching wish.

- [ ] **Step 5: Commit acceptance evidence**

After all rows pass or have an approved allowed difference:

```powershell
git add docs/reviews/wishlist-parity-matrix.md
git commit -m "test: verify wishlist parity in game"
```

Do not mark the wishlist complete or merge the PR while any required row remains unverified.
