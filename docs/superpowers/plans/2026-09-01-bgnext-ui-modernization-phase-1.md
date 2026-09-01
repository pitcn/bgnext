# BGNext UI Modernization Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in BGNext preview theme to the existing team ledger without changing its geometry, events, data, transparency preference, or screenshot workflow.

**Architecture:** Keep the legacy ledger as the only UI and project a reversible visual skin onto a small, explicit registry of existing frames. `UITheme.lua` owns pure tokens and preference validation; `LegacyLedgerSkin.lua` owns snapshot/apply/validate/rollback; `UIThemeSettings.lua` exposes the explicit classic/preview choice after the existing settings UI is built. Phase 1 does not create `WorkspaceUI` or restyle non-ledger pages.

**Tech Stack:** WoW Lua 5.1, existing Blizzard frame APIs and BGNext assets only, repository Lua test harness, PowerShell baseline/release verification.

---

## Non-negotiable implementation rules

- Work only in `D:\vibe coding\BGN\.worktrees\ui-modernization-design-v2` on branch `codex/ui-modernization-design-v2`.
- Read `CONTEXT.md`, `SECURITY.md`, `PRIVACY.md`, `docs/adr/0003-reference-study-original-implementation.md`, and `docs/superpowers/specs/2026-08-31-bgnext-ui-modernization-design.md` before code changes.
- Do not inspect, copy, translate, transform, or package EllesmereUI, BiaoGe, BGLite, WeakAuras, or other third-party source/assets. The approved spec already contains the permitted visible-principle research.
- Do not modify `Core/BiaoGe.lua`, `Core/Options.lua`, `Core/function1.lua`, `Core/function2.lua`, or any auction/trade/ledger business module for this phase.
- In `LegacyLedgerSkin.lua`, do not call `SetPoint`, `ClearAllPoints`, `SetSize`, `SetWidth`, `SetHeight`, `SetParent`, `SetFrameLevel`, `SetFrameStrata`, `SetScript`, `HookScript`, `hooksecurefunc`, `RegisterEvent`, or create frames/textures/font strings.
- Do not add `OnUpdate`, timers, animation groups, addon messages, chat messages, telemetry, file/clipboard access, or new media.
- Never write `BiaoGe.options.alpha`; preview surfaces derive their alpha from that existing value. The 0.58 value is a visual test reference only.
- Do not restyle item-quality text, class-colored player names, or business error/success/warning colors.
- Do not claim game-client visual acceptance. The maintainer performs that after receiving a test package.

## Planned file structure

- Create `Core/BGNext/UITheme.lua`: pure palette, alpha clamping, theme enum validation, and geometry snapshot/compare helpers.
- Create `Core/BGNext/LegacyLedgerSkin.lua`: explicit existing-widget registry, in-memory classic snapshot, transactional preview apply, geometry validation, rollback, and one-time warning.
- Create `Core/BGNext/UIThemeSettings.lua`: an isolated settings tab with classic/preview controls and immediate application.
- Create `tests/test_ui_theme.lua`: pure theme/token/geometry tests.
- Create `tests/test_legacy_ledger_skin.lua`: fake-frame transaction, idempotence, rollback, and forbidden-API source tests.
- Create `tests/test_ui_theme_settings.lua`: source/load-order and explicit-write tests.
- Modify `BGLite.toc`: load the pure module early, the skin after `Core/BiaoGe.lua`, and settings integration after `Core/Options.lua`.
- Modify `tests/run.lua`: register the three suites.
- Modify `docs/security/data-inventory.md`: document `settings.uiTheme`.
- Modify `docs/baseline/BGNext-overrides.sha256`: update only the changed upstream `BGLite.toc` hash.
- Create `docs/testing/ui-modernization-phase-1.md`: record automated evidence and the exact in-game acceptance matrix.

### Task 1: Pure theme contract

**Files:**
- Create: `Core/BGNext/UITheme.lua`
- Create: `tests/test_ui_theme.lua`
- Modify: `tests/run.lua`

- [ ] **Step 1: Register a failing test suite**

Insert `"tests/test_ui_theme.lua",` immediately after `tests/test_init.lua` in `tests/run.lua`. Create `tests/test_ui_theme.lua` with tests for the exact public contract below:

```lua
return function(test)
    BG = { BGNext = {} }
    local Theme = dofile("Core/BGNext/UITheme.lua")

    test.eq(Theme.normalize(nil), "classic", "missing preference stays classic")
    test.eq(Theme.normalize("classic"), "classic", "classic is accepted")
    test.eq(Theme.normalize("preview"), "preview", "preview is accepted")
    test.eq(Theme.normalize("future"), "classic", "unknown value safely falls back")
    test.eq(Theme.clampAlpha(-1), 0, "alpha lower bound")
    test.eq(Theme.clampAlpha(2), 1, "alpha upper bound")
    test.eq(Theme.clampAlpha(nil), 0.8, "missing alpha uses legacy default")

    local p = Theme.tokens.preview
    test.eq(p.colors.window, "010F23", "brand navy")
    test.eq(p.colors.surface, "07182A", "brand surface")
    test.eq(p.colors.raised, "0C2033", "brand raised surface")
    test.eq(p.colors.gold, "F5B230", "brand gold")
    test.eq(p.colors.cyan, "00E6FF", "brand cyan")
    test.eq(p.colors.text, "E8F1F8", "brand text")

    local frame = {
        GetParent = function() return "parent" end,
        GetNumPoints = function() return 1 end,
        GetPoint = function() return "TOP", "relative", "BOTTOM", 3, -4 end,
        GetWidth = function() return 900 end,
        GetHeight = function() return 700 end,
    }
    local before = Theme.captureGeometry({ main = frame })
    test.eq(Theme.geometryMatches(before, { main = frame }), true, "unchanged geometry passes")
    frame.GetWidth = function() return 901 end
    test.eq(Theme.geometryMatches(before, { main = frame }), false, "changed width fails")
    test.eq(Theme.geometryMatches(before, {}), false, "missing key frame fails")
end
```

- [ ] **Step 2: Run the suite and confirm the missing-module failure**

Run: `lua tests/run.lua`

Expected: `tests/test_ui_theme.lua` fails because `Core/BGNext/UITheme.lua` does not exist; all prior suites remain unchanged.

- [ ] **Step 3: Implement the minimal pure module**

Create `Core/BGNext/UITheme.lua` with this public shape:

```lua
BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}
M.tokens = {
    classic = { id = "classic" },
    preview = {
        id = "preview",
        colors = {
            window = "010F23", surface = "07182A", raised = "0C2033",
            gold = "F5B230", cyan = "00E6FF", text = "E8F1F8",
            secondaryText = "8EA6BA", border = "24445E",
        },
        localAlphaLift = 0.14,
    },
}

function M.normalize(value)
    return value == "preview" and "preview" or "classic"
end

function M.clampAlpha(value)
    value = tonumber(value)
    if value == nil then return 0.8 end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function pointSnapshot(frame)
    local points = {}
    local count = tonumber(frame:GetNumPoints()) or 0
    for index = 1, count do
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(index)
        points[index] = { point, relativeTo, relativePoint, x, y }
    end
    return points
end

function M.captureGeometry(frames)
    local snapshot = {}
    for key, frame in pairs(frames or {}) do
        if frame and frame.GetParent and frame.GetNumPoints and frame.GetPoint
            and frame.GetWidth and frame.GetHeight then
            snapshot[key] = {
                parent = frame:GetParent(), points = pointSnapshot(frame),
                width = frame:GetWidth(), height = frame:GetHeight(),
            }
        end
    end
    return snapshot
end

local function samePoints(left, right)
    if #left ~= #right then return false end
    for index = 1, #left do
        for field = 1, 5 do
            if left[index][field] ~= right[index][field] then return false end
        end
    end
    return true
end

function M.geometryMatches(snapshot, frames)
    for key, before in pairs(snapshot or {}) do
        local frame = frames and frames[key]
        if not frame then return false end
        local now = M.captureGeometry({ value = frame }).value
        if not now or before.parent ~= now.parent or before.width ~= now.width
            or before.height ~= now.height or not samePoints(before.points, now.points) then
            return false
        end
    end
    return true
end

BG.BGNext.UITheme = M
return M
```

Keep all colors as six-character uppercase hex strings. Do not resolve WoW font paths, frames, or globals in this pure module.

- [ ] **Step 4: Run tests and commit**

Run: `lua tests/run.lua`

Expected: `failed=0`.

Commit:

```powershell
git add Core/BGNext/UITheme.lua tests/test_ui_theme.lua tests/run.lua
git commit -m "feat: define BGNext preview theme contract"
```

### Task 2: Transactional ledger skin

**Files:**
- Create: `Core/BGNext/LegacyLedgerSkin.lua`
- Create: `tests/test_legacy_ledger_skin.lua`
- Modify: `tests/run.lua`

- [ ] **Step 1: Write fake-widget transaction tests**

Register `tests/test_legacy_ledger_skin.lua` after the theme suite. The test must construct fake texture/backdrop objects that record `SetColorTexture`, `SetGradient`, `SetAlpha`, and `SetBackdropBorderColor` calls while exposing matching getters. Assert all of the following through public methods:

```lua
local Skin = dofile("Core/BGNext/LegacyLedgerSkin.lua")
local registry = fakeRegistry()
local before = registry.visualState()
local function eqTable(left, right, path)
    path = path or "root"
    test.eq(type(left), type(right), path .. " type")
    if type(left) ~= "table" then
        test.eq(left, right, path)
        return
    end
    for key, value in pairs(left) do
        eqTable(value, right[key], path .. "." .. tostring(key))
    end
    for key in pairs(right) do
        test.eq(left[key] ~= nil, true, path .. " has " .. tostring(key))
    end
end

test.eq(Skin.apply("preview", registry, 0.58), true, "preview applies")
local afterFirst = registry.visualState()
test.eq(Skin.apply("preview", registry, 0.58), true, "repeat apply succeeds")
eqTable(registry.visualState(), afterFirst, "repeat apply is idempotent")
test.eq(Skin.apply("classic", registry, 0.58), true, "classic restores")
eqTable(registry.visualState(), before, "classic is byte-for-byte visual restore")

registry.background.mutateGeometryOnStyle = true
test.eq(Skin.apply("preview", registry, 0.58), false, "geometry change rolls back")
eqTable(registry.visualState(), before, "failed apply restores classic")
```

Implement `fakeRegistry()` so `background:SetColorTexture(...)` changes `main`'s reported width only when `mutateGeometryOnStyle` is true; that makes the geometry mutation happen inside the transaction and proves post-apply validation rolls it back. Keep `eqTable` local; do not change the shared test library solely for this suite. Also scan `Core/BGNext/LegacyLedgerSkin.lua` as text and assert it contains none of:

```lua
{
  "SetPoint", "ClearAllPoints", "SetSize", "SetWidth", "SetHeight",
  "SetParent", "SetFrameLevel", "SetFrameStrata", "SetScript",
  "HookScript", "hooksecurefunc", "OnUpdate", "C_Timer", "CreateFrame",
  "CreateTexture", "CreateFontString", "SendAddonMessage", "SendChatMessage"
}
```

- [ ] **Step 2: Run the suite and confirm failure**

Run: `lua tests/run.lua`

Expected: only the new suite fails because `LegacyLedgerSkin.lua` is missing.

- [ ] **Step 3: Implement snapshot/apply/rollback with dependency injection**

Implement this API in `Core/BGNext/LegacyLedgerSkin.lua`:

```lua
function M.apply(themeId, registry, legacyAlpha) -> boolean, optionalError
function M.applySavedPreference() -> boolean, optionalError
function M.buildRuntimeRegistry() -> table or nil, error
function M.getRuntimeTheme() -> "classic" or "preview"
```

The registry is an explicit table with these keys only:

```lua
{
    main = BG.MainFrame,
    background = BG.MainFrame.Bg,
    title = BG.MainFrame.titleBg,
    moduleTabs = { existing v.button values from BG.tabButtons },
    raidTabs = { existing BG["Button" .. v.FB] values from BG.FBtable2 },
}
```

`buildRuntimeRegistry()` must return `nil, "ledger-not-ready"` if `main`, `background`, or `title` is absent. It may skip a missing optional tab. It must not enumerate arbitrary descendants or regions.

On the first successful call for a registry, capture in module-local memory only:

- main backdrop border color, when getter exists;
- background texture/color and alpha, when getters exist;
- title texture/color/gradient-relevant state and alpha, using only states that can be restored exactly on every supported client;
- each tab background texture color/alpha and font-string text color when exposed.

If a state cannot be read and therefore restored exactly, leave that property untouched in preview. Do not guess a classic value.

Before styling, capture geometry through `UITheme.captureGeometry` for `main`, every module tab, and every raid tab. Apply preview in one `pcall`, then validate with `UITheme.geometryMatches`. Preview changes are limited to:

- `main:SetBackdropBorderColor(0.141, 0.267, 0.369, 1)`;
- existing `background` color texture to navy/surface RGB and alpha exactly `UITheme.clampAlpha(legacyAlpha)`;
- existing `title` color/gradient using surface/raised colors and alpha `min(1, legacyAlpha + 0.14)`;
- existing inactive tab backgrounds to the raised surface at the legacy alpha;
- existing active/disabled tab text to cyan and inactive tab text to gold only when doing so does not overwrite an item-quality/class/business color (the explicit registry contains navigation tabs only).

Do not apply a second alpha multiplier. Every preview call computes alpha from `legacyAlpha`; it never reads the previously styled alpha as input.

Applying `classic` restores the in-memory snapshot and sets runtime theme to classic. Any exception, absent key widget, or geometry mismatch restores the snapshot, sets runtime theme to classic, returns `false, reason`, and emits no error itself. `applySavedPreference()` reads `BiaoGe.BGNext.settings.uiTheme` if present, normalizes it, and uses `BiaoGe.options.alpha` without writing either value.

- [ ] **Step 4: Run tests and commit**

Run: `lua tests/run.lua`

Expected: `failed=0`, including idempotence, rollback, and forbidden-call assertions.

Commit:

```powershell
git add Core/BGNext/LegacyLedgerSkin.lua tests/test_legacy_ledger_skin.lua tests/run.lua
git commit -m "feat: add reversible legacy ledger skin"
```

### Task 3: Runtime wiring and one-time safe fallback

**Files:**
- Modify: `BGLite.toc`
- Modify: `Core/BGNext/LegacyLedgerSkin.lua`
- Modify: `tests/test_legacy_ledger_skin.lua`

- [ ] **Step 1: Add failing load-order and warning tests**

Extend the suite to assert:

- `Core\BGNext\UITheme.lua` occurs after `Core\BGNext\Init.lua` and before `Core\BiaoGe.lua` in the TOC;
- `Core\BGNext\LegacyLedgerSkin.lua` occurs after `Core\BiaoGe.lua` and before `Core\Options.lua`;
- calling an injected `installRuntime(init2, warn)` registers exactly one `init2` callback;
- calling the callback twice after a forced failure invokes `warn` once only;
- a missing/invalid saved preference applies classic without warning;
- no runtime path writes `BiaoGe.options.alpha`.

- [ ] **Step 2: Run and confirm the wiring assertions fail**

Run: `lua tests/run.lua`

Expected: the new TOC and `installRuntime` assertions fail.

- [ ] **Step 3: Wire the modules without touching the ledger constructor**

In `BGLite.toc`:

```text
Core\BGNext\Init.lua
Core\BGNext\UITheme.lua
...
Core\BiaoGe.lua
Core\BGNext\LegacyLedgerSkin.lua
...
Core\Options.lua
Core\BGNext\UIThemeSettings.lua
```

Add `M.installRuntime(init2, warn)` to the skin. It registers one `PLAYER_ENTERING_WORLD` callback via the supplied `init2` function. The callback calls `applySavedPreference()` once per invocation, but module-local installation state prevents duplicate callback registration. On failure, call the supplied warning function once per login. The production warning uses `BG.SendSystemMessage` when available and this concise Chinese text:

```text
BGNext 预览外观加载失败，已安全恢复经典外观。
```

At file load, call `installRuntime(BG.Init2, productionWarn)` only when `BG.Init2` is a function. Do not add timers or events.

- [ ] **Step 4: Run tests and commit**

Run: `lua tests/run.lua`

Expected: `failed=0`.

Commit:

```powershell
git add BGLite.toc Core/BGNext/LegacyLedgerSkin.lua tests/test_legacy_ledger_skin.lua
git commit -m "feat: initialize ledger preview skin safely"
```

### Task 4: Explicit classic/preview setting

**Files:**
- Create: `Core/BGNext/UIThemeSettings.lua`
- Create: `tests/test_ui_theme_settings.lua`
- Modify: `tests/run.lua`
- Modify: `docs/security/data-inventory.md`

- [ ] **Step 1: Write failing preference and source-safety tests**

Register the suite after the skin suite. Test the pure exported methods:

```lua
function M.read(root) -> normalizedTheme
function M.choose(root, themeId, apply) -> boolean, optionalError
function M.buildPanel() -> nil
```

Assertions:

- `read({ settings = {} })` returns `classic` and does not add `uiTheme`;
- `read({ settings = { uiTheme = "future" } })` returns `classic` and does not rewrite the invalid value;
- `choose(root, "preview", successfulApply)` writes `preview` only after `successfulApply` returns true;
- failed apply leaves the prior saved value unchanged;
- `choose(root, "future", apply)` returns false and does not call apply;
- source contains no assignment to `BiaoGe.options.alpha`, no `ReloadUI`, and no geometry API;
- TOC loads this module after `Core\Options.lua`.

- [ ] **Step 2: Run and confirm failure**

Run: `lua tests/run.lua`

Expected: only the missing settings-module suite fails.

- [ ] **Step 3: Implement an isolated appearance settings tab**

Create the module and keep all user-facing construction inside `buildPanel()`. At file load register `BG.Init(function() M.buildPanel() end)` so its callback runs after the existing `Core/Options.lua` callback. `buildPanel()` must return harmlessly unless all of `BG.OptionsCreateTab`, `BG.CreateButton`, `BG.BGNext.DB`, and `BG.BGNext.LegacyLedgerSkin` are available.

Create a new top-level settings tab named `Options_appearance` with text `外观预览`. Inside it, create only existing-style controls:

- heading `BGNext 外观`;
- description `预览主题只改变团队账单外观，不改变布局、透明度、拍卖或账单数据。`;
- two fixed-size buttons `经典外观` and `BGNext 预览`;
- status text `当前：经典外观` or `当前：BGNext 预览`;
- secondary note `预览主题仍在测试；如遇显示问题可立即切回经典外观。`.

The buttons call `choose(BG.BGNext.DB, themeId, function(id) return Skin.apply(id, Skin.buildRuntimeRegistry(), BiaoGe.options.alpha) end)`. After success, update only button enabled/text-color state and the status text. Do not require reload. Do not write a default on panel construction; only a click calls `choose`.

Use existing `BG.CreateButton` and existing font objects. Fixed dimensions and anchors are allowed in this new settings page; the ledger geometry prohibition applies to `LegacyLedgerSkin.lua`, not newly created settings controls.

- [ ] **Step 4: Document the only new persistent field**

Add this row immediately after `settings` in `docs/security/data-inventory.md`:

```markdown
| `settings.uiTheme` | Explicit user choice (`classic` or `preview`) | Select the reversible ledger appearance; absence and invalid values behave as `classic` and are not migrated automatically | Local until changed or all BGNext data is cleared | None | Appearance settings buttons / existing full reset | Low |
```

The existing full reset (`BiaoGe = nil`) already clears this field; do not add a second destructive reset path.

- [ ] **Step 5: Run tests and commit**

Run: `lua tests/run.lua`

Expected: `failed=0`.

Commit:

```powershell
git add BGLite.toc Core/BGNext/UIThemeSettings.lua tests/test_ui_theme_settings.lua tests/run.lua docs/security/data-inventory.md
git commit -m "feat: expose opt-in ledger preview theme"
```

### Task 5: Baseline, package, and automated evidence

**Files:**
- Modify: `docs/baseline/BGNext-overrides.sha256`
- Create: `docs/testing/ui-modernization-phase-1.md`

- [ ] **Step 1: Update the single baseline override**

Compute the SHA-256 of the changed `BGLite.toc` and replace only its entry in `docs/baseline/BGNext-overrides.sha256`. Do not add BGNext-only modules to the upstream override manifest and do not change `docs/baseline/BGLite-2.4.0.sha256`.

Run:

```powershell
(Get-FileHash -Algorithm SHA256 BGLite.toc).Hash.ToLowerInvariant()
pwsh -NoProfile -File tools/verify-baseline.ps1
```

Expected: the verifier reports the 188-file upstream manifest intact and all approved overrides matching.

- [ ] **Step 2: Add the evidence document**

Create `docs/testing/ui-modernization-phase-1.md` containing:

```markdown
# UI modernization phase 1 verification

## Automated scope

- Theme enum defaults to classic and rejects unknown values.
- Brand token values and alpha bounds are fixed and tested.
- Preview application is idempotent and classic restores the captured visual state.
- Any exception or geometry mismatch rolls back to classic.
- Parent, all points, width and height are compared for the main frame and explicit navigation tabs.
- The skin source contains no geometry mutation, event replacement, polling, object creation, communication, or transparency-setting writes.
- Only an explicit successful user choice persists `BiaoGe.BGNext.settings.uiTheme`.

## Maintainer game-client acceptance (not yet verified)

For each available client family (permanent 60, TBC, Titan/Mists, Retail):

1. Back up SavedVariables and log in with the classic default.
2. Open a populated ledger and capture screenshots at 1920x1080 and 2560x1440 where available.
3. Record main frame, raid tabs, boss/area sections, summary, bottom actions, and full screenshot boundary.
4. Switch to BGNext preview without reload and confirm the same positions, dimensions, row/column capacity, text clipping, clicks, focus, auction entry, and screenshot composition.
5. Fill or load approximately 100 equipment rows and confirm one-image sharing remains practical.
6. Test the user's existing background alpha and the 0.58 reference while combat scenery remains visible.
7. Switch repeatedly classic -> preview -> classic and confirm no drift, darkening, duplicated scripts, or new objects.
8. Reload in preview, then switch back to classic; verify preference persistence and exact rollback.
9. Verify item-quality colors, class colors, error/success/warning colors, and input focus remain distinguishable.

Do not mark a client visually verified until the maintainer records the result from that client.
```

- [ ] **Step 3: Run the complete verification set**

Run:

```powershell
lua tests/run.lua
pwsh -NoProfile -File tools/verify-baseline.ps1
pwsh -NoProfile -File tools/build-release.ps1 -OutputPath .local/packages/BGNext-ui-preview-test.zip -Force
git diff --check
git status --short
```

Expected:

- Lua prints `failed=0`.
- Baseline verification succeeds.
- The release builder creates `.local/packages/BGNext-ui-preview-test.zip` and includes all three new runtime modules.
- `git diff --check` is silent.
- status lists only the intended plan implementation/evidence changes.

- [ ] **Step 4: Inspect the package and commit evidence**

List the ZIP and confirm it excludes repository docs, tests, `.git`, `.superpowers`, and quarantined legacy modules while including:

```text
BGNext/Core/BGNext/UITheme.lua
BGNext/Core/BGNext/LegacyLedgerSkin.lua
BGNext/Core/BGNext/UIThemeSettings.lua
```

Commit:

```powershell
git add docs/baseline/BGNext-overrides.sha256 docs/testing/ui-modernization-phase-1.md
git commit -m "test: verify ledger preview theme boundaries"
```

### Task 6: Delivery for maintainer validation

**Files:**
- No runtime changes expected.

- [ ] **Step 1: Review the full branch diff**

Run:

```powershell
git diff main...HEAD --stat
git diff main...HEAD -- BGLite.toc Core/BGNext tests docs/security docs/testing docs/baseline/BGNext-overrides.sha256
```

Confirm the diff contains no business-module edits, no third-party code/assets, no theme default migration, no release-version change, and no Release publishing.

- [ ] **Step 2: Provide the test handoff**

Report:

- branch and final commit;
- absolute test-package path;
- automated verification results;
- the appearance setting path: WoW Settings -> AddOns -> BGNext -> 外观预览;
- that classic remains default and the preview switch is immediate;
- that permanent 60/TBC/Titan-Mists/Retail visuals remain pending the maintainer's in-game validation.

Do not create a GitHub Release or publish to 新手盒子 in this task. A later explicit release request must include a ready-to-paste Chinese 新手盒子 changelog under repository rules.
