return function(test)
    local enabled = false
    BG = {
        IsTitan = true,
        realmID = 1,
        playerName = "Me",
        BGNext = {
            DB = { settings = {}, wishlist = {}, equipmentFilters = {} },
            FeatureSettings = { isCurrentEnabled = function(id) return enabled end },
        },
    }

    local init = {}
    BG.Init = function(fn) init[#init + 1] = fn end
    BG.BGNext.Wishlist = {
        highestPriority = function() return "backup" end,
        priorityNameKey = function() return "备选" end,
    }
    local notices = 0
    BG.SendSystemMessage = function() notices = notices + 1 end
    local reminder = dofile("Core/BGNext/WishlistReminder.lua")
    test.eq(reminder.notify("loot", 1, "ULD", "event-1", "item:1", 245), false,
        "disabled wishlist emits no reminder")
    test.eq(notices, 0, "disabled wishlist sends no local message")
    enabled = true
    test.eq(reminder.notify("loot", 1, "ULD", "event-1", "item:1", 245), true,
        "re-enabled wishlist resumes reminders")

    enabled = false
    local ui = dofile("Core/BGNext/WishlistUI.lua")
    test.eq(ui.isFeatureEnabled(), false, "wishlist UI exposes the shared feature gate")

    local root = BG.BGNext.DB
    root.equipmentFilters[1] = { Me = { enabled = true, selectedId = "p", profiles = { p = { id = "p" } } } }
    local filter = dofile("Core/BGNext/EquipmentFilter.lua")
    test.eq(BG.BGNext.GetActiveEquipmentFilterProfile(), nil, "disabled equipment filter returns no active profile")
    test.eq(root.equipmentFilters[1].Me.profiles.p.id, "p", "disabled filter preserves saved profiles")
    enabled = true
    test.eq(BG.BGNext.GetActiveEquipmentFilterProfile().id, "p", "re-enabled filter restores prior profile")

    local runtime = dofile("Core/BGNext/OwnCharactersRuntime.lua")
    local deps = { root = { settings = {} }, family = "titan", catalog = { status = "tested-in-game", raidColumns = { 1 } } }
    enabled = false
    test.eq(runtime.isEnabled(deps), false, "role overview honors the shared feature gate")
    enabled = true
    test.eq(runtime.isEnabled(deps), true, "role overview can be re-enabled")

    enabled = false
    local announcement = dofile("Core/BGNext/TradeAnnouncement.lua")
    test.eq(announcement.isFeatureEnabled(), false, "trade announcements honor the shared feature gate")
    local settlement = dofile("Core/BGNext/CurrentSettlementRuntime.lua")
    test.eq(settlement.isFeatureEnabled(), false, "settlement tools honor the shared feature gate")
    local prices = dofile("Core/BGNext/AuctionPriceRuntime.lua")
    test.eq(prices.isFeatureEnabled(), false, "price presets honor the shared feature gate")

    BG.BGNext.UITheme = dofile("Core/BGNext/UITheme.lua")
    local style = dofile("Core/BGNext/UIStyle.lua")
    local appearanceRoot = { settings = { uiTheme = "preview" } }
    test.eq(style.isPreviewEnabled(appearanceRoot), false, "disabled appearance falls back to classic rendering")
    test.eq(appearanceRoot.settings.uiTheme, "preview", "appearance fallback preserves the saved theme")
end
