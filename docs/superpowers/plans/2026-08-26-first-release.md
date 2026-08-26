# BGNext First Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 BGLite 2.4.0 基线上交付 BGNext 首版，提供熟悉布局的九项用户功能、最近一次团本七日结算记录、受控自动出价和全部声明版本的明确兼容状态。

**Architecture:** 保留 BGLite 基础拍卖、账单和协议能力，把新增逻辑放入 `Core/BGNext/` 小模块。数据写入 `BiaoGe.BGNext`，运行期自动出价状态只存在内存；纯逻辑模块使用 Lua 5.1 测试，WoW API 通过薄适配层接入。

**Tech Stack:** World of Warcraft Lua 5.1、WoW Frame/XML API、SavedVariables、PowerShell、GitHub Actions、现有 BGLite 库。

---

## 本地测试前置条件

当前 Windows 环境尚未安装 Lua 命令行。执行 Task 1 前安装与 WoW Lua 版本一致的 Lua for Windows 5.1：

```powershell
winget install --id rjpcomputing.luaforwindows --exact --scope user --accept-package-agreements --accept-source-agreements
```

安装后重新打开终端并运行 `lua -v`，预期输出包含 `Lua 5.1`。GitHub Actions 使用 Ubuntu 的 `lua5.1` 包，不依赖本地安装。

## 交付分组

本计划按依赖关系分为五个可独立验证的交付组：

1. 安全基础：测试框架、模块加载、数据生命周期和七日结算约束；
2. 社区与个人功能：关于、更新日志、感谢名单、心愿、过滤、购物清单、角色总览；
3. 拍卖增强：价格预设和受控自动出价；
4. 界面与协议：熟悉布局、BGLite 混用和安全降级；
5. 全版本验证与发布。

实施在 `codex/v0.1.0` 分支完成。任何阶段不得以刷新覆盖哈希的方式掩盖未说明的 BGLite 文件修改。

## 每个任务的提交门禁

每个任务新建测试文件后，必须把该文件路径追加到 `tests/run.lua` 的 `suites` 数组；提交前必须依次执行：

```powershell
pwsh -NoProfile -File tools/run-lua-tests.ps1
pwsh -NoProfile -File tools/verify-baseline.ps1
git diff --check
```

预期结果分别为 `failed=0`、基线验证通过、无格式错误。修改任何 BGLite 基线文件时，先审阅该文件的实际差异，再用 `Get-FileHash -Algorithm SHA256` 更新 `docs/baseline/BGNext-overrides.sha256` 中对应且仅对应的条目；禁止批量接受未知差异。

### Task 1: 建立 Lua 测试框架和 BGNext 模块入口

**Files:**
- Create: `tests/testlib.lua`
- Create: `tests/run.lua`
- Create: `tests/test_init.lua`
- Create: `tools/run-lua-tests.ps1`
- Create: `Core/BGNext/Init.lua`
- Modify: `BGLite.toc`
- Create: `.github/workflows/lua-tests.yml`

- [ ] **Step 1: 创建失败的模块入口测试**

```lua
-- tests/test_init.lua
return function(test)
    BG = nil
    dofile("Core/BGNext/Init.lua")
    test.eq(type(BG.BGNext), "table", "BG.BGNext namespace")
    test.eq(BG.BGNext.schemaVersion, 1, "schema version")
end
```

- [ ] **Step 2: 创建最小测试运行器**

```lua
-- tests/testlib.lua
local T = { passed = 0, failed = 0 }
function T.eq(actual, expected, label)
    if actual ~= expected then
        error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end
function T.run(name, fn)
    local ok, err = pcall(fn, T)
    if ok then T.passed = T.passed + 1 else T.failed = T.failed + 1; io.stderr:write(name .. ": " .. err .. "\n") end
end
return T
```

```lua
-- tests/run.lua
local T = dofile("tests/testlib.lua")
local suites = { "tests/test_init.lua" }
for _, path in ipairs(suites) do T.run(path, dofile(path)) end
print(string.format("passed=%d failed=%d", T.passed, T.failed))
if T.failed > 0 then os.exit(1) end
```

```powershell
# tools/run-lua-tests.ps1
$ErrorActionPreference = "Stop"
$lua = Get-Command lua5.1, lua -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $lua) { throw "Lua 5.1 is required. Install rjpcomputing.luaforwindows." }
& $lua.Source tests/run.lua
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
```

- [ ] **Step 3: 在 Lua 5.1 中验证测试失败**

Run: `pwsh -NoProfile -File tools/run-lua-tests.ps1`

Expected: FAIL，错误包含 `cannot open Core/BGNext/Init.lua`。

- [ ] **Step 4: 实现模块入口**

```lua
-- Core/BGNext/Init.lua
BG = BG or {}
BG.BGNext = BG.BGNext or {}
BG.BGNext.schemaVersion = 1
return BG.BGNext
```

在 `BGLite.toc` 的 `Core\DB\DB.xml` 后加入：

```text
Core\BGNext\Init.lua
```

- [ ] **Step 5: 添加 CI**

```yaml
name: Lua tests
on:
  workflow_dispatch:
  push:
    branches: [main, "codex/**"]
  pull_request:
    branches: [main]
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - run: sudo apt-get update && sudo apt-get install -y lua5.1
      - run: lua5.1 tests/run.lua
```

- [ ] **Step 6: 验证并提交**

Run: `pwsh -NoProfile -File tools/run-lua-tests.ps1`

Expected: `passed=1 failed=0`。

Run: `pwsh -NoProfile -File tools/verify-baseline.ps1`

Expected: 仅在把 `BGLite.toc` 加入明确覆盖清单后通过。

```powershell
git add Core/BGNext/Init.lua tests tools/run-lua-tests.ps1 .github/workflows/lua-tests.yml BGLite.toc docs/baseline/BGNext-overrides.sha256
git commit -m "test: establish BGNext Lua harness"
```

### Task 2: 实现数据根和最近一次团本七日生命周期

**Files:**
- Create: `Core/BGNext/DataLifecycle.lua`
- Create: `tests/test_data_lifecycle.lua`
- Modify: `tests/run.lua`
- Modify: `BGLite.toc`

- [ ] **Step 1: 写入生命周期失败测试**

```lua
-- tests/test_data_lifecycle.lua
return function(test)
    BG = { BGNext = {} }
    local life = dofile("Core/BGNext/DataLifecycle.lua")
    local root = life.ensureRoot({})
    life.beginSettlement(root, "raid-a", 100)
    root.currentSettlement.trades[1] = { amount = 100 }
    life.beginSettlement(root, "raid-a", 200)
    test.eq(#root.currentSettlement.trades, 1, "same raid preserved")
    life.beginSettlement(root, "raid-b", 300)
    test.eq(#root.currentSettlement.trades, 0, "new raid clears old data")
    root.currentSettlement.trades[1] = { amount = 200 }
    test.eq(life.purgeExpired(root, 300 + 7 * 86400 - 1), false, "before expiry")
    test.eq(life.purgeExpired(root, 300 + 7 * 86400), true, "at expiry")
    test.eq(#root.currentSettlement.trades, 0, "expired trades cleared")
end
```

- [ ] **Step 2: 运行测试确认失败**

Run: `pwsh -NoProfile -File tools/run-lua-tests.ps1`

Expected: FAIL，错误包含 `cannot open Core/BGNext/DataLifecycle.lua`。

- [ ] **Step 3: 实现数据生命周期**

```lua
-- Core/BGNext/DataLifecycle.lua
BG = BG or {}; BG.BGNext = BG.BGNext or {}
local M, MAX_AGE = {}, 7 * 86400
local function emptySettlement()
    return { raidId = nil, startedAt = nil, expiresAt = nil, trades = {}, mails = {} }
end
function M.ensureRoot(saved)
    saved.BGNext = saved.BGNext or {}
    local root = saved.BGNext
    root.schemaVersion = 1
    root.settings = root.settings or {}
    root.wishlist = root.wishlist or {}
    root.equipmentFilters = root.equipmentFilters or {}
    root.ownCharacters = root.ownCharacters or {}
    root.currentRaid = root.currentRaid or {}
    root.auctionPresets = root.auctionPresets or {}
    root.currentSettlement = root.currentSettlement or emptySettlement()
    return root
end
function M.clearSettlement(root)
    root.currentSettlement = emptySettlement()
end
function M.beginSettlement(root, raidId, now)
    local current = root.currentSettlement
    if current.raidId ~= raidId or (current.expiresAt and now >= current.expiresAt) then
        M.clearSettlement(root)
        current = root.currentSettlement
        current.raidId, current.startedAt, current.expiresAt = raidId, now, now + MAX_AGE
    end
    return current
end
function M.purgeExpired(root, now)
    local expiresAt = root.currentSettlement.expiresAt
    if expiresAt and now >= expiresAt then M.clearSettlement(root); return true end
    return false
end
BG.BGNext.DataLifecycle = M
return M
```

- [ ] **Step 4: 在插件加载时初始化但不迁移旧历史**

在文件末尾增加：

```lua
if BG.Init then
    BG.Init(function()
        BiaoGe = type(BiaoGe) == "table" and BiaoGe or {}
        BG.BGNext.DB = M.ensureRoot(BiaoGe)
        M.purgeExpired(BG.BGNext.DB, time())
    end)
end
```

- [ ] **Step 5: 验证并提交**

Run: `pwsh -NoProfile -File tools/run-lua-tests.ps1`

Expected: 所有测试通过。

```powershell
git add Core/BGNext/DataLifecycle.lua tests BGLite.toc docs/baseline/BGNext-overrides.sha256
git commit -m "feat: enforce single-settlement retention"
```

### Task 3: 收口现有交易、邮件和历史记录

**Files:**
- Create: `Core/BGNext/CurrentTrade.lua`
- Create: `Core/BGNext/CurrentMail.lua`
- Create: `tests/test_current_settlement.lua`
- Modify: `tests/run.lua`
- Modify: `BGLite.toc`
- Modify: `Core/BiaoGe.lua`

- [ ] **Step 1: 写入最小数据测试**

```lua
return function(test)
    BG = { BGNext = {} }
    local life = dofile("Core/BGNext/DataLifecycle.lua")
    local trade = dofile("Core/BGNext/CurrentTrade.lua")
    local mail = dofile("Core/BGNext/CurrentMail.lua")
    local root = life.ensureRoot({})
    life.beginSettlement(root, "raid-a", 100)
    test.eq(trade.append(root, { raidId="raid-a", player="甲", itemId=1, amount=100, time=101, status="complete" }), true)
    test.eq(trade.append(root, { raidId="raid-b", player="乙", amount=200, time=102 }), false)
    test.eq(mail.append(root, { raidId="raid-a", player="甲", itemId=1, amount=100, time=103, status="sent", body="secret" }), true)
    test.eq(root.currentSettlement.mails[1].body, nil, "mail body discarded")
end
```

- [ ] **Step 2: 实现只接受当前团本的追加函数**

`CurrentTrade.lua` 和 `CurrentMail.lua` 必须复制允许字段到新表，不得直接保存传入对象。允许字段分别为：

```lua
local TRADE_FIELDS = { "player", "itemId", "amount", "time", "status" }
local MAIL_FIELDS = { "player", "itemId", "amount", "time", "status", "direction" }
```

两者统一拒绝 `record.raidId ~= root.currentSettlement.raidId`、缺失时间或无法确认玩家名的记录。

- [ ] **Step 3: 替换旧入口**

从 `BGLite.toc` 移除：

```text
Core\Module\TradeHistory.lua
Core\Module\MailHistory.lua
```

加入：

```text
Core\BGNext\CurrentTrade.lua
Core\BGNext\CurrentMail.lua
```

在 `Core/BiaoGe.lua` 保留原入口位置，但将标题改为“交易记录（当前团）”和“邮件记录（当前团）”，内容源改为 `BiaoGe.BGNext.currentSettlement`。不得读取 `BiaoGe.tradeHistory` 或 `BiaoGe.mailHistory`。

- [ ] **Step 4: 验证旧数据保持但不再被读取**

增加测试存档，其中包含 `tradeHistory`、`mailHistory` 和 `History`；初始化后断言这些字段仍存在，`BGNext.currentSettlement` 为空且没有引用旧表。

- [ ] **Step 5: 验证并提交**

Run: `pwsh -NoProfile -File tools/run-lua-tests.ps1`

Expected: 所有测试通过。

```powershell
git add Core/BGNext Core/BiaoGe.lua BGLite.toc tests docs/baseline/BGNext-overrides.sha256
git commit -m "feat: scope settlement records to one raid"
```

### Task 4: 添加关于、更新日志和感谢名单

**Files:**
- Create: `Core/BGNext/About.lua`
- Create: `Core/BGNext/ReleaseInfo.lua`
- Create: `tests/test_release_info.lua`
- Modify: `tests/run.lua`
- Modify: `Core/BiaoGe.lua`
- Modify: `BGLite.toc`
- Modify: `CONTRIBUTORS.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: 写入静态内容完整性测试**

```lua
return function(test)
    BG = { BGNext = {} }
    local info = dofile("Core/BGNext/ReleaseInfo.lua")
    test.eq(info.projectName, "BGNext")
    test.eq(info.author, "国服社区共创")
    test.eq(type(info.changelog), "table")
    test.eq(type(info.credits.upstream), "table")
    test.eq(info.official, false)
end
```

- [ ] **Step 2: 实现本地静态数据**

```lua
local info = {
    projectName = "BGNext",
    author = "国服社区共创",
    official = false,
    changelog = { "首个社区共创版本", "完整变更以发布说明为准" },
    credits = { upstream = { "CQZS (Lite) — BGLite 2.4.0 上游作者" }, contributors = {} },
}
BG.BGNext.ReleaseInfo = info
return info
```

- [ ] **Step 3: 实现三个小按钮和只读滚动面板**

`About.lua` 使用现有 `BG.CreateButton`、`BG.CreateMainFrame` 和 `UIPanelScrollFrameTemplate`。三个按钮必须固定在主界面底部，不打开网页、不包含远程内容，按钮文字为“关于”“更新日志”“感谢名单”。

- [ ] **Step 4: 修改作者元数据**

将 `BGLite.toc` 中作者改为：

```text
## Author: 国服社区共创
## X-Upstream-Author: CQZS (Lite)
```

- [ ] **Step 5: 验证并提交**

Run: `pwsh -NoProfile -File tools/run-lua-tests.ps1`

Expected: 所有测试通过。

```powershell
git add Core/BGNext Core/BiaoGe.lua BGLite.toc tests CONTRIBUTORS.md CHANGELOG.md docs/baseline/BGNext-overrides.sha256
git commit -m "feat: add project and contributor panels"
```

### Task 5: 实现个人心愿清单

**Files:**
- Create: `Core/BGNext/Wishlist.lua`
- Create: `tests/test_wishlist.lua`
- Modify: `tests/run.lua`
- Modify: `Core/BiaoGe.lua`
- Modify: `Core/Module/Loot.lua`
- Modify: `Core/Module/Auction.lua`
- Modify: `BGLite.toc`

- [ ] **Step 1: 写入角色隔离和提醒测试**

测试必须证明同一服务器两个本人角色的清单隔离、添加重复物品幂等、取消只影响当前角色、`contains` 只返回布尔值且不产生通信。

```lua
test.eq(wish.add(root, "realm", "A", "ICC", 5001), true)
test.eq(wish.add(root, "realm", "A", "ICC", 5001), false)
test.eq(wish.contains(root, "realm", "A", "ICC", 5001), true)
test.eq(wish.contains(root, "realm", "B", "ICC", 5001), false)
```

- [ ] **Step 2: 实现纯本地清单 API**

导出 `add`、`remove`、`clear`、`contains` 和 `list`。键路径固定为 `wishlist[realmId][player][raidId][itemId] = true`，不得保存其他玩家名或发送插件消息。

- [ ] **Step 3: 连接熟悉布局**

在原版对应页签位置创建心愿页；保留 ALT+左键添加、右键取消、清空确认和装备出现提醒。声音只使用 BGLite 已有且权利清晰的本地声音。

- [ ] **Step 4: 连接掉落和拍卖提醒**

`Loot.lua` 与 `Auction.lua` 只调用 `Wishlist.contains`。不得实现心愿分享、竞争查询或其他玩家心愿汇总。

- [ ] **Step 5: 验证并提交**

Run: `pwsh -NoProfile -File tools/run-lua-tests.ps1`

Expected: 所有测试通过。

```powershell
git add Core/BGNext/Wishlist.lua Core/BiaoGe.lua Core/Module/Loot.lua Core/Module/Auction.lua BGLite.toc tests docs/baseline/BGNext-overrides.sha256
git commit -m "feat: add private wishlists"
```

### Task 6: 实现装备过滤和当前团本购物清单

**Files:**
- Create: `Core/BGNext/EquipmentFilter.lua`
- Create: `Core/BGNext/CurrentShopping.lua`
- Create: `tests/test_equipment_filter.lua`
- Create: `tests/test_current_shopping.lua`
- Modify: `tests/run.lua`
- Modify: `Core/Module/Auction.lua`
- Modify: `Core/Module/Trade.lua`
- Modify: `BGLite.toc`

- [ ] **Step 1: 写入过滤三态测试**

`classify(character, item)` 只允许返回 `"recommended"`、`"dimmed"` 或 `"unknown"`。缺失职业、护甲类型或 API 元数据时必须返回 `"unknown"`。

- [ ] **Step 2: 实现过滤规则和手动覆盖**

规则输入只包含本人职业、专精、护甲和武器能力以及物品元数据。自定义覆盖保存在 `equipmentFilters[realmId][player]`，不得接受其他玩家作为目标。

- [ ] **Step 3: 写入购物清单重置测试**

测试同一 raidId 追加本人购买，切换 raidId 后旧项目清空；传入非本人买家时返回 `false`。

- [ ] **Step 4: 实现购物清单**

记录字段仅为 `itemId`、`itemLink`、`amount`、`time`。数据写入 `currentRaid.purchases`，开始新团时由 `DataLifecycle` 清空。

- [ ] **Step 5: 连接界面并提交**

拍卖界面只改变本地显示状态；交易完成时只为本人添加购物记录。

Run: `pwsh -NoProfile -File tools/run-lua-tests.ps1`

Expected: 所有测试通过。

```powershell
git add Core/BGNext Core/Module/Auction.lua Core/Module/Trade.lua BGLite.toc tests docs/baseline/BGNext-overrides.sha256
git commit -m "feat: add personal gear and shopping tools"
```

### Task 7: 实现自有角色总览

**Files:**
- Create: `Core/BGNext/OwnCharacters.lua`
- Create: `tests/test_own_characters.lua`
- Modify: `tests/run.lua`
- Modify: `Core/DB/Init2.lua`
- Modify: `Core/BiaoGe.lua`
- Modify: `Bindings.xml`
- Modify: `BGLite.toc`

- [ ] **Step 1: 写入只接受本人登录快照的测试**

`recordLogin(root, snapshot)` 必须要求 `snapshot.isPlayer == true`，并只复制 `realmId`、`player`、`class`、`level`、`itemLevel`、`equipment`、`lockouts` 和 `updatedAt`。

- [ ] **Step 2: 实现快照存储和删除**

键路径为 `ownCharacters[realmId][player]`。提供 `recordLogin`、`list` 和 `remove`，不提供查询其他玩家或通信方法。

- [ ] **Step 3: 创建 WoW API 适配器**

在 `PLAYER_LOGIN` 或现有 `BG.Init3` 中只采集 `unit="player"`；API 缺失时省略对应字段，不阻止插件加载。

- [ ] **Step 4: 实现熟悉布局与快捷键**

沿用原版角色总览的栏目顺序、固定窗口、排序和右键删除习惯。移除其他玩家备注、评价和外部数据。

- [ ] **Step 5: 验证并提交**

Run: `pwsh -NoProfile -File tools/run-lua-tests.ps1`

Expected: 所有测试通过。

```powershell
git add Core/BGNext/OwnCharacters.lua Core/DB/Init2.lua Core/BiaoGe.lua Bindings.xml BGLite.toc tests docs/baseline/BGNext-overrides.sha256
git commit -m "feat: add self-only character overview"
```

### Task 8: 实现拍卖预设

**Files:**
- Create: `Core/BGNext/AuctionPreset.lua`
- Create: `tests/test_auction_preset.lua`
- Modify: `tests/run.lua`
- Modify: `Core/BiaoGe.lua`
- Modify: `Core/Module/AuctionWA.lua`
- Modify: `BGLite.toc`

- [ ] **Step 1: 写入价格校验测试**

覆盖正整数步进、最高价必须不低于当前价、非法字符串、负数、零和超出 WoW 安全整数范围。`nextBid(current, increment, cap)` 超过 cap 时返回 `nil, "cap"`。

- [ ] **Step 2: 实现纯价格 API**

导出 `validate`、`save`、`remove`、`list` 和 `nextBid`。预设只保存名称、步进和最高价，不保存其他玩家或物品历史价格。

- [ ] **Step 3: 实现熟悉的预设页**

沿用原版页签位置、预设列表、编辑框和启用操作；显示当前步进、最高价和下一口预览。

- [ ] **Step 4: 验证并提交**

Run: `pwsh -NoProfile -File tools/run-lua-tests.ps1`

Expected: 所有测试通过。

```powershell
git add Core/BGNext/AuctionPreset.lua Core/BiaoGe.lua Core/Module/AuctionWA.lua BGLite.toc tests docs/baseline/BGNext-overrides.sha256
git commit -m "feat: add personal auction presets"
```

### Task 9: 实现受控自动出价状态机

**Files:**
- Create: `Core/BGNext/AutoBid.lua`
- Create: `tests/test_auto_bid.lua`
- Modify: `tests/run.lua`
- Modify: `Core/Module/AuctionWA.lua`
- Modify: `Core/Module/AuctionWAEvent.lua`
- Modify: `BGLite.toc`

- [ ] **Step 1: 写入状态机失败测试**

测试必须覆盖 `IDLE → ARMED → WAITING → BID_PENDING → BID_SENT → WAITING`，以及用户取消、换物品、离团、协议异常、发送失败、达到上限和重载导致 `STOPPED`。

```lua
local state = auto.new()
test.eq(auto.arm(state, { auctionId="a", itemId=1, current=100, increment=100, cap=500 }), true)
test.eq(state.status, "ARMED")
test.eq(auto.onPrice(state, "a", 200), 300)
test.eq(state.status, "BID_PENDING")
auto.stop(state, "user")
test.eq(state.status, "STOPPED")
test.eq(state.stopReason, "user")
```

- [ ] **Step 2: 实现不持久化的状态机**

模块只返回内存对象，不访问 `BiaoGe`。所有事件处理函数先校验 auctionId 和 itemId；任何未知事件调用 `stop(state, "protocol")`。

- [ ] **Step 3: 用依赖注入连接现有发送路径**

适配器只接收 `sendBid(amount)` 函数。状态机不得直接调用聊天 API；发送成功后调用 `onBidSent`，失败调用 `stop(state, "send-failed")`。

- [ ] **Step 4: 实现持续可见的控制界面**

当前拍卖界面显示“开启自动出价/取消自动出价”、最高价、步进、下一口和停止原因。每件物品必须重新启用；关闭界面、离团和 `PLAYER_LEAVING_WORLD` 均停止。

- [ ] **Step 5: 验证无隐藏卡秒或随机化**

Run: `rg -n "math\.random|C_Timer\.NewTicker|后台|离线|卡秒" Core/BGNext/AutoBid.lua Core/Module/AuctionWA.lua`

Expected: 新自动出价路径不包含随机化、持久 ticker 或隐藏运行逻辑；如现有 BGLite 代码命中，必须在 PR 中逐项说明并证明不属于 BGNext 新路径。

- [ ] **Step 6: 验证并提交**

Run: `pwsh -NoProfile -File tools/run-lua-tests.ps1`

Expected: 自动出价状态机全部测试通过。

```powershell
git add Core/BGNext/AutoBid.lua Core/Module/AuctionWA.lua Core/Module/AuctionWAEvent.lua BGLite.toc tests docs/baseline/BGNext-overrides.sha256
git commit -m "feat: add bounded per-auction auto bidding"
```

### Task 10: 完成界面一致性和模块开关

**Files:**
- Create: `Core/BGNext/ModuleRegistry.lua`
- Create: `tests/test_module_registry.lua`
- Modify: `tests/run.lua`
- Modify: `Core/BiaoGe.lua`
- Modify: `Core/Options.lua`
- Modify: `BGLite.toc`

- [ ] **Step 1: 测试模块独立启停**

注册表必须允许九个用户模块独立启用和禁用；`DataLifecycle` 始终启用，记录型模块依赖它。一个模块初始化抛错时，注册表记录本地错误并继续初始化其他模块。

- [ ] **Step 2: 实现模块注册表**

导出 `register(name, init, options)`、`enable(name)`、`disable(name)` 和 `initializeAll()`。错误对象只保存在本次会话内，不上传、不包含聊天或玩家数据。

- [ ] **Step 3: 按原版习惯检查界面**

逐页记录页签位置、字段顺序、按钮位置、快捷操作和反馈方式。只对这些功能性布局做一致化；颜色、纹理、图标和长文案使用 BGNext 自有实现。

- [ ] **Step 4: 验证并提交**

Run: `pwsh -NoProfile -File tools/run-lua-tests.ps1`

Expected: 模块隔离和失败降级测试通过。

```powershell
git add Core/BGNext/ModuleRegistry.lua Core/BiaoGe.lua Core/Options.lua BGLite.toc tests docs/baseline/BGNext-overrides.sha256
git commit -m "feat: isolate BGNext feature modules"
```

### Task 11: 建立全版本适配和兼容矩阵

**Files:**
- Create: `Core/BGNext/Compatibility.lua`
- Create: `tests/test_compatibility.lua`
- Modify: `tests/run.lua`
- Create: `docs/COMPATIBILITY.md`
- Modify: `BGLite.toc`

- [ ] **Step 1: 测试全部声明接口映射**

测试包含 `11508, 11509, 20506, 30405, 38002, 40402, 50503, 50504, 50505, 120005, 120007, 120100`，每个值必须映射到明确的客户端系列和能力集合。

- [ ] **Step 2: 实现版本适配层**

导出 `detect(interfaceVersion)` 和能力标记，例如 `hasSpecialization`、`hasModernAddonAPI`、`hasRaidLockoutAPI`。功能模块只读取能力标记，不散布版本号判断。

- [ ] **Step 3: 创建兼容矩阵**

`docs/COMPATIBILITY.md` 对每个接口记录“代码覆盖、自动测试、模拟验证、实机验证、已知限制”。没有实机证据时必须写“未实机验证”。

- [ ] **Step 4: 执行 BGLite 混用测试**

至少准备两套客户端：团长使用 BGNext、团员使用 BGLite；交换角色后再测一次。记录拍卖开始、普通出价、自动出价、顶价、取消、流拍和结束消息。

- [ ] **Step 5: 验证并提交**

Run: `pwsh -NoProfile -File tools/run-lua-tests.ps1`

Expected: 全部接口映射测试通过。

```powershell
git add Core/BGNext/Compatibility.lua BGLite.toc tests docs/COMPATIBILITY.md docs/baseline/BGNext-overrides.sha256
git commit -m "test: define full client compatibility matrix"
```

### Task 12: 发布前审计和首版打包

**Files:**
- Create: `tools/package-release.ps1`
- Create: `docs/release/V0.1.0-CHECKLIST.md`
- Modify: `README.md`
- Modify: `PRIVACY.md`
- Modify: `SECURITY.md`
- Modify: `docs/COMPLIANCE.md`
- Modify: `CHANGELOG.md`
- Modify: `CONTRIBUTORS.md`
- Modify: `addon_version.txt`
- Modify: `BGLite.toc`

- [ ] **Step 1: 编写发布清单**

清单逐项覆盖：数据字段、七日清理、本人角色边界、自动出价停止条件、BGLite 混用、全部接口状态、第三方素材、Lua 错误、已知问题和贡献者。

- [ ] **Step 2: 编写确定性打包脚本**

脚本只把 `BGLite.toc`、`addon_version.txt`、`Bindings.xml`、`Templates.xml`、`Core/`、`Libs/`、`Locales/`、`Media/` 放入名为 `BGLite` 的发布目录，排除 `.git`、`docs`、`tests`、`tools` 和仓库治理文件，并生成 SHA-256。

- [ ] **Step 3: 更新公开政策和变更说明**

公开文档必须写明：最近一次团本结算最长七日、开始新团自动覆盖、邮件正文不保存、自动出价不持久化、无游戏外上传、全部版本的实际验证状态。

- [ ] **Step 4: 执行完整验证**

Run: `pwsh -NoProfile -File tools/run-lua-tests.ps1`

Expected: `failed=0`。

Run: `pwsh -NoProfile -File tools/verify-baseline.ps1`

Expected: 所有未覆盖上游文件保持基线哈希，所有覆盖文件与明确覆盖清单一致。

Run: `git diff --check`

Expected: 无输出，退出码 0。

Run: `pwsh -NoProfile -File tools/package-release.ps1 -Version 0.1.0`

Expected: 生成 `dist/BGNext-0.1.0.zip` 和对应 SHA-256；压缩包内顶层插件目录为 `BGLite`。

- [ ] **Step 5: 实机验收**

在每个可取得的客户端中执行：首次安装、旧存档升级、重载、离团、新团覆盖、七日过期模拟、心愿提醒、装备过滤、购物记录、角色总览、交易/邮件核对、普通拍卖和自动出价停止场景。无法取得的客户端在兼容矩阵中保留“未实机验证”。

- [ ] **Step 6: 提交发布候选**

```powershell
git add tools docs README.md PRIVACY.md SECURITY.md CHANGELOG.md CONTRIBUTORS.md addon_version.txt BGLite.toc docs/baseline/BGNext-overrides.sha256
git commit -m "release: prepare BGNext 0.1.0"
```

## 最终验收

- 所有 Lua 自动测试通过；
- 基线及明确覆盖验证通过；
- 九个用户功能可独立禁用；
- 数据生命周期不可绕过；
- 不存在跨团历史表格或玩家画像入口；
- 当前结算同一时间只有一组，最长七日；
- 自动出价不跨拍卖、不跨登录、不隐藏运行；
- BGLite 基础拍卖混用测试有证据；
- 全部声明接口都有明确验证状态；
- 发布包不包含测试、仓库治理文件或未授权素材。
