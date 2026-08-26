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
            "本项目为独立、非官方社区项目，不代表上游作者或任何平台背书。",
            "所有增强功能遵守本地优先、最小必要和可审计原则。",
        }, "\n\n")
    elseif kind == "changelog" then
        return "当前版本更新\n\n" .. bulletList(info.changelog)
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
