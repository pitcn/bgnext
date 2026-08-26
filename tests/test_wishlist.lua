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

    local matches = wish.findItem(root, "realm", "A", "ICC", 5001)
    test.eq(#matches, 2, "both matching slots returned")
    test.eq(matches[1].difficultyIndex, 1, "matches sorted by difficulty")
    test.eq(matches[1].bossIndex, 2, "matches report boss")
    test.eq(matches[1].slotIndex, 1, "matches sorted by slot")
    test.eq(wish.contains(root, "realm", "A", "ICC", 5001), true, "one or more slots match")
    test.eq(wish.contains(root, "realm", "A", "ICC", 5999), false, "missing item does not match")

    test.eq(wish.clearSlot(root, "realm", "A", "ICC", 1, 2, 1), true, "right-click removal clears one slot")
    test.eq(wish.getSlot(root, "realm", "A", "ICC", 1, 2, 1), nil, "cleared slot is empty")
    wish.setSlot(root, "realm", "A", "TOC", limits, 1, 1, 1, 5100)
    test.eq(wish.clearRaid(root, "realm", "A", "ICC"), true, "clear removes current raid")
    test.eq(wish.getSlot(root, "realm", "A", "TOC", 1, 1, 1), 5100, "clear preserves other raid")
    test.eq(wish.getSlot(root, "realm", "B", "ICC", 1, 1, 1), nil, "clear preserves character isolation")

    test.eq(wish.itemIdFromValue(6001), 6001, "numeric item id accepted")
    test.eq(wish.itemIdFromValue("6004"), 6004, "numeric text accepted")
    test.eq(wish.itemIdFromValue("item:6002:0:0:0"), 6002, "item string parsed")
    test.eq(wish.itemIdFromValue("|cff0070dd|Hitem:6003::::::::|h[Test]|h|r"), 6003, "item link parsed")
    test.eq(wish.itemIdFromValue("not an item"), nil, "unrelated text rejected")
end
