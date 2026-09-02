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
        "新增价格预设：团长可按团本保存多套起拍价方案，团员可为自己的角色保存单件心理价；打开拍卖或出价窗口时自动预填，最终仍由玩家手动确认。",
        "新增团队拍卖就绪检查：进入团队后底部显示“团队拍卖：已就绪 X/Y”，悬停可逐人查看状态；未响应成员不再被误标为未安装。",
        "新增可切换的 BGNext 预览外观：保持原版账单布局、半透明背景和同屏容量，可在“外观预览”设置中随时切回经典外观。",
        "价格预设页改为高密度双列展示并移除装饰性 Boss 模型，整体字号与颜色更易读。",
    },
    credits = {
        upstream = {
            "CQZS (Lite) — BGLite 2.4.0 上游作者",
        },
        contributors = {
            "Yuke Huang (@pitcn) — BGNext 发起与社区维护",
            "国服社区贡献者、测试者与安全报告者",
        },
    },
}

BG.BGNext.ReleaseInfo = info
return info
