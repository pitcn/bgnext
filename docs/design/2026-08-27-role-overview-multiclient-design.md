# BGNext 角色总览多客户端适配设计

日期：2026-08-27
状态：维护者已确认，进入测试驱动实现

## 目标

在不改变周年时光服已验收界面的前提下，共用现有角色总览模型、投影、渲染与交互，为经典永久 60、周年服 TBC、熊猫人怀旧服和正式服建立独立栏目白名单。探索赛季不注册角色总览入口，也不采集角色总览快照。

所有团本实例 ID 取自当前已验证的 BGLite 2.4.0 基线 `Core/DB/DB.lua`。BiaoGe 仅作为玩家可见布局和操作习惯的参考，不读取、复制或改写其源码和素材。

## 支持状态

| clientFamily | 状态 | 说明 |
| --- | --- | --- |
| `titan` | `tested-in-game` | 保留当前实现与已完成的时光服实机结果 |
| `vanilla` | `pending-in-game-verification` | 仅经典永久 60；探索赛季在识别阶段排除 |
| `tbc` | `pending-in-game-verification` | 周年服 TBC，所有团本按独立实例 ID 展示 |
| `mop` | `pending-in-game-verification` | 五个团本独立展示；世界 Boss 因完成状态 API 尚未确认而暂不声明 |
| `retail` | `pending-in-game-verification` | 当前 BGLite 版本对应的当季实例默认显示，旧赛季实例默认隐藏 |
| `wrath` / `cata` | `unverified` | 本轮不实现，不显示猜测栏目 |
| 探索赛季 | `hidden` | 不返回角色总览 clientFamily，不显示入口、不采集数据 |

## 团本栏目白名单

| 客户端 | enabled | hidden / pending |
| --- | --- | --- |
| 永久 60 | MC 409、奥妮克希亚 249、黑翼 469、祖格 309、安其拉废墟 509、安其拉神殿 531、NAXX 533 | 无合并列 |
| TBC | 卡拉赞 532、格鲁尔 565、玛瑟里顿 544、毒蛇 548、风暴 550、海山 534、黑庙 564、祖阿曼 568、太阳井 580 | 无合并列 |
| 熊猫人 | 魔古山 1008、恐惧之心 1009、永春台 996、雷电王座 1098、决战奥格瑞玛 1136 | 世界 Boss：`pending`，在 API 证据补齐前不显示 |
| 正式服 | 当前 BGLite P2 实例 3004 默认显示 | BGLite P1 实例 2912、2939、2913、1592 保留但默认隐藏 |

## 候选摘要栏目矩阵

`enabled` 表示已有安全本地 API 与维护者确认的可见语义；`hidden` 表示该版本不适用；`pending` 表示不得猜测。

| 栏目 | 永久 60 | TBC | 熊猫人 | 正式服 |
| --- | --- | --- | --- | --- |
| 主专业 | enabled | enabled | enabled | enabled |
| 武器 | enabled | enabled | enabled | enabled |
| 饰品 | enabled | enabled | enabled | enabled |
| 金币 | enabled | enabled | enabled | enabled |
| 装备详情 | enabled，默认隐藏 | enabled，默认隐藏 | enabled，默认隐藏 | enabled，默认隐藏 |
| 已有特殊装备 | pending | pending | pending | pending |
| 升级物品 | hidden | hidden | hidden | hidden |
| 版本货币 | pending | pending | pending | pending |

`pending` 栏目不进入运行目录，因此设置页不能恢复它，也不会渲染错误的零值。非时光服不得继承泰坦余烬、泰坦碎片、岩石守卫碎片、泰坦升级材料或泰坦橙装目录。

## 数据与降级

- 继续只保存用户实际登录角色的最后一次本地快照。
- 继续使用 `ownCharacters[clientFamily][realmId][player]` 隔离数据与列显示偏好。
- API 不存在、返回受保护值或栏目未确认时，整列隐藏；不以 `0` 代替未知。
- 团本必须按真实实例 ID 独立匹配 `GetSavedInstanceInfo`，不得按显示名称合并。
- 本轮不新增通信、上传、遥测、其他玩家数据或历史数组。

## 验证

- 自动化测试覆盖识别、独立实例、候选栏目白名单、版本隔离、默认显示状态和安全降级。
- 四个新增客户端分别生成实机清单，完成朋友实测前只声明 `pending-in-game-verification`。
- 自动化通过不等于支持；发布说明不得把代码覆盖写成实机验证。
