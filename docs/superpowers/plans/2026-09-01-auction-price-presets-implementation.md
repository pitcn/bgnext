# BGNext Auction Price Presets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the local “团长起拍价 / 我的心理价” page, safe import/export, and silent prefill of the two existing auction price inputs.

**Architecture:** Keep validated SavedVariables operations, loot-catalog indexing, text codec, frame creation, and auction hooks in separate BGNext modules. The page shares one indexed and row-reusing item list across two price modes; runtime hooks only query a resolved price and set an existing EditBox, never send or click anything.

**Tech Stack:** World of Warcraft Lua 5.1, existing BGLite frame helpers and loot catalog, plain-Lua test harness, PowerShell release/baseline tools.

---

## Preconditions and file map

Work from `D:\vibe coding\BGN` after the v0.3.1 fixes are integrated. Read these documents before editing runtime code:

- `CONTEXT.md`
- `SECURITY.md`
- `docs/policies/PRIVACY.md`
- `docs/security/data-inventory.md`
- `docs/adr/0001-verified-baseline-and-release-package.md`
- `docs/adr/0003-reference-study-original-implementation.md`
- `docs/superpowers/specs/2026-09-01-auction-price-presets-design.md`

Create or modify only these feature files unless a failing test proves another integration point is required:

| Path | Responsibility |
| --- | --- |
| `Core/BGNext/AuctionPriceStore.lua` | Validated leader/personal storage, scheme operations, defaults, price resolution |
| `Core/BGNext/AuctionPriceCatalog.lua` | Approved raid/Boss/item projection and pure filtering |
| `Core/BGNext/AuctionPriceCodec.lua` | Deterministic separated export formats, parse/preview, atomic apply descriptors |
| `Core/BGNext/AuctionPriceUI.lua` | Tab 2 page, hierarchy, reused rows, toolbars, confirmation and import/export panels |
| `Core/BGNext/AuctionPriceRuntime.lua` | Thin leader and bidder EditBox prefill hooks |
| `tests/test_auction_price_store.lua` | Store and resolution tests |
| `tests/test_auction_price_catalog.lua` | Catalog grouping/filter tests |
| `tests/test_auction_price_codec.lua` | Codec limits, preview and round-trip tests |
| `tests/test_auction_price_ui.lua` | Pure layout/state and source-boundary tests |
| `tests/test_auction_price_runtime.lua` | Hook decisions and no-send tests |

Expected existing modifications:

- `Core/BGNext/DataLifecycle.lua`
- `Core/Module/Auction.lua`
- `BGLite.toc`
- `tests/run.lua`
- `Locales/zhCN.lua`, `Locales/zhTW.lua`, `Locales/enUS.lua`
- `docs/security/data-inventory.md`
- `docs/baseline/BGNext-overrides.sha256`
- `CHANGELOG.md`

Do not read, copy, transform, or package Gargul/BiaoGe implementation or assets. The observable workflow is already recorded in the spec.

Locked product constraints for every task:

- The page labels are exactly `团长起拍价` and `我的心理价`.
- Navigation remains `团本 → Boss／杂项 → 装备掉落池`; the description row must not replace the scheme toolbar.
- Fresh defaults are 100 G for Vanilla/SoD, TBC, and Titan; existing `BiaoGe.Auction.money` is read and preserved. Wrath remains 1,000 G, Mists 10,000 G, and Cataclysm/Retail 100,000 G.
- Valid stored prices are integer `0..10,000,000 G`, with zero distinct from an absent value.
- Price prefill must not automatically start an auction, enable automatic bidding, or send any message（不自动开拍、不自动启用、不自动发送）.
- Existing auction windows receive no permanent labels, source text, or size increase.

### Task 1: Add SavedVariables roots and safe client defaults

**Files:**
- Modify: `Core/BGNext/DataLifecycle.lua`
- Modify: `Core/Module/Auction.lua:33-60`
- Modify: `tests/test_data_lifecycle.lua`
- Create: `tests/test_auction_price_store.lua`
- Modify: `tests/run.lua`

- [ ] **Step 1: Register the empty store suite and write failing root/default tests**

Add `tests/test_auction_price_store.lua` to `tests/run.lua`. Test that `ensureRoot` creates both new roots without reading the retired field, and test this pure default table contract:

```lua
test.eq(type(root.leaderAuctionPricePresets), "table", "leader price root")
test.eq(type(root.personalAuctionExpectations), "table", "personal price root")
test.eq(root.auctionPresets, nil, "retired auto-bid presets stay unread")

local expected = {
    vanilla = 100, tbc = 100, wrath = 1000, titan = 100,
    cataclysm = 100000, mop = 10000, retail = 100000,
}
for family, money in pairs(expected) do
    test.eq(store.defaultGlobalPrice(family), money, family .. " default")
end
```

- [ ] **Step 2: Run the suite and verify the new assertions fail**

Run: `pwsh -NoProfile -File tools/run-lua-tests.ps1`

Expected: FAIL because the roots and `AuctionPriceStore` do not exist.

- [ ] **Step 3: Add roots and the pure default mapping**

In `DataLifecycle.ensureRoot` add only:

```lua
root.leaderAuctionPricePresets = root.leaderAuctionPricePresets or {}
root.personalAuctionExpectations = root.personalAuctionExpectations or {}
```

Create `AuctionPriceStore.lua` with constants and this public function:

```lua
local DEFAULTS = {
    vanilla = 100, tbc = 100, wrath = 1000, titan = 100,
    cataclysm = 100000, mop = 10000, retail = 100000,
}
function M.defaultGlobalPrice(clientFamily)
    return DEFAULTS[clientFamily]
end
```

In `Core/Module/Auction.lua`, change only fresh-value branches: `BG.verLess2` to `100`, `BG.IsTitan` to `100`, keep WLK `1000`, MOP `10000`, and the final Cataclysm/Retail branch `100000`. Preserve every `or` assignment so an existing `BiaoGe.Auction.money` is never overwritten.

- [ ] **Step 4: Load the store and rerun tests**

Add `Core\BGNext\AuctionPriceStore.lua` after `DataLifecycle.lua` in `BGLite.toc` and rerun the full Lua suite.

Expected: the new root/default assertions PASS and all prior tests remain green.

- [ ] **Step 5: Commit the foundation**

```powershell
git add BGLite.toc Core/BGNext/DataLifecycle.lua Core/BGNext/AuctionPriceStore.lua Core/Module/Auction.lua tests/run.lua tests/test_data_lifecycle.lua tests/test_auction_price_store.lua
git commit -m "feat: add auction price storage roots"
```

### Task 2: Implement leader scheme storage and price resolution

**Files:**
- Modify: `Core/BGNext/AuctionPriceStore.lua`
- Modify: `tests/test_auction_price_store.lua`

- [ ] **Step 1: Write failing leader scheme tests**

Cover `ensureLeaderRaid`, `createPreset`, `copyPreset`, `renamePreset`, `deletePreset`, `selectPreset`, `setBasePrice`, `setLeaderItemPrice`, `clearLeaderItemPrice`, and `resolveLeaderPrice` with this contract:

```lua
local raid = store.ensureLeaderRaid(root, "titan", "ULD", 777)
test.eq(raid.presets[raid.activePresetId].name, "默认方案", "default name")
test.eq(raid.presets[raid.activePresetId].basePrice, 777, "copies local global price")
test.eq(store.resolveLeaderPrice(root, "titan", "ULD", 1001), 777, "base fallback")
test.eq(store.setLeaderItemPrice(root, "titan", "ULD", raid.activePresetId, 1001, 0), true, "zero is explicit")
test.eq(store.resolveLeaderPrice(root, "titan", "ULD", 1001), 0, "item zero wins")
```

Also assert max 20 schemes, integer price range `0..10000000`, 24 UTF-8-character names, deep-copy independence, and deletion refusal when no valid fallback exists.

- [ ] **Step 2: Run and observe the missing API failures**

Run: `pwsh -NoProfile -File tools/run-lua-tests.ps1`

Expected: FAIL on the first missing leader-store function.

- [ ] **Step 3: Implement validated leader operations**

Use constants and public signatures exactly as follows:

```lua
M.MAX_MONEY = 10000000
M.MAX_PRESETS = 20
M.MAX_ITEMS = 500
M.MAX_NAME_CHARS = 24

M.ensureLeaderRaid(root, clientFamily, raidId, currentGlobalPrice)
M.createPreset(root, clientFamily, raidId, name, basePrice)
M.copyPreset(root, clientFamily, raidId, presetId, newName)
M.renamePreset(root, clientFamily, raidId, presetId, newName)
M.deletePreset(root, clientFamily, raidId, presetId, fallbackPresetId)
M.selectPreset(root, clientFamily, raidId, presetId)
M.setBasePrice(root, clientFamily, raidId, presetId, money)
M.setLeaderItemPrice(root, clientFamily, raidId, presetId, itemId, money)
M.clearLeaderItemPrice(root, clientFamily, raidId, presetId, itemId)
M.resolveLeaderPrice(root, clientFamily, raidId, itemId)
```

Generate opaque local IDs (`p1`, `p2`, ...) by finding the next unused integer. Rebuild written scheme records from `name`, `basePrice`, and numeric `itemPrices`; never copy arbitrary imported keys. Count UTF-8 code points with a small local validator that rejects malformed sequences and never truncates mid-character.

- [ ] **Step 4: Run the focused and full suites**

Run: `lua tests/run.lua`

Expected: leader scheme tests PASS; full output ends with zero failures.

- [ ] **Step 5: Commit leader storage**

```powershell
git add Core/BGNext/AuctionPriceStore.lua tests/test_auction_price_store.lua
git commit -m "feat: manage leader auction price schemes"
```

### Task 3: Implement per-character personal prices

**Files:**
- Modify: `Core/BGNext/AuctionPriceStore.lua`
- Modify: `tests/test_auction_price_store.lua`

- [ ] **Step 1: Write failing character-isolation tests**

```lua
test.eq(store.setPersonalPrice(root, "titan", "realm1", "Leader", "ULD", 1001, 900), true)
test.eq(store.getPersonalPrice(root, "titan", "realm1", "Leader", "ULD", 1001), 900)
test.eq(store.getPersonalPrice(root, "titan", "realm1", "Alt", "ULD", 1001), nil)
test.eq(store.getPersonalPrice(root, "wrath", "realm1", "Leader", "ULD", 1001), nil)
test.eq(store.clearPersonalPrice(root, "titan", "realm1", "Leader", "ULD", 1001), true)
```

Add tests for explicit zero, 500-entry ceiling, `clearPersonalRaid`, and invalid realm/player/raid/item inputs leaving the root unchanged.

- [ ] **Step 2: Run and verify failure**

Run: `pwsh -NoProfile -File tools/run-lua-tests.ps1`

Expected: FAIL because personal APIs are absent.

- [ ] **Step 3: Implement the personal API without plans or base price**

```lua
M.setPersonalPrice(root, clientFamily, realmId, player, raidId, itemId, money)
M.getPersonalPrice(root, clientFamily, realmId, player, raidId, itemId)
M.clearPersonalPrice(root, clientFamily, realmId, player, raidId, itemId)
M.clearPersonalRaid(root, clientFamily, realmId, player, raidId)
M.countPersonalPrices(root, clientFamily, realmId, player, raidId)
```

Create nested tables only after all context keys and money validate. Remove empty leaf tables after clearing; do not store specialization, timestamps, names, links, or history.

- [ ] **Step 4: Run all tests and commit**

Expected: full suite ends with zero failures.

```powershell
git add Core/BGNext/AuctionPriceStore.lua tests/test_auction_price_store.lua
git commit -m "feat: store personal auction expectations"
```

### Task 4: Project approved loot into a searchable catalog

**Files:**
- Create: `Core/BGNext/AuctionPriceCatalog.lua`
- Create: `tests/test_auction_price_catalog.lua`
- Modify: `BGLite.toc`
- Modify: `tests/run.lua`

- [ ] **Step 1: Write failing pure catalog tests using a tiny fake BG loot tree**

```lua
local model = catalog.build({
    raidId = "ULD",
    difficulties = { "N", "H" },
    bosses = { { id = "boss1", name = "烈焰巨兽" }, { id = "misc", name = "杂项" } },
    loot = { N = { boss1 = { 101, 102 }, boss1other = { 103 } }, H = { boss1 = { 101, 104 } } },
    describeItem = function(id) return { itemId=id, name="装备"..id, equipLoc=id==102 and "INVTYPE_TRINKET" or "INVTYPE_HEAD", quality=4 } end,
})
test.eq(#model.groups[1].items, 3, "difficulty duplicates collapse by item id")
test.eq(catalog.resolveRaidForItem({ ULD=model }, 104), "ULD")
test.eq(#catalog.filter(model, { text="102", equipLoc="INVTYPE_TRINKET", quality=4 }), 1)
```

Test Boss/misc grouping, deterministic ordering, unknown item names remaining searchable by ID, state filtering through a supplied `hasPrice(itemId)` callback, and ambiguous cross-raid item resolution returning `nil`.

- [ ] **Step 2: Run and verify missing module failure**

Run: `pwsh -NoProfile -File tools/run-lua-tests.ps1`

- [ ] **Step 3: Implement the pure projection and filter API**

```lua
M.build(options)
M.buildAll(optionsByRaid)
M.filter(raidModel, criteria)
M.resolveRaidForItem(modelsByRaid, itemId)
M.updateItemDescription(raidModel, itemId, description)
```

Deduplicate the same item ID across difficulties inside one Boss, preserve the first approved catalog order, and classify `bossNother`, quest/exchange/misc approved entries into the fixed misc group. Do not persist the model.

- [ ] **Step 4: Add the module before UI modules, run tests, and commit**

```powershell
git add BGLite.toc Core/BGNext/AuctionPriceCatalog.lua tests/run.lua tests/test_auction_price_catalog.lua
git commit -m "feat: index raid loot for price presets"
```

### Task 5: Build separated deterministic codecs and atomic apply descriptors

**Files:**
- Create: `Core/BGNext/AuctionPriceCodec.lua`
- Create: `tests/test_auction_price_codec.lua`
- Modify: `BGLite.toc`
- Modify: `tests/run.lua`

- [ ] **Step 1: Write failing round-trip and rejection tests**

Use explicit prefixes `BGNP-L1` and `BGNP-P1`. Assert identical data always exports identical text, leader text cannot parse as personal, personal text cannot parse as leader, and invalid input returns a preview without mutating root.

```lua
local text = codec.exportLeader("titan", "ULD", leaderRaid, "current")
local preview = codec.parse(text, "leader", catalogSet)
test.eq(preview.ok, true)
test.eq(preview.raidId, "ULD")
test.eq(preview.presetCount, 1)
test.eq(codec.applyLeader(root, preview, { mode="new" }), true)
```

Cover 64 KB, 20-scheme, 500-item, 24-character, money, duplicate-key, unsupported-version, client mismatch, raid mismatch, unknown-item, same-name suffix, personal merge/replace, and atomic-failure cases.

- [ ] **Step 2: Run and verify failure**

Run: `pwsh -NoProfile -File tools/run-lua-tests.ps1`

- [ ] **Step 3: Implement a plain delimiter format with strict escaping**

Expose only:

```lua
M.exportLeader(clientFamily, raidId, leaderRaid, scope)
M.exportPersonal(clientFamily, raidId, itemPrices)
M.parse(text, expectedType, knownItemSet)
M.applyLeader(root, preview, options)
M.applyPersonal(root, context, preview, options)
```

Sort preset IDs and item IDs numerically/lexically before output. Percent-escape only scheme names; reject malformed escapes, duplicate fields, unknown structural keys, and non-canonical integers. Build a fully sanitized temporary result before a single root replacement/merge operation.

- [ ] **Step 4: Run all tests and commit**

```powershell
git add BGLite.toc Core/BGNext/AuctionPriceCodec.lua tests/run.lua tests/test_auction_price_codec.lua
git commit -m "feat: import and export auction prices"
```

### Task 6: Create testable page state and row-reuse rules

**Files:**
- Create: `Core/BGNext/AuctionPriceUI.lua`
- Create: `tests/test_auction_price_ui.lua`
- Modify: `BGLite.toc`
- Modify: `tests/run.lua`

- [ ] **Step 1: Write failing pure UI-state tests before Frame code**

```lua
local state = ui.newState("ULD")
test.eq(state.mode, "leader")
ui.selectBoss(state, "boss4")
ui.setFilter(state, "text", "饰品")
ui.setMode(state, "personal")
test.eq(state.bossId, "boss4", "mode switch preserves boss")
test.eq(state.filters.text, "饰品", "mode switch preserves search")
test.eq(ui.visibleRowCount(100, 12), 12, "large list reuses fixed rows")
```

Test the exact labels `团长起拍价` and `我的心理价`, their approved one-line descriptions, leader toolbar actions, personal toolbar actions, Enter-next-visible behavior, and filters clearing back to the saved Boss position.

- [ ] **Step 2: Run and verify the UI module is missing**

- [ ] **Step 3: Implement pure state/layout functions at the top of the file**

```lua
M.tabNumber = 2
M.newState(raidId)
M.setMode(state, mode)
M.selectRaid(state, raidId)
M.selectBoss(state, bossId)
M.setFilter(state, key, value)
M.clearFilters(state)
M.nextVisibleIndex(filteredItems, currentIndex)
M.visibleRowCount(total, capacity)
M.toolbarActions(mode)
M.description(mode)
```

Keep these functions above any `CreateFrame` calls so plain Lua tests can load them with absent WoW globals.

- [ ] **Step 4: Add source-boundary assertions and commit the pure shell**

Assert the file contains no `SendChatMessage`, `SendAddonMessage`, clipboard, HTTP, telemetry, or Gargul/BiaoGe source paths.

```powershell
git add BGLite.toc Core/BGNext/AuctionPriceUI.lua tests/run.lua tests/test_auction_price_ui.lua
git commit -m "feat: define auction price page state"
```

### Task 7: Build the hierarchical price page with fixed reusable rows

**Files:**
- Modify: `Core/BGNext/AuctionPriceUI.lua`
- Modify: `tests/test_auction_price_ui.lua`
- Modify: `Locales/zhCN.lua`, `Locales/zhTW.lua`, `Locales/enUS.lua`

- [ ] **Step 1: Add failing source/layout integration assertions**

Assert tab 2 creation, raid controls, leader/personal mode buttons, separate description and toolbar frames, Boss sidebar, filter controls, a fixed `ROW_CAPACITY = 12`, and no loop that creates one Frame per catalog item.

- [ ] **Step 2: Run tests and verify failure**

- [ ] **Step 3: Build the Frame hierarchy inside `BG.Init`**

Use this ownership shape:

```lua
BG.PricePresetMainFrame
  .raidBar
  .modeBar
  .description
  .toolbar
  .bossScroll
  .filterBar
  .itemScroll
  .rows[1..12]
```

Call `BG.Create_TabButton(2, L["价格预设"], BG.PricePresetMainFrame)`. Populate raid/Boss controls from `AuctionPriceCatalog`, never directly from third-party data. On scroll, update each reused row’s icon, text, price, and item ID; clear unused rows.

- [ ] **Step 4: Wire leader and personal edits to store APIs**

On leader Enter: call `setLeaderItemPrice`; on personal Enter: call `setPersonalPrice`; on red X call the matching clear function. Refresh only visible rows and focus `nextVisibleIndex`.

Create scheme popups for new/copy/rename/delete. Delete requires a selected fallback and confirmation. Personal clear requires confirmation. Keep the description row present above the toolbar.

- [ ] **Step 5: Run tests, manually inspect source boundaries, and commit**

```powershell
git add Core/BGNext/AuctionPriceUI.lua Locales/zhCN.lua Locales/zhTW.lua Locales/enUS.lua tests/test_auction_price_ui.lua
git commit -m "feat: add hierarchical auction price page"
```

### Task 8: Add import/export preview panels

**Files:**
- Modify: `Core/BGNext/AuctionPriceUI.lua`
- Modify: `tests/test_auction_price_ui.lua`

- [ ] **Step 1: Write failing preview-state tests**

Test that leader mode offers current/all export and new/replace import, personal mode offers merge/replace, unknown items default to blocked, replacement requires confirmation, and the edit text remains user-selectable.

- [ ] **Step 2: Implement panels using existing wishlist visual conventions**

Reuse the Backdrop/EditBox/ScrollFrame approach from `WishlistUI.createTextPanel`, but call only `AuctionPriceCodec`. The import button first renders a preview summary; the commit button remains disabled until the preview is valid and required choices are explicit.

```lua
panel.preview = codec.parse(panel.edit:GetText(), state.mode, knownItems)
panel.commit:SetEnabled(panel.preview.ok and panel.choiceIsExplicit)
```

Never call automatic clipboard or chat APIs. Export selects the entire text with `HighlightText()` and focuses the box.

- [ ] **Step 3: Run tests and commit**

```powershell
git add Core/BGNext/AuctionPriceUI.lua tests/test_auction_price_ui.lua
git commit -m "feat: preview auction price imports"
```

### Task 9: Integrate silent leader prefill

**Files:**
- Create: `Core/BGNext/AuctionPriceRuntime.lua`
- Create: `tests/test_auction_price_runtime.lua`
- Modify: `BGLite.toc`
- Modify: `tests/run.lua`

- [ ] **Step 1: Write failing pure decision tests**

```lua
test.eq(runtime.chooseLeaderPrefill({100,100}), 100)
test.eq(runtime.chooseLeaderPrefill({100,200}), nil)
test.eq(runtime.chooseLeaderPrefill({100,nil}), nil)
test.eq(runtime.resolveRaid("ULD", {ULD=true}, nil), "ULD")
test.eq(runtime.resolveRaid("ULD", {ICC=true}, "ICC"), nil)
```

Assert no permission bypass, no prefill when raid/item/plan is unresolved, and no write back after the EditBox is changed.

- [ ] **Step 2: Run and verify failure**

- [ ] **Step 3: Implement the thin leader hook**

Load `AuctionPriceRuntime.lua` after `Core\Module\AuctionWAEvent.lua` in the TOC. During `BG.Init`, wrap the existing `BG.StartAuction` once. Call the original first so it performs existing gates and creates `BG.StartAucitonFrame`; then inspect its `items` and set only `BG.StartAucitonFrame.Edit2` when every resolved price is equal.

```lua
local original = BG.StartAuction
BG.StartAuction = function(...)
    local result = original(...)
    M.prefillLeaderFrame(BG.StartAucitonFrame, contextProvider())
    return result
end
```

Guard against recursive wrapping with a module-local installed flag. Do not modify `Start_OnClick`, `BG.SendStartAuctionMsg`, permissions, or protocol.

- [ ] **Step 4: Add forbidden-call assertions, run tests, and commit**

Assert runtime source contains no call to `SendStartAuctionMsg`, `SendMyMoney_OnClick`, `SendAddonMessage`, or `SendChatMessage`.

```powershell
git add BGLite.toc Core/BGNext/AuctionPriceRuntime.lua tests/run.lua tests/test_auction_price_runtime.lua
git commit -m "feat: prefill leader starting prices"
```

### Task 10: Integrate silent personal prefill

**Files:**
- Modify: `Core/BGNext/AuctionPriceRuntime.lua`
- Modify: `tests/test_auction_price_runtime.lua`

- [ ] **Step 1: Write failing bidder-frame tests**

Use a fake frame with `itemID`, `myMoneyEdit:SetText`, start money, and send/auto spies. Assert the exact saved value is set, a value below start remains unchanged, missing value leaves existing text untouched, and every send/enable spy remains zero.

- [ ] **Step 2: Run and verify failure**

- [ ] **Step 3: Chain the existing `BG.HookCreateAuction` without replacing wishlist behavior**

During `BG.Init`, retain the current function and call it first:

```lua
local previous = BG.HookCreateAuction
BG.HookCreateAuction = function(frame)
    if previous then previous(frame) end
    M.prefillPersonalFrame(frame, contextProvider())
end
```

Set only `frame.myMoneyEdit:SetText(savedMoney)`. Let its existing `OnTextChanged` validation run. Do not click `ButtonSendMyMoney`, toggle `isAuto`, start timers, or write the value back.

- [ ] **Step 4: Run all tests and commit**

```powershell
git add Core/BGNext/AuctionPriceRuntime.lua tests/test_auction_price_runtime.lua
git commit -m "feat: prefill personal auction expectations"
```

### Task 11: Document data, clear behavior, provenance, and release text

**Files:**
- Modify: `docs/security/data-inventory.md`
- Modify: `CHANGELOG.md`
- Modify: `Core/BGNext/ReleaseInfo.lua` only when preparing the actual release
- Modify: `docs/baseline/BGNext-overrides.sha256`
- Modify: relevant tests if release metadata changes

- [ ] **Step 1: Add exact data-inventory rows**

Document `leaderAuctionPricePresets` as client/raid-shared local scheme data and `personalAuctionExpectations` as per-character local item-price data. State fields, purpose, retention, user clear action, no recipients, and Medium sensitivity. Explicitly state there is no history and no communication.

- [ ] **Step 2: Record third-party and baseline boundaries**

State that no Gargul/BiaoGe code, text, format, database, or asset was imported. Review every changed BGLite baseline file, calculate its SHA-256, and replace only its corresponding line in `docs/baseline/BGNext-overrides.sha256`.

- [ ] **Step 3: Add user-facing changelog text without implementation jargon**

Use concise Chinese such as:

```text
新增价格预设：团长可按团本保存多套起拍价方案，团员可为自己的角色保存单件心理价。打开现有操作窗口时自动填入已保存价格，最终操作仍由玩家手动确认。
```

- [ ] **Step 4: Run baseline and full tests, then commit**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
pwsh -NoProfile -File tools/verify-baseline.ps1
git diff --check
git add docs/security/data-inventory.md docs/baseline/BGNext-overrides.sha256 CHANGELOG.md Core/BGNext/ReleaseInfo.lua tests
git commit -m "docs: audit auction price preset data"
```

Do not include `Core/BGNext/ReleaseInfo.lua` or release-version tests in the commit unless the user has explicitly authorized a release/version bump.

### Task 12: Final verification and Titan test package

**Files:**
- Create locally only: `.local/packages/BGNext-price-presets-test.zip`
- Create locally only: a timestamped file under `.local/handoffs/inbox/`, computed in Step 3

- [ ] **Step 1: Run fresh automated evidence on final HEAD**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
pwsh -NoProfile -File tools/verify-baseline.ps1
git diff --check HEAD
$files = @(git diff --name-only 5ff71168f33dd3723dc2960c287482193e228d35..HEAD -- '*.lua')
foreach ($file in $files) { luac -p $file; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } }
```

Expected: zero Lua test failures, baseline integrity verified, no diff errors, and every changed Lua file parses under Lua 5.1. The immutable comparison base is the approved design commit `5ff71168f33dd3723dc2960c287482193e228d35`.

- [ ] **Step 2: Build and audit the runtime-only ZIP**

```powershell
pwsh -NoProfile -File tools/build-release.ps1 -OutputPath '.local\packages\BGNext-price-presets-test.zip' -Force
```

Audit one `BGNext/` root, packaged TOC presence, no `BGLite/` root, no tests/tools/Git files, no quarantined history modules, and a matching `.sha256` sidecar.

- [ ] **Step 3: Write the mandatory handoff**

Record exact branch, HEAD, base/range, commits, changed files, commands/results, SavedVariables additions, baseline overrides, ZIP path/hash, unverified clients, and these Titan checks:

```powershell
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$handoffPath = ".local\handoffs\inbox\$stamp--auction-price-presets.md"
```

1. 100-item raid browsing remains responsive.
2. Raid → Boss/misc → item navigation and filters preserve position.
3. Scheme create/copy/rename/delete/switch works.
4. Import preview and both format types behave atomically.
5. Leader single/multi-item prefill follows equality rules.
6. Personal value prefills exactly and never auto-sends.
7. Existing auction windows gain no permanent text or size.

- [ ] **Step 4: Stop before external release actions**

Do not install into game folders, push, open a PR, publish GitHub Release, upload NetEase DD, or edit real SavedVariables without explicit user authorization.
