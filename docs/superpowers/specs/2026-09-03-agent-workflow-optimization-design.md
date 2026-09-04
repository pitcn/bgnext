# Agent 工作流轻量化设计

日期：2026-09-03  
状态：待用户确认

## 目标

减少 BGNext 日常 Agent 开发中重复阅读、重复验证和重复汇报造成的 token 与时间消耗，同时保留交易、拍卖、隐私、持久化和 Release 的严格安全边界。

## 方案

采用“风险分级 + 一键验证 + 精简 handoff”。风险由改动内容决定，不由 Agent 自行宣称“安全”来绕过检查；无法确定时自动升级一级。

### 低风险（low）

适用：纯文案、Locale、README、注释、无行为变化的 UI 尺寸/颜色、测试自身修正。

- 必读：`AGENTS.md`、改动文件及其直接上下文。
- 验证：相关定向测试；提交或 PR 前运行轻量统一验证。
- 不要求：完整 SECURITY/PRIVACY/ADR/数据清单重读、RED 测试、长 handoff。
- 若触及 Lua 运行时逻辑、基线文件或持久化字段，自动升级为 normal/high。

### 普通风险（normal）

适用：一般功能和 Bug 修复，不改变通信、隐私边界、SavedVariables schema、baseline 来源或 Release 内容。

- 必读：`AGENTS.md`、精简安全摘要、相关模块和相关 ADR；无需每次重读全部治理文档。
- 行为修复先写能复现问题的定向测试并观察 RED。
- 开发中只跑定向测试；准备提交/更新 PR 时一次性运行完整 Lua 测试、baseline 校验、Lua 5.1 语法及 diff-check。
- 自动生成短 handoff，只记录可机器提取的信息和未验证项。

### 高风险（high）

适用：交易与拍卖发送、插件通信、隐私或玩家数据、SavedVariables/schema/迁移、baseline override、第三方来源、权限/战斗门禁、安全修复、打包与 Release。

- 保留当前完整阅读、TDD、数据与来源审计、全套验证和详细 handoff。
- Release 继续执行兼容矩阵、包内容、更新日志及平台文案要求。

## 风险判定

新增一份短小的机器可读配置，由路径和改动类型给出最低风险等级。例如：

- `Locales/**`、Markdown 文档默认 low。
- `Core/BGNext/**` 默认 normal。
- `Core/Module/Trade.lua`、拍卖发送/通信模块、数据生命周期、TOC、baseline 清单和打包脚本强制 high。
- 新增持久化字段、消息字段、外部传输或 baseline 修改，无论路径如何都强制 high。

Agent 可主动升级，不可低于配置给出的最低等级。检测到跨等级文件时取最高等级。

## 一键验证

新增 `tools/agent-verify.ps1`，统一入口：

```powershell
pwsh -NoProfile -File tools/agent-verify.ps1 -Risk low
pwsh -NoProfile -File tools/agent-verify.ps1 -Risk normal -Base origin/main
pwsh -NoProfile -File tools/agent-verify.ps1 -Risk high -Base origin/main
```

脚本职责：

1. 验证当前仓库、origin、分支和工作树状态。
2. 根据 base diff 检测最低风险；显式 `-Risk` 低于最低风险时失败。
3. low：运行变更 Lua 的 `luac -p`、diff-check，并允许传入定向测试。
4. normal：运行完整 Lua 测试、baseline 校验、变更 Lua 语法及 diff-check。
5. high：在 normal 基础上检查必需治理文件是否被评估，并输出 Release/数据/协议/来源核对项；脚本不伪造人工或实机验证。
6. 只输出紧凑摘要；失败时输出具体命令和错误。
7. 可选生成 `.local/handoffs/inbox` 精简 handoff，记录分支、base/head、改动、命令结果、风险等级和未验证项。

现有 `run-lua-tests.ps1`、`verify-baseline.ps1` 和 release 工具保持单一事实来源，新脚本只编排，不复制其逻辑。

## 文档结构

- 精简 `AGENTS.md`：保留不可协商边界；把工作流改为三级表格。
- 新增 `docs/agents/safety-summary.md`：normal 任务所需的短摘要，链接到完整 SECURITY/PRIVACY/ADR/数据清单。
- 高风险任务仍必须读取完整原文；摘要不覆盖原文。
- handoff 模板分 `short` 与 `full`，high 使用 full，low/normal 默认 short。

## GitHub 流程

- 有现成 Issue 的实现必须关联 Issue。
- 独立用户可见行为或 Bug 仍建立/使用 PR。
- 纯文档、Locale、测试维护等 low 改动允许一个维护 PR 合并处理，不强制每个小改动单独 Issue。
- Agent 只在发现阻塞、需要用户决策或修复完成时评论，禁止重复粘贴测试全文。
- CI 结果通过链接引用；PR 正文保留根因、行为变化、风险影响和未实机项，不重复 handoff 的机器信息。

## 失败与升级规则

- 风险检测不确定、baseline 失败、来源不明、隐私边界不清或测试无法运行：停止并升级 high。
- 定向测试通过但完整验证失败：不得标记完成。
- low 任务出现运行时行为变化：停止，改按 normal 重新执行。
- 脚本不得自动更新 baseline hash、自动弱化测试、自动发布或自动关闭 Issue。

## 验收标准

- 三个风险等级有稳定、可测试的路径判定。
- 显式降级会失败，升级始终允许。
- normal 只需一次命令完成当前三个提交前门禁。
- high 保留现有安全、隐私、来源和 Release 要求。
- 输出足够让 Codex 独立复核，但默认不包含完整日志。
- 文档、脚本和模板本身有 PowerShell/规则测试。
- 不修改插件运行时、SavedVariables、通信协议或游戏安装目录。

## 非目标

- 不取消真实行为测试或完成前验证。
- 不让 Agent 自行跳过隐私、来源或 Release 审计。
- 不把 CI 绿色当成实机验证。
- 不在本次工作中修改 BGNext 游戏功能。
