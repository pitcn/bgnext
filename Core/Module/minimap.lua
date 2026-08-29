if BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local L = ns and ns.L or setmetatable({}, { __index = function(_, key) return tostring(key) end })

local ldb = LibStub:GetLibrary("LibDataBroker-1.1", true)
if not ldb then return end

local plugin = ldb:NewDataObject(AddonName, { text = "BGNext", type = "data source", icon = "Interface\\AddOns\\BGLite\\Media\\icon\\icon.tga" })

-- The pure mapper and the sole owner of role-overview window state. This
-- module only adapts mouse input to their public entry points; it never
-- creates or pins a role-overview window itself.
local EntryInteractions = BG.BGNext.EntryInteractions
local RoleOverviewEntry = BG.BGNext.RoleOverviewEntry
local LibBG = LibStub:GetLibrary("BiaoGe-LibUIDropDownMenu-4.0")

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
    local state = {
        mainShown = BG.MainFrame and BG.MainFrame:IsVisible() or false,
        roleShown = RoleOverviewEntry.isPinned(),
        roleAvailable = RoleOverviewEntry.canOpen(),
    }
    local menu = {}
    for _, item in ipairs(EntryInteractions.menuModel(state)) do
        menu[#menu + 1] = {
            text = menuText(item),
            notCheckable = true,
            func = menuAction(item),
        }
    end
    LibBG:EasyMenu(menu, BG.dropDown, "cursor", 0, 0, "MENU", 2)
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
    local icon = LibStub("LibDBIcon-1.0", true)
    if not icon then return end
    icon:Register(AddonName, plugin, BiaoGe)

    if BiaoGe.miniMoney then
        BiaoGe.miniMoney = nil
    end

    C_Timer.After(0.2, function()
        if BiaoGe.options["miniMap"] == 0 then
            icon:Hide(AddonName)
        end
    end)
end)
