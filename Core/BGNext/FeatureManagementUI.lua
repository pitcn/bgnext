local _, ns = ...

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local L = ns and ns.L or setmetatable({}, { __index = function(_, key) return tostring(key) end })
local M = {}

local function familyFromGlobals()
    local adapters = BG.BGNext.OwnCharactersAdapters
    if adapters and type(adapters.detect) == "function" then return adapters.detect(BG) end
    if BG.IsRetail then return "retail" end
    if BG.IsMOP then return "mop" end
    if BG.IsCTM then return "cata" end
    if BG.IsTitan then return "titan" end
    if BG.IsWLK then return "wrath" end
    if BG.IsTBC then return "tbc" end
    if BG.IsVanilla then return "vanilla" end
end

function M.viewModel(root, family)
    local catalog, settings = BG.BGNext.FeatureCatalog, BG.BGNext.FeatureSettings
    local result = { mode = settings.mode(root, family), groups = {} }
    for _, group in ipairs(catalog.groups()) do
        local projected = { id = group.id, titleKey = group.titleKey, rows = {} }
        for _, entry in ipairs(catalog.all()) do
            if entry.group == group.id and catalog.available(entry, family) then
                local required = entry.policy == "required"
                projected.rows[#projected.rows + 1] = {
                    id = entry.id,
                    nameKey = entry.nameKey,
                    summaryKey = entry.summaryKey,
                    required = required,
                    saved = required and nil or settings.savedValue(root, entry.id),
                    enabled = settings.isEnabled(root, entry.id, family),
                }
            end
        end
        if #projected.rows > 0 then result.groups[#result.groups + 1] = projected end
    end
    return result
end

function M.applyMode(root, family, mode)
    return BG.BGNext.FeatureSettings.applyMode(root, mode, family)
end

function M.toggleFeature(root, family, id, value)
    local catalog = BG.BGNext.FeatureCatalog
    local entry = catalog.get(id)
    if not entry then return false, "unknown" end
    if not catalog.available(entry, family) then return false, "unavailable" end
    return BG.BGNext.FeatureSettings.setEnabled(root, id, value)
end

function M.buildPanel()
    if type(CreateFrame) ~= "function" or type(BG.OptionsCreateTab) ~= "function"
        or type(BG.CreateButton) ~= "function" or type(BG.BGNext.DB) ~= "table"
        or not BG.BGNext.FeatureCatalog or not BG.BGNext.FeatureSettings then return nil end

    local family = familyFromGlobals()
    if not family then return nil end
    local panel = BG.OptionsCreateTab("Options_featureManagement", L["功能管理"])
    if type(panel) ~= "table" then return nil end
    local widgets, y = {}, 0

    local title = panel:CreateFontString()
    title:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
    title:SetPoint("TOPLEFT", panel, 15, y)
    title:SetText(L["BGNext 功能管理"])
    y = y - 28

    local modeText = panel:CreateFontString()
    modeText:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    modeText:SetPoint("TOPLEFT", panel, 15, y)
    y = y - 28

    local fullButton = BG.CreateButton(panel)
    fullButton:SetPoint("TOPLEFT", panel, 15, y)
    fullButton:SetText(L["完整模式"])
    fullButton:SetSize(math.max(95, fullButton:GetFontString():GetStringWidth() + 24), 24)
    local basicButton = BG.CreateButton(panel)
    basicButton:SetPoint("LEFT", fullButton, "RIGHT", 10, 0)
    basicButton:SetText(L["基础模式"])
    basicButton:SetSize(math.max(95, basicButton:GetFontString():GetStringWidth() + 24), 24)
    y = y - 42

    local function render()
        for _, widget in ipairs(widgets) do widget:Hide() end
        widgets, y = {}, -98
        local model = M.viewModel(BG.BGNext.DB, family)
        local modeLabels = { full = L["完整模式"], basic = L["基础模式"], custom = L["自定义模式"] }
        modeText:SetText(L["当前模式："] .. (modeLabels[model.mode] or model.mode))
        for _, group in ipairs(model.groups) do
            local heading = panel:CreateFontString()
            widgets[#widgets + 1] = heading
            heading:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
            heading:SetTextColor(0, 0.75, 1)
            heading:SetPoint("TOPLEFT", panel, 15, y)
            heading:SetText(L[group.titleKey])
            y = y - 25
            for _, row in ipairs(group.rows) do
                local line = CreateFrame("Frame", nil, panel)
                widgets[#widgets + 1] = line
                line:SetPoint("TOPLEFT", panel, 15, y)
                line:SetSize(620, 46)
                if row.required then
                    local name = line:CreateFontString()
                    name:SetPoint("TOPLEFT", line, 24, 0)
                    name:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
                    name:SetText(L[row.nameKey] .. " |cff80c0ff" .. L["（必需）"] .. "|r")
                else
                    local check = CreateFrame("CheckButton", nil, line, "UICheckButtonTemplate")
                    check:SetPoint("TOPLEFT", line, 0, 4)
                    check:SetChecked(row.enabled)
                    check:SetScript("OnClick", function(self)
                        M.toggleFeature(BG.BGNext.DB, family, row.id, self:GetChecked() and true or false)
                        render()
                    end)
                    local name = line:CreateFontString()
                    name:SetPoint("TOPLEFT", line, 24, 0)
                    name:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
                    name:SetText(L[row.nameKey])
                end
                local summary = line:CreateFontString()
                summary:SetPoint("TOPLEFT", line, 24, -20)
                summary:SetWidth(570)
                summary:SetJustifyH("LEFT")
                summary:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
                summary:SetTextColor(0.75, 0.75, 0.75)
                summary:SetText(L[row.summaryKey])
                y = y - 49
            end
            y = y - 8
        end
        panel:SetSize(650, math.max(1, -y + 20))
    end

    fullButton:SetScript("OnClick", function() M.applyMode(BG.BGNext.DB, family, "full"); render() end)
    basicButton:SetScript("OnClick", function() M.applyMode(BG.BGNext.DB, family, "basic"); render() end)
    render()
    return panel
end

if type(BG.Init) == "function" then BG.Init(function() M.buildPanel() end) end

BG.BGNext.FeatureManagementUI = M
return M
