BG = BG or {}
BG.BGNext = BG.BGNext or {}

local UITheme = BG.BGNext.UITheme

local M = {}

-- read resolves the saved theme choice to a normalized value without writing.
function M.read(root)
    if type(root) ~= "table" or type(root.settings) ~= "table" then
        return "classic"
    end
    return UITheme.normalize(root.settings.uiTheme)
end

-- choose validates the theme, applies it through the supplied function, and
-- persists the value only after a successful apply.
function M.choose(root, themeId, apply)
    if themeId ~= "classic" and themeId ~= "preview" then
        return false, "invalid-theme"
    end
    if type(root) ~= "table" then
        return false, "no-root"
    end
    if type(apply) ~= "function" then
        return false, "no-apply"
    end
    local ok, err = apply(themeId)
    if not ok then
        return false, err
    end
    if type(root.settings) ~= "table" then
        root.settings = {}
    end
    root.settings.uiTheme = themeId
    return true
end

-- buildPanel constructs the isolated appearance tab. It returns harmlessly
-- unless every required existing API and runtime module is available.
function M.buildPanel()
    if type(BG) ~= "table"
        or type(BG.OptionsCreateTab) ~= "function"
        or type(BG.CreateButton) ~= "function"
        or type(BG.BGNext) ~= "table"
        or type(BG.BGNext.DB) ~= "table"
        or type(BG.BGNext.LegacyLedgerSkin) ~= "table" then
        return
    end

    local Skin = BG.BGNext.LegacyLedgerSkin
    local UIStyle = BG.BGNext.UIStyle
    local panel = BG.OptionsCreateTab("Options_appearance", "外观预览")
    if type(panel) ~= "table" then
        return
    end

    local y = 0

    local heading = panel:CreateFontString()
    heading:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
    heading:SetTextColor(1, 1, 1)
    heading:SetText("BGNext 外观")
    heading:SetPoint("TOPLEFT", panel, 15, y)
    y = y - 32

    local description = panel:CreateFontString()
    description:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    description:SetTextColor(1, 1, 1)
    description:SetText("预览主题只改变团队账单外观，不改变布局、透明度、拍卖或账单数据。")
    description:SetPoint("TOPLEFT", panel, 15, y)
    y = y - 40

    local status = panel:CreateFontString()
    status:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    status:SetTextColor(1, 0.82, 0)
    status:SetPoint("TOPLEFT", panel, 15, y)

    local function refresh()
        local current = M.read(BG.BGNext.DB)
        status:SetText(current == "preview" and "当前：BGNext 预览" or "当前：经典外观")
    end

    local classicButton = BG.CreateButton(panel)
    classicButton:SetSize(100, 25)
    classicButton:SetPoint("TOPLEFT", panel, 15, y - 32)
    classicButton:SetText("经典外观")
    classicButton:SetScript("OnClick", function()
        local ok = M.choose(BG.BGNext.DB, "classic", function(id)
            local applied, err = Skin.apply(id, Skin.buildRuntimeRegistry(), BiaoGe.options.alpha)
            if applied and UIStyle then UIStyle.refreshButtons(id, BiaoGe.options.alpha) end
            return applied, err
        end)
        if ok then
            refresh()
        end
    end)

    local previewButton = BG.CreateButton(panel)
    previewButton:SetSize(100, 25)
    previewButton:SetPoint("LEFT", classicButton, "RIGHT", 10, 0)
    previewButton:SetText("BGNext 预览")
    previewButton:SetScript("OnClick", function()
        local ok = M.choose(BG.BGNext.DB, "preview", function(id)
            local applied, err = Skin.apply(id, Skin.buildRuntimeRegistry(), BiaoGe.options.alpha)
            if applied and UIStyle then UIStyle.refreshButtons(id, BiaoGe.options.alpha) end
            return applied, err
        end)
        if ok then
            refresh()
        end
    end)

    local note = panel:CreateFontString()
    note:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    note:SetTextColor(0.8, 0.8, 0.8)
    note:SetText("预览主题仍在测试；如遇显示问题可立即切回经典外观。")
    note:SetPoint("TOPLEFT", panel, 15, y - 72)

    refresh()
end

if type(BG) == "table" and type(BG.Init) == "function" then
    BG.Init(function()
        M.buildPanel()
    end)
end

BG.BGNext.UIThemeSettings = M
return M
