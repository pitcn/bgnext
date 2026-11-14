# 同一 BGNext 插件的无限服目录

按维护者要求，在同一个插件包内根据客户端切换团本目录，沿用现有记账、拍卖、心愿、清空和角色总览流程。

- `16000 <= Interface < 17000` 识别为 Forever；保留经典版共用能力，但不进入永久 60/赛季服专属团本分支。本次仅把观察到的 `16001` 加入包声明。
- P0 默认选中黑石塔上层：八个常规/稀有首领，以及可选召唤首领瓦塔拉克公爵。小怪使用杂项栏。
- P1：深穴 8 个首领、海加尔峰 13 个首领、奥妮克希亚的巢穴 1 个首领。掉落留空，不套用经典团本表。
- 表格使用独立的 `UBRSforever`、`BDforever`、`HSforever`、`ONYforever` 键。角色总览使用 `forever` 家族，避免混入永久 60 的目录和资源；黑石塔上层不加入周锁总览。
- 不改变旧目录、玩家字段、协议、接收方、生命周期或清除规则。不读真实 SavedVariables，不安装或发布。

## 来源与独立实现

参考本地喵影 MYLoots 0.3.0 / MYLoots_DungeonLoot 0.1.1，确认黑石塔上层按首领展示装备，包含稀有和可选召唤首领。没有导入喵影文件、实现、内部对象、私有表结构、导入格式、文案或素材，也不增加运行时依赖。

P0 是人工筛选的游戏装备 ID 参考集合，排除任务、配方、材料及未确认的额外物品，不是第三方全库的转换或完整复制。仅重述游戏事实标识及首领关系，目录装配、布局和实现独立编写。它不是无限服实测掉落表；属性仍由客户端提供，不存掉率或物品属性副本。

P1 团本名、人数依据[国服官方概览](https://wow.blizzard.cn/news/24303009/index.html)。通过[公开客户端资料页](https://thewowdb.com/wow-forever/raids/)定位成就后，直接用 wowdata 查询本地 Blizzard 客户端核对首领名和顺序。目标：本地产品 `wowf`，CN，`1.60.1.70938`，`zhCN` / `enUS`。

```sql
-- Achievement 62034 -> Criteria_tree 230811
-- Achievement 62035 -> Criteria_tree 230799
SELECT ID, Description_lang, Parent, OrderIndex FROM CriteriaTree
WHERE Parent IN (230811,230799) ORDER BY Parent, OrderIndex;
SELECT ID, MapID, Name_lang, OrderIndex FROM DungeonEncounter
WHERE MapID IN (229,249,2981,3052) ORDER BY MapID, OrderIndex;
```

DungeonEncounter 确认 P0 事件 3062、3063、3068、3069、3070 和奥妮克希亚 1084。盖斯不冒用雷德的事件；可选首领无事件 ID 时留空。该构建没有两个新团本的完整事件行，不把成就中的生物 ID 当 encounter ID。

简中、英文新首领名采用上述客户端记录。该安装未能读取 zhTW 数据切片，新首领繁中采用上述简中名称的繁体转写，暂不声明与 zhTW 客户端官方本地化一致。

## 验证与限制

先观察路由和家族隔离测试失败，再实现。测试执行实际路由段、布局/注册分支、首领和掉落模块，覆盖原客户端路由、独立表格键、首领/事件对应、P1 空掉落及资源隔离。

仍需游戏内验证：加载、四个标签、长首领名、P0 装备记录与拾取归属、拍卖/账单、心愿、清空、角色总览。P1 真实事件和掉落待开放后验证，仅有名字不能保证其自动拾取归属。自动化结果不等于已验证支持。

基线逐文件审阅：Init.lua 仅增加客户端路由；DB.lua 仅增加 Forever 的布局、注册和来源过滤分支；DB.xml 仅增加三个原创模块的加载；TOC 仅增加 16001；三个 Locale 文件仅追加名称。核对后仅更新这七个文件的显式 override 哈希，不刷新上游清单。
