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
        "在 BGLite 2.4.0 的基础上建立 BGNext，保留原有团队拍卖兼容能力。",
        "重新整理个人心愿清单：按副本、难度和首领分别记录，支持本地提醒及手动导入、导出。",
        "加入装备过滤和自有角色总览，方便查看自己的副本进度、常用装备与资源。",
        "加入当前团本购物、交易和邮件核对；只保留最近一个团，最长七天，不保存邮件正文。",
        "修正自动出价连续跟价、异常输入处理和部分界面错位问题。",
        "加入重复插件提醒，停用旧跨团历史入口，并收紧数据保存与消息校验。",
        "经典永久 60、周年服 TBC、熊猫人及正式服的角色总览适配仍待对应客户端实测。",
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
