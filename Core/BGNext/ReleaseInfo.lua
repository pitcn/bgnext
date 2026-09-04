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
        L["新增团长待拍队列：逐件确认价格后开拍，不会自动连拍；离团、切表或重载即清空。"],
        L["拍卖结束后，侧边卡片会短暂显示买家和成交金额；流拍或取消也有明确状态。"],
        L["交易记录改进：保留同物品多件数量，确认时采集双方物品与金币，并区分已交易和待核对。"],
        L["修复交易成功或失败通报；同一交易只通报一次，不记录聊天内容或跨团历史。"],
        L["价格预设快捷开拍统一进行权限、战斗、活动拍卖、方案和价格检查；价格列表会随窗口自动重排。"],
        L["进入新进度时，如旧表仍有未结算内容，自动清空前会先确认；取消不会删除。"],
        L["正式服角色总览按 Boss 和难度统计团本进度；证据不足时留空，不显示错误完成状态。"],
        L["修复底栏按钮重叠及表格组合键误删装备；待拍窗口新增关闭按钮并统一外观。"],
        L["上游基础升级到官方 BGLite 纯净版 2.4.1；拍卖聊天不再跨重载保存，并补充拍卖记录空数据容错。"],
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
