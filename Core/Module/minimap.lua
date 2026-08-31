if BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local L = ns and ns.L or setmetatable({}, { __index = function(_, key) return tostring(key) end })

local ldb = LibStub:GetLibrary("LibDataBroker-1.1", true)
if not ldb then return end

local plugin = ldb:NewDataObject(AddonName, {
    text = "BGNext",
    type = "data source",
    icon = "Interface\\AddOns\\BGNext\\Media\\icon\\icon.tga",
})

-- The pure mapper and the sole owner of role-overview window state. This
-- module only adapts mouse input to their public entry points; it never
-- creates or pins a role-overview window itself.
local EntryInteractions = BG.BGNext.EntryInteractions
local EntryMenuLifecycle = BG.BGNext.EntryMenuLifecycle
local RoleOverviewEntry = BG.BGNext.RoleOverviewEntry
local ENTRY_MENU_DISMISS_DELAY = 0.25
local entryMenuLifecycle = EntryMenuLifecycle.new(ENTRY_MENU_DISMISS_DELAY)
local entryMenu
local entryMenuWatcher
local entryMenuButtons = {}
local entryMenuButton
local stopEntryMenuWatch

-- BG.CreateButton uses the font chosen during ADDON_LOADED. Building these
-- controls while this Lua file is loading can therefore pass a nil font to
-- SetFont on clients where ADDON_LOADED has not run yet. The minimap broker
-- cannot be clicked before PLAYER_LOGIN, so create its private menu there.
local function ensureEntryMenu()
    if entryMenu then return end
    entryMenu = CreateFrame("Frame", nil, UIParent)
    entryMenu:SetSize(190, 82)
    entryMenu:SetFrameStrata("DIALOG")
    entryMenu:SetClampedToScreen(true)
    entryMenu:EnableMouse(true)
    local background = entryMenu:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.03, 0.03, 0.03, 0.95)
    entryMenu:Hide()
    entryMenuWatcher = CreateFrame("Frame")
    for i = 1, 3 do
        local button = BG.CreateButton(entryMenu)
        button:SetSize(180, 22)
        button:SetPoint("TOPLEFT", entryMenu, "TOPLEFT", 5, -5 - (i - 1) * 24)
        button:Hide()
        entryMenuButtons[i] = button
    end
    entryMenu:SetScript("OnHide", function() stopEntryMenuWatch() end)
end

stopEntryMenuWatch = function()
    entryMenuLifecycle:close()
    if entryMenuWatcher then entryMenuWatcher:SetScript("OnUpdate", nil) end
end

local function entryMenuPointerInside()
    if entryMenuButton and entryMenuButton:IsMouseOver() then return true end
    return entryMenu:IsMouseOver()
end

local function startEntryMenuWatch()
    entryMenuLifecycle:open()
    entryMenuWatcher:SetScript("OnUpdate", function(_, elapsed)
        local ownerVisible = entryMenu:IsShown()
        if entryMenuLifecycle:update(elapsed, ownerVisible, entryMenuPointerInside()) then
            entryMenu:Hide()
        elseif not ownerVisible then
            stopEntryMenuWatch()
        end
    end)
end

local function toggleMain()
    if BG.MainFrame then
        BG.MainFrame:SetShown(not BG.MainFrame:IsVisible())
    end
end

local function openSettings()
    if BG.OpenOption then BG.OpenOption() end
    if BG.MainFrame and BG.MainFrame.Hide then BG.MainFrame:Hide() end
end

local function menuText(item)
    if item.id == "main" then
        return item.verb == "close" and L["关闭金团表格"] or L["打开金团表格"]
    end
    if item.id == "role" then
        return item.verb == "close" and L["关闭角色总览"] or L["打开角色总览"]
    end
    if item.id == "settings" then return L["设置"] end
    return ""
end

local function menuAction(item)
    if item.id == "main" then return toggleMain end
    if item.id == "role" then
        return function() RoleOverviewEntry.togglePinned() end
    end
    if item.id == "settings" then return openSettings end
    return nil
end

-- Projects the menu fresh from live visibility each time it opens, so the
-- labels and actions never go stale. The role item is present only when the
-- current client can actually open the role overview.
local function openEntryMenu()
    ensureEntryMenu()
    if entryMenu:IsShown() then
        entryMenu:Hide()
        return
    end
    local state = {
        mainShown = BG.MainFrame and BG.MainFrame:IsVisible() or false,
        roleShown = RoleOverviewEntry.isPinned(),
        roleAvailable = RoleOverviewEntry.canOpen(),
    }
    local menu = EntryInteractions.menuModel(state)
    for _, button in ipairs(entryMenuButtons) do button:Hide() end
    for i, item in ipairs(menu) do
        local menuItem = item
        local button = entryMenuButtons[i]
        button:SetText(menuText(menuItem))
        button:SetScript("OnClick", function()
            entryMenu:Hide()
            local action = menuAction(menuItem)
            if action then action() end
        end)
        button:Show()
    end
    entryMenu:SetHeight(#menu * 24 + 10)
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    entryMenu:ClearAllPoints()
    entryMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    entryMenu:Show()
    startEntryMenuWatch()
end

function plugin:OnClick(button)
    local action = EntryInteractions.minimapAction(button)
    if action == "toggle-main" then
        toggleMain()
    elseif action == "menu" then
        openEntryMenu()
    elseif action == "toggle-role" then
        RoleOverviewEntry.togglePinned()
    end
    BG.PlaySound(1)
end

function plugin:OnEnter(button)
end

function plugin:OnLeave(button)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    ensureEntryMenu()
    local icon = LibStub("LibDBIcon-1.0", true)
    if not icon then return end
    icon:Register(AddonName, plugin, BiaoGe)
    entryMenuButton = icon:GetMinimapButton(AddonName)

    if BiaoGe.miniMoney then
        BiaoGe.miniMoney = nil
    end

    C_Timer.After(0.2, function()
        if BiaoGe.options["miniMap"] == 0 then
            icon:Hide(AddonName)
        end
    end)
end)
