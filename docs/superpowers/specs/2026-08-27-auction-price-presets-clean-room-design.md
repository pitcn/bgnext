# 受控自动出价（含价格配置）— 净室设计说明

- **状态**: ready_for_codex_review（设计定稿，进入 TDD 实现）
- **日期**: 2026-08-27
- **分支**: `codex/v0.1.0`
- **基线**: BGLite 2.4.0（`docs/baseline/BGNext-overrides.sha256` 19 条覆盖，本次**不修改任何基线文件**）

## 1. 目标与产品语义（维护者已裁定）

「拍卖价格预设」与「受控自动出价」是**同一个竞价方功能的两部分**，不是两个独立页面：

1. **价格配置**：本地保存；持久化「每次加价金额」与「心理最高价」两个常用值；可提供少量快捷金额。
2. **受控自动出价**：只作用于玩家当前明确参与的那一件拍卖物品；必须由用户主动以「心理最高价」启用；运行状态仅存内存（重载/重登不恢复）。
3. **不做**独立于拍卖场景的大型预设管理页；入口位于 BGLite 既有竞价拍卖框/当前物品卡内。
4. **不是**团长侧的「开始拍卖」面板（勿把起拍面板误当竞价方自动出价）。
5. 禁止后台出价、跨物品自动出价、离线出价、最后 1 秒狙击。

## 2. 知识产权边界（网易新规：新代码一律以 BGLite 为原创基线）

- **允许**：直接复用/修改仓库内 BGLite 基线代码；参考 BiaoGe 公开可见的玩家界面布局/文字层级/操作习惯；参考作者公开教程中可观察的功能流程。
- **禁止**：读取/复制/改写/翻译/移植 `C:\Users\hyk06\Downloads\BiaoGe-v2.3.5` 源码；复制 BiaoGe 独有图片/贴图/字体/素材；机械改名/洗稿/逐行改写规避相似；宣称未经证实的「100% 像素级一致」。
- 本设计**只复用** BGLite 已批准的当前拍卖通信协议（通道名、消息格式、SendMyMoney 操作码），**不新增**公开通道，**不扩展**协议。

## 3. 架构（四层，严格分离，全部净室原创）

```
Core/BGNext/AuctionPresetStore.lua        本地价格配置 + 校验（纯函数，无 Frame / 无 SavedVariables 写）
Core/BGNext/ControlledAutoBid.lua         纯状态机 + 金额计算（无 Frame / 无 SavedVariables / 无 SendAddonMessage）
Core/BGNext/AuctionBidMessage.lua         消息解析 + 合法性校验 + 节流/去重决策（纯函数）
Core/BGNext/AuctionBidUI.lua              最小 UI 扩展（渲染 + 交互；纯投影逻辑可测）
Core/BGNext/AuctionPresetRuntime.lua      薄运行时装配（仅此层触碰 WoW API：注册事件 / 装配 UI / 发消息）
```

依赖方向：`Runtime → UI → Message/Store → ControlledAutoBid`。纯核心（Store/ControlledAutoBid/Message）不依赖任何 WoW 全局，可离线测试。

运行时装配点（不修改基线，全部用既有钩子链式包裹）：

- `BG.HookCreateAuction(f)`（Auction.lua:1328，由 AuctionWAEvent.lua:592 调用）→ 链式包裹，向每个竞价框附加紧凑区域。
- `BG.AuctionWAEnd(endType, link, player, money, logs)` → 链式包裹，拍卖结束（成功/流拍/取消）时停机。
- 自注册 `CHAT_MSG_ADDON` 观察者（复用通道 `"BiaoGeAuction"`，gen1 逗号格式）→ 解析 `SendMyMoney` 喂给状态机。
- `GROUP_ROSTER_UPDATE` → 离队即停机。

## 4. 数据模型（仅价格配置写入 SavedVariables）

```
BiaoGe.BGNext.auctionPresets = {
    increment = number | nil,   -- 每次加价金额（铜，正整数）
    cap       = number | nil,   -- 心理最高价（铜，正整数）
}
```

- 仅此两个字段持久化。快捷金额由 UI 从既有递增档位表派生，**不单独持久化**（避免无谓数据）。
- `DataLifecycle.ensureRoot` 已初始化 `root.auctionPresets = {}`（DataLifecycle.lua:26），无需改动。
- **自动出价运行状态绝不出现在 SavedVariables**（见 §6 状态机 `new()` 每次返回独立内存表）。

## 5. 受控自动出价规则（14 条 → 状态机映射）

| # | 规则 | 实现 |
|---|------|------|
| 1 | 用户为当前物品输入心理最高价 | `arm()` 传入 `cap` |
| 2 | 仅用户点击「启用自动出价」后生效 | 状态机 `status` 非 `armed` 时 `onPrice` 返回 nil |
| 3 | 新价高于本人当前有效出价时 `nextBid = currentHighestBid + increment` | `nextBid(current, increment, cap)` 纯函数 |
| 4 | 仅当 `nextBid` 不超心理最高价才出价 | `nextBid > cap` → 停机（cap） |
| 5 | 达上限即停，显示「已达心理价位」 | `status="cap"` |
| 6 | 已是最高出价者不重复出价 | `onPrice` 中 `bidder == me` → hold |
| 7 | 同一价格事件不重复响应 | `lastPrice` 去重 |
| 8 | 每次自动出价节流 + 去重 | `lastBidAt` + `MIN_INTERVAL`（1s），无随机延迟 |
| 9 | 复用 BGLite 已批准当前拍卖消息格式 | `"SendMyMoney," .. auctionID .. "," .. money`，通道 `"BiaoGeAuction"` |
| 10 | 入站消息校验：发送者在当前团队 / 物品实例匹配 / 字段金额序号合法 / 非法过期重复丢弃 | `AuctionBidMessage` |
| 11 | 手动停止/成交/流拍/取消/切换物品/离队/发送者无效/重载/禁用 → 立即停机并清空 | `stop(state, reason)` |
| 12 | 登录/进团/进本/收到任何拍卖消息时绝不自动启用 | 无自动 `arm` 路径 |
| 13 | 运行状态永不写 SavedVariables | 状态机零持久化 |
| 14 | 本地价格配置仅在 `BiaoGe.BGNext` 下 | `AuctionPresetStore` 白名单写 |

## 6. 状态机（`ControlledAutoBid.lua`）

状态集合（对应界面 7 态）：

| status | 界面文案 |
|--------|---------|
| `idle` | 未启用 |
| `armed` | 自动出价中 |
| `leading` | 当前本人领先 |
| `cap` | 已达心理价位 |
| `stopped` | 已手动停止 |
| `ended` | 拍卖已结束 |
| `invalid` | 当前拍卖数据无效 |

核心 API（纯函数，无副作用）：

```lua
M.new()                                              -- 返回独立内存状态表
M.arm(state, cfg, now)                               -- 启用；cfg = {auctionId, itemId, increment, cap, currentPrice, currentBidder}
M.onPrice(state, cfg, now)                           -- 新价事件；cfg = {auctionId, price, bidder}
M.stop(state, reason)                                -- 停机；reason ∈ {user, success, unsold, cancel, change, leave, invalid, reload, disabled}
M.nextBid(current, increment, cap)                   -- 纯金额：返回 amount 或 nil + 原因
M.statusText(state)                                  -- status → 中文文案（供 UI 与测试共用）
```

`nextBid` 计算（严格遵循规则 3–5）：

```
amount = current + increment
if amount > cap  -> 返回 nil, "cap"     -- 超过心理价位即停（不与 BGLite 的"补齐到 cap"行为一致，见 §10）
if amount == cap -> 返回 amount          -- 等于心理价位时允许最后一口
return amount                            -- amount < cap 正常出价
```

`onPrice` 决策（严格顺序）：

1. `status ~= "armed"` → 返回 nil（未启用绝不出价）。
2. `auctionId ~= state.auctionId` → 返回 `{error="auction"}`（错物品/错拍卖实例拒绝）。
3. `price == state.lastPrice` → 返回 nil（重复价格去重）。
4. `price <= state.currentPrice` → 返回 nil（非新高价，忽略）。
5. 节流：`now - state.lastBidAt < MIN_INTERVAL` → 返回 nil（丢弃，不发消息）。
6. `bidder == me`（`cfg.bidder` 或 `state.self` 领先）→ `status="leading"`，返回 nil。
7. `nextBid(price, increment, cap)` → 若 `nil` → `stop(state,"cap")`，返回 nil；否则记录 `currentPrice=price`、`lastBidAt=now`、`lastPrice=price`，返回 `{bid=amount}`。

`arm` 时若当前无出价者（`currentBidder == nil`，即"起拍"），返回首口起拍价 `{bid=currentPrice}`（与 BGLite 起拍分支一致）；已有领先者则按 `onPrice` 规则计算下一口。`arm` 前校验 `increment`、`cap` 为正整数且 `cap >= increment`，否则 `status="invalid"`。

停机（`stop`）：置 `status` 为对应终态、清 `auctionId/itemId/increment/cap/currentPrice/currentBidder/lastPrice/lastBidAt`，保留 `stopReason` 供状态文案。停机后不可再出价，除非重新 `arm`。

## 7. 消息协议（复用 BGLite，不扩展）

- 通道：`"BiaoGeAuction"`（gen1）。**gen2（`BiaoGeAuction1..10` 旋转 + 脱字号 + 匿名）列为范围外/未验证**。
- 出价消息：`"SendMyMoney," .. auctionID .. "," .. money`（逗号分隔，money 为铜）。
- 入站同样解析 gen1 逗号分隔：`SendMyMoney,<auctionID>,<money>`。
- 不新增公开通道、不扩展操作码、不发送除 `SendMyMoney` 外的任何消息。

## 8. 消息解析与校验（`AuctionBidMessage.lua`）

```lua
M.parseGen1(prefix, message)                         -- "BiaoGeAuction" + "SendMyMoney,12,500000" -> {opcode="SendMyMoney", auctionId="12", money=500000}
M.validateBidEvent(parsed, ctx)                      -- ctx = {auctionId, raidMembers=set, validOpcodes, maxMoney}
```

校验规则（规则 10）：

1. `parsed` 非 nil 且 `opcode == "SendMyMoney"`；其余操作码（StartAuction/CancelAuction/…）交由既有 BGLite 处理，本适配器只关心 `SendMyMoney`。
2. `auctionId` 必须与 `state.auctionId` 完全一致（错拍卖实例丢弃）。
3. `money` 必须是正整数且 ≤ `maxMoney`（非法金额丢弃）。
4. 发送者在 `ctx.raidMembers` 中（非团队丢弃）；`SendAddonMessage` 本身只收 RAID 作用域消息，此校验是纵深防御。
5. 重复/过期（`money <= state.currentPrice`）由状态机层去重（§6 第 4 步）。

## 9. 节流与去重

- 节流：状态机 `MIN_INTERVAL = 1`（秒），`now - lastBidAt < 1` 时丢弃。**不使用** BGLite 既有 `C_Timer.NewTicker(3, …)` 轮询与 `AutoSendLate` 的随机延迟（后者为最后 1 秒狙击规避，违反规则 8 的"无高频/无狙击"）。
- 去重：`lastPrice` 记录已处理价格，同一价格不重复响应（规则 7）。
- 事件驱动，非轮询：仅在收到合法新 `SendMyMoney` 时触发一次决策。

## 10. 界面（`AuctionBidUI.lua`，最小扩展）

在既有竞价框内增加紧凑区域，至少包含：**每次加价 / 心理最高价 / 启用/停止按钮 / 当前状态文字**。

- 状态文字与 §6 七态一一对应（未启用 / 自动出价中 / 当前本人领先 / 已达心理价位 / 已手动停止 / 拍卖已结束 / 当前拍卖数据无效）。
- 编辑锁定：启用前可编辑两个输入框；启用后锁定；手动停止后恢复可编辑。
- 非法金额（非正整数、`cap < increment`）本地拦截，**不发消息**。
- 输入框/按钮/提示的颜色与尺寸沿用既有组件；未确认的像素值集中为布局常量（无散落魔法数）。
- 中文文案。不做覆盖主表格的大窗口。不宣称「原版完全一致」。

UI 分两层：纯投影函数（可测）返回 `{point, relativeTo, relativePoint, x, y, width, height, text, locked}` 等；薄帧创建代码在 `Runtime` 内仅做 `CreateFrame`/`SetPoint`/`SetScript`，不进入单元测试。

## 11. 测试清单（16 类，TDD）

| 类 | 断言 |
|----|------|
| 未启用绝不出价 | `onPrice` 在 `idle/stopped/ended/cap` 下返回 nil |
| 正确计算下一口 | `nextBid(100, 100, 1000) == 200` |
| 超上限即停 | `nextBid(950, 100, 1000)` → nil/"cap" |
| 等于上限允许最后一口 | `nextBid(900, 100, 1000) == 1000` |
| 本人领先不重复出价 | `onPrice` 且 `bidder==me` → nil + `status="leading"` |
| 重复消息不重复响应 | 同 `price` 二次 `onPrice` → nil |
| 非团队发送者拒绝 | `validateBidEvent` sender ∉ raidMembers → 丢弃 |
| 错物品/错拍卖拒绝 | `auctionId` 不匹配 → 丢弃 |
| 非法金额拒绝 | money 非正/超上限 → 丢弃 |
| 节流 | 两次 `onPrice` 间隔 < 1s → 第二次 nil |
| 用户停止 | `stop(state,"user")` → `status="stopped"`，后续不出价 |
| 成交/流拍/取消/离队/重载清空 | 各 reason → 对应终态 + 清运行态；`M.new()` 每次独立 |
| 运行态不持久化 | 状态机源码无 `BiaoGe`/`SavedVariables` 引用（源码扫描） |
| 仅价格配置写 `BiaoGe.BGNext` | Store 源码仅白名单字段；`ensureRoot` 无需改动 |
| 无新增上传/遥测/跨团历史/玩家数据 | 全模块源码扫描禁串 `SendChatMessage`/`C_ChatInfo`(除 `SendAddonMessage`)/`COMBAT_LOG_EVENT`/`NotifyInspect` 等 |

测试文件：`tests/test_auction_preset_store.lua`、`tests/test_controlled_auto_bid.lua`、`tests/test_auction_bid_message.lua`、`tests/test_auction_bid_ui.lua`；注册进 `tests/run.lua`。

## 12. 范围边界（明确声明，避免过度承诺）

- **gen1 模式**（普通模式）为目标；gen2 / 匿名拍卖**未验证、范围外**。
- 本次**不修改任何基线文件**（BGLite.toc 已含 `Core\BGNext` 加载路径；模块加载顺序早于 AuctionWA.lua，故在 `BG.Init` 回调内取 `BGA.aura_env`）。
- 既有 BGLite 自动出价（`isAuto`/`autoTimer` 3s 轮询 / `AutoSendLate` 随机延迟）**本次不替换、不中和**：受控自动出价是并行的更安全路径。二者的共存与中和（如需）列为**实机验证后续项**，不阻塞本设计。
- 实机验证（真实客户端）**不可用**，按规则标记为 unverified。

## 13. 数据清单更新

`docs/security/data-inventory.md` 第 18 行 `auctionPresets` 需更新为：

| 字段 | 内容 | 用途 | 保留期限 | 访问/使用 | 删除 | 敏感度 |
|------|------|------|---------|-----------|------|--------|
| auctionPresets.increment / auctionPresets.cap | 用户输入的正整数加价/最高价 | 受控自动出价的默认价格配置 | 本地直至用户清除 | 用户启用受控自动出价时读取；运行时状态不落盘 | 手动清除 | Medium |
