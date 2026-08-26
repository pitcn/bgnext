return function(test)
    BG = { BGNext = {} }
    local life = dofile("Core/BGNext/DataLifecycle.lua")
    local saved = {}
    local root = life.ensureRoot(saved)

    test.eq(saved.BGNext, root, "BGNext root attached")
    test.eq(root.schemaVersion, 1, "schema version")

    life.beginSettlement(root, "raid-a", 100)
    root.currentSettlement.trades[1] = { amount = 100 }
    life.beginSettlement(root, "raid-a", 200)
    test.eq(#root.currentSettlement.trades, 1, "same raid preserved")

    life.beginSettlement(root, "raid-b", 300)
    test.eq(#root.currentSettlement.trades, 0, "new raid clears old data")
    root.currentSettlement.trades[1] = { amount = 200 }

    test.eq(life.purgeExpired(root, 300 + 7 * 86400 - 1), false, "before expiry")
    test.eq(life.purgeExpired(root, 300 + 7 * 86400), true, "at expiry")
    test.eq(#root.currentSettlement.trades, 0, "expired trades cleared")
end
