BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

local function bulletList(values)
    local lines = {}
    for _, value in ipairs(values or {}) do
        lines[#lines + 1] = "• " .. value
    end
    return table.concat(lines, "\n")
end

function M.buildText(kind, info)
    if kind == "about" then
        return table.concat({
            info.projectName,
            info.summary,
            "作者：" .. info.author,
            "项目缘起",
            "BGNext 响应网易DD发起的“BGLite增强版开发激励活动”而建立。项目由社区自行开发和维护，不是《魔兽世界》、网易DD或 BGLite 上游作者的官方产品，也不代表任何一方对本项目背书。",
            "活动公告：" .. info.activityUrl,
            "代码与版权",
            "BGNext 以活动提供的 BGLite 2.4.0 纯净版为基础。BGLite 上游代码和既有通信标识保留原有权利归属；BGNext 新增功能代码由社区独立原创实现。插件提交明文源码，不使用代码混淆或加密。",
            "数据与隐私",
            table.concat({
                "• 数据默认保存在玩家本地。",
                "• 除当前团队协作所需的游戏内消息外，不自动向游戏外上传或同步数据。",
                "• 不生成他人的历史信息记录，不建立第三方排名，也不做玩家画像。",
                "• 导出或传输必须由玩家主动触发，并在操作前说明内容和用途。",
                "• 不加入遥测、后门、远程控制或外部可执行程序。",
            }, "\n"),
            "公益承诺",
            "与 BGNext 有关的活动奖金、赞助及其他项目收入不作为个人收益。依法必须承担的税费会单独记录；扣除这些税费后，剩余资金全部捐赠给具备合法资质、信息可核验的慈善组织，并公开脱敏后的收支和捐赠凭证。",
            "社区共创",
            "欢迎通过 GitHub 提交建议、问题和代码。贡献者、测试者及安全问题报告者会在征得同意后列入感谢名单。",
            "项目地址：" .. info.repositoryUrl,
        }, "\n\n")
    elseif kind == "changelog" then
        return info.projectName .. " " .. info.version .. " 更新内容\n\n" .. bulletList(info.changelog)
    elseif kind == "credits" then
        return table.concat({
            "上游致谢",
            bulletList(info.credits.upstream),
            "",
            "社区贡献",
            bulletList(info.credits.contributors),
            "",
            "完整、可核验名单见仓库 CONTRIBUTORS.md。",
        }, "\n")
    end
    return ""
end

local function createPanel(info)
    local panel = CreateFrame("Frame", nil, BG.MainFrame, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", BG.MainFrame, "TOPLEFT", 18, -34)
    panel:SetPoint("BOTTOMRIGHT", BG.MainFrame, "BOTTOMRIGHT", -18, 34)
    panel:SetFrameLevel(BG.MainFrame:GetFrameLevel() + 20)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeSize = 1 })
    panel:SetBackdropColor(0.03, 0.03, 0.03, 0.97)
    panel:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
    panel:Hide()

    local title = panel:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -12)
    title:SetFont(BIAOGE_TEXT_FONT, 17, "OUTLINE")
    title:SetTextColor(1, 0.82, 0)

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 2, 2)

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 14)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    local body = content:CreateFontString(nil, "OVERLAY")
    body:SetPoint("TOPLEFT")
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetSpacing(5)
    body:SetFont(BIAOGE_TEXT_FONT, 14, "")
    body:SetTextColor(0.92, 0.92, 0.92)

    panel:SetScript("OnSizeChanged", function(_, width)
        content:SetWidth(math.max(1, width - 68))
        body:SetWidth(math.max(1, width - 68))
        content:SetHeight(math.max(1, body:GetStringHeight()))
    end)

    function panel:ShowSection(kind, label)
        title:SetText(label)
        body:SetText(M.buildText(kind, info))
        content:SetHeight(math.max(1, body:GetStringHeight()))
        self:Show()
    end

    return panel
end

if BG.Init then
    BG.Init(function()
        if not BG.MainFrame or not BG.CreateButton or not BG.BGNext.ReleaseInfo then
            return
        end
        local panel = createPanel(BG.BGNext.ReleaseInfo)
        BG.BGNext.AboutPanel = panel

        local buttons = {
            { label = "关于", kind = "about", width = 54 },
            { label = "更新日志", kind = "changelog", width = 72 },
            { label = "感谢名单", kind = "credits", width = 72 },
        }
        local previous
        for _, definition in ipairs(buttons) do
            local kind = definition.kind
            local label = definition.label
            local button = BG.CreateButton(BG.MainFrame)
            button:SetSize(definition.width, 19)
            button:SetText(label)
            if previous then
                button:SetPoint("RIGHT", previous, "LEFT", -4, 0)
            elseif BG.ButtonExportHope then
                button:SetPoint("RIGHT", BG.ButtonExportHope, "LEFT", -12, 0)
            else
                button:SetPoint("TOPRIGHT", BG.MainFrame, "TOPRIGHT", -31, -2)
            end
            button:SetScript("OnClick", function()
                panel:ShowSection(kind, label)
            end)
            previous = button
        end
    end)
end

BG.BGNext.About = M
return M
