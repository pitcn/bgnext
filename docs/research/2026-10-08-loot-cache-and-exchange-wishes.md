# 拾取缓存修复与旧版兑换心愿行为

## 本次范围

修复真实 CHAT_MSG_LOOT 回调中 GetItemInfo 返回空结果时的报错／漏记。保留交易、购买、任务奖励、品质、黑白名单、特殊 Boss、杂项、叠加和 TOC 宝箱规则；不改拍卖协议、不改持久化结构、不更换游戏目录。

真实回调的回归测试先复现 quality 与 nil 比较错误，再检查延迟记账、原 Boss／难度归属、重复加载回调、独立重复掉落、清空／离团／地图／表格切换、关闭记录、超时与截止边界。已缓存装备沿原有即时处理路径，不请求额外元数据加载。缺失信息最长等待 15 秒，超时在原有效作用域内提示手动补记；不猜品质或物品类型。

待加载事件仅保留解析后的必要字段，心愿提醒用规范化的事件／物品链接／拾取者／数量键，不保留原始聊天正文。表格记录沿用已有接口，晚到信息不会重放整条聊天事件或重新套用后来发生的交易、购买、任务窗口状态。

清空任意掉落栏会保守取消该表仍在等待元数据的事件，避免清空后重新写回；其他表的待加载事件不受此操作影响。已接受的原有短延时写入仍检查清空和团队作用域。

## 旧版心愿行为研究

- BGNext 0.8.7（`30ab28c`）与本次修复前的 Wishlist.resolveDrop 均只查实际 `bossN` 掉落；这不是新增奥杜尔目录后才出现的限制。
- 已验证的官方 BGLite 2.4.2 Pure Edition 基线（`5649f58`）没有完整的旧心愿模块，不能从这一基线推断完整 BiaoGe 心愿行为。
- 按 ADR-0003 只读研究用户提供的本地 BGLite 白云飞整合版 2.10.8。其 `Core/FBUI/Hope.lua` 的心愿定位仍查实际掉落。其装备库 Alt 点击入口在添加前查询兑换来源：存在映射时，把来源兑换物交给心愿设置，而不是直接把兑换成品存为 Boss 掉落。
- 因此玩家可以在该整合版装备库里点击兑换成品，但结果可能是记录对应兑换物。对多个兑换来源、升级材料链或没有明确映射的成品，不能推断都支持可靠定位。
- BGNext 当前没有这一来源转换入口。本次按用户要求先修拾取，不扩大心愿匹配范围、不修改旧心愿、不把成品加入拍卖目录。若后续补齐，应独立实现明确的“成品 → 来源兑换物”选择与反馈；多来源不能随意选第一项。

研究只记录玩家可见行为；没有导入、改写或复制该整合版的实现、映射表、文本或素材。数据继续使用 ADR-0006 授权的事实目录。

## API 与验证边界

wowdoc 定点查询官方 `wow-ui-source` / `titan` / `latest`，matchedTag=null，commit `ba472e5e1b5580b557e3dbf02c9e5ff23b223347`：

- `Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua:393–417` 返回摘录含 `Name = "GetItemInfo"` 与 `MayReturnNothing = true`。
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/PartyInfoDocumentation.lua:333–336` 返回摘录含 `Name = "GroupLeft"`、`LiteralName = "GROUP_LEFT"`、`SynchronousEvent = true`；Classic ReadyCheck 等源中也有注册关系。

以上为 latest API 合约／事件证据，不是当前游戏构建的实机验收。回归测试通过也不能代替首次掉落、箱子延迟、多人交易与混合插件团队的客户端验证。
