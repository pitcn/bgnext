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
    summary = "由国服玩家共同维护的非官方金团表格插件。",
    activityUrl = "https://m.ds.163.com/article/6a8e490b5b32bc1f3ab97aaa/?isNew=1",
    repositoryUrl = "https://github.com/pitcn/bgnext",
    changelog = {
        "修复在表格装备格按住 Alt 右键无法直接发起拍卖的问题。",
        "修复团长自己拍得装备时，带服务器名的角色未被识别为本人而无法记账的问题。",
        "拍卖记录和由拍卖记录回填的账单现在会正确显示买家职业颜色。",
        "装备过滤方案旁新增红叉按钮，可临时显示全部装备，并随时恢复原方案。",
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
