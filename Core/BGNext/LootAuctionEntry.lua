BG = BG or {}
BG.BGNext = BG.BGNext or {}

local AddonName, ns = ...
local L = ns and ns.L or setmetatable({}, { __index = function(_, key) return tostring(key) end })

-- Visible boss-loot entry for the existing memory-only pending auction queue.
-- This module only discovers the loot currently exposed by Blizzard's loot API
-- and adds it to AuctionQueueRuntime. It does not send auction messages and it
-- deliberately leaves confirmation and every send-time check to that runtime.
local M = {}
local Runtime = assert(BG.BGNext.AuctionQueueRuntime, "AuctionQueueRuntime must load before LootAuctionEntry")

local button
local queuedSlots = {}
local lootOpen = false

local function featureEnabled()
    local settings = BG.BGNext and BG.BGNext.FeatureSettings
    if not settings then return true end
    if type(settings.isCurrentEnabled) == "function" then
        return settings.isCurrentEnabled("auction_queue", BG, BG.BGNext.DB)
    end
    if type(settings.isEnabled) ~= "function" then return true end
    return settings.isEnabled(BG.BGNext.DB, "auction_queue", "wrath")
end

local function isShown(frame)
    return frame and type(frame.IsShown) == "function" and frame:IsShown()
end

-- Replacement loot addons can coexist with the native frame. Prefer the frame
-- that is actually visible; before any frame has shown, retain the established
-- ElvUI -> XLoot -> native fallback order used by the baseline loot module.
function M.selectLootFrame()
    if isShown(ElvLootFrame) then return ElvLootFrame end
    if isShown(XLootFrame) then return XLootFrame end
    if isShown(LootFrame) then return LootFrame end
    return ElvLootFrame or XLootFrame or LootFrame or UIParent
end

local function itemIdFromLink(link)
    if type(link) ~= "string" then return nil end
    local itemId = tonumber(link:match("item:(%d+)"))
    if not itemId or itemId <= 0 or itemId % 1 ~= 0 then return nil end
    return itemId
end

local function eligible(slot)
    if type(LootSlotHasItem) ~= "function" or not LootSlotHasItem(slot) then return nil end
    local link = type(GetLootSlotLink) == "function" and GetLootSlotLink(slot) or nil
    local itemId = itemIdFromLink(link)
    if not itemId then return nil end

    local quantity, slotQuality
    if type(GetLootSlotInfo) == "function" then
        quantity = select(3, GetLootSlotInfo(slot))
        slotQuality = select(5, GetLootSlotInfo(slot))
    end
    quantity = tonumber(quantity) or 1
    if quantity < 1 or quantity % 1 ~= 0 then return nil end

    local quality, stackCount, bindType
    if type(GetItemInfo) == "function" then
        quality = select(3, GetItemInfo(link))
        stackCount = select(8, GetItemInfo(link))
        bindType = select(14, GetItemInfo(link))
    end
    quality = tonumber(quality) or tonumber(slotQuality)
    local threshold = type(GetLootThreshold) == "function" and tonumber(GetLootThreshold()) or nil
    if threshold and quality and quality < threshold then return nil end
    if bindType == 4 then return nil end -- quest item
    if bindType == 1 and tonumber(stackCount) and stackCount > 1 then return nil end

    return {
        slot = slot,
        itemId = itemId,
        link = link,
        quantity = quantity,
    }
end

function M.collectEligibleLoot()
    local result = {}
    local count = type(GetNumLootItems) == "function" and tonumber(GetNumLootItems()) or 0
    count = math.max(0, math.min(math.floor(count or 0), 40))
    for slot = 1, count do
        local item = eligible(slot)
        if item then result[#result + 1] = item end
    end
    return result
end

local function systemMessage(text)
    if text and type(BG.SendSystemMessage) == "function" then BG.SendSystemMessage(text) end
end

local function state()
    if not Runtime.isController() then return "no-permission" end
    if type(IsInInstance) == "function" and not IsInInstance() then return "not-instance" end
    if Runtime.inCombat() then return "combat" end
    if #M.collectEligibleLoot() == 0 then return "no-loot" end
    return nil
end

local function reasonText(reason)
    if reason == "combat" then return L["战斗状态下无法发起拍卖"] end
    if reason == "no-loot" then return L["没有可拍卖的物品"] end
    if reason == "no-permission" then return L["仅团长或拾取负责人可以发起拍卖"] end
    if reason == "not-instance" then return L["仅在副本拾取时提供一键拍卖"] end
end

local function layout()
    if not button then return end
    local parent = M.selectLootFrame()
    if not parent then return end
    if type(button.SetParent) == "function" then button:SetParent(parent) end
    if type(button.ClearAllPoints) == "function" then button:ClearAllPoints() end
    local assign = BG.autoLootButton
    if assign and (type(assign.GetParent) ~= "function" or assign:GetParent() == parent) then
        button:SetPoint("LEFT", assign, "RIGHT", 4, 0)
    else
        button:SetPoint("BOTTOM", parent, "TOP", 48, 0)
    end
    if type(button.SetFrameLevel) == "function" and type(parent.GetFrameLevel) == "function" then
        button:SetFrameLevel(parent:GetFrameLevel() + 10)
    end
end

function M.refresh()
    if not button then return end
    if not featureEnabled() then button:Hide(); return end
    if not lootOpen then
        button:Hide()
        return
    end
    layout()
    local reason = state()
    if reason == "no-permission" or reason == "not-instance" then
        button:Hide()
        button.blockReason = reason
        return
    end
    button:Show()
    button:SetEnabled(reason == nil)
    button.blockReason = reason
end

function M.enqueueVisibleLoot()
    if not featureEnabled() then return 0, "feature-disabled" end
    local reason = state()
    if reason then
        systemMessage(reasonText(reason))
        return 0, reason
    end

    local added = 0
    for _, item in ipairs(M.collectEligibleLoot()) do
        local key = tostring(item.slot) .. "\1" .. item.link .. "\1" .. tostring(item.quantity)
        if not queuedSlots[key] then
            local id, addReason = Runtime.add({
                itemId = item.itemId,
                link = item.link,
                quantity = item.quantity,
            })
            if id then
                queuedSlots[key] = true
                added = added + 1
            elseif addReason then
                systemMessage(Runtime.reasonText(addReason))
                break
            end
        end
    end
    Runtime.refreshUI()
    Runtime.openFrame()
    return added
end

function M.refreshFeatureState()
    M.refresh()
    return featureEnabled()
end

local function install()
    if button or type(BG.CreateButton) ~= "function" then return end
    local parent = M.selectLootFrame()
    if not parent then return end
    button = BG.CreateButton(parent)
    BG.lootAuctionButton = button
    button:SetText(L["拍卖"])
    local width = 50
    if type(button.GetFontString) == "function" then
        local font = button:GetFontString()
        if font and type(font.GetWidth) == "function" then width = math.max(width, font:GetWidth() + 14) end
    end
    button:SetSize(width, 25)
    layout()
    button:Hide()
    button:SetScript("OnClick", function()
        if type(BG.PlaySound) == "function" then BG.PlaySound(1) end
        M.enqueueVisibleLoot()
    end)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0)
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["拍卖当前掉落"], 1, 1, 1, true)
        GameTooltip:AddLine(L["把当前可拍物品加入待拍队列，仍需逐件确认。"], 1, 0.82, 0, true)
        if self.blockReason then
            GameTooltip:AddLine(reasonText(self.blockReason), 1, 0.2, 0.2, true)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    if type(BG.RegisterEvent) == "function" then
        BG.RegisterEvent("LOOT_OPENED", function()
            lootOpen = true
            queuedSlots = {}
            M.refresh()
        end)
        BG.RegisterEvent("LOOT_SLOT_CLEARED", function() M.refresh() end)
        BG.RegisterEvent("LOOT_CLOSED", function()
            lootOpen = false
            queuedSlots = {}
            button:Hide()
        end)
        BG.RegisterEvent("PLAYER_REGEN_DISABLED", function() M.refresh() end)
        BG.RegisterEvent("PLAYER_REGEN_ENABLED", function() M.refresh() end)
    end
end

if type(BG.Init2) == "function" then BG.Init2(install) end

BG.BGNext.LootAuctionEntry = M
return M
