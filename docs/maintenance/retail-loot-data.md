# 正式服掉落资料维护说明

本文说明 BGNext 正式服（Retail）掉落资料的存放位置、每个赛季需要人工确认哪些 ID，以及“待适配（pending）”状态的约束。维护者必须在实机客户端上核对 ID 后再改动数据文件，**不得猜测**。

## 数据位置

| 文件 | 作用 |
| --- | --- |
| `Core/DB/DB.lua` | 用 `AddDB("VS", …)` / `AddDB("VA", …)` 注册团本，声明难度数量、Boss 数量、难度名称（N/H/M）、实例宽度等。 |
| `Core/DB/DB_Loot_Retail.lua` | 实际掉落物品数据。`FBs` 列表决定哪些团本有掉落；`InsertItem` 把“遭遇战 ID + 物品 ID + 装等”写入 `BG.Loot[FB][难度]["bossN"]`。 |
| `Core/DB/DB_BossName.lua` | Boss 中文名与颜色。 |
| `Core/DB/DB_EncounterID.lua` | 团本 → 遭遇战 ID 的映射（`BG.Loot.encounterID.VS` / `.VA`）。 |
| `Core/BGNext/RetailLootStatus.lua` | **数据就绪状态声明**：`available` / `pending` / `hidden`。心愿清单空掉落提示据此区分“该团本资料尚在适配”与“该 Boss 暂无掉落”。 |

## 数据状态约束

- `available`：该团本在 `DB_Loot_Retail.lua` 中，每个启用的难度（N/H/M）都有非空的 Boss 掉落桶。
- `pending`：该团本已在 `DB.lua` 注册、在 `DB_BossName.lua` / `DB_EncounterID.lua` 有 Boss/遭遇战映射，但掉落物品数据尚未适配。**必须声明为 `pending`，绝不能用空表或伪造 ID 假装“已支持”。**
- `hidden`：未注册、未映射的团本，不显示。

示例：当前 `VS` 为 `available`，`VA` 为 `pending`。`VA` 有 Boss 名和遭遇战映射，但没有物品数据；玩家点击 `VA` 的心愿格子时，应看到“该团本掉落资料尚在适配，可通过拖入装备或选中格子后 Shift 点击装备手动加入个人心愿。”，而不是误以为整个插件没有装备库。

## 每个赛季需要确认的 ID

1. **遭遇战 ID（Boss）**：`DB_EncounterID.lua` 中该团本每个 Boss 的 `encounterID`，以及 `DB_Loot_Retail.lua` 的 `encounterIDs` 表。
2. **物品 ID**：`DB_Loot_Retail.lua` 的 `tbl.M` / `tbl.H` / `tbl.N` 字符串中的 `物品ID`。必须来自实机客户端的掉落，不能从历史 BiaoGe 数据恢复。
3. **难度 ID**：`difficultyIDs`（当前 14/15/16 = N/H/M）。若赛季/客户端改变了难度 ID，需同步确认。
4. **装等（item level）与 `raidLevels`**：`raidLevels` 中难度 → 各装等对应 `bonus` ID 的映射，用于生成带 bonus 的装备链接。
5. **实例 ID / 副本 ID**：`DB.lua` 中 `AddDB` 的实例信息与 `DB_EncounterID.lua` 的遭遇战映射要对应到正确的副本。

## Boss 映射核对

- `DB_Loot_Retail.lua` 的 `encounterIDs[遭遇战ID] = boss序号` 必须与 `DB_EncounterID.lua` 中 `BG.Loot.encounterID[FB]` 的顺序一致，否则物品会进错 Boss 的格子。
- 改动后运行自动校验（`tests/run.lua` 的 `test_retail_loot_status.lua`）确认声明与数据文件一致：`available` 团本必须每个难度都有非空掉落，`pending` 团本保持空。

## 禁止事项

- **不得**从历史 BiaoGe 原版装备库复制或移植任何物品数据、算法或文本。
- **不得**猜测团本、Boss、物品或货币 ID。无法在实机客户端确认的，一律保持 `pending`。
- **不得**把空表当作“已支持”。空表只表示“尚无数据”。

## 未来：冒险指南（Adventure Guide）API 适配器

理想方案是读取暴雪冒险指南 API（`EJ_*` / `C_EncounterJournal`）动态生成掉落，再经实机核对后落库。该工作作为一个独立的 GitHub Issue 跟踪，**不在本次改动中实现**；在它完成前，掉落资料继续以人工确认的静态数据维护。
