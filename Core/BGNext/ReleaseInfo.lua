BG = BG or {}
BG.BGNext = BG.BGNext or {}
local _, ns = ...
local L = ns and ns.L or setmetatable({}, { __index = function(_, key) return key end })

local identity = assert(BG.BGNext.Identity, "BGNext Identity must load before ReleaseInfo")

local info = {
    projectName = identity.projectName,
    version = identity.version,
    upstreamName = identity.upstreamName,
    upstreamVersion = identity.upstreamVersion,
    protocolVersion = identity.protocolVersion,
    author = "国服社区共创",
    official = false,
    summary = L["BGNext 是为金团记账、拍卖和结算准备的非官方社区插件：团长管理起拍价与账单，团员整理心愿和个人心理价，自己的角色进度集中查看。"],
    activityUrl = "https://m.ds.163.com/article/6a8e490b5b32bc1f3ab97aaa/?isNew=1",
    repositoryUrl = "https://github.com/pitcn/bgnext",
    changelog = {
        L["新增基础模式、完整模式和自定义模式；可按功能组关闭增强功能，已保存数据不会被删除。"],
        L["新增游戏内说明书，集中介绍主要功能、快捷键、命令、权限限制和隐私边界；更新日志可查看历代版本。"],
        L["重做待拍队列的布局、关闭与清空交互；输入框支持 Shift+点击背包装备，也可粘贴物品链接或输入物品ID。"],
        L["有团长或拾取职责时，Boss 拾取窗口新增可见拍卖入口，并复用统一的开拍安全检查。"],
        L["修复混合使用 BGNext 与 BGLite 时同物品拍卖计时不同步、卡片误隐藏及拍卖结果缺失。"],
        L["修复部分成功交易和邮件记录遗漏；交易记录继续区分已交易与待核对，不把未知金额伪造为零。"],
        L["当前团账单可标记退货待处理并在结算前提醒，不会自动退款或改写原买家与金额。"],
        L["熊猫人角色总览新增天神首胜、农场收菜、四天神和斡耳朵斯追踪；证据不足时显示未知。"],
        L["上游基础升级到官方 BGLite 2.4.2 纯净版，并保留 BGNext 的隐私与发送前安全保护。"],
    },
    history = {
        { version = "0.6.0", changelog = { L["新增待拍队列并修复拍卖结果、交易记录、交易通报、预设开拍和正式服团本进度。"] } },
        { version = "0.5.0", changelog = { L["新增备选、次 BIS、BIS 三级心愿、结算前检查、旧历史清理，并优化价格预设和性能。"] } },
        { version = "0.4.0", changelog = { L["新增多套团长起拍价、个人心理价、团队拍卖就绪检查和可切换预览外观。"] } },
        { version = "0.3.1", changelog = { L["修复 Alt+右键开拍、姓名匹配和拍卖记录职业颜色，并增加临时关闭装备过滤。"] } },
        { version = "0.3.0", changelog = { L["装备过滤改为按客户端与专精提供默认方案，并修复角色姓名、交易匹配和角色总览交互。"] } },
        { version = "0.2.3", changelog = { L["修复正式服心愿与角色总览显示，改进表格缩放，并新增 /biaoge 兼容命令。"] } },
        { version = "0.2.2", changelog = { L["修复跨客户端拍卖编号兼容、小地图菜单和货币上限显示，并精简拍卖发起窗口。"] } },
        { version = "0.2.1", changelog = { L["修复启动时访问停用窗口及简体中文临时对账按钮报错。"] } },
        { version = "0.2.0", changelog = { L["统一 BGNext 身份与安装目录，新增图标、小地图入口、YY 复制和拍卖安全改进。"] } },
        { version = "0.1.0", changelog = { L["首个社区版本：新增心愿、装备过滤、自有角色总览和当前团核对，并停止加载跨团历史功能。"] } },
    },
    credits = {
        upstream = {
            "CQZS (Lite) — BGLite 2.4.2 上游作者",
        },
        contributors = {
            "Yuke Huang (@pitcn) — BGNext 发起与社区维护",
            "Wesley (@wesleysui) — 副本标签切换高亮修复",
            "国服社区贡献者、测试者与安全报告者",
        },
    },
}

BG.BGNext.ReleaseInfo = info
return info
