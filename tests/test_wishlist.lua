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
end
