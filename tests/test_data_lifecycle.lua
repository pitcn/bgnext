return function(test)
    BG = { BGNext = {} }
    local life = dofile("Core/BGNext/DataLifecycle.lua")
    local saved = {}
    local root = life.ensureRoot(saved)

    test.eq(saved.BGNext, root, "BGNext root attached")
    test.eq(root.schemaVersion, 1, "schema version")
    test.eq(root.auctionPresets, nil, "duplicate auto-bid presets are not auto-created")

    life.beginSettlement(root, "raid-a", 100)
    root.currentSettlement.trades[1] = { amount = 100 }
    life.beginSettlement(root, "raid-a", 200)
    test.eq(#root.currentSettlement.trades, 1, "same raid preserved")
    life.beginSettlement(root, "raid-a", 200, { fb = "ICC", realm = "测试服" })
    test.eq(root.currentSettlement.sourceFb, "ICC", "same raid backfills missing source table")
    test.eq(root.currentSettlement.sourceRealm, "测试服", "same raid backfills missing source realm")
    test.eq(#root.currentSettlement.trades, 1, "source backfill preserves same-raid records")

    life.beginSettlement(root, "raid-b", 300)
    test.eq(#root.currentSettlement.trades, 0, "new raid clears old data")
    root.currentSettlement.trades[1] = { amount = 200 }

    test.eq(life.purgeExpired(root, 300 + 7 * 86400 - 1), false, "before expiry")
    test.eq(life.purgeExpired(root, 300 + 7 * 86400), true, "at expiry")
    test.eq(#root.currentSettlement.trades, 0, "expired trades cleared")

    life.beginRaid(root, "raid-c", 1000)
    root.currentRaid.purchases[1] = { itemId = 10 }
    life.beginRaid(root, "raid-c", 1100)
    test.eq(#root.currentRaid.purchases, 1, "same raid shopping preserved")
    life.beginRaid(root, "raid-d", 1200)
    test.eq(#root.currentRaid.purchases, 0, "new raid shopping cleared")
    test.eq(root.currentSettlement.raidId, "raid-d", "new raid settlement selected")

    -- Login cleanup uses the same authoritative clock as runtime writes.
    local init
    BG = { BGNext = {}, Init = function(callback) init = callback end }
    BiaoGe = {
        BGNext = {
            currentSettlement = {
                raidId = "expired", startedAt = 1, expiresAt = 100,
                trades = { { amount = 1 } }, mails = {},
            },
        },
    }
    GetServerTime = function() return 100 end
    time = function() return 1 end
    life = dofile("Core/BGNext/DataLifecycle.lua")
    init()
    test.eq(BiaoGe.BGNext.currentSettlement.raidId, nil,
        "login expiry uses server time even when the local clock is behind")
end
