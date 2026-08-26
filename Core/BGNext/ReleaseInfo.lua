BG = BG or {}
BG.BGNext = BG.BGNext or {}

local identity = assert(BG.BGNext.Identity, "BGNext Identity must load before ReleaseInfo")

local info = {
    projectName = identity.projectName,
    version = identity.version,
    upstreamName = identity.upstreamName,
    upstreamVersion = identity.upstreamVersion,
    protocolVersion = identity.protocolVersion,
    author = "国服社区共创",
    official = false,
    summary = "基于 BGLite 上游维护的独立、非官方社区共创项目。",
    changelog = {
        "建立可重复执行的 Lua 5.1 测试与基线校验。",
        "停用上游遗留的跨角色交易和邮件历史采集入口。",
        "新增最近一次团本、最长七日的数据生命周期基础。",
        "新增仅本人可见的分副本心愿清单，以及当前掉落和拍卖提醒。",
    },
    credits = {
        upstream = {
            "CQZS (Lite) — BGLite 2.4.0 上游作者",
        },
        contributors = {
            "国服社区贡献者、测试者与安全报告者",
        },
    },
}

BG.BGNext.ReleaseInfo = info
return info
