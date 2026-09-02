# BGNext UI Polish Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the existing one-screen BGNext ledger and price-preset page a coherent premium visual system without changing geometry, data, interaction, or transparency behavior.

**Architecture:** Add a BGNext-owned `UIStyle` adapter that converts existing `UITheme` tokens into explicit widget states and keeps a weak registry of shared buttons. The reversible ledger skin delegates navigation color states to it, while the BGNext-owned price page adds a bounded number of surfaces and a column divider. Two narrowly reviewed baseline factories call the adapter only when the preview theme is active and retain their classic fallback.

**Tech Stack:** World of Warcraft Lua APIs, existing BGLite frame factories, BGNext pure Lua tests, PowerShell baseline/package tools.

---

### Task 1: Define the scoped visual-state adapter

**Files:**
- Create: `Core/BGNext/UIStyle.lua`
- Create: `tests/test_ui_style.lua`
- Modify: `tests/run.lua`
- Modify: `BGLite.toc`

- [ ] **Step 1: Write the failing pure state tests**

Add `tests/test_ui_style.lua` and register it immediately after `test_ui_theme.lua`. The suite must assert:

```lua
local Style = dofile("Core/BGNext/UIStyle.lua")
local selected = Style.palette("selected")
test.eq(selected.fill, "073044", "selected fill")
test.eq(selected.border, "00E6FF", "selected cyan border")
test.eq(selected.text, "E8F1F8", "selected primary text")
test.eq(Style.palette("future").id, "normal", "unknown state is normal")
test.eq(Style.objectBudget(), 4, "price decoration budget is bounded")
```

Use fake buttons exposing `bg:SetColorTexture`, `bg:SetAlpha`, `SetBackdropBorderColor`, `GetFontString():SetTextColor`, `IsEnabled`, and `GetAlpha`. Verify `applyButton(button, "normal", 0.58)`, `hover`, `selected`, `disabled`, and `danger`; verify repeated application is idempotent; verify `setButtonState` records the state without changing geometry. Scan the module source and reject `SetPoint`, `SetSize`, `SetWidth`, `SetHeight`, `SetParent`, `SetScript`, `HookScript`, `OnUpdate`, `C_Timer`, communication APIs, and SavedVariables assignments.

- [ ] **Step 2: Run the suite and observe the missing-module failure**

Run:

```powershell
lua tests/run.lua
```

Expected: the new suite fails because `Core/BGNext/UIStyle.lua` does not exist; previous suites remain green.

- [ ] **Step 3: Implement the adapter and load it before page modules**

Create `Core/BGNext/UIStyle.lua` with these public methods:

```lua
function M.palette(state) -> table
function M.isPreviewEnabled(root) -> boolean
function M.applyButton(button, state, alpha) -> boolean
function M.setButtonState(button, state, alpha) -> boolean
function M.registerButton(button) -> nil
function M.refreshButtons(themeId, alpha) -> nil
function M.applyNavigationTab(tab, state, alpha) -> boolean
function M.applySurface(frame, variant, alpha) -> boolean
function M.objectBudget() -> 4
```

Use the following fixed state recipes:

```lua
normal   = { fill = "0C2033", border = "24445E", text = "F5B230", alpha = 0.72 }
hover    = { fill = "10314A", border = "2A7896", text = "E8F1F8", alpha = 0.90 }
selected = { fill = "073044", border = "00E6FF", text = "E8F1F8", alpha = 0.88 }
disabled = { fill = "07182A", border = "24445E", text = "8EA6BA", alpha = 0.42 }
danger   = { fill = "2A1018", border = "8F3347", text = "FF8098", alpha = 0.78 }
```

Keep registered buttons in a weak-key table. Store the logical state only on the button as `_BGNextVisualState`; do not persist it. `refreshButtons("preview", alpha)` applies each button's recorded state. `refreshButtons("classic", alpha)` applies the explicit legacy recipe: vertical black gradient, black border, gold normal text, grey disabled text. Use `CreateColor` when available and a table fallback for tests.

Insert `Core\BGNext\UIStyle.lua` immediately after `Core\BGNext\UITheme.lua` in `BGLite.toc`.

- [ ] **Step 4: Run tests and commit**

Run `lua tests/run.lua`; expected `failed=0`.

Commit:

```powershell
git add Core/BGNext/UIStyle.lua tests/test_ui_style.lua tests/run.lua BGLite.toc
git commit -m "feat: define scoped BGNext visual states"
```

### Task 2: Route shared buttons and module tabs through the visual states

**Files:**
- Modify: `Core/function2.lua`
- Modify: `Core/BiaoGe.lua`
- Modify: `Core/BGNext/UIThemeSettings.lua`
- Modify: `tests/test_ui_style.lua`
- Modify: `tests/test_ui_theme_settings.lua`

- [ ] **Step 1: Add failing integration assertions**

Extend `tests/test_ui_style.lua` to read `Core/function2.lua` and `Core/BiaoGe.lua`. Assert that the button factory contains `UIStyle.registerButton(bt)`, routes `OnEnter`, `OnLeave`, and `SetEnabled` through `UIStyle.setButtonState`, and keeps the legacy gradient fallback. Assert that `BG.ClickTabButton` calls `UIStyle.applyNavigationTab` for selected and inactive states.

Extend `tests/test_ui_theme_settings.lua` to assert each settings-button apply callback calls `UIStyle.refreshButtons(id, BiaoGe.options.alpha)` only after `Skin.apply` succeeds.

- [ ] **Step 2: Run and observe the source-integration failure**

Run `lua tests/run.lua`.

Expected: only the new source assertions fail.

- [ ] **Step 3: Integrate without changing geometry or click behavior**

In `BG.CreateButton`, resolve `local UIStyle = BG.BGNext and BG.BGNext.UIStyle`. Register each new button. In the existing hover/leave/enabled hooks, call `UIStyle.setButtonState` when `UIStyle.isPreviewEnabled(BiaoGe and BiaoGe.BGNext)` is true; otherwise execute the unchanged legacy gradient code. On leave, restore `_BGNextVisualState` when it is `selected`, `danger`, or `disabled`; otherwise restore `normal`.

In `BG.ClickTabButton` and its local `SetColor`, delegate preview selected/hover/inactive colors to `UIStyle.applyNavigationTab`; retain the current class-color/black implementation for classic mode. Do not add hooks, timers, or new events.

In each appearance button's apply callback, capture the result of `Skin.apply`. Call `UIStyle.refreshButtons(id, BiaoGe.options.alpha)` only when that result is successful, then return the original result to `choose`. This makes the appearance switch immediate for already-created buttons without coupling the pure `choose` function to runtime widgets.

- [ ] **Step 4: Run all Lua tests and commit**

Run `lua tests/run.lua`; expected `failed=0`.

Commit:

```powershell
git add Core/function2.lua Core/BiaoGe.lua Core/BGNext/UIThemeSettings.lua tests/test_ui_style.lua tests/test_ui_theme_settings.lua
git commit -m "feat: apply BGNext states to shared controls"
```

### Task 3: Make reversible ledger navigation consistently cyan

**Files:**
- Modify: `Core/BGNext/LegacyLedgerSkin.lua`
- Modify: `tests/test_legacy_ledger_skin.lua`

- [ ] **Step 1: Write failing navigation-state tests**

Extend the fake tabs with enabled and disabled states. After `Skin.apply("preview", registry, 0.58)`, assert inactive tabs receive `UIStyle.palette("normal")`, active/disabled navigation tabs receive `UIStyle.palette("selected")`, and repeated preview apply remains byte-for-byte idempotent. After classic apply, assert the original tab backgrounds and text colors are restored exactly.

Add a test for `Skin.refreshNavigation()` that changes a fake tab from enabled to disabled, reapplies navigation colors, and leaves every captured geometry field unchanged.

- [ ] **Step 2: Run and observe the missing refresh failure**

Run `lua tests/run.lua`.

Expected: the new navigation assertions fail because `refreshNavigation` is absent and selected tabs retain legacy state.

- [ ] **Step 3: Delegate explicit tab styling to UIStyle**

Add:

```lua
function M.refreshNavigation(registry, legacyAlpha) -> boolean
```

When runtime theme is preview, apply `selected` to disabled/active module and raid tabs and `normal` to enabled/inactive tabs. Validate geometry before and after. On error or mismatch, restore the classic snapshot and return `false` with the existing error vocabulary. `applyPreview` calls this internal navigation routine rather than maintaining a second palette implementation. Classic restore remains unchanged.

- [ ] **Step 4: Run tests and commit**

Run `lua tests/run.lua`; expected `failed=0`.

Commit:

```powershell
git add Core/BGNext/LegacyLedgerSkin.lua tests/test_legacy_ledger_skin.lua
git commit -m "feat: unify reversible ledger navigation states"
```

### Task 4: Polish the price-preset page without reducing density

**Files:**
- Modify: `Core/BGNext/AuctionPriceUI.lua`
- Modify: `tests/test_auction_price_ui.lua`

- [ ] **Step 1: Add failing bounded-decoration and state tests**

Extend `tests/test_auction_price_ui.lua` source assertions to require:

```lua
test.eq(source:find('CreateFrame("Frame", nil, main, "BackdropTemplate")', 1, true) ~= nil, true,
    "price page creates bounded surface frames")
test.eq(source:find("main.columnDivider", 1, true) ~= nil, true,
    "price page has one column divider")
test.eq(source:find('Style.setButtonState(bt, "selected"', 1, true) ~= nil, true,
    "selected price navigation uses the brand state")
test.eq(source:find("for i = 1, pageCapacity do", 1, true) ~= nil, true,
    "visual polish retains reusable row capacity")
```

Count literal decorative creation markers and assert they do not exceed `Style.objectBudget()`.

- [ ] **Step 2: Run and observe the expected failure**

Run `lua tests/run.lua`.

Expected: the new surface, divider, and state assertions fail; viewport tests remain green.

- [ ] **Step 3: Add the scoped surfaces and explicit selected states**

Create the existing `main.bossScroll` and `main.itemScroll` frames with `BackdropTemplate` and apply `Style.applySurface(..., "surface", 0.44)` directly to them; do not introduce duplicate container frames. Add one vertical `columnDivider` texture at `layout.columnWidth + layout.columnGap / 2`, using the border token at low alpha. Add no row backgrounds and no additional per-item objects.

Register price-page buttons through the existing shared factory. After each refresh enables/disables raid, mode, or boss buttons, call `Style.setButtonState(bt, selected and "selected" or "normal", BiaoGe.options.alpha)`. Mark delete, clear-personal, and row clear controls as `danger` without changing their labels or click behavior.

Keep `layout.capacity`, `pageCapacity`, row anchors, slider math, filters, and tooltips unchanged.

- [ ] **Step 4: Run tests and commit**

Run `lua tests/run.lua`; expected `failed=0`.

Commit:

```powershell
git add Core/BGNext/AuctionPriceUI.lua tests/test_auction_price_ui.lua
git commit -m "feat: polish dense auction price layout"
```

### Task 5: Review baseline overrides and produce the test package

**Files:**
- Modify: `docs/baseline/BGNext-overrides.sha256`
- Create: `docs/testing/ui-polish-phase-2.md`
- Create locally: `.local/handoffs/inbox/<timestamp>--codex-combined-auction-ui-test-v5--ui-polish-phase-2.md`

- [ ] **Step 1: Review and update only affected override hashes**

Compute SHA-256 for `BGLite.toc`, `Core/function2.lua`, `Core/BiaoGe.lua`, and `Core/BGNext/AuctionPriceUI.lua`. Compare their diffs with the specification, then replace only those entries in `docs/baseline/BGNext-overrides.sha256`. Do not modify `docs/baseline/BGLite-2.4.0.sha256`.

- [ ] **Step 2: Record verification scope**

Create `docs/testing/ui-polish-phase-2.md` stating that automated tests cover token/state determinism, idempotence, exact classic restore, geometry preservation, bounded objects, absence of polling/communication, and the unchanged price row capacity. Mark permanent 60, TBC, Titan/Mists, and Retail appearance as `needs_game_validation`.

- [ ] **Step 3: Run mandatory verification**

Run:

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
pwsh -NoProfile -File tools/verify-baseline.ps1
git diff --check
pwsh -NoProfile -File tools/build-release.ps1 -OutputPath 'D:\vibe coding\BGN\.local\packages\BGNext-0.3.1-combined-auction-ui-test-v7.zip' -Force
```

Expected: all Lua suites pass, the 188-file baseline plus explicit overrides verifies, whitespace check is silent, and the v7 ZIP plus SHA-256 sidecar is created.

- [ ] **Step 4: Inspect package boundaries**

Confirm the ZIP has only the `BGNext/` root, includes `UITheme.lua`, `UIStyle.lua`, `LegacyLedgerSkin.lua`, `UIThemeSettings.lua`, and `AuctionPriceUI.lua`, and excludes `Core/FBUI/Model.lua`, tests, development docs, `.git`, and quarantined modules.

- [ ] **Step 5: Commit evidence and write the required local handoff**

Commit:

```powershell
git add docs/baseline/BGNext-overrides.sha256 docs/testing/ui-polish-phase-2.md
git commit -m "test: verify BGNext UI polish phase 2"
```

Write the repository-local handoff with status `needs_game_validation`, exact HEAD, changed files, commands and observed results, baseline/provenance/privacy evidence, package path, and the unverified in-game visual checks. Do not publish a GitHub Release or upload to an external platform.
