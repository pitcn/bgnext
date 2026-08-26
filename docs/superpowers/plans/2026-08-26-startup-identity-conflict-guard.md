# BGNext Startup Identity and Conflict Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make BGNext identify itself as version 0.1.0, expose `/bgn` and `/bgnext` while retaining `/bglite`, replace the upstream guide with a BGNext guide, and warn before the local client runs another known BiaoGe/BGLite-family addon alongside BGNext.

**Architecture:** Keep identity and duplicate-addon classification in small `Core/BGNext/` modules with pure functions that run under Lua 5.1 tests. `Core/BiaoGe.lua` remains the integration point for the existing main-frame toggle. Runtime conflict detection enumerates only local addons, never sends addon messages, and disables named conflicts only after the player clicks the confirmation button.

**Tech Stack:** World of Warcraft Lua 5.1, WoW `C_AddOns`/legacy addon APIs, `StaticPopupDialogs`, existing BGNext test harness, PowerShell verification scripts.

---

## File map

- Create `Core/BGNext/Identity.lua`: canonical BGNext name, version, slash aliases and guide metadata.
- Create `Core/BGNext/ConflictGuard.lua`: pure conflict classification plus the local runtime prompt adapter.
- Create `tests/test_identity.lua`: identity, version and slash-alias assertions.
- Create `tests/test_conflict_guard.lua`: duplicate detection, self-exclusion, disabled-addon and confirmation-target tests.
- Modify `BGLite.toc`: version/notes metadata and module load order.
- Modify `Core/BiaoGe.lua`: display BGNext version and register only the approved slash aliases.
- Modify `Core/BGNext/ReleaseInfo.lua`: consume the canonical identity version and publish the upstream version separately.
- Modify `Locales/zhCN.lua`, `Locales/zhTW.lua`, `Locales/enUS.lua`: replace the obsolete BGLite Pure Edition guide with BGNext instructions.
- Modify `tests/run.lua`: execute the two new suites.
- Modify `tests/test_release_info.lua`: verify version separation and guide claims.
- Modify `docs/security/data-inventory.md`: state that conflict detection reads addon metadata transiently and stores/transmits nothing.
- Modify `docs/baseline/BGNext-overrides.sha256`: add only hashes for reviewed BGLite baseline files changed by this plan.

### Task 1: Canonical identity and slash commands

**Files:**
- Create: `Core/BGNext/Identity.lua`
- Create: `tests/test_identity.lua`
- Modify: `tests/run.lua`
- Modify: `BGLite.toc`
- Modify: `Core/BiaoGe.lua:129-140,1896-1905`
- Modify: `Core/BGNext/ReleaseInfo.lua`

- [ ] **Step 1: Write the failing identity test**

Create `tests/test_identity.lua`:

```lua
return function(test)
    BG = { BGNext = {} }
    local identity = dofile("Core/BGNext/Identity.lua")

    test.eq(identity.projectName, "BGNext", "project name")
    test.eq(identity.version, "0.1.0", "BGNext release version")
    test.eq(identity.upstreamName, "BGLite", "upstream name")
    test.eq(identity.upstreamVersion, "2.4.0", "upstream version")
    test.eq(identity.protocolVersion, "2.4.0", "BGLite compatibility version")
    test.eq(identity.commands[1], "/bgn", "primary command")
    test.eq(identity.commands[2], "/bgnext", "full command")
    test.eq(identity.commands[3], "/bglite", "legacy command")
    test.eq(identity.isPublicCommand("/bgn"), true, "primary command is public")
    test.eq(identity.isPublicCommand("/bgnext"), true, "full command is public")
    test.eq(identity.isPublicCommand("/bglite"), false, "legacy command stays hidden")
    test.eq(identity.isRegisteredCommand("/bglite"), true, "legacy command remains registered")
    test.eq(identity.isRegisteredCommand("/biaoge"), false, "old BiaoGe command removed")
    test.eq(identity.isRegisteredCommand("/gbg"), false, "old gbg command removed")

    local tocFile = assert(io.open("BGLite.toc", "rb"))
    local toc = tocFile:read("*a")
    tocFile:close()
    test.eq(toc:find("## X-BGNext-Version: 0.1.0", 1, true) ~= nil, true, "BGNext metadata version")
    test.eq(toc:find("## Version: 2.4.0", 1, true) ~= nil, true, "BGLite protocol version retained")

    local coreFile = assert(io.open("Core/BiaoGe.lua", "rb"))
    local core = coreFile:read("*a")
    coreFile:close()
    test.eq(core:find('SLASH_BGNEXT1 = "/bgn"', 1, true) ~= nil, true, "primary slash registered")
    test.eq(core:find('SLASH_BGNEXT2 = "/bgnext"', 1, true) ~= nil, true, "full slash registered")
    test.eq(core:find('SLASH_BGNEXT3 = "/bglite"', 1, true) ~= nil, true, "legacy slash registered")
    test.eq(core:find('SLASH_BIAOGE1 = "/biaoge"', 1, true) == nil, true, "old BiaoGe slash removed")
    test.eq(core:find('SLASH_BIAOGE2 = "/gbg"', 1, true) == nil, true, "old gbg slash removed")
end
```

Add `tests/test_identity.lua` to `tests/run.lua` immediately after `tests/test_init.lua`.

- [ ] **Step 2: Run the suite and observe the missing module failure**

Run:

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
```

Expected: `tests/test_identity.lua` fails because `Core/BGNext/Identity.lua` does not exist.

- [ ] **Step 3: Add the canonical identity module**

Create `Core/BGNext/Identity.lua`:

```lua
BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {
    projectName = "BGNext",
    version = "0.1.0",
    upstreamName = "BGLite",
    upstreamVersion = "2.4.0",
    protocolVersion = "2.4.0",
    commands = { "/bgn", "/bgnext", "/bglite" },
}

local publicCommands = {
    ["/bgn"] = true,
    ["/bgnext"] = true,
}

local registeredCommands = {
    ["/bgn"] = true,
    ["/bgnext"] = true,
    ["/bglite"] = true,
}

function M.isPublicCommand(command)
    return publicCommands[type(command) == "string" and command:lower() or ""] == true
end

function M.isRegisteredCommand(command)
    return registeredCommands[type(command) == "string" and command:lower() or ""] == true
end

BG.BGNext.Identity = M
return M
```

Load it immediately after `Core\BGNext\Init.lua` in `BGLite.toc`.

- [ ] **Step 4: Separate the BGNext display version from the BGLite protocol version**

Change the visible notes and add a BGNext-specific metadata field, but deliberately keep the standard TOC version at the BGLite compatibility value:

```toc
## Notes: /bgn or /bgnext
## X-BGNext-Version: 0.1.0
## Version: 2.4.0
```

`Core/DB/DB.lua` currently derives `BG.ver` from the standard `Version` field, and the auction module broadcasts and compares that value. Keeping `## Version: 2.4.0` therefore preserves mixed-group protocol behavior. BGNext UI, documentation, changelog and GitHub Release use `Identity.version` instead; they must never use `BG.ver` as the BGNext product version.

Add these fields to `Core/BGNext/ReleaseInfo.lua` and construct them from `BG.BGNext.Identity`:

```lua
local identity = assert(BG.BGNext.Identity, "BGNext Identity must load before ReleaseInfo")

local info = {
    projectName = identity.projectName,
    version = identity.version,
    upstreamName = identity.upstreamName,
    upstreamVersion = identity.upstreamVersion,
    protocolVersion = identity.protocolVersion,
    author = "国服社区共创",
    official = false,
```

Keep the existing changelog and credits tables following these fields.

- [ ] **Step 5: Replace the old slash registration and version label**

In `Core/BiaoGe.lua`, set the top-right label from the canonical identity:

```lua
local identity = BG.BGNext and BG.BGNext.Identity
VerText:SetText(identity and (identity.projectName .. " v" .. identity.version) or "BGNext")
```

Replace the current `BIAOGE` slash block with:

```lua
BG.Init2(function()
    SlashCmdList["BGNEXT"] = function()
        if BG.MainFrame then
            BG.MainFrame:SetShown(not BG.MainFrame:IsVisible())
        end
    end
    SLASH_BGNEXT1 = "/bgn"
    SLASH_BGNEXT2 = "/bgnext"
    SLASH_BGNEXT3 = "/bglite"

    SlashCmdList["BIAOGEMOVE"] = function()
        BG.Move()
    end
    SLASH_BIAOGEMOVE1 = "/bgm"

    SlashCmdList["BIAOGEOPTIONS"] = function()
        BG.OpenOption()
        BG.MainFrame:Hide()
    end
    SLASH_BIAOGEOPTIONS1 = "/bgo"
end)
```

Do not register `/biaoge` or `/gbg` anywhere else.

- [ ] **Step 6: Run tests and exact-string scans**

Run:

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
rg -n 'SLASH_BIAOGE[123]|/biaoge|/gbg' Core BGLite.toc
rg -n 'SLASH_BGNEXT[123]|/bgnext|/bglite' Core BGLite.toc
```

Expected: tests pass; the first scan has no active command registration; the second scan shows all three approved aliases.

- [ ] **Step 7: Commit the identity slice**

```powershell
git add BGLite.toc Core/BGNext/Identity.lua Core/BGNext/ReleaseInfo.lua Core/BiaoGe.lua tests/run.lua tests/test_identity.lua
git commit -m "feat: establish BGNext identity and commands"
```

### Task 2: Pure duplicate-addon classification

**Files:**
- Create: `Core/BGNext/ConflictGuard.lua`
- Create: `tests/test_conflict_guard.lua`
- Modify: `tests/run.lua`
- Modify: `BGLite.toc`

- [ ] **Step 1: Write duplicate classification tests**

Create `tests/test_conflict_guard.lua`:

```lua
return function(test)
    BG = { BGNext = {} }
    local guard = dofile("Core/BGNext/ConflictGuard.lua")
    local addons = {
        { name = "BGLite", project = "BGNext", enabled = true, loaded = true },
        { name = "BiaoGe", enabled = true, loaded = true },
        { name = "DisabledCopy", project = "BGLite", enabled = false, loaded = false },
        { name = "Unrelated", title = "Damage Meter", enabled = true, loaded = true },
    }

    local conflicts = guard.findConflicts("BGLite", addons)
    test.eq(#conflicts, 1, "only one confirmed local conflict")
    test.eq(conflicts[1].name, "BiaoGe", "BiaoGe is reported")
    test.eq(guard.isKnownFamily({ name = "BGNext" }), true, "BGNext folder is known")
    test.eq(guard.isKnownFamily({ name = "Renamed", project = "BGNext" }), true, "BGNext metadata is known")
    test.eq(guard.isKnownFamily({ name = "Renamed", upstream = "BGLite 2.4.0" }), true, "BGLite upstream metadata is known")
    test.eq(guard.isKnownFamily({ name = "Unrelated", title = "BGLite guide" }), false, "title text alone is not enough")
end
```

Register this suite after `tests/test_identity.lua` in `tests/run.lua`.

- [ ] **Step 2: Run tests and observe the missing module failure**

Run `pwsh -NoProfile -File tools/run-lua-tests.ps1`.

Expected: `tests/test_conflict_guard.lua` fails because the module is missing.

- [ ] **Step 3: Implement conservative classification**

Create the pure portion of `Core/BGNext/ConflictGuard.lua`:

```lua
local currentAddonName = ...

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}
local knownNames = { BGLite = true, BiaoGe = true, BGNext = true }

function M.isKnownFamily(addon)
    if type(addon) ~= "table" then return false end
    if knownNames[addon.name] then return true end
    if addon.project == "BGNext" or addon.project == "BGLite" then return true end
    return type(addon.upstream) == "string" and addon.upstream:match("^BGLite[%s%-]?") ~= nil
end

function M.findConflicts(selfAddonName, addons)
    local result = {}
    for _, addon in ipairs(addons or {}) do
        if addon.name ~= selfAddonName
            and (addon.enabled == true or addon.loaded == true)
            and M.isKnownFamily(addon)
        then
            result[#result + 1] = addon
        end
    end
    table.sort(result, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return result
end
```

Do not classify an addon from its title text alone, because an uncertain match must never enter the one-click disable list.

- [ ] **Step 4: Load the module and rerun tests**

Add `Core\BGNext\ConflictGuard.lua` after `Core\BGNext\Identity.lua` in `BGLite.toc`, then run the complete test suite.

Expected: the new suite passes and existing suites remain green.

- [ ] **Step 5: Commit pure classification**

```powershell
git add BGLite.toc Core/BGNext/ConflictGuard.lua tests/run.lua tests/test_conflict_guard.lua
git commit -m "feat: classify conflicting local addons"
```

### Task 3: Runtime prompt with explicit confirmation

**Files:**
- Modify: `Core/BGNext/ConflictGuard.lua`
- Modify: `tests/test_conflict_guard.lua`
- Modify: `docs/security/data-inventory.md`

- [ ] **Step 1: Extend tests for prompt data and disable targets**

Append to `tests/test_conflict_guard.lua` before its final `end`:

```lua
    local names = guard.conflictNames(conflicts)
    test.eq(names, "BiaoGe", "prompt lists exact conflict names")

    local disabled = {}
    local reloaded = false
    guard.disableConfirmed(conflicts, function(name)
        disabled[#disabled + 1] = name
        return true
    end, function()
        reloaded = true
    end)
    test.eq(#disabled, 1, "only confirmed conflicts disabled")
    test.eq(disabled[1], "BiaoGe", "self addon never disabled")
    test.eq(reloaded, true, "reload occurs after confirmed disable")
```

- [ ] **Step 2: Run tests and observe missing helper failures**

Run `pwsh -NoProfile -File tools/run-lua-tests.ps1`.

Expected: the conflict suite fails because `conflictNames` and `disableConfirmed` are not defined.

- [ ] **Step 3: Add pure confirmation helpers**

Add to `Core/BGNext/ConflictGuard.lua`:

```lua
function M.conflictNames(conflicts)
    local names = {}
    for _, addon in ipairs(conflicts or {}) do
        names[#names + 1] = tostring(addon.name)
    end
    return table.concat(names, "、")
end

function M.disableConfirmed(conflicts, disableAddon, reloadUI)
    assert(type(disableAddon) == "function", "disableAddon callback required")
    assert(type(reloadUI) == "function", "reloadUI callback required")
    for _, addon in ipairs(conflicts or {}) do
        if disableAddon(addon.name) ~= true then
            return false
        end
    end
    reloadUI()
    return true
end
```

- [ ] **Step 4: Add a version-adapted local addon inventory**

In the same module, add this runtime adapter after the pure helpers. The modern `C_AddOns.GetAddOnEnableState` parameter order is `(addon, character)`; the legacy global order is `(character, addon)`, so they must not share an unadapted call site.

```lua
local function getRuntimeInventory()
    local modern = C_AddOns
    local getNumAddOns = modern and modern.GetNumAddOns or GetNumAddOns
    local getAddOnInfo = modern and modern.GetAddOnInfo or GetAddOnInfo
    local getMetadata = modern and modern.GetAddOnMetadata or GetAddOnMetadata
    local isLoaded = modern and modern.IsAddOnLoaded or IsAddOnLoaded
    local player = UnitName and UnitName("player") or nil
    local inventory = {}

    if type(getNumAddOns) ~= "function" or type(getAddOnInfo) ~= "function" then
        return inventory
    end

    for index = 1, getNumAddOns() do
        local first, second = getAddOnInfo(index)
        local name, title
        if type(first) == "table" then
            name = first.name
            title = first.title
        else
            name = first
            title = second
        end

        if type(name) == "string" and name ~= "" then
            local enabled = false
            if modern and type(modern.GetAddOnEnableState) == "function" then
                enabled = (modern.GetAddOnEnableState(name, player) or 0) > 0
            elseif type(GetAddOnEnableState) == "function" then
                enabled = (GetAddOnEnableState(player, name) or 0) > 0
            end

            inventory[#inventory + 1] = {
                name = name,
                title = title,
                project = type(getMetadata) == "function" and getMetadata(name, "X-Project") or nil,
                upstream = type(getMetadata) == "function" and getMetadata(name, "X-Upstream") or nil,
                enabled = enabled,
                loaded = type(isLoaded) == "function" and isLoaded(name) == true or false,
            }
        end
    end
    return inventory
end

local function disableForCurrentCharacter(name)
    local player = UnitName and UnitName("player") or nil
    if C_AddOns and type(C_AddOns.DisableAddOn) == "function" then
        return pcall(C_AddOns.DisableAddOn, name, player)
    elseif type(DisableAddOn) == "function" then
        return pcall(DisableAddOn, name, player)
    end
    return false
end

function M.installRuntime(selfAddonName)
    if type(CreateFrame) ~= "function"
        or type(StaticPopupDialogs) ~= "table"
        or type(StaticPopup_Show) ~= "function"
    then
        return false
    end

    StaticPopupDialogs.BGNEXT_DUPLICATE_ADDON = {
        text = "检测到多个表格/BGLite 系列插件同时启用：%s\n\n它们可能共用存档入口和团队通信协议，同时运行可能造成重复界面、重复消息或拍卖状态异常。建议只启用 BGNext。",
        button1 = "只保留 BGNext 并重载",
        button2 = "暂不处理",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept = function(_, conflicts)
            local ok = M.disableConfirmed(conflicts, disableForCurrentCharacter, ReloadUI)
            if not ok and print then
                print("<BGNext> 无法自动禁用冲突插件，请手动禁用：" .. M.conflictNames(conflicts))
            end
        end,
    }

    local prompted = false
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function()
        if prompted then return end
        local conflicts = M.findConflicts(selfAddonName, getRuntimeInventory())
        if #conflicts == 0 then return end
        prompted = true
        StaticPopup_Show("BGNEXT_DUPLICATE_ADDON", M.conflictNames(conflicts), nil, conflicts)
    end)
    return true
end

if currentAddonName then
    M.installRuntime(currentAddonName)
end

BG.BGNext.ConflictGuard = M
return M
```

If no supported disable API exists or any disable call raises an error, the helper returns `false`, prints the exact addon names that require manual action and does not call `ReloadUI()`.

- [ ] **Step 5: Document the transient data use**

Add a data-inventory row stating:

```markdown
| Local addon conflict inventory | Addon folder name, enabled/loaded state, `X-Project`, `X-Upstream` | WoW local addon APIs at login | Prevent simultaneous local loading of known conflicting addons | Memory only; discarded after login check | Current player UI only | No channel messages, no SavedVariables, explicit confirmation before disabling | Low |
```

- [ ] **Step 6: Run tests and commit**

Run the full Lua suite and `git diff --check`. Expected: all suites pass and no whitespace errors.

```powershell
git add Core/BGNext/ConflictGuard.lua tests/test_conflict_guard.lua docs/security/data-inventory.md
git commit -m "feat: warn about duplicate local addon versions"
```

### Task 4: Replace the upstream guide with the BGNext guide

**Files:**
- Modify: `Locales/zhCN.lua`
- Modify: `Locales/zhTW.lua`
- Modify: `Locales/enUS.lua`
- Modify: `tests/test_release_info.lua`
- Modify: `Core/BGNext/ReleaseInfo.lua`

- [ ] **Step 1: Add release and guide assertions**

Extend `tests/test_release_info.lua`:

```lua
    test.eq(info.version, "0.1.0", "BGNext version is independent")
    test.eq(info.upstreamVersion, "2.4.0", "upstream version remains disclosed")
    test.eq(info.protocolVersion, "2.4.0", "mixed-group protocol version remains compatible")

    for _, path in ipairs({ "Locales/zhCN.lua", "Locales/zhTW.lua", "Locales/enUS.lua" }) do
        local file = assert(io.open(path, "rb"))
        local text = file:read("*a")
        file:close()
        test.eq(text:find("/bgn", 1, true) ~= nil, true, path .. " documents /bgn")
        test.eq(text:find("/bgnext", 1, true) ~= nil, true, path .. " documents /bgnext")
        test.eq(text:find("/gbg", 1, true) == nil, true, path .. " removes /gbg")
    end
```

- [ ] **Step 2: Run tests and observe the stale-guide failure**

Run `pwsh -NoProfile -File tools/run-lua-tests.ps1`.

Expected: release/locale assertions fail because the upstream BGLite guide still advertises `/gbg`.

- [ ] **Step 3: Replace all three localized guides**

The Simplified Chinese guide must state, in this order:

```lua
ns.instructionsText = {
    "|cff00BFFF<BGNext 说明书>|r",
    "BGNext v0.1.0 是基于 BGLite 2.4.0 维护的独立、非官方社区共创项目。",
    "基础拍卖继续使用 BGLite 现有公开协议；不同玩家分别使用 BGNext 与 BGLite 时可以共同参与基础拍卖，实际兼容状态以版本说明中的测试结果为准。",
    "个人心愿、自有角色和个人辅助数据仅保存在本地，不向团队或游戏外发送。当前团本交易与邮件核对只保留最近一团，最长七日，不保存邮件正文。",
    "检测到本机同时启用其他表格/BGLite 系列插件时，BGNext 会提示玩家处理，但不会在未经确认时自动禁用插件。",
    "本项目欢迎通过 Issue 和 Pull Request 参与代码、测试、翻译、设计及安全审查；贡献者记录在感谢名单和对应版本说明中。",
    "本项目不代表上游作者、游戏运营方或任何平台背书。",
    " ",
    "|cff00BFFF操作指令：|r",
    "|cffFFFFFF-打开命令：|r/bgn 或 /bgnext，或在游戏设置中绑定按键。旧版 /bglite 命令仍可使用。",
    "|cffFFFFFF-快捷操作：|r右键点击输入框可清除内容。",
    "|cffFFFFFF-自动拍卖：|rALT+点击表格、背包或聊天框中的装备以打开拍卖面板。",
    "|cffFFFFFF-拍卖倒数：|r右键点击聊天框装备以开始自动倒数。（当你是团长或物品分配者时）",
}
```

Write equivalent Traditional Chinese and English text with the same claims and command list. Do not retain the upstream operations-team signature or claim that BGNext is an official pure edition.

- [ ] **Step 4: Run tests and inspect the rendered tooltip in the available client**

Run the full Lua suite. When the game is available, hover “说明书” at 100% UI scale and verify that the tooltip remains inside the screen, contains no clipped lines, and identifies `BGNext v0.1.0` separately from `BGLite 2.4.0`.

- [ ] **Step 5: Commit the guide update**

```powershell
git add Core/BGNext/ReleaseInfo.lua Locales/zhCN.lua Locales/zhTW.lua Locales/enUS.lua tests/test_release_info.lua
git commit -m "docs: replace upstream guide with BGNext manual"
```

### Task 5: Baseline, packaging and game verification

**Files:**
- Modify: `docs/baseline/BGNext-overrides.sha256`
- Modify: `CHANGELOG.md`
- Verify: all files changed by Tasks 1-4

- [ ] **Step 1: Review every changed baseline file before updating hashes**

Run:

```powershell
git diff main...HEAD -- BGLite.toc Core/BiaoGe.lua Locales/zhCN.lua Locales/zhTW.lua Locales/enUS.lua
```

Expected: only identity, slash registration, guide text, version label and declared load-order changes are present. `Core/DB/DB.lua` and the `BG.ver` auction-version send paths remain unchanged, and the standard TOC version remains `2.4.0`.

- [ ] **Step 2: Update explicit override hashes**

Use the repository’s documented baseline process to replace hashes only for the reviewed files above and add hashes for new BGNext modules. Do not regenerate or accept unrelated baseline differences.

- [ ] **Step 3: Add changelog entries**

Under the unreleased `0.1.0` section, record:

```markdown
- 将公开呼出命令改为 `/bgn` 和 `/bgnext`，并保留 `/bglite` 兼容别名。
- 将 BGNext 版本与上游 BGLite 版本分开显示。
- 增加本机重复加载保护；只有玩家确认后才禁用检测到的冲突插件并重载界面。
- 将旧 BGLite 纯净版说明替换为 BGNext 项目、兼容性、隐私边界和社区共创说明。
```

- [ ] **Step 4: Run all offline gates**

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
pwsh -NoProfile -File tools/verify-baseline.ps1
git diff --check
```

Expected: all Lua suites pass, baseline integrity passes, and `git diff --check` prints nothing.

- [ ] **Step 5: Run the in-game smoke matrix after maintenance**

Verify all of these cases and record the result in the Pull Request:

1. `/bgn`, `/bgnext` and `/bglite` each toggle the same main frame.
2. `/biaoge` and `/gbg` do not invoke BGNext.
3. The title shows `BGNext v0.1.0`; the guide separately names `BGLite 2.4.0` as upstream.
4. BGNext alone produces no conflict prompt.
5. An installed but disabled known addon produces no prompt.
6. BGNext plus an enabled known conflict lists the exact addon and prompts once.
7. “暂不处理” makes no addon-state changes and does not prompt again during that login session.
8. “只保留 BGNext 并重载” disables only the displayed conflict, keeps BGNext enabled and reloads successfully.
9. Another player using BGLite does not trigger a local conflict prompt.

- [ ] **Step 6: Commit verification metadata**

```powershell
git add CHANGELOG.md docs/baseline/BGNext-overrides.sha256
git commit -m "chore: verify BGNext startup identity changes"
```

## Follow-up boundary

The current simplified wishlist is intentionally not modified by this plan. Its replacement requires a separate original-parity plan built from a verified behavior inventory and same-state screenshots of `Core/FBUI/Hope.lua`; that plan must remove the standalone item-ID list UI while retaining the local-only privacy boundary. Equipment filtering, shopping, own-character overview, auction presets and automatic bidding each receive their own plan after the wishlist slice.
