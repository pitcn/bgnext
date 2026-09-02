# Auction Price Dense View and Boss Model Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Fix the incompatible price-page scrollbar, use a responsive two-column reusable viewport, and remove decorative Boss models from BGNext.

**Architecture:** Keep the existing catalog/store/filter data flow. Replace only the price page's viewport geometry and slider widget, deriving a 24–60 row reusable capacity once from the main frame dimensions. Remove the unused model runtime file, creation call, and option together so no dead control remains.

**Tech Stack:** WoW Lua 5.1, existing test harness, PowerShell baseline/release verification.

---

### Task 1: Pure responsive layout contract

**Files:**
- Modify: `Core/BGNext/AuctionPriceUI.lua`
- Modify: `tests/test_auction_price_ui.lua`

- [ ] Add failing tests for `M.viewportLayout(width, height)`: two columns, 12–30 rows per column, 24–60 total rows, positive flexible column width, and stable results for invalid dimensions.
- [ ] Run `lua tests/run.lua` and require the new assertions to fail for the missing function.
- [ ] Add constants `COLUMN_COUNT=2`, `MIN_ROWS_PER_COLUMN=12`, `MAX_ROWS_PER_COLUMN=30`, `ROW_HEIGHT=24`, and implement the pure layout helper.
- [ ] Run the suite and commit `test: define responsive auction price viewport`.

### Task 2: Compatible plain slider and two-column runtime

**Files:**
- Modify: `Core/BGNext/AuctionPriceUI.lua`
- Modify: `tests/test_auction_price_ui.lua`

- [ ] Add failing source/runtime-contract assertions that no `UIPanelScrollBarTemplate` remains, a plain vertical Slider is used, row creation uses computed `pageCapacity`, and the second column receives rows.
- [ ] Run tests and confirm failure.
- [ ] Replace the templated slider with a plain Slider, set orientation/thumb once, and install the custom value handler before its first explicit value update.
- [ ] Anchor the item area to use remaining width, calculate two responsive columns, create only `pageCapacity` reusable rows, and anchor price/edit/clear controls from the right.
- [ ] Replace every runtime use of fixed `M.ROW_CAPACITY` with `pageCapacity`; preserve visibleWindow, Enter navigation, wheel scrolling, tooltip, filtering and save behavior.
- [ ] Run tests and commit `fix: expand auction price item viewport`.

### Task 3: Remove Boss model runtime and setting

**Files:**
- Modify: `Core/FBUI/FBUI.xml`
- Modify: `Core/BiaoGe.lua`
- Modify: `Core/Options.lua`
- Modify: `tests/test_baseline_safety.lua`
- Modify: `docs/baseline/BGNext-overrides.sha256`

- [ ] Add failing tests asserting FBUI.xml does not load Model.lua, BiaoGe.lua does not call CreateBossModel, and Options.lua contains no Boss model control or BG.bossModels loop.
- [ ] Run tests and confirm those assertions fail.
- [ ] Remove the Model.lua script entry, creation call, and complete model option block. Do not delete the provenance file itself and do not mutate old SavedVariables.
- [ ] Recalculate only the changed override hashes for FBUI.xml, BiaoGe.lua and Options.lua.
- [ ] Run tests and baseline verification; commit `fix: remove decorative boss models`.

### Task 4: Final joint package

- [ ] Run `lua tests/run.lua`, `pwsh -NoProfile -File tools/verify-baseline.ps1`, and `git diff --check`.
- [ ] Build `D:\vibe coding\BGN\.local\packages\BGNext-0.3.1-combined-auction-ui-test-v6.zip`.
- [ ] Inspect the archive: price modules and UI theme modules present; quarantined history/receive modules and `Core/FBUI/Model.lua` absent.
- [ ] Report package, checksum, commit and pending in-game validation. Do not publish a Release.

