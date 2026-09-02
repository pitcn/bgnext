# BGNext UI Semantic Hierarchy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify BGNext text, button, Boss-label, character-overview, and price-row hierarchy without changing layout density or runtime data behavior.

**Architecture:** Extend the existing pure `UIStyle` adapter with semantic roles and low-emphasis list states. Runtime modules consume those roles at their existing rendering boundaries; price-row decisions stay in a pure helper so visibility and text are regression-tested.

**Tech Stack:** Lua 5.1, WoW frame APIs, repository plain-Lua test runner.

---

### Task 1: Semantic style tokens

**Files:**
- Modify: `tests/test_ui_style.lua`
- Modify: `Core/BGNext/UIStyle.lua`

- [ ] Add failing assertions for `textColor("brand"|"primary"|"secondary"|"danger")`, `listNormal`, `listSelected`, and per-state border alpha.
- [ ] Run `lua tests/run.lua test_ui_style` and confirm failure because the roles/states do not exist.
- [ ] Add the semantic palette entries and pure color resolver; make `applyButton` use each state's border alpha.
- [ ] Re-run the focused test and commit the green change.

### Task 2: Shared controls and ledger Boss labels

**Files:**
- Modify: `tests/test_ui_style.lua`
- Modify: `Core/function2.lua`
- Modify: `Core/FBUI/FBUIfunction.lua`

- [ ] Add source assertions for 14px shared buttons and semantic Boss label application.
- [ ] Run the focused test and confirm it fails on the old 15px/color-registry paths.
- [ ] Keep main navigation unchanged, set only `BG.CreateButton` to 14px, and apply preview semantic roles to normal, structural and danger Boss labels.
- [ ] Restore the same semantic Boss role after ICC tooltip hover and re-run the focused test.

### Task 3: Price-page information noise

**Files:**
- Modify: `tests/test_auction_price_ui.lua`
- Modify: `Core/BGNext/AuctionPriceUI.lua`

- [ ] Add failing tests for `priceDisplay`: inherited leader price, explicit leader price, unset personal price, and explicit personal price.
- [ ] Run `lua tests/run.lua test_auction_price_ui` and confirm the helper is absent.
- [ ] Implement the pure helper; render `X G`/`—`, assign primary versus secondary text, and show the red clear action only for explicit values.
- [ ] Apply `listNormal`/`listSelected` only to the Boss picker and run the focused test.

### Task 4: Character overview hierarchy and window controls

**Files:**
- Modify: `tests/test_own_character_ui.lua`
- Modify: `tests/test_role_overview_entry.lua`
- Modify: `Core/BGNext/OwnCharactersUI.lua`
- Modify: `Core/BGNext/RoleOverviewEntry.lua`

- [ ] Change tests to require cyan section titles, gray-blue hints, neutral column headings, and consistent 16px controls with hover feedback.
- [ ] Run both focused tests and confirm the old green/multicolour behavior fails.
- [ ] Replace presentation-only colors, preserve class colors and completion green, and add consistent hover vertex colors to the three controls.
- [ ] Re-run both focused tests.

### Task 5: Verification and package

**Files:**
- Modify only if required by the existing release builder.

- [ ] Run `lua tests/run.lua` and require zero failures.
- [ ] Run the repository baseline/safety command used by the v7 package and require zero regressions.
- [ ] Review `git diff --check`, inspect the diff against the design boundaries, and commit.
- [ ] Build a new combined test ZIP from the verified worktree and inspect its archive root and hashes.

