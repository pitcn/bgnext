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
        "插件安装目录已更名为 BGNext 文件夹，并换用新的 BGNext 图标。",
        "小地图按钮现在可以打开金团表格、角色总览和设置，角色总览快捷键也已恢复。",
        "聊天中明确显示的 YY 号码可以手动点击复制；只处理当前可见消息，不保存聊天历史。",
        "加强拍卖金额校验和消息限流，减少异常消息对正常拍卖的影响。",
        "对账数据仅用于当前游戏会话，不再保存其他玩家的历史账单。",
        "从旧版本升级时请删除 AddOns 下原有的 BGLite 文件夹，但不要删除 WTF 或 BiaoGe.lua 存档。",
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
