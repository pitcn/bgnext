# 无限服旧 API 调用修正

玩家实测出现 `DB.lua` 天赋读取 nil 调用、`hooks.lua` 的背包离开钩子不存在、`Auction.lua` 的修改键点击钩子不存在。主窗口初始化也调用了同一个不存在的点击钩子；该处被既有 pcall 捕获，因此停留在通用加载错误提示。

上一版只核对游戏数据和路由，没有核对这些运行时 API，验证范围不足。

## 精确源码证据

使用 wowdoc，对 `wow-ui-source` / `forever` / Tag `1.60.1`，解析到 Commit `ca8368f2f2380cbe696854f7f2646387c278a61b`，没有使用 latest fallback。来源仓库为 Gethe/wow-ui-source；这是按版本归档的 Blizzard UI/API 源码证据，不是本地运行结果。

- `Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:1668`：`ContainerFrameItemButtonMixin:OnClick(button)`。
- 同文件 `:1690`：`OnEnter()`；`:1706`：`OnLeave()`，内部调用 GameTooltip_Hide；`:1766`：`OnModifiedClick(button)` 使用 `self:GetBagID()` / `self:GetID()`。
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/SpecializationInfoDocumentation.lua:237`：命名空间 `C_SpecializationInfo.GetSpecialization`，返回 specializationIndex，specGroupIndex 为可选参数。
- `Interface/AddOns/Blizzard_DeprecatedSpecialization/Deprecated_Specialization_Vanilla.lua:10` 将旧 GetTalentTabInfo 转接到命名空间接口。不能根据其他客户端的兼容别名推断无限服实际存在该全局函数；玩家实测已证明旧调用失败。

## 改动

新增无存储、无发送的 ClientCompat。背包钩子保留可用旧入口；否则在实际按钮上 HookScript，并在 Mixin OnLoad 时为新按钮装配，弱引用去重。不能只 hook Mixin 的 OnClick，因为旧按钮已复制了原方法。已有框体通过 ContainerFrameUtil_EnumerateContainerFrames 与 BaseContainerFrameMixin:EnumerateItems（同文件 :563）枚举。离开可用 GameTooltip_Hide 时保留该钩子。背包定位优先 GetBagID，旧按钮退回父框体 ID。Alt 拍卖及 Shift 插入继续调用原有流程，不新增发送动作，不替换暴雪函数或创建全局兼容别名。

Forever 的角色天赋读命名空间索引；旧客户端继续读旧树接口，组接口不存在时使用其可选默认参数。缺失/无选择时返回未知，不使登录回调中断。

对 DB.lua、DB.xml、BiaoGe.lua、Auction.lua、hooks.lua 和三个 Locale 文件分别审阅后更新对应 override。Locale 补上上一版新增目录使用但尚未显式翻译的奥妮克希亚的巢穴。

## 回归证据

测试执行真实调用点代码，在缺少旧全局函数、存在 Mixin 和命名空间天赋 API 的环境重现原错误（RED），修复后验证 Alt 右键、Shift 插入、悬停离开、bag ID、天赋索引及旧客户端路径（GREEN）。现有拍卖发送测试继续执行原安全门槛。完整 Lua 套件 117 项通过。

这些是受控接口模拟和版本源码证据，尚未完成修正版游戏内加载、拍卖或拾取验证。未读取真实角色存档，不记录或传播玩家身份、角色名或原始错误 locals。
