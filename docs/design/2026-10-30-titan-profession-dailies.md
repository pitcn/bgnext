# 时光服达拉然专业日常

本方案按时光服沿用 WLK 达拉然任务 ID 的机制接入三列完成状态，仅作用于 titan 角色总览，不扩大到尚未适配的 wrath 客户端。

## 行为

新增默认显示、可单独隐藏的“钓鱼任务 / 珠宝任务 / 烹饪任务”列，完整提示说明为达拉然日常今日完成状态。保留原代币数量列和数据键。每组任一任务已交付即完成；所有任务明确未完成才显示未完成；可靠证据证明未学专业则不适用；接口、专业资格、阵营或重置时间不可靠时显示未知。烹饪按当前角色阵营选组。

接口不存在时沿用现有目录策略，不提供不可读的列；接口存在但返回异常时保留未知。专业存在性先读当前角色的完整专业元组，包括第二专业；旧客户端可用 Blizzard 自己的本地化技能名在当前技能列表中作正向确认。短元组、折叠/缺失的技能项或异常数据不能据此判定未学习，也不自动展开技能列表。显示未完成仅证明今日尚无交付标记，不承诺角色等级/技能点数或前置任务已满足接取条件。

沿用本人角色最近快照，仅保存 activityStates 的 status/observedAt/resetsAt，覆盖更新，无任务日志、任务 ID、任务列表、原始 API 返回或其他玩家数据。到每日官方重置时间作废；离线角色不伪造新状态。当前角色在可见窗口跨过重置后仅重读一次该区块；隐藏时不新增轮询。登录、刷新、任务事件及专业变化更新当前角色。停用总览即停止。

任务数据来源为公开 WLK 任务数据库，IDs 已逐页核对。钓鱼 13830/13832/13833/13834/13836；珠宝 12958–12963；联盟烹饪 13100/13101/13102/13103/13107；部落烹饪 13112–13116。不包含外域日常或其他节日任务。参考 https://www.wowhead.com/wotlk/guide/professions/fishing/daily-quests 、https://www.wowhead.com/wotlk/guide/professions/jewelcrafting/daily-quests 、https://www.wowhead.com/wotlk/guide/professions/cooking/daily-quests 。独立实现，不导入第三方源码、文案或素材，接入范围不替代客户端验证。

## 实施与验证计划

API 契约参考：wowdoc 的 `sourceId=wow-ui-source`、`product=titan`、Tag `3.80.2`，固定提交 `ba472e5e1b5580b557e3dbf02c9e5ff23b223347`。`Interface/AddOns/Blizzard_UIPanels_Game/Cata/SpellBookProfessions.lua:182` 显示 `local prof1, prof2, arch, fish, cook, firstAid = GetProfessions()`；同快照 `Mists/SpellBookFrame.lua:700` 亦保留该六项顺序。这仅作为共享 API 用法依据，不代表已验证当前客户端加载路径或真实返回值。代码对短返回、旧技能列表和异常值保守降级。

1. 先以真实目录和适配器的成功采集测试复现缺少三列；再接入固定任务组、专业存在性与 fail-closed 读取。
2. 逐项覆盖每个任务、双方阵营、无专业、旧技能列表回退、缺失/异常 API 与日重置边界；接入现有投影及过期显示。
3. 驱动真实 collector/runtime/model，验证交任务、专业变化、隐藏/停用、跨日一次刷新、离线过期、其他区块和旧记录保留。
4. 补齐简中/繁中/英文与数据清单、兼容说明、未发布日志；运行全套 Lua、语法和基线检查，并作针对性审查。自动验证不标为实机通过。本次不安装或发布。

## 审查处置

一次独立审查提出旧技能列表非标题标记的兼容疑点，已用失败测试复现并支持 `false/0/nil`，同时拒绝 `true/1` 标题，避免将标题作为专业存在证据。另一个意见假设 Titan 不存在 C_QuestLog，且旧全局函数必定返回 `1/nil`；该假设没有本轮客户端证据。上述同一固定 Titan 快照的 `Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua:99–109` 明确声明 `C_QuestLog.IsQuestFlaggedCompleted` 返回 `{ Name = "isCompleted", Type = "bool", Nilable = false }`。因此按已证实的布尔契约读取；异常的 `1/nil` 契约保留未知，不把无法确认的 nil 自动变成未完成，亦不声称兼容原始 3.3.5 客户端。单独补齐 canReadColumn 的版本及缺失接口门测试。专业事件的新增读取只对 titan 生效，其他版本保持原事件路径。
