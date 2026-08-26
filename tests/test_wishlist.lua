return function(test)
    BG = { BGNext = {} }
    local wish = dofile("Core/BGNext/Wishlist.lua")
    local root = { wishlist = {} }

    test.eq(wish.add(root, "realm", "A", "ICC", 5001), true, "first wish added")
    test.eq(wish.add(root, "realm", "A", "ICC", 5001), false, "duplicate wish ignored")
    test.eq(wish.contains(root, "realm", "A", "ICC", 5001), true, "current character wish found")
    test.eq(wish.contains(root, "realm", "B", "ICC", 5001), false, "other own character isolated")
    test.eq(wish.contains(root, "realm", "A", "TOC", 5001), false, "other raid isolated")
    test.eq(#wish.list(root, "realm", "A", "ICC"), 1, "one wish listed")
    test.eq(wish.remove(root, "realm", "A", "ICC", 5001), true, "wish removed")
    test.eq(wish.remove(root, "realm", "A", "ICC", 5001), false, "missing wish ignored")

    wish.add(root, "realm", "A", "ICC", 5002)
    wish.add(root, "realm", "A", "ICC", 5003)
    test.eq(wish.clear(root, "realm", "A", "ICC"), true, "raid wishes cleared")
    test.eq(#wish.list(root, "realm", "A", "ICC"), 0, "cleared list empty")
    test.eq(wish.add(root, "", "A", "ICC", 5001), false, "invalid realm rejected")
    test.eq(wish.add(root, 123, "A", "ICC", 5004), true, "numeric realm id accepted")

    test.eq(wish.itemIdFromValue(6001), 6001, "numeric item id accepted")
    test.eq(wish.itemIdFromValue("6004"), 6004, "numeric text accepted")
    test.eq(wish.itemIdFromValue("item:6002:0:0:0"), 6002, "item string parsed")
    test.eq(wish.itemIdFromValue("|cff0070dd|Hitem:6003::::::::|h[Test]|h|r"), 6003, "item link parsed")
    test.eq(wish.itemIdFromValue("not an item"), nil, "unrelated text rejected")

    test.eq(wish.toggle(root, "realm", "A", "ICC", 7001), true, "toggle adds a missing wish")
    test.eq(wish.contains(root, "realm", "A", "ICC", 7001), true, "toggled wish stored locally")
    test.eq(wish.toggle(root, "realm", "A", "ICC", 7001), false, "toggle removes an existing wish")
    test.eq(wish.contains(root, "realm", "A", "ICC", 7001), false, "removed wish no longer reminds")
    test.eq(wish.toggle(root, "", "A", "ICC", 7002), nil, "toggle reports unavailable context")
end
