local _, ns = ...

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local L = ns and ns.L or setmetatable({}, { __index = function(_, key) return tostring(key) end })
local M = {}
local window

local interactionLines = {
    table_right_click = "表格装备：右键删除该装备（不可撤销）。",
    table_ctrl_right_click = "表格装备：Ctrl+右键编辑单件预设价格。",
    table_alt_right_click = "表格装备：Alt+右键按当前预设打开拍卖确认。",
    table_shift_right_click = "表格装备：Shift+右键执行原版快捷交互。",
    wishlist_mouse_wheel = "心愿装备：滚轮切换备选、次 BIS、BIS。",
    loot_auction_button = "拾取窗口：有拾取职责时可把 Boss 掉落加入待拍队列。",
}

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

function M.hoverLines()
    return { L["点击打开完整说明书"], L["包含功能、快捷键、命令与隐私说明。"] }
end

function M.sections(root, family)
    local catalog, settings = BG.BGNext.FeatureCatalog, BG.BGNext.FeatureSettings
    local actions = catalog.publicActions()
    local quick = {
        id = "quick_start",
        title = L["快速开始"],
        lines = {
            L["输入 /bgn 或 /bgnext 打开主窗口；/bgo 打开设置；/bgm 解锁移动。"],
            L["输入 /bgnqueue 或 /bgnq 打开待拍队列。"],
            L["完整模式启用全部可选功能；基础模式只保留原版流程和必需保护；单独改动后显示为自定义模式。"],
        },
    }
    for _, interaction in ipairs(actions.interactions) do
        if interactionLines[interaction] then quick.lines[#quick.lines + 1] = L[interactionLines[interaction]] end
    end

    local result = { quick }
    for _, group in ipairs(catalog.groups()) do
        local section = { id = group.id, title = L[group.titleKey], lines = {} }
        for _, entry in ipairs(catalog.all()) do
            if entry.group == group.id and catalog.available(entry, family) then
                local annotation
                if entry.policy == "required" then annotation = L["必需，不能关闭"]
                elseif not settings.isEnabled(root, entry.id, family) then annotation = L["已关闭"]
                else annotation = L["已启用"] end
                section.lines[#section.lines + 1] = L[entry.nameKey] .. " · " .. annotation .. "\n" .. L[entry.summaryKey]
                for _, command in ipairs(entry.commands or {}) do
                    section.lines[#section.lines + 1] = L["命令："] .. command
                end
            end
        end
        if #section.lines > 0 then result[#result + 1] = section end
    end
    return result
end

local function releaseLines()
    if not window then return end
    for _, line in ipairs(window.active or {}) do line:Hide() end
    window.active = {}
end

local function render()
    if not window then return end
    releaseLines()
    local root, family = BG.BGNext.DB, familyFromGlobals()
    if not root or not family then return end
    local y, index = -8, 0
    for _, section in ipairs(M.sections(root, family)) do
        index = index + 1
        local heading = window.pool[index]
        if not heading then heading = window.child:CreateFontString(); window.pool[index] = heading end
        window.active[#window.active + 1] = heading
        heading:Show()
        heading:ClearAllPoints()
        heading:SetPoint("TOPLEFT", window.child, 8, y)
        heading:SetWidth(window.contentWidth - 16)
        heading:SetJustifyH("LEFT")
        heading:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
        heading:SetTextColor(0, 0.75, 1)
        heading:SetText(section.title)
        y = y - 28
        for _, value in ipairs(section.lines) do
            index = index + 1
            local line = window.pool[index]
            if not line then line = window.child:CreateFontString(); window.pool[index] = line end
            window.active[#window.active + 1] = line
            line:Show()
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", window.child, 16, y)
            line:SetWidth(window.contentWidth - 28)
            line:SetJustifyH("LEFT")
            line:SetWordWrap(true)
            line:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
            line:SetTextColor(0.9, 0.9, 0.9)
            line:SetText("• " .. value)
            local height = math.max(18, line:GetStringHeight())
            y = y - height - 8
        end
        y = y - 8
    end
    window.child:SetHeight(math.max(window.scrollHeight, -y + 12))
end

local function createWindow()
    if type(CreateFrame) ~= "function" or type(BG.CreateMainFrame) ~= "function"
        or type(BG.CreateScrollFrame) ~= "function" then return nil end
    local parentHeight = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 768
    local height = math.max(360, math.min(650, parentHeight - 100))
    local width = 690
    local frame = BG.CreateMainFrame()
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:Hide()
    frame.titleText:SetText(L["BGNext 说明书"])
    local scrollHeight = height - 42
    local scroll, child = BG.CreateScrollFrame(frame, width - 24, scrollHeight)
    scroll:SetPoint("TOPLEFT", frame, 12, -30)
    window = { frame = frame, scroll = scroll, child = child, contentWidth = width - 55,
        scrollHeight = scrollHeight, pool = {}, active = {} }
    frame:SetScript("OnShow", render)
    frame:SetScript("OnHide", releaseLines)
    return window
end

function M.toggle()
    if not window and not createWindow() then return false end
    if window.frame:IsShown() then window.frame:Hide() else window.frame:Show() end
    return true
end

function M.install()
    if type(BG.ShuoMingShu) ~= "table" or type(BG.ShuoMingShu.SetScript) ~= "function" then return false end
    BG.ShuoMingShu:EnableMouse(true)
    BG.ShuoMingShu:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then M.toggle() end
    end)
    return true
end

if type(BG.Init) == "function" then BG.Init(function() M.install() end) end

BG.BGNext.GuideUI = M
return M
