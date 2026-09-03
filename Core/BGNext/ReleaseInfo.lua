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
        L["心愿清单：新选装备默认备选，可用滚轮按备选、次 BIS、BIS 切换；已有优先级保持不变。"],
        L["心愿优先级改用独立文字徽标，不遮挡装备名称与装等；长列表可以滚动。"],
        L["修复价格预设失焦保存、Alt+右键按预设开拍、Ctrl+右键改价；支持旧价格和心愿字符串导入。"],
        L["同时拍卖相同装备时，收到有效出价后同步刷新截止时间。"],
        L["减少角色总览和背包变化时的重复刷新；结算检查不再每秒扫描账单。"],
        L["新增当前团结算前检查，提示欠款、缺失账目信息及待核对交易；证据不足时不会自动判为结清。"],
        L["新增存储与隐私清理入口，旧历史数据只有手动确认后才删除；修复该页面的文字报错。"],
        L["完善简中、繁中与其他语言回落英文的文案及部分按钮排版。"],
    },
    credits = {
        upstream = {
            "CQZS (Lite) — BGLite 2.4.0 上游作者",
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
