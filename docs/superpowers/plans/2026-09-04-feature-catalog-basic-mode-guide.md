# Feature Catalog, Basic Mode, and In-Game Guide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build one catalog that powers reversible BGNext feature controls and a complete, maintainable in-game guide.

**Architecture:** `FeatureCatalog.lua` owns immutable metadata; `FeatureSettings.lua` owns persisted booleans and effective dependency checks. A feature-management options page and a scrollable guide render that shared data, while existing modules call the settings service only at their public UI/event boundaries. Required compatibility, correctness, security, migration, and privacy code never becomes optional.

**Tech Stack:** World of Warcraft Lua 5.1, existing BGNext frame helpers, SavedVariables under `BiaoGe.BGNext.settings`, repository Lua harness, PowerShell verification tools.

---

### Task 1: Declarative feature catalog

**Files:**
- Create: `Core/BGNext/FeatureCatalog.lua`
- Create: `tests/test_feature_catalog.lua`
- Modify: `tests/run.lua`
- Modify: `BGLite.toc`

- [ ] **Step 1: Write the failing catalog behavior test**

Test the public API `all()`, `get(id)`, `groups()`, `available(entry, family)`, and `validate()`. Assert unique stable IDs, known dependencies, required entries cannot be marked optional, four ordered groups, client filtering, and registration of `/bgn`, `/bgnext`, `/bgo`, `/bgm`, `/bgnqueue`, `/bgnq`, right-click, Ctrl/Alt/Shift-right-click, and wishlist wheel interactions.

- [ ] **Step 2: Run the suite and observe RED**

Run `lua tests/run.lua`. Expected: `test_feature_catalog.lua` fails because `Core/BGNext/FeatureCatalog.lua` does not exist.

- [ ] **Step 3: Implement the immutable catalog API**

Use entries shaped as:

```lua
{
    id = "auction_queue",
    group = "auction",
    policy = "optional",
    basic = false,
    nameKey = "待拍队列",
    summaryKey = "将多件装备加入有界队列，逐件确认后开拍。",
    depends = {},
    clients = { vanilla = true, tbc = true, titan = true, mists = true, retail = true },
    commands = { "/bgnqueue", "/bgnq" },
    interactions = { "拾取框拍卖按钮", "逐件确认" },
}
```

Return copies/read-only projections so callers cannot mutate the source table. Include required catalog entries for compatibility/safety, trade-capture correctness, data lifecycle, and privacy controls, plus the optional IDs from the approved design.

- [ ] **Step 4: Run the catalog test and observe GREEN**

Run `lua tests/run.lua`. Expected: all catalog assertions pass.

- [ ] **Step 5: Commit the catalog slice**

Commit `FeatureCatalog.lua`, its test, TOC wiring, and test registration as `feat: add declarative BGNext feature catalog`.

### Task 2: Reversible feature settings and modes

**Files:**
- Create: `Core/BGNext/FeatureSettings.lua`
- Create: `tests/test_feature_settings.lua`
- Modify: `Core/BGNext/DataLifecycle.lua`
- Modify: `docs/security/data-inventory.md`
- Modify: `tests/run.lua`
- Modify: `BGLite.toc`

- [ ] **Step 1: Write the first settings RED test**

Through public methods, assert absent values are enabled, required features reject disable attempts, `applyMode("basic")` disables exactly optional entries with `basic=false`, `applyMode("full")` enables them, and one changed value yields `custom`.

- [ ] **Step 2: Run and observe RED**

Run `lua tests/run.lua`. Expected failure: missing `FeatureSettings.lua`.

- [ ] **Step 3: Implement settings behavior**

Expose:

```lua
M.isEnabled(root, id, family)
M.savedValue(root, id)
M.setEnabled(root, id, enabled)
M.applyMode(root, mode, family)
M.mode(root, family)
M.sanitize(root)
```

`sanitize` rebuilds `settings.features` from known optional IDs and boolean values only. Missing values remain absent and mean enabled. Dependencies are evaluated recursively with a bounded visited set; saved child preferences are never overwritten by a disabled parent.

- [ ] **Step 4: Add migration compatibility RED→GREEN**

Add a test where legacy `settings.roleOverviewEnabled=false` and no new feature value exist. It must keep role overview disabled. When the new setting is explicitly changed, mirror the legacy field until old callers are removed. Unknown keys and non-booleans must be discarded without changing unrelated settings or feature data.

- [ ] **Step 5: Document the new preference field**

Add `settings.features[featureId]` to the data inventory: local boolean preference, retained until changed/reset, no recipients, controlled in Feature Management, low risk.

- [ ] **Step 6: Run tests and commit**

Run the full Lua suite; commit as `feat: add reversible feature modes`.

### Task 3: Feature-management options page

**Files:**
- Create: `Core/BGNext/FeatureManagementUI.lua`
- Create: `tests/test_feature_management_ui.lua`
- Modify: `BGLite.toc`
- Modify: `tests/run.lua`
- Modify: `Locales/zhCN.lua`
- Modify: `Locales/zhTW.lua`
- Modify: `Locales/enUS.lua`

- [ ] **Step 1: Write UI model RED test**

Test a public `viewModel(root, family)` without frames. Assert ordered groups, unavailable entries omitted, required rows use `required=true` without a toggle, optional rows expose effective/saved state, and mode labels report Full/Basic/Custom.

- [ ] **Step 2: Run and observe RED**

Run `lua tests/run.lua`; expected failure is the missing UI module.

- [ ] **Step 3: Implement view model and actions**

Expose `viewModel`, `applyMode`, and `toggleFeature`, delegating every write to `FeatureSettings`. Return user-facing result codes for required, unknown, and unavailable features.

- [ ] **Step 4: Add the options-frame RED→GREEN slice**

Using the existing frame harness pattern, verify the module creates a `功能管理` tab through `BG.OptionsCreateTab`, renders Full and Basic preset buttons, groups rows, uses disabled text for required features, refreshes mode text after a toggle, and calculates widths from localized font strings.

- [ ] **Step 5: Add three-language strings**

Add reviewed labels and descriptions for the page, groups, modes, required state, and catalog entries. Verify non-Chinese clients use English fallback and placeholders match.

- [ ] **Step 6: Run and commit**

Run the full suite and commit as `feat: add feature management settings page`.

### Task 4: Scrollable catalog-driven in-game guide

**Files:**
- Create: `Core/BGNext/GuideUI.lua`
- Create: `tests/test_guide_ui.lua`
- Modify: `Core/BiaoGe.lua`
- Modify: `BGLite.toc`
- Modify: `tests/run.lua`
- Modify: `Locales/zhCN.lua`
- Modify: `Locales/zhTW.lua`
- Modify: `Locales/enUS.lua`

- [ ] **Step 1: Write guide model RED test**

Test `GuideUI.sections(root, family)`: Quick Start first; catalog groups after it; current-client filtering; required and disabled annotations; public command and interaction coverage; basic-mode explanation; destructive-action warnings.

- [ ] **Step 2: Run and observe RED**

Run the suite; expected failure is missing `GuideUI.lua`.

- [ ] **Step 3: Implement catalog-driven sections**

Build section records `{ id, title, lines }` from `FeatureCatalog` and `FeatureSettings`. Do not parse Lua source at runtime. Keep a test-only/static public action inventory in the catalog validator so undocumented actions fail CI.

- [ ] **Step 4: Implement the visible window RED→GREEN slice**

Replace the top entry's hover-only full manual behavior with a short hover hint plus click-to-toggle guide window. The window must use `BG.CreateMainFrame`, `BG.CreateScrollFrame`, pooled font strings, a visible close button supplied by the frame helper, and a bounded height based on `UIParent`. Closing drops rendered line references but does not change settings.

- [ ] **Step 5: Preserve slash behavior**

Keep `/bgn`, `/bgnext`, `/bglite`, `/biaoge`, `/bgm`, and `/bgo` behavior unchanged. Catalog registration documents aliases but does not become a second command dispatcher.

- [ ] **Step 6: Run localization/UI tests and commit**

Run `tests/test_guide_ui.lua`, `tests/test_english_locale.lua`, then the full suite. Commit as `feat: add catalog-driven in-game guide`.

### Task 5: Runtime gates for optional feature domains

**Files:**
- Modify: `Core/BGNext/WishlistUI.lua`
- Modify: `Core/BGNext/WishlistReminder.lua`
- Modify: `Core/BGNext/AuctionPriceRuntime.lua`
- Modify: `Core/BGNext/AuctionPriceUI.lua`
- Modify: `Core/BGNext/AuctionQueueRuntime.lua`
- Modify: `Core/BGNext/LootAuctionEntry.lua`
- Modify: `Core/BGNext/CurrentSettlementRuntime.lua`
- Modify: `Core/BGNext/CurrentSettlementUI.lua`
- Modify: `Core/BGNext/OwnCharactersRuntime.lua`
- Modify: `Core/BGNext/RoleOverviewEntry.lua`
- Modify: `Core/BGNext/EquipmentFilterRuntime.lua`
- Modify: `Core/BGNext/UIStyle.lua`
- Modify: `Core/BGNext/TradeAnnouncement.lua`
- Modify: relevant existing tests

- [ ] **Step 1: Add one representative entry-gate RED→GREEN slice**

Disable `auction_queue`; assert its main-window entry and loot-window button are hidden, `/bgnqueue` gives a local disabled explanation, queue data remains in memory, and re-enabling restores the entry. Implement a shared local helper call to `FeatureSettings.isEnabled` at these boundaries.

- [ ] **Step 2: Add personal-tool RED→GREEN slices**

For wishlist, role overview, and equipment filter, assert disabled state prevents UI entry/refresh/collection while preserving all stored wishlist, character, column, and profile data. Re-enable and assert the prior state returns.

- [ ] **Step 3: Add settlement-tool RED→GREEN slice**

Disable `settlement_tools`; assert current-settlement UI entries and derived refresh/recording stop. Keep `TradeCapture`, lifecycle expiry/clear, migration, and baseline bill correctness active because they are required safeguards. Re-enable and verify existing records remain visible.

- [ ] **Step 4: Add price/appearance/announcement RED→GREEN slices**

Assert disabled auction prices do not prefill or expose preset UI but `AuctionPreSend` remains active; disabled appearance uses classic rendering without overwriting `uiTheme`; disabled trade announcements send nothing while trade capture/records remain independent.

- [ ] **Step 5: Run each focused suite then the full suite**

Run the directly affected test after every vertical slice, then `lua tests/run.lua` once all domains are green.

- [ ] **Step 6: Commit runtime integration**

Commit as `feat: gate optional BGNext feature domains`.

### Task 6: Final integrity, documentation, and PR

**Files:**
- Modify: `docs/baseline/BGNext-overrides.sha256`
- Modify: Issue #81 and #82 through GitHub

- [ ] **Step 1: Review every baseline-file change**

Only after reviewing TOC, `Core/BiaoGe.lua`, and Locale diffs, recompute their explicit override hashes. Do not add BGNext-only modules to the upstream override list.

- [ ] **Step 2: Run the complete high-risk gate**

Run:

```powershell
pwsh -NoProfile -File tools/agent-verify.ps1 -Risk high -Base origin/main -WriteHandoff
```

Expected automated results: Lua tests PASS, baseline PASS, diff-check PASS, changed Lua 5.1 parse PASS. Record real-client layout and all-domain game interaction as unverified.

- [ ] **Step 3: Review the requirements line by line**

Confirm settings and guide share the catalog, old users remain enabled, basic mode is reversible, required safeguards cannot be disabled, data is preserved, disabled commands explain themselves, and three locales are present.

- [ ] **Step 4: Push and create one PR**

Push `codex/issues-81-82-feature-catalog` and create a PR whose body includes RED→GREEN evidence, data/privacy review, compatibility evidence, and both `Closes #81` and `Closes #82`. Do not merge or release until independent review and CI pass.
