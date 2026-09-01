return function(test)
    BG = { BGNext = {} }
    local primaryStats = dofile("Core/BGNext/ItemPrimaryStats.lua")

    local calls = {}
    local statsByLink = {
        ["item:strength"] = { ITEM_MOD_STRENGTH_SHORT = 100 },
        ["item:intellect"] = { ITEM_MOD_INTELLECT_SHORT = 100 },
        ["item:mixed"] = { ITEM_MOD_STRENGTH_SHORT = 50, ITEM_MOD_INTELLECT_SHORT = 50 },
        ["item:secondary-only"] = { ITEM_MOD_CRIT_RATING_SHORT = 80 },
        ["item:variant:strength"] = { ITEM_MOD_STRENGTH_SHORT = 100 },
        ["item:variant:intellect"] = { ITEM_MOD_INTELLECT_SHORT = 100 },
    }
    local detector = primaryStats.new({
        getItemStats = function(link)
            calls[#calls + 1] = link
            return statsByLink[link]
        end,
        tooltipPatterns = {
            STRENGTH = "Strength",
            AGILITY = "Agility",
            INTELLECT = "Intellect",
        },
    })

    local intellectOnly = { INTELLECT = true }
    test.eq(detector:isMismatch(intellectOnly, "item:strength"), true,
        "an explicitly incompatible primary stat is filtered")
    test.eq(detector:isMismatch(intellectOnly, "item:intellect"), false,
        "an allowed primary stat is retained")
    test.eq(detector:isMismatch(intellectOnly, "item:mixed"), false,
        "an item matching any allowed primary stat is retained")
    test.eq(detector:isMismatch(intellectOnly, "item:secondary-only"), false,
        "an item without a primary stat is conservatively retained")
    test.eq(detector:isMismatch(intellectOnly, "item:unknown"), false,
        "an item whose stats are unavailable is conservatively retained")
    test.eq(detector:isMismatch({}, "item:strength"), false,
        "an intentionally empty profile does not filter by primary stat")

    test.eq(detector:isMismatch(intellectOnly, "item:variant:strength"), true,
        "one item-link variant can be incompatible")
    test.eq(detector:isMismatch(intellectOnly, "item:variant:intellect"), false,
        "another item-link variant with the same conceptual item can be compatible")

    local apiUnavailable = primaryStats.new({
        getItemStats = function() return nil end,
        tooltipPatterns = {
            STRENGTH = "Strength",
            AGILITY = "Agility",
            INTELLECT = "Intellect",
        },
    })
    test.eq(apiUnavailable:isMismatch(intellectOnly, "item:fallback", "+100 Strength\n+50 Stamina"), true,
        "localized tooltip text is used when the item stats API has no result")
    test.eq(apiUnavailable:isMismatch(intellectOnly, "item:fallback-int", "+100 Intellect"), false,
        "tooltip fallback retains an allowed primary stat")
    test.eq(apiUnavailable:isMismatch(intellectOnly, "item:fallback-unknown", "Equip: proc effect"), false,
        "tooltip fallback without a primary stat remains conservative")

    local productionFallback = primaryStats.new({
        getItemStats = function() return nil end,
        tooltipPatterns = {
            STRENGTH = "^%+%C-Strength",
            AGILITY = "^%+%C-Agility",
            INTELLECT = "^%+%C-Intellect",
        },
    })
    test.eq(productionFallback:isMismatch(intellectOnly, "item:multiline",
        "Item Level 232\n+100 Strength\n+120 Stamina"), true,
        "production tooltip patterns match primary stats after the first line")

    local attempts = 0
    local eventuallyLoaded = primaryStats.new({
        getItemStats = function()
            attempts = attempts + 1
            if attempts == 1 then return {} end
            return { ITEM_MOD_STRENGTH_SHORT = 100 }
        end,
    })
    test.eq(eventuallyLoaded:isMismatch(intellectOnly, "item:loading"), false,
        "a temporarily empty API result is conservatively retained")
    test.eq(eventuallyLoaded:isMismatch(intellectOnly, "item:loading"), true,
        "a temporarily empty API result is retried after item data loads")

    local before = #calls
    detector:isMismatch(intellectOnly, "item:intellect")
    test.eq(#calls, before, "resolved full item links are cached independently")

    test.eq(primaryStats.selectItemRef("item:123:random-suffix", "item:123", 123),
        "item:123:random-suffix", "auction filtering prefers the frame's exact item link")
    test.eq(primaryStats.selectItemRef(nil, "item:123", 123), "item:123",
        "auction filtering falls back to the loaded item link")
    test.eq(primaryStats.selectItemRef(nil, nil, 123), 123,
        "auction filtering remains conservative when only an item ID is available")

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end
    local filterSource = read("Core/function2.lua")
    test.eq(filterSource:find("ItemPrimaryStats.new", 1, true) ~= nil, true,
        "the shared filter engine constructs the primary-stat adapter")
    test.eq(filterSource:find("BG.IsRetail and not itemAttributeCache", 1, true), nil,
        "primary-stat collection is not restricted to Retail")
    test.eq(filterSource:find("BG.FilterAll(text, typeID, EquipLoc, subclassID)", 1, true) ~= nil, true,
        "table and item-list filtering preserve the full item link")
    test.eq(filterSource:find("ItemPrimaryStats.selectItemRef(f.link, itemLink, f.itemID)", 1, true) ~= nil,
        true, "auction filtering passes the frame's exact item link to the tested selector")
    test.eq(filterSource:find("BG.FilterAll(link, typeID, EquipLoc, subclassID)", 1, true) ~= nil, true,
        "loot filtering preserves the full item link")

    local toc = read("BGLite.toc")
    local adapterAt = toc:find("Core\\BGNext\\ItemPrimaryStats.lua", 1, true)
    local engineAt = toc:find("Core\\function2.lua", 1, true)
    test.eq(adapterAt ~= nil and engineAt ~= nil and adapterAt < engineAt, true,
        "the primary-stat adapter loads before the shared filter engine")
end
