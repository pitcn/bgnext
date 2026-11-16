# BGNext 兼容性矩阵

Forever 两段名补充修复（2026-11-16）：当前角色的名、姓两项返回值组成完整
空格键，优先于可能截短的初始化键。仅同一完整名的大小写/连字符别名归并；
单段旧键无法确定归属，Forever 加载时按 PRIVACY 所述范围丢弃，不猜归属、不转移数据。维护者已在无限服游戏内确认两段名分开记录，且旧单段残留会在加载时被清理。两种姓氏、重复切换、完整别名、
歧义短键、缺姓降级及两行投影由 Lua 模拟测试覆盖；上述边界情形尚未单独实机穷尽验证。
同一版本源码证据 `wow-ui-source` / `forever` / tag `1.60.1` / commit
`ca8368f2f2380cbe696854f7f2646387c278a61b`：
`Interface/AddOns/Blizzard_UnitFrame/Mainline/UnitFrame.lua:1094` 的
`GetUnitName` 委托给 NameUtil；
`Interface/AddOns/Blizzard_FrameXMLUtil/Camelot/NameUtil.lua:4` 与 `:23`
使用 `UnitName` 的名、姓两项组成完整名。通用 NameUtil 的第二段按 realm
分隔符处理，不能用该通用含义解释 Forever 姓氏。此为静态源码与受控接口
证据，不证明当前游戏会话的 API 实际返回值或最终显示已通过验收。

角色总览键与装备缓存修复（2026-11-16）：完整角色键、保守短键迁移、
link 未缓存保留、槽位合并、物品信息事件及有界后备重试由 Lua 5.1
模拟回归覆盖，尚未实机验证。版本化证据：`wow-ui-source`，product
`forever`，tag `1.60.1`，commit
`ca8368f2f2380cbe696854f7f2646387c278a61b`；
`Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua:1815`
声明 `GET_ITEM_INFO_RECEIVED`，
`Interface/AddOns/Blizzard_APIDocumentationGenerated/UITimerDocumentation.lua:11`
声明 `C_Timer.After`。事件注册失败仍继续安装；缓存未完整时最多延迟重试
三次，缺少计时器则临时使用帧 `OnUpdate`。静态 API 声明不等于实机事件
已确认触发。暂时缺失与真正空槽未区分，旧槽位保留最后观察值，直到新 link
替换或手动清空；不会生成装备历史。

无限服（0.8.17 首次随主线发布，仅基础适配）：同一 BGNext 包增加 Interface 16001 与独立 Forever 路由，P0 黑石塔上层、P1 深穴/海加尔峰/奥妮克希亚首领目录由自动化测试覆盖；名称及已知事件核对本地 wowf 1.60.1.70938。P0 掉落仅为初始装备参考，P1 掉落留空。角色总览单独隔离 Forever。维护者已在无限服游戏内验证：插件加载与角色总览显示（默认显示未满级、满级筛选、空状态提示）、两段名分开记录、旧单段残留清理、武器/饰品登录后仍显示，以及新建拍卖价格方案默认基础价 10g。未单独完成拾取、完整拍卖流程、清空或周锁验证；团本目录、周常/专业冷却/货币列以及背包、天赋、物品及提示框接口适配仍以本机测试与静态核对为准，不宣称正式支持。P1 两个新团本的完整事件行缺失，自动归属待验证。

0.8.16 改动：心愿按部位浏览、时光服周常及“我买的”身份匹配由本机模拟与回归测试覆盖，尚未实机验证。周常候选 ID 与共享完成位已通过国服 wow_classic_titan 3.80.2.70522 静态数据核对；这不证明当前可接任务、奖励或服务器策略。周重置使用官方接口，缺失或异常时为未知，不用本地日期推算。部位浏览缺少物品信息时保留待分类，原有心愿直接掉落限制和容量规则不变。

入团欢迎语：新增普通团队频道自动发送路径，默认关闭，仅当前团长可触发。名单差分、合并限流、权限复核、世界切换与取消路径由本机模拟测试覆盖；未进行本轮任何客户端实机验证，不宣称集合石插件集成或新增客户端支持。发布前需披露该自动聊天能力并复核平台规则与客户端发送限制。

本文件区分代码覆盖、自动化测试、模拟验证和游戏内实机验证。某个客户端出现在 BGLite 的 TOC 中，不代表 BGNext 新增功能已在该客户端完成适配。

## 自有角色总览

时光服专业日常（0.8.15）：新增达拉然钓鱼、珠宝、烹饪任务状态，按沿用 WLK 原始任务 ID 的机制接入。采集、阵营隔离、专业资格、异常读数和日重置通过自动化验证；尚未进行本轮客户端实测。不因此启用未适配的 wrath 总览。缺少完成/重置接口时不提供相应列；存在接口但无法可靠读取、旧记录缺失或离线记录过期时显示未知。旧代币数量列保持原样。

时光服 P6：奥杜尔独立列已接入，限制为 API 确认的 25 人锁定，历史 10 人和人数未知的锁定不会展示成本次 CD。10 月 8 日已按获准的 AtlasLootMY 2.6.0 / 团本模块 3.0.0 数据接入十四 Boss、共享掉落、明确兑换关系及心愿/价格目录，并通过自动化测试。仍待当前客户端实机验收；橙锤任务链监控未新增，不声明完整支持。来源、范围和验收步骤见 [P6 清单](maintenance/titan-p6.md)。

| 客户端 | 当前状态 | 说明 |
| --- | --- | --- |
| 周年时光服 | 代码覆盖、自动化测试通过；等待本轮实机复验 | 团本按独立实例 ID 展示；时光服装备、物品和货币目录已接入 |
| 经典永久 60 | 代码覆盖、自动化测试通过；待实机验证 | MC、奥妮克希亚、黑翼、祖格、安其拉废墟、安其拉神殿和 NAXX 均按独立实例 ID 展示 |
| 探索赛季 | 明确不支持 | 不注册角色总览入口，不采集或展示角色总览快照 |
| 周年服 TBC | 代码覆盖、自动化测试通过；待实机验证 | 九个团本均按独立实例 ID 展示；不再合并毒蛇/风暴或海山/黑庙 |
| 巫妖王 | 适配中；未声明支持 | 10/25 人及难度、纹章和专业冷却尚待独立适配 |
| 大地的裂变 | 适配中；未声明支持 | 团本、货币和任务目录尚待独立适配 |
| 熊猫人 | 代码覆盖、自动化测试通过；待实机验证 | 五个团本独立展示；默认显示勇气/正义/战火徽记；天神首胜、农场收菜、四天神、斡耳朵斯为四个独立可选列且默认关闭。天神首胜读取 LFG 每日奖励状态，四天神/斡耳朵斯读取 33117/33118 周常标记，均待当前国服客户端实测；农场仅在当前角色于日歌农场实际拾取已知作物后标记当天完成，未捕获时显示未知；其他隐藏货币与专业冷却仍待实机确认 |
| 正式服 | 代码覆盖、自动化测试通过；待实机验证 | 采用当前 BGLite 版本的独立实例目录；当季默认显示，旧赛季与候选实例默认隐藏；普通/英雄/史诗按 Boss 分别统计，部分击杀显示已击杀数/总数，API 证据不足时留空而不伪造完成；候选货币无 ID，确认前不渲染 |

四个新增客户端只声明代码覆盖和自动化测试，不等于已经支持。版本专属货币、特殊装备和升级物品没有可靠证据时不会进入目录、设置页或快照；API 不可用时不显示错误的零。货币单元格与表头悬停提示只在 Blizzard 货币 API 实际返回名称与上限字段时展示这些字段，缺失的字段不显示为伪造的零。共享快照模型和渲染器不等于对应客户端已经通过实机验证。

## 按专精的装备过滤默认方案

| 客户端 | 当前状态 | 说明 |
| --- | --- | --- |
| 经典永久 60（vanilla） | 代码覆盖、自动化测试通过；待实机验证 | 按旧式三系天赋树（战士/圣骑/猎人/盗贼/牧师/萨满/法师/术士/德鲁伊）生成默认方案 |
| 周年服 TBC（tbc） | 代码覆盖、自动化测试通过；待实机验证 | 沿用三系天赋树目录 |
| 周年时光服（titan） | 代码覆盖、自动化测试通过；待实机验证 | 三系天赋树加死亡骑士；德鲁伊野性为熊/猫歧义，仅提供保守野性默认，不自动判定熊或猫 |
| 熊猫人（mop） | 代码覆盖、自动化测试通过；待实机验证 | 按稳定专精 ID 生成默认方案，含武僧 |
| 正式服（retail） | 代码覆盖、自动化测试通过；待实机验证 | 按稳定专精 ID 生成默认方案，含恶魔猎手与唤魔师 |

明确不支持的降级与限制：巫妖王（wrath）与大地的裂变（cata）已解析 API 事实，但未建立专精目录，跟随专精时报告未知并保留当前方案；正式服未记录的专精 ID（含未验证的新恶魔猎手专精）返回未知而非猜测；德鲁伊野性无法从天赋点数安全推断熊/猫，不自动判定。上述所有未知、零点、并列、API 缺失或未验证客户端均保留当前方案，不猜测。内置专精方案仅在游戏内实机验证后才会在版本说明中声明对应客户端兼容。

## 验证等级

- **代码覆盖：**存在明确实现路径，但不代表真实客户端可用。
- **自动化测试：**Lua 测试覆盖投影、边界和降级行为。
- **模拟验证：**使用受控 API 桩验证，不等同于游戏内结果。
- **实机验证：**在对应游戏客户端完成加载、界面和交互测试并保存记录。

版本发布说明必须按上述等级陈述证据，不得把“代码覆盖”或“模拟验证”写成“全面兼容”。

### Forever overview activities (2026-11-15)

Booty Bay weekly completion and five profession cooldown columns are code-covered and simulated, pending in-game testing. Verified local target: wowf / CN / zhCN / 1.60.1.70938. Versioned Blizzard source: wow-ui-source, forever, tag 1.60.1, commit ca8368f2f2380cbe696854f7f2646387c278a61b. Weeklies require a readable quest-completion API; missing or invalid official weekly reset produces unknown. Shared transmute recipes render one timer, while one-hour Iron to Gold and Mithril to Truesilver are separate. Missing learned-recipe evidence or missing Salt Shaker/Leatherworking evidence hides the unavailable timer rather than fabricating readiness. No separate daily is declared for the pictured weekly quest.

Forever currency overview (2026-11-15): Faded/Tarnished Undermine Real (3469) defaults visible; Honor Points (1792) and Merchant's Favor (3402) default hidden and can be enabled in column settings. IDs and localized names were checked against the same local wowf 1.60.1.70938 CurrencyTypes build. Counts use the existing C_CurrencyInfo.GetCurrencyInfo reader and CURRENCY_DISPLAY_UPDATE handling; no new runtime API or events. Automated visibility/count projection coverage passes; real-client display is pending user testing.
