return function(test)
    BG = { BGNext = {}, IsRetail = false }
    dofile("Core/BGNext/ItemPrimaryStats.lua")
    dofile("Core/BGNext/EquipmentFilterProfiles.lua")
    local catalog = dofile("Core/BGNext/EquipmentFilterSpecializations.lua")

    -- Load the real equipment-filter block without executing the unrelated UI
    -- helpers in the rest of the large baseline file.
    local file = assert(io.open("Core/function2.lua", "rb"))
    local source = file:read("*a")
    file:close()
    local startMarker = "------------------过滤装备------------------"
    local stopMarker = "------------------函数：按职业排序------------------"
    local startAt = assert(source:find(startMarker, 1, true)) + #startMarker
    local stopAt = assert(source:find(stopMarker, startAt, true))

    ITEM_SOCKET_BONUS = "镶孔奖励：%s"
    ITEM_MOD_FERAL_ATTACK_POWER = "在猎豹、熊等等攻击强度提高%s点"
    ITEM_LIMIT_CATEGORY_MULTIPLE = "最多装备%s个"
    ITEM_MOD_STRENGTH_SHORT = "力量"
    ITEM_MOD_AGILITY_SHORT = "敏捷"
    ITEM_MOD_INTELLECT_SHORT = "智力"
    ITEM_MOD_MASTERY_RATING_SHORT = "精通"
    STAT_MASTERY = "精通"
    WARDROBE_SETS = "套装"
    CLASS = "职业"
    ITEM_BIND_TO_BNETACCOUNT = "战网通行证绑定"
    strfind = string.find
    tinsert = table.insert

    local tooltipText = "+10 智力"
    BiaoGeTooltip = {
        SetOwner = function() end,
        ClearLines = function() end,
        SetItemByID = function() end,
        SetHyperlink = function() end,
        NumLines = function() return 2 end,
    }
    UIParent = {}
    BiaoGeTooltipTextLeft2 = { GetText = function() return tooltipText end }

    local activeProfile
    BG.BGNext.GetActiveEquipmentFilterProfile = function() return activeProfile end
    assert(loadstring(source:sub(startAt, stopAt - 1), "equipment-filter-engine"))()

    activeProfile = catalog.getDefault("titan", "WARRIOR", "tree:WARRIOR:1")
    test.eq(BG.FilterAll(1001, 4, "INVTYPE_CHEST", 4), true,
        "non-Retail physical profile filters intellect-only armor")

    activeProfile = catalog.getDefault("titan", "MAGE", "tree:MAGE:1")
    test.eq(BG.FilterAll(1002, 4, "INVTYPE_CHEST", 1), nil,
        "non-Retail caster profile keeps intellect armor")

    activeProfile = catalog.getDefault("mop", "WARRIOR", "spec:73")
    test.eq(BG.FilterAll(1003, 4, "INVTYPE_CHEST", 4, "20 精通"), nil,
        "MoP tank profile keeps mastery armor")
    test.eq(BG.FilterAll(1004, 4, "INVTYPE_CHEST", 4, "100 护甲"), true,
        "MoP tank profile filters armor without a tank stat")

    activeProfile = catalog.getDefault("retail", "WARRIOR", "spec:73")
    test.eq(BG.FilterAll(1005, 4, "INVTYPE_CHEST", 4, "100 护甲"), nil,
        "Retail tank profile does not apply the legacy tank-stat filter")

    -- Auction payloads already carry cached item data on the normal BGLite/WA
    -- path. Apply that data immediately: MoP clients must not depend on a later
    -- ItemMixin callback merely to mark and fold an incompatible auction.
    activeProfile = catalog.getDefault("mop", "MAGE", "spec:62")
    tooltipText = "+10 智力"
    BGA = { aura_env = { SetFrameColor = function(frame, color) frame.color = color end } }
    BG.playerName = "Local"
    BG.itemCaches = {}
    BG.After = function(_, callback) callback() end
    GetRealmName = function() return "Realm" end
    GetItemInfo = function()
        return "板甲", "item:2001", 4, 500, 90, "护甲", "板甲", 1,
            "INVTYPE_CHEST", 0, 0, 4, 4, 1
    end
    local deferredCallbacks = 0
    Item = {
        CreateFromItemID = function()
            return {
                ContinueOnItemLoad = function()
                    deferredCallbacks = deferredCallbacks + 1
                    -- Reproduce the affected client path: callback is not
                    -- delivered even though GetItemInfo is already complete.
                end,
            }
        end,
    }
    local updated, updatedBindType
    local frame = { itemID = 2001, link = "item:2001", player = "Other" }
    BG.UpdateAuctionFilter(frame, function(filtered, bindType)
        updated, updatedBindType = filtered, bindType
    end)
    test.eq(frame.filter, true, "cached MoP auction is filtered synchronously")
    test.eq(frame.color, 2, "cached MoP auction receives the filtered frame color")
    test.eq(updated, true, "cached MoP auction immediately reaches the fold callback")
    test.eq(updatedBindType, 1, "cached auction passes binding type to the fold policy")
    test.eq(deferredCallbacks, 0, "cached auction data does not wait on ItemMixin")

    -- Preserve the reason the deferred path was added: a genuinely uncached
    -- auction must be retried after item data arrives.
    local loaded = false
    GetItemInfo = function()
        if not loaded then return nil end
        return "板甲", "item:2002", 4, 500, 90, "护甲", "板甲", 1,
            "INVTYPE_CHEST", 0, 0, 4, 4, 1
    end
    Item.CreateFromItemID = function()
        return {
            ContinueOnItemLoad = function(_, callback)
                loaded = true
                callback()
            end,
        }
    end
    local deferredFrame = { itemID = 2002, link = "item:2002", player = "Other" }
    local deferredUpdated
    BG.UpdateAuctionFilter(deferredFrame, function(filtered) deferredUpdated = filtered end)
    test.eq(deferredFrame.filter, true, "uncached auction is filtered after item data loads")
    test.eq(deferredUpdated, true, "uncached auction still reaches the fold callback")

    -- A delayed result belongs to the captured item only. If a host addon ever
    -- reuses the frame first, the old result must not recolor or fold the new row.
    loaded = false
    local pendingLoad
    Item.CreateFromItemID = function()
        return {
            ContinueOnItemLoad = function(_, callback) pendingLoad = callback end,
        }
    end
    local staleUpdated
    local reusedFrame = { itemID = 2003, link = "item:2003", player = "Other" }
    BG.UpdateAuctionFilter(reusedFrame, function(filtered) staleUpdated = filtered end)
    reusedFrame.itemID = 2004
    reusedFrame.link = "item:2004"
    loaded = true
    pendingLoad()
    test.eq(reusedFrame.filter, nil, "stale item load does not filter a reused auction frame")
    test.eq(reusedFrame.color, nil, "stale item load does not recolor a reused auction frame")
    test.eq(staleUpdated, nil, "stale item load does not invoke the new row's fold callback")
end
