return function(test)
    local function fakeFrame(name, shown)
        local frame = {
            name = name,
            shown = shown == true,
            enabled = true,
            scripts = {},
            parent = nil,
        }
        function frame:IsShown() return self.shown end
        function frame:Show() self.shown = true end
        function frame:Hide() self.shown = false end
        function frame:SetShown(value) if value then self:Show() else self:Hide() end end
        function frame:SetEnabled(value) self.enabled = value end
        function frame:IsEnabled() return self.enabled end
        function frame:SetScript(event, fn) self.scripts[event] = fn end
        function frame:SetPoint(...) self.point = { ... } end
        function frame:ClearAllPoints() self.point = nil end
        function frame:SetParent(parent) self.parent = parent end
        function frame:GetParent() return self.parent end
        function frame:SetSize(width, height) self.width, self.height = width, height end
        function frame:SetText(text) self.text = text end
        function frame:GetFontString()
            return { GetWidth = function() return 35 end }
        end
        function frame:SetFrameLevel(level) self.level = level end
        function frame:GetFrameLevel() return self.level or 1 end
        return frame
    end

    BG = { BGNext = {}, FB1 = "SW" }
    local added, opened, refreshed, messages = {}, 0, 0, {}
    BG.BGNext.AuctionQueueRuntime = {
        isController = function() return true end,
        inCombat = function() return false end,
        add = function(item)
            added[#added + 1] = item
            return #added
        end,
        refreshUI = function() refreshed = refreshed + 1 end,
        openFrame = function() opened = opened + 1 end,
        reasonText = function(reason) return reason end,
    }
    BG.CreateButton = function(parent)
        local button = fakeFrame("auction-button")
        button.parent = parent
        return button
    end
    BG.SendSystemMessage = function(message) messages[#messages + 1] = message end

    local events = {}
    BG.RegisterEvent = function(event, fn)
        events[event] = events[event] or {}
        events[event][#events[event] + 1] = fn
    end

    local tooltipLines = {}
    GameTooltip = {
        SetOwner = function() end,
        ClearLines = function() tooltipLines = {} end,
        AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = text end,
        Show = function() end,
        Hide = function() end,
    }

    local loot = {
        { link = "|cff0070dd|Hitem:1001:0:0|h[Boss sword]|h|r", quantity = 1, quality = 3, bindType = 1, stack = 1 },
        { link = "|cffa335ee|Hitem:1002:0:0|h[Boss staff]|h|r", quantity = 2, quality = 4, bindType = 2, stack = 1 },
        { link = nil, quantity = 1, quality = 0, bindType = 0, stack = 1 },
    }
    GetNumLootItems = function() return #loot end
    LootSlotHasItem = function(slot) return loot[slot] and loot[slot].link ~= nil end
    GetLootSlotLink = function(slot) return loot[slot] and loot[slot].link end
    GetLootSlotInfo = function(slot)
        local item = loot[slot]
        return nil, nil, item and item.quantity
    end
    GetItemInfo = function(link)
        for _, item in ipairs(loot) do
            if item.link == link then
                return nil, link, item.quality, 245, nil, nil, nil, item.stack, nil, nil, nil, nil, nil, item.bindType
            end
        end
    end
    GetLootThreshold = function() return 2 end
    IsInInstance = function() return true end

    local native = fakeFrame("LootFrame", true)
    local elv = fakeFrame("ElvLootFrame", false)
    local xloot = fakeFrame("XLootFrame", false)
    LootFrame, ElvLootFrame, XLootFrame = native, elv, xloot
    BG.autoLootButton = fakeFrame("one-click", true)
    BG.autoLootButton.parent = native
    BG.autoLootButton.level = 10

    local init2 = {}
    BG.Init2 = function(fn) init2[#init2 + 1] = fn end
    local M = assert(loadfile("Core/BGNext/LootAuctionEntry.lua"))("BGNEXT", { L = setmetatable({}, { __index = function(_, key) return key end }) })

    -- Frame adaptation follows the currently visible provider, with a stable
    -- fallback when the provider does not expose visibility yet.
    test.eq(M.selectLootFrame(), native, "native loot is selected when visible")
    native.shown, elv.shown = false, true
    test.eq(M.selectLootFrame(), elv, "ElvUI loot is selected when visible")
    elv.shown, xloot.shown = false, true
    test.eq(M.selectLootFrame(), xloot, "XLoot is selected when visible")
    xloot.shown = false
    test.eq(M.selectLootFrame(), elv, "an installed replacement is the fallback before OnShow")
    ElvLootFrame = nil
    native.shown = true
    test.eq(M.selectLootFrame(), native, "visible native wins over an installed but hidden XLoot frame")
    native.shown = false
    test.eq(M.selectLootFrame(), xloot, "XLoot is the next replacement fallback")
    XLootFrame = nil
    test.eq(M.selectLootFrame(), native, "native loot is the final fallback")

    -- Public loot projection accepts item slots only, preserves one row per
    -- slot and forwards the observed stack quantity to the memory-only queue.
    local items = M.collectEligibleLoot()
    test.eq(#items, 2, "two valid loot slots are projected")
    test.eq(items[1].itemId, 1001, "first item id is parsed")
    test.eq(items[2].quantity, 2, "loot quantity is preserved")

    -- Install the visible control beside the existing one-click assignment.
    for _, fn in ipairs(init2) do fn() end
    local button = BG.lootAuctionButton
    test.eq(button ~= nil, true, "a visible auction button is created")
    test.eq(button.text, "拍卖", "button uses the localized auction label")
    test.eq(button.point[1], "LEFT", "button sits beside one-click assignment")
    test.eq(button.point[2], BG.autoLootButton, "one-click assignment is the layout anchor")

    events.LOOT_OPENED[1]()
    test.eq(button.shown, true, "controller sees the auction button in an instance")
    test.eq(button.enabled, true, "eligible loot enables the auction button")
    button.scripts.OnClick(button)
    test.eq(#added, 2, "click queues each eligible loot slot")
    test.eq(opened, 1, "click opens the existing pending-auction queue")
    test.eq(refreshed > 0, true, "queue UI refreshes after adding loot")

    -- Clicking twice in the same loot session never duplicates rows.
    button.scripts.OnClick(button)
    test.eq(#added, 2, "the same loot session is queued at most once")
    test.eq(opened, 2, "a repeated click still reveals the existing queue")

    -- Permission, combat and empty-loot states fail closed before queueing.
    BG.BGNext.AuctionQueueRuntime.isController = function() return false end
    events.LOOT_OPENED[1]()
    test.eq(button.shown, false, "non-controller never sees the auction action")

    BG.BGNext.AuctionQueueRuntime.isController = function() return true end
    BG.BGNext.AuctionQueueRuntime.inCombat = function() return true end
    events.LOOT_OPENED[1]()
    test.eq(button.shown, true, "controller still sees why auction is unavailable")
    test.eq(button.enabled, false, "combat disables the button")
    button.scripts.OnEnter(button)
    test.eq(tooltipLines[#tooltipLines], "战斗状态下无法发起拍卖", "combat reason is visible")

    test.eq(type(events.PLAYER_REGEN_DISABLED), "table", "combat start is observed while loot stays open")
    test.eq(type(events.PLAYER_REGEN_ENABLED), "table", "combat end is observed while loot stays open")

    BG.BGNext.AuctionQueueRuntime.inCombat = function() return false end
    loot = {}
    events.LOOT_OPENED[1]()
    test.eq(button.enabled, false, "no eligible loot disables the button")
    button.scripts.OnEnter(button)
    test.eq(tooltipLines[#tooltipLines], "没有可拍卖的物品", "empty-loot reason is visible")

    IsInInstance = function() return false end
    events.LOOT_OPENED[1]()
    test.eq(button.shown, false, "ordinary world loot does not expose the boss-loot action")

    -- No alternate send path may exist in this entry module.
    local file = assert(io.open("Core/BGNext/LootAuctionEntry.lua", "rb"))
    local source = file:read("*a")
    file:close()
    for _, token in ipairs({ "SendStartAuctionMsg", "SendAddonMessage", "SendChatMessage", "BG.StartAuction(" }) do
        test.eq(source:find(token, 1, true), nil, "loot entry has no direct send token: " .. token)
    end
    test.eq(source:find("AuctionQueueRuntime", 1, true) ~= nil, true,
        "loot entry routes through the existing queue runtime")
end
