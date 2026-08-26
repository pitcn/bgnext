return function(test)
    BG = { BGNext = {} }
    local wish = dofile("Core/BGNext/Wishlist.lua")
    local ui = dofile("Core/BGNext/WishlistUI.lua")
    local root = { wishlist = {} }

    wish.add(root, 123, "A", "ICC", 8001)
    test.eq(ui.isWish(root, 123, "A", "ICC", "item:8001"), true, "current character item link reminds")
    test.eq(ui.isWish(root, 123, "B", "ICC", "item:8001"), false, "other character wish stays private")
    test.eq(ui.isWish(root, 123, "A", "TOC", "item:8001"), false, "other raid wish does not remind")
    test.eq(ui.isWish(root, 123, "A", "ICC", "invalid"), false, "invalid item never reminds")

    local enabled, itemId = ui.toggleWish(root, 123, "A", "ICC", "item:8002")
    test.eq(enabled, true, "shortcut adds a missing current wish")
    test.eq(itemId, 8002, "shortcut reports the affected item")
    test.eq(ui.toggleWish(root, 123, "A", "ICC", "item:8002"), false, "shortcut removes an existing current wish")
    test.eq(ui.toggleWish(root, 123, "A", "ICC", "invalid"), nil, "shortcut rejects invalid item text")

    test.eq(ui.shortcutAction(false, "LeftButton"), "wishlist", "member alt-left toggles wishlist")
    test.eq(ui.shortcutAction(true, "LeftButton"), "wishlist", "master looter alt-left toggles wishlist")
    test.eq(ui.shortcutAction(true, "RightButton"), "auction", "master looter alt-right starts auction")
    test.eq(ui.shortcutAction(false, "RightButton"), nil, "member alt-right has no privileged action")
end
