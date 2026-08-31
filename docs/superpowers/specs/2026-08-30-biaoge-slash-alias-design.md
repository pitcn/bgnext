# `/biaoge` 兼容命令设计

日期：2026-08-30
状态：待维护者书面复核

## 目的

让从 BiaoGe 或 BGLite 迁移到 BGNext 的用户继续使用熟悉的命令呼出 BGNext，同时保留 BGNext 自己的公开名称和命令习惯。

## 当前行为

- `/bgn`：公开主命令，呼出 BGNext。
- `/bgnext`：公开完整名称命令，呼出 BGNext。
- `/bglite`：已经注册的隐藏兼容别名，呼出 BGNext。
- `/biaoge`：当前未注册。

## 设计

新增 `/biaoge` 作为第四个隐藏兼容别名，复用现有 `SlashCmdList.BGNEXT` 分发函数。它必须与 `/bgn`、`/bgnext` 和 `/bglite` 执行完全相同的默认呼出行为，并继续支持现有子命令解析，例如 `role`。

公开说明、TOC Notes 和主要帮助文字仍只推荐 `/bgn` 与 `/bgnext`。`/bglite` 与 `/biaoge` 不作为 BGNext 品牌命令宣传，只用于保留旧宏和用户习惯。

## 冲突边界

原版 BiaoGe 与 BGNext 同时启用时可能同时注册 `/biaoge`，WoW 不能为这个别名提供可靠的跨插件所有权保证。因此：

- BGNext 单独启用时，保证 `/biaoge` 呼出 BGNext。
- 多个表格/BGLite 系列插件同时启用时，不保证 `/biaoge` 最终由哪个插件处理。
- 不为此增加加载顺序争抢、延迟覆盖或强制接管逻辑。
- 继续使用现有 ConflictGuard 提示玩家只启用一个表格插件。

## 代码和测试范围

- `Core/BiaoGe.lua`：增加 `SLASH_BGNEXT4 = "/biaoge"`。
- `Core/BGNext/Identity.lua`：把 `/biaoge` 加入已注册命令，但不加入公开命令。
- `tests/test_identity.lua`：更新命令数量、注册状态、公开状态与源码注册断言。
- 更新被修改基线文件的允许覆盖哈希；不改上游基线文件。

## 验收标准

- BGNext 单独启用时，`/biaoge`、`/bglite`、`/bgn`、`/bgnext` 均能呼出同一主界面。
- `/biaoge role` 使用与 `/bgn role` 相同的现有子命令分发。
- 玩家可见说明仍只推荐 `/bgn` 和 `/bgnext`。
- 未增加第三方插件探测、通信、保存数据或隐私行为。
- Lua 测试、基线校验和 `git diff --check` 全部通过。

## 非目标

- 恢复旧 `/gbg` 命令。
- 在多个表格插件同时启用时抢占 `/biaoge`。
- 把 BGNext 重命名为 BiaoGe 或 BGLite。
