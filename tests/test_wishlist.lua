return function(test)
    BG = { BGNext = {} }
    local wish = dofile("Core/BGNext/Wishlist.lua")
    local root = { wishlist = {}, wishlistUnplaced = {} }
    local limits = { difficulties = 2, bosses = 3, slots = 2 }

    test.eq(wish.setSlot(root, "realm", "A", "ICC", limits, 1, 2, 1, 5001), true, "valid slot stored")
    test.eq(wish.getSlot(root, "realm", "A", "ICC", 1, 2, 1), 5001, "slot returns item")
    test.eq(wish.getSlot(root, "realm", "B", "ICC", 1, 2, 1), nil, "other character isolated")
    test.eq(wish.getSlot(root, "realm", "A", "TOC", 1, 2, 1), nil, "other raid isolated")
    test.eq(wish.setSlot(root, "realm", "A", "ICC", limits, 3, 1, 1, 5002), false, "difficulty out of range")
    test.eq(wish.setSlot(root, "realm", "A", "ICC", limits, 1, 4, 1, 5002), false, "boss out of range")
    test.eq(wish.setSlot(root, "realm", "A", "ICC", limits, 1, 1, 3, 5002), false, "slot out of range")
    test.eq(wish.setSlot(root, "realm", "A", "ICC", limits, 1, 2, 2, 5001), true, "duplicate item may occupy another original slot")
    test.eq(wish.setSlot(root, "realm", "A", "ICC", limits, 2, 2, 1, 5001), true,
        "the same item may be wished independently on another difficulty")

    local matches = wish.findItem(root, "realm", "A", "ICC", 5001)
    test.eq(#matches, 3, "matching slots across both difficulties returned")
    test.eq(matches[1].difficultyIndex, 1, "matches sorted by difficulty")
    test.eq(matches[1].bossIndex, 2, "matches report boss")
    test.eq(matches[1].slotIndex, 1, "matches sorted by slot")
    test.eq(wish.contains(root, "realm", "A", "ICC", 5001), true, "one or more slots match")
    test.eq(wish.contains(root, "realm", "A", "ICC", 5999), false, "missing item does not match")

    test.eq(wish.clearSlot(root, "realm", "A", "ICC", 1, 2, 1), true, "right-click removal clears one slot")
    test.eq(wish.getSlot(root, "realm", "A", "ICC", 1, 2, 1), nil, "cleared slot is empty")
    test.eq(wish.getSlot(root, "realm", "A", "ICC", 2, 2, 1), 5001,
        "clearing normal difficulty preserves the heroic wish")
    wish.setSlot(root, "realm", "A", "TOC", limits, 1, 1, 1, 5100)
    test.eq(wish.clearRaid(root, "realm", "A", "ICC"), true, "clear removes current raid")
    test.eq(wish.getSlot(root, "realm", "A", "TOC", 1, 1, 1), 5100, "clear preserves other raid")
    test.eq(wish.getSlot(root, "realm", "B", "ICC", 1, 1, 1), nil, "clear preserves character isolation")

    test.eq(wish.itemIdFromValue(6001), 6001, "numeric item id accepted")
    test.eq(wish.itemIdFromValue("6004"), 6004, "numeric text accepted")
    test.eq(wish.itemIdFromValue("item:6002:0:0:0"), 6002, "item string parsed")
    test.eq(wish.itemIdFromValue("|cff0070dd|Hitem:6003::::::::|h[Test]|h|r"), 6003, "item link parsed")
    test.eq(wish.itemIdFromValue("not an item"), nil, "unrelated text rejected")

    local resolveDrop = wish.resolveDrop
    test.eq(type(resolveDrop), "function", "drop resolver is available for difficulty-specific wishlist slots")
    if type(resolveDrop) == "function" then
        local sharedItem = 105857
        local difficultyNames = { "N", "H" }
        local raidLoot = {
            N = { boss14 = { sharedItem } },
            H = { boss14 = { sharedItem } },
        }
        local function exactItem(left, right) return left == right end
        local normal = resolveDrop(sharedItem, difficultyNames, raidLoot, 14, exactItem, 1, 14)
        local heroic = resolveDrop(sharedItem, difficultyNames, raidLoot, 14, exactItem, 2, 14)
        test.eq(normal and normal.difficultyIndex, 1, "shared MoP token resolves to the requested normal difficulty")
        test.eq(heroic and heroic.difficultyIndex, 2, "shared MoP token resolves to the requested heroic difficulty")
        test.eq(heroic and heroic.bossIndex, 14, "shared MoP token remains assigned to Garrosh")
    end

    local function resolver(itemId)
        if itemId == 6001 or itemId == 6002 or itemId == 6003 then
            return { difficultyIndex = 1, bossIndex = 2 }
        end
        return nil
    end

    local placed = wish.placeItem(root, "realm", "A", "ICC", limits, 6001, resolver)
    test.eq(placed.ok, true, "normal boss drop placed")
    test.eq(placed.slotIndex, 1, "first free original-order slot used")
    wish.setSlot(root, "realm", "A", "ICC", limits, 1, 2, 2, 6002)
    local full = wish.placeItem(root, "realm", "A", "ICC", limits, 6003, resolver)
    test.eq(full.ok, false, "full boss does not place")
    test.eq(full.reason, "boss-full", "full boss rejected")
    test.eq(wish.placeItem(root, "realm", "A", "ICC", limits, 6999, resolver).reason, "unknown-drop",
        "unknown drop rejected")

    local legacy = {
        wishlist = { realm = { A = { ICC = { [6001] = true, [6999] = true } } } },
        wishlistUnplaced = {},
    }
    local result = wish.migrateFlatRaid(legacy, "realm", "A", "ICC", limits, resolver)
    test.eq(result.placed, 1, "known legacy item placed")
    test.eq(result.quarantined, 1, "unknown legacy item quarantined")
    test.eq(legacy.wishlistUnplaced.realm.A.ICC[6999], true, "unknown item preserved")
    local repeated = wish.migrateFlatRaid(legacy, "realm", "A", "ICC", limits, resolver)
    test.eq(repeated.changed, false, "slot data is not migrated twice")
    test.eq(repeated.placed, 0, "second migration places nothing")
    test.eq(repeated.quarantined, 0, "second migration quarantines nothing")

    local codecRoot = { wishlist = {} }
    wish.setSlot(codecRoot, "realm", "A", "ICC", limits, 1, 2, 1, 7001)
    wish.setSlot(codecRoot, "realm", "A", "ICC", limits, 1, 2, 2, 7002)
    test.eq(wish.exportRaid(codecRoot, "realm", "A", "ICC", limits), "ICC:n1b2-7001-7002",
        "stable original text format")
    test.eq(wish.exportRaid({ wishlist = {} }, "realm", "A", "ICC", limits), nil, "empty raid has no payload")

    local imported = wish.parseImport("ICC:n1b2-7001-7002,n2b1-7100", { ICC = limits })
    test.eq(imported.ok, true, "valid import parsed")
    test.eq(imported.itemCount, 3, "valid import counts items")
    test.eq(imported.raids.ICC[1][2][1], 7001, "first imported slot")
    test.eq(imported.raids.ICC[2][1][1], 7100, "second difficulty imported")
    test.eq(wish.parseImport("ICC:n9b2-7001", { ICC = limits }).reason, "out-of-range",
        "out-of-range import rejected")
    test.eq(wish.parseImport("ICC:n1b2-doSomething()", { ICC = limits }).reason, "invalid-item",
        "non-numeric payload rejected")
    test.eq(wish.parseImport(string.rep("1", 32769), { ICC = limits }).reason, "too-large",
        "oversized import rejected")

    wish.setSlot(codecRoot, "realm", "A", "TOC", limits, 1, 1, 1, 7200)
    local beforeInvalid = wish.getSlot(codecRoot, "realm", "A", "ICC", 1, 2, 1)
    test.eq(wish.applyImport(codecRoot, "realm", "A", wish.parseImport("bad", { ICC = limits })), false,
        "invalid import is not applied")
    test.eq(wish.getSlot(codecRoot, "realm", "A", "ICC", 1, 2, 1), beforeInvalid,
        "invalid import preserves existing raid")
    test.eq(wish.applyImport(codecRoot, "realm", "A", imported), true, "valid import applied")
    test.eq(wish.getSlot(codecRoot, "realm", "A", "ICC", 2, 1, 1), 7100, "valid import replaces raid")
    test.eq(wish.getSlot(codecRoot, "realm", "A", "TOC", 1, 1, 1), 7200, "valid import preserves other raid")
end
