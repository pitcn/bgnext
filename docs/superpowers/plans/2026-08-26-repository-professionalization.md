# BiaoGe Next Repository Professionalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 在不修改 188 个 BGLite 2.4.0 运行文件的前提下，为 BiaoGe Next 建立完整、可信、可审计的社区维护文档与 GitHub 协作流程。

**Architecture:** 将项目入口、社区治理、安全隐私、合规边界、慈善透明和贡献者认可拆分为职责单一的 Markdown 文件；用固定 SHA-256 清单和 PowerShell 校验脚本保护官方基线；用 GitHub Issue、PR 模板和 CI 将规则落实到每次贡献。

**Tech Stack:** Markdown、GitHub Issue Forms、GitHub Actions、PowerShell 7、Git、SHA-256

---

## 文件结构

- `README.md`：面向所有访客的项目入口和核心承诺。
- `SECURITY.md`：安全问题报告、响应和披露政策。
- `PRIVACY.md`：本地优先的数据处理规则。
- `CONTRIBUTING.md`：贡献流程、提交要求和审查门槛。
- `CODE_OF_CONDUCT.md`：社区行为边界和处理方式。
- `COPYRIGHT.md`：上游、第三方及新增贡献的权利说明。
- `CHANGELOG.md`：版本历史。
- `CONTRIBUTORS.md`：分类且不排名的贡献者名单。
- `SUPPORT.md`：问题分流和支持范围。
- `docs/PROJECT_CHARTER.md`：治理、决策、维护者和发布职责。
- `docs/COMPLIANCE.md`：允许、需评估和禁止功能，以及 PR 合规清单。
- `docs/CHARITY.md`：全部收入捐赠政策和公开账目格式。
- `docs/baseline/BGLite-2.4.0.sha256`：官方基线文件哈希。
- `tools/verify-baseline.ps1`：可复现的本地基线校验器。
- `.github/ISSUE_TEMPLATE/bug-report.yml`：错误报告表单。
- `.github/ISSUE_TEMPLATE/feature-request.yml`：功能建议和数据影响表单。
- `.github/ISSUE_TEMPLATE/config.yml`：关闭空白 Issue 并提供支持/安全入口。
- `.github/pull_request_template.md`：贡献、测试、隐私、通信和版权声明。
- `.github/workflows/baseline-integrity.yml`：Windows CI 中执行基线校验。

### Task 1: 固化 BGLite 2.4.0 基线

**Files:**
- Create: `docs/baseline/BGLite-2.4.0.sha256`
- Create: `tools/verify-baseline.ps1`

- [x] **Step 1: 生成固定哈希清单**

从初始提交 `9e0b119c66a644cce0083b5ffe4e59c6c946d0f1` 的 188 个文件生成格式为 `<SHA256>  <relative/path>` 的清单，路径统一使用 `/`，按路径排序。清单不得包含 `.git`、`docs`、`.github`、`tools` 或任何后续治理文件。

Run:

```powershell
$baseline = '9e0b119c66a644cce0083b5ffe4e59c6c946d0f1'
git ls-tree -r --name-only $baseline | Sort-Object
```

Expected: 输出 188 个路径，包含 `BGLite.toc`，不包含 `README.md`。

- [x] **Step 2: 编写严格校验脚本**

脚本读取清单，逐项验证文件存在且 SHA-256 一致；同时读取初始提交的文件列表，确保清单没有漏项或多项。失败时列出路径并返回非零退出码；成功时输出 `Baseline integrity verified: 188 files.`。

- [x] **Step 3: 运行正向校验**

Run:

```powershell
pwsh -NoProfile -File tools/verify-baseline.ps1
```

Expected: `Baseline integrity verified: 188 files.` 且退出码为 0。

- [x] **Step 4: 运行破坏性测试并恢复测试文件**

临时向 `addon_version.txt` 追加一个换行，校验应失败并点名该文件；随后用 Git 恢复测试前内容，再次校验应成功。不得提交临时改动。

- [x] **Step 5: 提交基线保护文件**

```powershell
git add docs/baseline/BGLite-2.4.0.sha256 tools/verify-baseline.ps1
git commit -m "chore: protect the BGLite 2.4.0 baseline"
```

### Task 2: 建立项目入口、身份与权利说明

**Files:**
- Create: `README.md`
- Create: `COPYRIGHT.md`
- Create: `CHANGELOG.md`

- [x] **Step 1: 创建 README**

README 必须依次包含：项目一句话说明、醒目的安全合规原则、项目缘起与非官方声明、当前 BGLite 2.4.0 基线、项目目标、不会接受的功能、安装方式、社区共创入口、贡献者致谢规则、慈善承诺、文档导航和商标版权说明。活动表述必须使用“响应活动”，不得使用“官方合作”“官方指定”或“官方认证”。

- [x] **Step 2: 创建版权与权利说明**

`COPYRIGHT.md` 明确上游和第三方内容归各自权利人；仓库不把 BGLite 代码声明为项目原创；当前不擅自添加统一开源许可证；贡献者只能提交原创或已授权内容。

- [x] **Step 3: 创建变更日志**

`CHANGELOG.md` 使用 Keep a Changelog 风格，包含 `Unreleased` 和 `2.4.0-baseline - 2026-08-26`；基线条目只记录“导入官方 BGLite 纯净版 2.4.0，未修改运行文件”。

- [x] **Step 4: 校验措辞和链接**

Run:

```powershell
rg -n "官方合作|官方指定|官方认证|MIT License|GNU General Public License" README.md COPYRIGHT.md CHANGELOG.md
```

Expected: 无匹配。

- [x] **Step 5: 提交项目入口文档**

```powershell
git add README.md COPYRIGHT.md CHANGELOG.md
git commit -m "docs: establish project identity and purpose"
```

### Task 3: 建立安全、隐私与合规边界

**Files:**
- Create: `SECURITY.md`
- Create: `PRIVACY.md`
- Create: `docs/COMPLIANCE.md`

- [x] **Step 1: 创建安全政策**

`SECURITY.md` 包含支持版本、安全问题应使用 GitHub Private Vulnerability Reporting、普通 Issue 不得披露利用细节、收到报告后的确认/评估/修复/协调披露流程，以及恶意代码、隐藏通信和数据外传的零容忍原则。不得承诺无法保证的固定修复时间。

- [x] **Step 2: 创建隐私政策**

`PRIVACY.md` 明确无遥测、本地优先、最小化处理、禁止自动上传、用户主动导出前的四项告知要求、日志和截图脱敏要求，以及政策变化必须在 Release Notes 中披露。

- [x] **Step 3: 创建合规边界**

`docs/COMPLIANCE.md` 将功能分为“通常允许”“必须单独评估”“禁止”三类，逐项覆盖官方活动的数据安全要求、知识产权、博彩现金交易、刷量、强制分享、外部程序、后台敏感行为和平台审核。

- [x] **Step 4: 交叉一致性检查**

Run:

```powershell
rg -n "自动上传|主动.*触发|本地|隐藏通信|远程控制|知识产权" SECURITY.md PRIVACY.md docs/COMPLIANCE.md
```

Expected: 三份文件均能找到与其职责相关的明确规则，且不存在允许自动上传或隐藏通信的表述。

- [x] **Step 5: 提交安全隐私文档**

```powershell
git add SECURITY.md PRIVACY.md docs/COMPLIANCE.md
git commit -m "docs: define security privacy and compliance boundaries"
```

### Task 4: 建立社区治理、贡献和支持规则

**Files:**
- Create: `CONTRIBUTING.md`
- Create: `CODE_OF_CONDUCT.md`
- Create: `CONTRIBUTORS.md`
- Create: `SUPPORT.md`
- Create: `docs/PROJECT_CHARTER.md`

- [x] **Step 1: 创建贡献指南**

指南说明 Issue 优先、Fork/分支/PR 流程、提交消息建议、必要测试、合规自查、素材来源证明和贡献授权声明。明确小型代码、测试、翻译、设计、文档和合规建议均可计入贡献。

- [x] **Step 2: 创建行为准则**

采用原创的简洁行为准则，不复制带有额外归属要求的模板。要求尊重、就事论事、保护隐私、禁止骚扰和利益冲突披露；说明维护者可编辑、隐藏或拒绝不当内容并限制参与。

- [x] **Step 3: 创建贡献者名单规则**

按代码与架构、测试与复现、翻译与文档、视觉与交互、安全隐私与合规、社区维护分类；同类不排名；无实际贡献不收录；赞助不换取署名。

- [x] **Step 4: 创建支持分流与治理章程**

`SUPPORT.md` 将使用问题、可复现错误、功能建议和安全问题分别引导到 Discussions、Issue、功能表单和私密安全报告。`docs/PROJECT_CHARTER.md` 规定维护者职责、基于证据的决策、回避利益冲突、审查门槛、发布责任和紧急回滚权。

- [x] **Step 5: 提交社区治理文档**

```powershell
git add CONTRIBUTING.md CODE_OF_CONDUCT.md CONTRIBUTORS.md SUPPORT.md docs/PROJECT_CHARTER.md
git commit -m "docs: establish community contribution governance"
```

### Task 5: 建立慈善透明政策

**Files:**
- Create: `docs/CHARITY.md`

- [x] **Step 1: 创建慈善政策与账目模板**

明确全部活动奖金、赞助及其他项目收入均不归个人；依法必须承担的税费单列，税后剩余资金全部捐赠。账目字段固定为日期、来源、收入总额、税费、可捐金额、受赠机构、捐赠日期、公开凭证和备注。凭证必须脱敏。

- [x] **Step 2: 写明利益隔离规则**

不得通过赞助换取功能优先级、代码合并、维护权限、署名排序或审核豁免；维护者与受赠机构存在利益关系时必须公开并回避决策。

- [x] **Step 3: 提交慈善政策**

```powershell
git add docs/CHARITY.md
git commit -m "docs: define transparent charity policy"
```

### Task 6: 建立 GitHub 协作模板

**Files:**
- Create: `.github/ISSUE_TEMPLATE/bug-report.yml`
- Create: `.github/ISSUE_TEMPLATE/feature-request.yml`
- Create: `.github/ISSUE_TEMPLATE/config.yml`
- Create: `.github/pull_request_template.md`

- [x] **Step 1: 创建错误报告表单**

必填字段包括游戏版本、插件版本、复现步骤、预期结果、实际结果、错误信息、其他插件排查和隐私确认。提醒提交者删除角色名、战网信息、聊天内容和其他敏感数据。

- [x] **Step 2: 创建功能建议表单**

必填字段包括用户问题、建议行为、数据读取、数据保存、外部通信、自动化行为、素材来源和替代方案。包含确认框：不要求隐藏采集、自动上传、后台敏感行为或其他禁止功能。

- [x] **Step 3: 创建 PR 模板和模板配置**

PR 模板包含改动摘要、关联 Issue、测试证据、游戏版本、数据/隐私、通信、自动化、素材版权、兼容性和基线文件变更清单。`config.yml` 关闭空白 Issue，并链接支持与安全政策。

- [x] **Step 4: 校验 YAML**

Run:

```powershell
python -c "import pathlib,yaml; [yaml.safe_load(p.read_text(encoding='utf-8')) for p in pathlib.Path('.github/ISSUE_TEMPLATE').glob('*.yml')]; print('Issue forms valid')"
```

Expected: `Issue forms valid`。

- [x] **Step 5: 提交 GitHub 模板**

```powershell
git add .github/ISSUE_TEMPLATE .github/pull_request_template.md
git commit -m "chore: add GitHub contribution templates"
```

### Task 7: 建立自动基线检查

**Files:**
- Create: `.github/workflows/baseline-integrity.yml`

- [x] **Step 1: 创建 GitHub Actions 工作流**

工作流在对 `main` 的 Pull Request 和 push 时运行，使用 `windows-latest`、`actions/checkout` 的固定主版本，并执行：

```powershell
pwsh -NoProfile -File tools/verify-baseline.ps1
```

工作流只授予 `contents: read` 权限，不上传仓库数据和构建产物。

- [x] **Step 2: 校验工作流 YAML 和权限**

Run:

```powershell
python -c "import yaml; d=yaml.safe_load(open('.github/workflows/baseline-integrity.yml',encoding='utf-8')); assert d['permissions']=={'contents':'read'}; print('Workflow valid')"
```

Expected: `Workflow valid`。

- [x] **Step 3: 提交工作流**

```powershell
git add .github/workflows/baseline-integrity.yml
git commit -m "ci: verify the upstream baseline"
```

### Task 8: 最终验证并发布文档变更

**Files:**
- Verify: all files created in Tasks 1-7

- [x] **Step 1: 验证官方基线完整性**

Run:

```powershell
pwsh -NoProfile -File tools/verify-baseline.ps1
```

Expected: `Baseline integrity verified: 188 files.`。

- [x] **Step 2: 验证仓库结构和文档链接**

检查所有计划文件存在；扫描 Markdown 相对链接，确认目标存在；扫描未完成标记、空链接和危险的官方背书措辞，结果必须为零。

- [x] **Step 3: 验证变更范围**

Run:

```powershell
git diff --name-only 9e0b119c66a644cce0083b5ffe4e59c6c946d0f1..HEAD
```

Expected: 只包含 Markdown、`.github`、`docs` 和 `tools/verify-baseline.ps1`；不包含原有 188 个运行文件。

- [x] **Step 4: 推送 main**

```powershell
git push origin main
```

- [x] **Step 5: 核验 GitHub**

确认默认分支为 `main`，README 正常展示，旧 PR/标签/Release 仍为空，新提交可见，GitHub Actions 已触发或可被识别。
