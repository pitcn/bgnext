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
        L["新增游戏内说明书，集中介绍主要功能、快捷键、命令、权限限制和隐私边界。"],
        L["重做待拍队列的布局、关闭与清空交互，窗口尺寸变化时会自动重排。"],
        L["有团长或拾取职责时，Boss 拾取窗口新增可见拍卖入口，并复用统一的开拍安全检查。"],
        L["修复混合使用 BGNext 与 BGLite 时同物品拍卖计时不同步、卡片误隐藏及拍卖结果缺失。"],
        L["修复部分成功交易和邮件记录遗漏；交易记录继续区分已交易与待核对，不把未知金额伪造为零。"],
        L["当前团账单可标记退货待处理并在结算前提醒，不会自动退款或改写原买家与金额。"],
        L["熊猫人角色总览新增天神首胜、农场收菜、四天神和斡耳朵斯追踪；证据不足时显示未知。"],
        L["上游基础升级到官方 BGLite 2.4.2 纯净版，并保留 BGNext 的隐私与发送前安全保护。"],
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
