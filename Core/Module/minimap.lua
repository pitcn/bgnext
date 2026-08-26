if BG.IsBlackListPlayer then return end
local AddonName, ns = ...


local ldb = LibStub:GetLibrary("LibDataBroker-1.1", true)
if not ldb then return end


local plugin = ldb:NewDataObject(AddonName, { text = "BGLite", type = "data source", icon = "Interface\\AddOns\\BGLite\\Media\\icon\\icon.tga" })

function plugin:OnClick(button) --function plugin.OnClick(self, button)
    if button == "LeftButton" then
        if IsControlKeyDown() then
            BG.SetFBCD(nil, nil, true)
        else
            BG.MainFrame:SetShown(not BG.MainFrame:IsVisible())
        end
    elseif button == "RightButton" then
        if SettingsPanel:IsVisible() then
            HideUIPanel(SettingsPanel)
        else
            BG.OpenOption()
            BG.MainFrame:Hide()
        end
    elseif button == "MiddleButton" then
        BG.SetFBCD(nil, nil, true)
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
