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
        L["紧急修复团长或物品分配者拍卖成功后，主表不自动填写买家和成交金额的问题。"],
        L["新增可选团长工具：支出模板、多拍品中心、实收与分金预览；均可在功能管理中单独开关。"],
        L["新增默认关闭的本地成交摘要；只在手动确认后保存最小信息，并可设置保留期或一键清空。"],
        L["改进新副本进度清表和交易候选过期处理，只处理当前副本范围，避免影响其他账表数据。"],
    },
    history = {
        { version = "0.7.0", changelog = { L["新增增强模式与游戏内说明书，重做待拍队列和 Boss 拾取拍卖入口，并改进拍卖、交易、退货与熊猫人角色追踪。"] } },
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
            "Pit (@pitcn) — BGNext 发起与社区维护",
            "Wesley (@wesleysui) — 副本标签切换高亮修复",
            "国服社区贡献者、测试者与安全报告者",
        },
    },
}

BG.BGNext.ReleaseInfo = info
return info
