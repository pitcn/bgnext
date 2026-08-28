# 当前团交易与邮件核对 — 净室设计与实现说明

- **状态**: ready_for_codex_review（TDD 实现完成，实机验收未做）
- **日期**: 2026-08-27
- **分支**: `codex/v0.1.0`
- **基线**: BGLite 2.4.0（本次修改 6 个已声明覆盖文件：`BGLite.toc`、`Core/BiaoGe.lua`、`Core/Module/SendMail.lua`、`Locales/zhCN.lua`、`Locales/zhTW.lua`、`Locales/enUS.lua`，逐文件更新哈希）
- **实机验证**: **unverified**（无法访问真实客户端）

## 1. 目标与范围

把已有的数据层（`CurrentTrade.lua` / `CurrentMail.lua` / `DataLifecycle.lua` 的 `currentSettlement`）做成玩家真正可用的两张表：

1. **交易记录（当前团）**：物品 / 交易对象 / 金额 / 时间 / 状态。
2. **邮件记录（当前团）**：物品 / 收件人或发件人 / 金额 / 时间 / 方向 / 状态。

**明确不做**：不重建「当前团本个人购物清单」。该能力由 BGLite 既有「拍卖记录 → 我买的」提供，由 `tests/test_current_purchases.lua` 覆盖；本次只复核其测试仍然通过，不新建 `CurrentShopping.lua`，不加第二个购物清单窗口，不改动已经正常工作的筛选。

## 2. 数据边界（硬约束，全部由代码强制）

| 约束 | 实现位置 |
|------|---------|
| 只保留**一个**当前或最近一次未结算团本 | `DataLifecycle.beginSettlement` 在 `raidId` 变化时直接覆盖，不追加 |
| **最长七日** | `currentSettlement.expiresAt`；`DataLifecycle.purgeExpired` |
| 新结算 / 用户清空 / 满七日 / 不属于当前团 任一先到即清除 | `beginSettlement`（新）/ `clearSettlement`（用户）/ `purgeExpired`（七日）/ `isCurrent` 的 `raidId` 校验（归属） |
| 交易字段白名单 `player, itemId, amount, time, status` | `CurrentTrade.lua` 的 `FIELDS`，逐字段重建副本 |
| 邮件字段白名单 `player, itemId, amount, time, status, direction` | `CurrentMail.lua` 的 `FIELDS` |
| `raidId` 只作归属校验，**不复制进记录** | `append` 只拷贝 `FIELDS`，`raidId` 仅存在于 `currentSettlement.raidId` |
| `status` / `direction` 只接受枚举值，拒绝自由文本 | 两个模块的 `STATUS` / `DIRECTION` 值白名单 |
| 重复事件不产生第二行 | 两个模块的 `isDuplicate`（全白名单字段相等即拒绝） |
| **不保存邮件主题或正文** | `recordMail` 只接受 `player` / `itemId` / `amount`；无主题/正文入参 |
| **不读取历史** | 全仓不出现 `BiaoGe.tradeHistory` / `BiaoGe.mailHistory` / `BiaoGe.History` / `GetInboxText`（测试内源码扫描） |
| **不做玩家统计** | 投影层零聚合、零分组、零排行；一条记录一行 |
| **不新增通信** | 无 `SendAddonMessage` / `SendChatMessage` / HTTP / 遥测（测试内源码扫描） |
| 无法可靠确认归属就忽略 | `activeSettlement` 返回 nil 即整体放弃写入，绝不猜测 |

## 3. 架构（三层，严格分层）

```
数据白名单层  Core/BGNext/CurrentTrade.lua           字段+值白名单、归属校验、去重（已有，本次加固）
              Core/BGNext/CurrentMail.lua
              Core/BGNext/DataLifecycle.lua          单团 + 七日保留（已有，未改）

纯投影层      Core/BGNext/CurrentSettlementView.lua   只读 currentSettlement，排序/格式化/空态（新增，纯函数）

UI/运行时层   Core/BGNext/CurrentSettlementUI.lua     渲染 + 用户操作（新增）
              Core/BGNext/CurrentSettlementRuntime.lua 只挂 BGLite 既有成功结果（新增）
```

依赖方向：`Runtime → 白名单层`、`UI → View → 白名单层`。View 与 UI 的纯函数部分不依赖任何 WoW 全局，可离线测试；`CreateFrame` 只出现在 UI 的函数体内。事件监听、数据清洗、Frame 创建分处三个文件。

## 4. 团本归属判定（关键设计，无新增字段）

BGLite 已经在击杀 Boss 时给当前表格盖了团队名单时间戳：`BiaoGe[<表格>].raidRoster = { time, realm, roster }`（`Core/Module/Loot.lua:312`），并在 `BG.ClearBiaoGe("biaoge", FB)` 时清除（`ClearBiaoGe.lua:72`）。本次**复用该已有戳**，不生成新标识、不复制名单内容：

```
raidId = <表格键> .. "@" .. <raidRoster.time>
```

判定分两级，刻意不对称：

- **建立**结算（`M.raidId`）要求证据完整：`IsInRaid(1)` 为真、`BG.FB1` 为非空字符串、该表格已有 `raidRoster.time`、`raidRoster.realm` 与当前服务器一致（两者都已知时）、戳距今不足七日。任一不满足 → 返回 nil，**不建立**结算。
- **追加**记录只要求：已有未过期结算，且事件来自插件已确认的成功结果。

这样做的理由：工资邮件通常在散团后、离开团队后才寄。若追加也要求「此刻仍在团队里」，最常见的真实场景反而记不上；若建立也放宽，则会凭空造出一个团本。新的 `raidRoster` 戳会自动覆盖上一个结算，满足「新团清旧团」。

**同时修好一个既有缺口**：`DataLifecycle.beginSettlement` / `beginRaid` 此前在运行时**没有任何调用方**，所以游戏里 `currentSettlement.raidId` 永远是 nil。新增的 Runtime 层是它的第一个真实调用者。

## 5. 采集点（只有两个，都是 BGLite 已确认的成功结果）

| 记录 | 触发 | 证据 | 是否需要改基线 |
|------|------|------|--------------|
| 交易 | `UI_INFO_MESSAGE` 且 `text == ERR_TRADE_COMPLETE` | BGLite 自己就用这个判定交易完成（`Core/Module/Trade.lua:2947`） | **否**（重复注册同一事件，读取仍在的 `BG.trade` 快照） |
| 邮件 | 批量邮寄流程自身的 `ERR_MAIL_SENT` 分支 | 该分支已被 `mainFrame.isSending and lastSend.colorName` 守卫，即「本插件刚刚寄出的这一封」 | **是**（`lastSend` / `mainFrame` 是文件局部变量，外部无法取得收件人） |

补充规则：

- 交易去重用一个内存 `booked` 标记，`TRADE_SHOW` / `TRADE_CLOSED` 时复位，防止客户端重复播报同一次完成。
- **失败 / 取消 / 关窗 / 超时都不进入采集**：交易只在 `ERR_TRADE_COMPLETE` 后写，邮件只在 `ERR_MAIL_SENT` 后写；`recordMail` 还要求 `mail.sent == true`，`tradeRows` 要求 `trade.completed == true`。
- 邮件只写 `status = "sent"`、`direction = "outgoing"`——插件只执行寄出，从不读收件箱，因此永远不会伪造「收到」。
- 无 `currentSettlement` ⇒ `activeSettlement` 返回 nil ⇒ 一行不写。
- 不新增轮询、不监听聊天、不读取整个收件箱、不扫描无关交易。

### 5.1 状态语义诚实性

一次交易若双方都只放物品、没有金币，BGLite 本身也无法判断谁是买方。此时**不编造金额、不编造买卖方向**，只写一行 `status = "pending"`（界面显示「待核对」）交由玩家人工核对。金币确实流动时才写 `status = "complete"`，且金额只落在该次交易的第一行（同一次交易打包多件物品时，金额属于交易而非每件物品）。

## 6. 纯投影层（`CurrentSettlementView.lua`）

只读 `root.currentSettlement.trades` / `.mails`，其他数据一律不碰。

```lua
M.trades(root, options)        -- 返回 rows, isEmpty
M.mails(root, options)
M.info(root, now)              -- 单个 raidId/startedAt/expiresAt/expired，供表头
M.statusColor(kind, status)    -- 成功=绿、待核对=金、失败=红、取消=灰、未知=灰
M.formatAmount(amount)
M.formatTime(value, dateFn)    -- dateFn 可注入，pcall 保护
```

- 排序稳定：先按时间，时间相同按原始插入序（`index`）——不做任何按玩家的分组、累计或排名。
- 结算已过期时直接返回 `{}, true`，不显示过期数据。
- 空态由 `isEmpty` 明确表达，不用「0 行」暗示。

## 7. 界面（`CurrentSettlementUI.lua`）

**全部为本仓库原创实现**：复用 BGLite 既有组件与视觉习惯，未读取、未复制、未改写、未移植任何历史 BiaoGe 源码或素材。

复用的既有组件：`BG.CreateMainFrame()`（可拖动、关闭按钮、`titleText`）、`BG.CreateScrollFrame`、`BG.HookScrollBarShowOrHide`、`BG.CreateButton`、`BIAOGE_TEXT_FONT`、`BG.PlaySound(1)`、`BG.SendSystemMessage`、`StaticPopupDialogs` / `StaticPopup_Show`、`GameTooltip:SetItemByID`。

- 名称直白：标题与入口按钮就是「交易记录（当前团）」「邮件记录（当前团）」。
- 表格式信息结构：列头 + 定宽列 + 行悬停条纹 + 滚动区，与主表格习惯一致；不做卡片仪表盘、不做跨团本选择器、不做玩家统计页。
- 物品格显示图标 + 物品链接，鼠标悬停出 `GameTooltip`；tooltip **只**由存储的数字 `itemId` 驱动（`M.tooltipTarget` 仅接受 number）。
- 状态列按 §6 配色明确区分 成功 / 待核对 / 失败或取消。
- 「清空当前团记录」按钮 → `StaticPopup` 二次确认；确认后**只**调用 `DataLifecycle.clearSettlement`，表格账单、心愿清单、角色总览、装备筛选、其他设置一律不动。
- 打开页面先跑保留期检查（`M.prepare` → `purgeExpired`），过期数据先删后显。
- 窗口底部常驻范围说明「只保留当前或最近一次未结算团本，最长七日。」

入口位置：仓库内旧版「交易记录 / 邮件记录」框体已被完全移除，历史 BiaoGe 源码为禁止读取项，因此入口沿用本仓库既有的 `RoleOverviewEntry.installEntry` 习惯——主窗口右下控制行，从右往左依次为 角色总览 / 邮件记录 / 交易记录。**未获得可靠截图的像素细节，不宣称与原版完全一致；入口位置与视觉列为待实机验收项。**

## 8. 本地化

`Locales/zhCN.lua` / `zhTW.lua` / `enUS.lua` 各追加一个 BGNext 区块（17 键）。已有键（物品 / 金额 / 时间 / 交易对象 / 收到）直接复用，不重复定义。

## 9. 测试（TDD，逐纵向切片 RED → GREEN）

新增 `tests/test_current_settlement_view.lua`、`tests/test_current_settlement_runtime.lua`、`tests/test_current_settlement_ui.lua`，并扩充 `tests/test_current_settlement.lua`、`tests/test_baseline_safety.lua`；全部注册进 `tests/run.lua`。行为断言优先走公开接口，源码扫描只作为**安全禁用项的纵深防御**（`SendAddonMessage` / `SendChatMessage` / `NotifyInspect` / `COMBAT_LOG_EVENT_UNFILTERED` / `tradeHistory` / `mailHistory` / `BiaoGe.History` / `GetInboxText`）。

覆盖：无结算拒绝写入、`raidId` 不匹配拒绝、两个字段白名单、主题/正文被丢弃、交易去重、邮件去重、新团清旧团、七日过期清除、手动清空只清结算、两个投影只读各自集合、稳定排序且无按玩家聚合、空态、tooltip 仅由 `itemId` 驱动、无法归属不记录、取消/失败不伪装成成功。

回归：`test_current_purchases.lua`（我买的）与受控自动出价 / 心愿清单 / 装备筛选 / 角色总览的既有测试全部保持通过。

## 10. 范围边界与待实机验证

- 邮件归属依赖 `raidRoster` 戳。**若从未击杀 Boss（戳不存在），本次不建立结算，邮件与交易都不记录**——宁可不记录，不扩大采集范围。
- 首个 Boss 击杀之前发生的交易不会被记录（此时没有可证明的团本身份）。
- 邮件只覆盖「本插件批量邮寄」路径；玩家手动用暴雪原生邮件界面寄出的工资**不采集**（无法证明归属，且不读收件箱）。
- 入口按钮位置、列宽、配色的实机视觉验收未做。
- 真实客户端测试不可用，按规则标记为 **unverified**；不声称任何客户端版本已支持。
