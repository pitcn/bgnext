# Titan Role Overview Release Scope Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the BGNext own-character overview for the Titan client while preventing unverified client catalogs from being presented as supported.

**Architecture:** Keep the existing shared snapshot, projection, and renderer layers. Add explicit catalog support status, make the Titan catalog the only release-ready catalog, enrich the pure projected column model with tooltip/header metadata and measured widths, then render the approved header controls and Blizzard tooltips without adding persistent or communicated data.

**Tech Stack:** World of Warcraft Lua 5.1, BGLite 2.4.0 APIs, Blizzard `GameTooltip`/`C_CurrencyInfo`/item APIs, repository Lua test harness, PowerShell verification scripts.

---

### Task 1: Make client support status explicit

**Files:**
- Modify: `Core/BGNext/OwnCharactersCatalog.lua`
- Modify: `Core/BGNext/OwnCharactersAdapters.lua`
- Test: `tests/test_own_character_adapters.lua`

- [ ] **Step 1: Write the failing catalog-status tests**

Add assertions that Titan is the only release-ready family and that unverified families do not expose the current synthetic grouped columns:

```lua
test.eq(Catalog.status("titan"), "tested-in-game", "Titan is the release-ready catalog")
for _, family in ipairs({ "vanilla", "tbc", "wrath", "cata", "mop", "retail" }) do
    test.eq(Catalog.status(family), "unverified", family .. " remains unverified")
    local catalog = Catalog.forFamily(family)
    test.eq(#catalog.raidColumns, 0, family .. " exposes no unreliable raid placeholders")
    test.eq(#catalog.resourceColumns, 0, family .. " exposes no unreliable resource placeholders")
end

local titan = Catalog.forFamily("titan")
local seenInstance = {}
for _, column in ipairs(titan.raidColumns) do
    test.eq(#column.instanceIds, 1, column.id .. " maps to one instance")
    test.eq(seenInstance[column.instanceIds[1]], nil, column.id .. " has a unique instance")
    seenInstance[column.instanceIds[1]] = column.id
end
```

- [ ] **Step 2: Run the focused test and observe the expected failure**

Run:

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
```

Expected: failure because `Catalog.status` does not exist and non-Titan catalogs still contain placeholder columns.

- [ ] **Step 3: Add catalog status and empty unverified catalogs**

Represent each family with an explicit status and keep the current Titan column declarations unchanged:

```lua
local CATALOG = {
    vanilla = { status = "unverified", raidColumns = {}, resourceColumns = {} },
    tbc = { status = "unverified", raidColumns = {}, resourceColumns = {} },
    wrath = { status = "unverified", raidColumns = {}, resourceColumns = {} },
    titan = {
        status = "tested-in-game",
        raidColumns = TITAN_RAID_COLUMNS,
        resourceColumns = TITAN_RESOURCE_COLUMNS,
    },
    cata = { status = "unverified", raidColumns = {}, resourceColumns = {} },
    mop = { status = "unverified", raidColumns = {}, resourceColumns = {} },
    retail = { status = "unverified", raidColumns = {}, resourceColumns = {} },
}

function M.status(family)
    local catalog = CATALOG[family]
    return catalog and catalog.status or "unverified"
end
```

Ensure `forFamily` includes `status` in the clone and unknown families return an empty `unverified` catalog. Do not fabricate support from API presence alone.

- [ ] **Step 4: Run the focused tests**

Run the same command. Expected: the new support and uniqueness assertions pass.

- [ ] **Step 5: Commit the isolated catalog change**

```powershell
git add Core/BGNext/OwnCharactersCatalog.lua Core/BGNext/OwnCharactersAdapters.lua tests/test_own_character_adapters.lua
git commit -m "fix: scope role overview support to Titan"
```

### Task 2: Project tooltip metadata and collision-free widths

**Files:**
- Modify: `Core/BGNext/OwnCharactersView.lua`
- Test: `tests/test_own_character_view.lua`

- [ ] **Step 1: Write failing projection tests**

Add tests for item tooltip identity, item-strip width, numeric width, and fixed column gaps:

```lua
local projection = View.project(input({ snapshots = {
    snapshot({
        equipment = {
            [13] = { itemId = 1001, link = "|Hitem:1001::::::::|h[Test Trinket]|h", icon = 11 },
            [14] = { itemId = 1002, icon = 12 },
        },
        currencies = { titanEmber = 18421, titanShard = 542 },
    }),
} }))

local trinkets = findColumn(projection.resource.columns, "trinkets")
test.eq(trinkets.cells[1].items[1].link, "|Hitem:1001::::::::|h[Test Trinket]|h", "item link reaches the renderer")
test.eq(trinkets.cells[1].items[2].itemId, 1002, "item id is retained as tooltip fallback")
test.eq(trinkets.width >= View.metrics.itemSize * 2 + View.metrics.itemGap, true,
    "two item icons fit without overflow")

local ember = findColumn(projection.resource.columns, "titanEmber")
local shard = findColumn(projection.resource.columns, "titanShard")
test.eq(ember.width >= View.measureNumber("18421"), true, "currency width fits its longest value")
test.eq(shard.x - (ember.x + ember.width) >= View.metrics.columnGap, true,
    "adjacent numeric columns retain a gap")
```

- [ ] **Step 2: Run the focused test and observe the expected failure**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
```

Expected: failure because numeric measurement/gap metadata and per-column positions are not yet projected consistently.

- [ ] **Step 3: Implement pure width measurement**

Add deterministic Lua-only helpers and use them during projection:

```lua
M.metrics.itemSize = 19
M.metrics.itemGap = 2
M.metrics.columnGap = 8

function M.measureNumber(value)
    return math.max(24, #tostring(value or "") * 8 + 8)
end

local function itemStripWidth(maxItems)
    if maxItems <= 0 then return M.metrics.itemSize + 8 end
    return maxItems * M.metrics.itemSize + math.max(0, maxItems - 1) * M.metrics.itemGap + 8
end
```

For `dynamic-items`, compute the maximum number of items in that column across visible rows. For numeric and money columns, measure the header icon minimum, every visible row, and the total row; choose the maximum. Assign each projected column a stable `x` and add `columnGap` between columns. Preserve `itemId`, `link`, `icon`, `itemLevel`, and `count` in projected item cells.

- [ ] **Step 4: Run the focused test and full view regressions**

Run the focused command. Expected: all view tests pass with no width or projection regression.

- [ ] **Step 5: Commit the pure projection change**

```powershell
git add Core/BGNext/OwnCharactersView.lua tests/test_own_character_view.lua
git commit -m "fix: measure role overview columns from content"
```

### Task 3: Render icon-only currency headers and Blizzard tooltips

**Files:**
- Modify: `Core/BGNext/OwnCharactersUI.lua`
- Test: `tests/test_own_character_ui.lua`

- [ ] **Step 1: Write failing UI-model tests**

Replace the old text-plus-icon expectation with an icon-only header descriptor and test its accessible tooltip name:

```lua
local header = UI.columnHeader({
    title = "余烬",
    source = { kind = "currency", currencyId = 3403, showHeaderIcon = true },
}, function()
    return { name = "泰坦余烬", iconFileID = 123456 }
end)
test.eq(header.text, "|T123456:14:14|t", "currency header is icon-only")
test.eq(header.tooltip, "泰坦余烬", "currency header tooltip uses the official full name")

local fallback = UI.columnHeader({
    title = "余烬",
    source = { kind = "currency", currencyId = 3403, showHeaderIcon = true },
}, function() return nil end)
test.eq(fallback.tooltip, "余烬", "catalog title is the safe fallback")
```

Retain and extend source assertions for `GameTooltip`, `SetHyperlink`, `SetItemByID`, `OnEnter`, `OnLeave`, and item-data request handling.

- [ ] **Step 2: Run the focused test and observe the expected failure**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
```

Expected: failure because `columnHeader` currently returns a text string containing both the short title and icon.

- [ ] **Step 3: Implement header descriptors and safe tooltips**

Return a descriptor for every header:

```lua
return {
    text = iconFileID and ("|T" .. iconFileID .. ":14:14|t") or column.title,
    tooltip = officialName or column.title,
    iconFileID = iconFileID,
}
```

During drawing, bind `OnEnter`/`OnLeave` to the header hit frame. Use `GameTooltip:SetText(descriptor.tooltip)` for headers. For item cells, prefer `SetHyperlink(item.link)` and fall back to `SetItemByID(item.itemId)`; if available, call `C_Item.RequestLoadItemDataByID(item.itemId)` before the fallback. Never construct custom attribute text.

Use the projected widths and positions rather than recomputing incompatible widths in `OwnCharactersUI.lua`.

- [ ] **Step 4: Run the focused tests**

Expected: UI tests pass and source checks confirm official tooltip APIs are wired.

- [ ] **Step 5: Commit the rendering change**

```powershell
git add Core/BGNext/OwnCharactersUI.lua tests/test_own_character_ui.lua
git commit -m "feat: add compact role overview tooltips"
```

### Task 4: Add header hide and section-add controls

**Files:**
- Modify: `Core/BGNext/OwnCharactersUI.lua`
- Modify: `Core/BGNext/RoleOverviewSettings.lua`
- Modify: `Core/BGNext/OwnCharactersRuntime.lua`
- Test: `tests/test_own_character_ui.lua`
- Test: `tests/test_own_character_runtime.lua`
- Test: `tests/test_own_character_view.lua`

- [ ] **Step 1: Write failing interaction tests**

Test a pure control-policy helper and runtime callback:

```lua
test.eq(UI.headerControls("pinned", true).canHide, true, "pinned headers can hide columns")
test.eq(UI.headerControls("preview", true).canHide, false, "preview headers cannot hide columns")
test.eq(UI.headerControls("pinned", false).canHide, false, "required columns cannot be hidden")
test.eq(UI.headerControls("pinned", true).canAdd, true, "pinned sections expose settings")

local before = runtime.getSnapshots()
runtime.setColumnVisible("resource", "titanShard", false)
test.eq(Settings.isVisible(root, "titan", "resource", "titanShard", catalog), false,
    "header hide persists only the current-family preference")
test.eq(runtime.getSnapshots(), before, "hiding a column does not replace snapshots")
```

- [ ] **Step 2: Run focused tests and observe failure**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
```

Expected: failure because header-control policy and runtime visibility callbacks do not exist.

- [ ] **Step 3: Implement the interaction boundary**

Add pure policy and callbacks:

```lua
function M.headerControls(mode, hideable)
    return {
        canHide = mode == "pinned" and hideable == true,
        canAdd = mode == "pinned",
    }
end
```

The UI creates a small `×` hit target only while a hideable pinned header is hovered. Its click calls the injected runtime callback with section and column ID, then refreshes. Add a `+` at the far right of each section header; it calls `RoleOverviewSettings.Open(section)` and does not mutate data. The runtime delegates visibility persistence to the existing `RoleOverviewSettings.setVisible` and refreshes the projection.

Add `RoleOverviewSettings.Open(section)` to show the existing settings page and focus/scroll to `raid` or `resource`. If the host settings container cannot focus a subsection, open the role-overview page at its top without error.

- [ ] **Step 4: Run all own-character tests**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
```

Expected: all own-character and entry tests pass; preview behavior remains non-interactive.

- [ ] **Step 5: Commit the interaction change**

```powershell
git add Core/BGNext/OwnCharactersUI.lua Core/BGNext/RoleOverviewSettings.lua Core/BGNext/OwnCharactersRuntime.lua tests/test_own_character_ui.lua tests/test_own_character_runtime.lua tests/test_own_character_view.lua
git commit -m "feat: add role overview column controls"
```

### Task 5: Document compatibility truthfully and verify the package

**Files:**
- Modify: `README.md`
- Create: `docs/compatibility.md`
- Modify: `docs/baseline/BGNext-overrides.sha256`
- Create: shared local handoff under `.local/handoffs/inbox`

- [ ] **Step 1: Update compatibility wording**

Document the role-overview matrix as:

```markdown
| 客户端 | 角色总览状态 |
| --- | --- |
| 周年时光服 | 代码覆盖；等待本轮实机复验 |
| 经典永久 60 / 探索赛季 / TBC / 巫妖王 / 大地的裂变 / 熊猫人 / 正式服 | 适配中；未声明支持 |
```

Do not imply official endorsement and do not disclose private communications.

- [ ] **Step 2: Review every changed baseline file and update only explicit override hashes**

Inspect:

```powershell
git diff -- Core/BGNext/OwnCharactersCatalog.lua Core/BGNext/OwnCharactersAdapters.lua Core/BGNext/OwnCharactersView.lua Core/BGNext/OwnCharactersUI.lua Core/BGNext/OwnCharactersRuntime.lua Core/BGNext/RoleOverviewSettings.lua
```

Then update only the changed BGNext override entries using the repository's documented baseline tool. Do not bulk-accept other drift.

- [ ] **Step 3: Run mandatory verification**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
pwsh -NoProfile -File tools/verify-baseline.ps1
git diff --check
rg -n -g "OwnCharacters*.lua" -g "RoleOverview*.lua" "SendAddonMessage|SendChatMessage|C_ChatInfo|BiaoGeAccounts" Core/BGNext
```

Expected: Lua tests report zero failures; baseline verification succeeds; diff check is empty; the privacy scan finds no communication or cross-account integration in the target modules.

- [ ] **Step 4: Commit documentation and verified hashes**

```powershell
git add README.md docs/compatibility.md docs/baseline/BGNext-overrides.sha256
git commit -m "docs: mark Titan role overview validation status"
```

- [ ] **Step 5: Install only after automated verification**

Back up the current game addon outside `AddOns`, sync the repository package to `C:\World of Warcraft1\_classic_titan_\Interface\AddOns\BGLite`, and compare SHA-256 hashes for every installed package file. Do not touch `WTF` or SavedVariables.

- [ ] **Step 6: Write the mandatory local handoff**

Resolve the shared inbox through `git rev-parse --path-format=absolute --git-common-dir` and write a `needs_game_validation` handoff containing exact HEAD, commits, changed files, observed command results, install backup path, installed-tree hash result, privacy/provenance findings, and the remaining in-game checklist.

- [ ] **Step 7: Request game validation**

Ask the maintainer to `/reload`, open the pinned and hover versions, and verify independent raid columns, item and currency tooltips, large numbers, multiple item icons, header `×`, section `+`, settings restoration, and window layering. Do not claim visual completion before screenshots and interaction results are received.
