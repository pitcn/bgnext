# BGNext Entry Interactions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` task by task. Do not parallelize because the tasks share interaction state and the baseline manifest.

**Goal:** Make the minimap button, role-overview footer button, and key binding follow one predictable entry contract.

**Architecture:** `RoleOverviewEntry` remains the sole owner of preview and pinned-window state. A small pure `EntryInteractions` module projects minimap actions and menu items; the LibDataBroker module and XML binding only adapt user input to guarded public entry methods. No new storage, communication, or data readers are introduced.

**Tech Stack:** Lua 5.1, WoW XML bindings, LibDataBroker/LibDBIcon, BiaoGe-LibUIDropDownMenu-4.0, repository Lua harness, PowerShell release checks.

---

### Task 1: Lock the pure interaction contract

**Files:**
- Create: `tests/test_entry_interactions.lua`
- Modify: `tests/test_role_overview_entry.lua`
- Modify: `tests/run.lua`

- [ ] Add failing role-button tests requiring `LeftButton -> toggle`, `RightButton -> settings`, `MiddleButton -> toggle`, `Ctrl+LeftButton -> toggle`, and `previewDelay() == 0.2`.
- [ ] Add a failing minimap suite requiring `LeftButton -> toggle-main`, `RightButton -> menu`, and `MiddleButton -> toggle-role`.
- [ ] Require `menuModel()` to return `main, role, settings` in that order when role overview is available, and only `main, settings` when unavailable. Each window item carries `open` or `close` according to live visibility.
- [ ] Register the suite in `tests/run.lua`.
- [ ] Run `lua tests/run.lua` and retain the expected RED output showing the missing module/functions.
- [ ] Commit as `test: define unified entry interactions`.

The test data must include:

```lua
local available = Interactions.menuModel({ mainShown = false, roleShown = true, roleAvailable = true })
test.eq(#available, 3, "available clients show three entries")
test.eq(available[1].id, "main", "main is first")
test.eq(available[1].verb, "open", "hidden main receives open")
test.eq(available[2].id, "role", "role is second")
test.eq(available[2].verb, "close", "shown role receives close")
test.eq(available[3].id, "settings", "settings is last")

local unavailable = Interactions.menuModel({ mainShown = true, roleAvailable = false })
test.eq(#unavailable, 2, "unavailable clients omit role")
test.eq(unavailable[1].verb, "close", "shown main receives close")
test.eq(unavailable[2].id, "settings", "settings remains")
```

### Task 2: Implement the pure interaction model

**Files:**
- Create: `Core/BGNext/EntryInteractions.lua`
- Modify: `Core/BGNext/RoleOverviewEntry.lua`
- Modify: `BGLite.toc`

- [ ] Create `EntryInteractions.lua`, attach it to `BG.BGNext`, and implement only `minimapAction(button)` and `menuModel(state)`.
- [ ] `menuModel` must always place main first and settings last, insert role only when `roleAvailable == true`, and derive open/close verbs from `mainShown` and `roleShown`.
- [ ] Add pure `RoleOverviewEntry.buttonAction(button, controlDown)` and `previewDelay()` functions. Ordinary left click and the retained middle/Ctrl-left aliases all return `toggle`; right click returns `settings`.
- [ ] Load the new module before `RoleOverviewEntry.lua` in `BGLite.toc`.
- [ ] Run `lua tests/run.lua`; the Task 1 tests must turn GREEN.
- [ ] Commit as `feat: model unified BGNext entry actions`.

The action mapper should be equivalent to:

```lua
function M.minimapAction(button)
    if button == "LeftButton" then return "toggle-main" end
    if button == "RightButton" then return "menu" end
    if button == "MiddleButton" then return "toggle-role" end
end
```

### Task 3: Make the footer button intuitive

**Files:**
- Modify: `Core/BGNext/RoleOverviewEntry.lua`
- Modify: `tests/test_role_overview_entry.lua`

- [ ] Add a failing delayed-hover test: entering then leaving before 0.2 seconds must never show the preview; a current token after 0.2 seconds may show it.
- [ ] Add source/runtime assertions that footer clicks route through `buttonAction` and settings route through `RoleOverviewSettings.Open`.
- [ ] Run `lua tests/run.lua` and retain RED.
- [ ] Replace split mouse-down/mouse-up toggling with one all-buttons `OnClick` path. Never let one physical click invoke two toggle handlers.
- [ ] Left/middle/Ctrl-left call the same guarded `togglePinned()`; right click calls `RoleOverviewSettings.Open("raid")`.
- [ ] Implement hover delay with `C_Timer.After(0.2, ...)` and a monotonically increasing token. OnLeave, pinning, disabling, or main-frame hiding invalidates the token. Do not create a ticker for the delay.
- [ ] When a visible preview is left-clicked, convert the same named frame to pinned mode; do not hide and recreate it.
- [ ] Run tests and commit as `fix: make role overview clicks intuitive`.

### Task 4: Add the minimap menu

**Files:**
- Modify: `Core/Module/minimap.lua`
- Modify: `Locales/zhCN.lua`
- Modify: `Locales/zhTW.lua`
- Modify: `Locales/enUS.lua`
- Modify: `tests/test_entry_interactions.lua`

- [ ] Add failing localization/source checks for player-facing open/close table, open/close role overview, and settings labels.
- [ ] Run tests and retain RED.
- [ ] Dispatch all minimap mouse buttons through `EntryInteractions.minimapAction`.
- [ ] Keep left click as the existing main-table toggle.
- [ ] Build one reusable right-click dropdown with BiaoGe-LibUIDropDownMenu-4.0. Project fresh menu text and actions from live main visibility, `RoleOverviewEntry.isPinned()`, and `RoleOverviewEntry.canOpen()` each time it opens.
- [ ] Map main to the existing main-frame toggle, role to `RoleOverviewEntry.togglePinned()`, and settings to existing option opening plus main-frame hide behavior.
- [ ] Change middle click from legacy `BG.SetFBCD` to the guarded role toggle; unavailable clients silently do nothing.
- [ ] Do not expose internal IDs or add more menu items.
- [ ] Run tests and commit as `feat: add BGNext minimap entry menu`.

### Task 5: Restore the independent key binding

**Files:**
- Modify: `Bindings.xml`
- Modify: `Core/DB/Init2.lua`
- Modify: `Locales/zhCN.lua`
- Modify: `Locales/zhTW.lua`
- Modify: `Locales/enUS.lua`
- Modify: `tests/test_role_overview_entry.lua`

- [ ] Add a failing test requiring a binding action distinct from `BIAOGE`, a matching global binding name, and a body that only calls the guarded role toggle.
- [ ] Run tests and retain RED.
- [ ] Replace the stale XML comment claiming role overview does not exist.
- [ ] Add a `BGNEXT_ROLE_OVERVIEW` binding under the existing BGNext category. Its body checks `BG`, `BG.BGNext`, and `RoleOverviewEntry` before calling `togglePinned()`.
- [ ] Register `BINDING_NAME_BGNEXT_ROLE_OVERVIEW` from the localized “打开/关闭角色总览” string. Keep `BIAOGE` unchanged.
- [ ] Confirm unavailable/disabled clients fail closed even if WoW still displays the static binding row.
- [ ] Run tests and commit as `fix: restore role overview key binding`.

The XML behavior should be equivalent to:

```xml
<Binding name="BGNEXT_ROLE_OVERVIEW" Category="BINDING_HEADER_BIAOGE">
    if BG and BG.BGNext and BG.BGNext.RoleOverviewEntry then BG.BGNext.RoleOverviewEntry.togglePinned() end
</Binding>
```

### Task 6: Refresh evidence and verify

**Files:**
- Modify: `docs/baseline/BGNext-overrides.sha256`

- [ ] Review every changed upstream file individually. Expected overrides include `BGLite.toc`, `Bindings.xml`, `Core/DB/Init2.lua`, `Core/Module/minimap.lua`, and the three locale files.
- [ ] Calculate SHA-256 for changed upstream files and update only `BGNext-overrides.sha256`. Do not modify `BGLite-2.4.0.sha256`; do not add the new BGNext-only module to the override list.
- [ ] Run `lua tests/run.lua` and require zero failures.
- [ ] Run `powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify-baseline.ps1` and require success.
- [ ] Run `git diff --check` and require no output.
- [ ] Run `powershell -NoProfile -ExecutionPolicy Bypass -File tools/build-release.ps1 -Force` and require a successful ZIP.
- [ ] Audit the ZIP for `BGLite/BGLite.toc`, `BGLite/Bindings.xml`, and `BGLite/Core/BGNext/EntryInteractions.lua`; reject History, TradeHistory, MailHistory, Receive, ReceiveUIfunction, tests, tools, and `.superpowers` paths.
- [ ] Push an Issue #5 branch and open a PR against `main` containing `Fixes #5`, RED-to-GREEN evidence, gate results, no-new-data/communication statement, and `pending-in-game-verification`. Do not merge.

### Task 7: Hand off minimal game validation

- [ ] Provide this checklist without claiming it has passed:

1. Minimap left click twice opens then closes the main table.
2. Minimap right click shows table, role overview, settings in order; each works.
3. Minimap middle click twice opens then closes one role window.
4. Crossing the footer button quickly causes no flash; hovering 0.2 seconds shows preview and leaving closes it.
5. Footer left click pins the preview; clicking again closes it; right click opens role settings.
6. A bound “打开/关闭角色总览” key toggles role overview without opening the main table.
7. ESC closes a fixed role window.
8. An unsupported client has no role minimap item and cannot open an empty role window.

- [ ] Report the commit, PR, automated results, package path, and checklist. Stop for maintainer review and game validation; do not merge or release.
