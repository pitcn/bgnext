return function(test)
    BG = { BGNext = {} }
    local life = dofile("Core/BGNext/DataLifecycle.lua")
    local store = dofile("Core/BGNext/AuctionPriceStore.lua")

    local saved = {}
    local root = life.ensureRoot(saved)

    test.eq(type(root.leaderAuctionPricePresets), "table", "leader price root")
    test.eq(type(root.personalAuctionExpectations), "table", "personal price root")
    test.eq(root.auctionPresets, nil, "retired auto-bid presets stay unread")

    -- Canonical BGNext client-family keys (matches OwnCharactersAdapters.families).
    local expected = {
        vanilla = 100, tbc = 100, wrath = 1000, titan = 100,
        cata = 100000, mop = 10000, retail = 100000,
    }
    for family, money in pairs(expected) do
        test.eq(store.defaultGlobalPrice(family), money, family .. " default")
    end

    -- Leader scheme storage and resolution
    local raid = store.ensureLeaderRaid(root, "titan", "ULD", 777)
    test.eq(raid.presets[raid.activePresetId].name, "默认方案", "default name")
    test.eq(raid.presets[raid.activePresetId].basePrice, 777, "copies local global price")
    test.eq(store.resolveLeaderPrice(root, "titan", "ULD", 1001), 777, "base fallback")
    test.eq(store.setLeaderItemPrice(root, "titan", "ULD", raid.activePresetId, 1001, 0), true, "zero is explicit")
    test.eq(store.resolveLeaderPrice(root, "titan", "ULD", 1001), 0, "item zero wins")

    -- Invalid local global price falls back to the family default.
    local raid2 = store.ensureLeaderRaid(root, "titan", "ICC", "bad")
    test.eq(raid2.presets[raid2.activePresetId].basePrice, 100, "invalid local price uses family default")

    -- Item price overrides base and clears back to base.
    local active = raid.activePresetId
    test.eq(store.setLeaderItemPrice(root, "titan", "ULD", active, 1002, 900), true, "set item price")
    test.eq(store.resolveLeaderPrice(root, "titan", "ULD", 1002), 900, "item price wins over base")
    test.eq(store.clearLeaderItemPrice(root, "titan", "ULD", active, 1002), true, "clear item price")
    test.eq(store.resolveLeaderPrice(root, "titan", "ULD", 1002), 777, "cleared item falls back to base")

    -- setBasePrice changes the fallback for unset items.
    test.eq(store.setBasePrice(root, "titan", "ULD", active, 500), true, "set base price")
    test.eq(store.resolveLeaderPrice(root, "titan", "ULD", 9999), 500, "new base price applies")

    -- createPreset with validated name and price.
    local p2 = store.createPreset(root, "titan", "ULD", "英雄团", 1200)
    test.eq(type(p2), "string", "createPreset returns an id")
    test.eq(raid.presets[p2].name, "英雄团", "created preset name")
    test.eq(raid.presets[p2].basePrice, 1200, "created preset base price")

    -- selectPreset switches the active scheme and resolution follows.
    test.eq(store.selectPreset(root, "titan", "ULD", p2), true, "select preset")
    test.eq(raid.activePresetId, p2, "active preset switched")
    test.eq(store.resolveLeaderPrice(root, "titan", "ULD", 9999), 1200, "resolution uses active scheme")
    test.eq(store.selectPreset(root, "titan", "ULD", active), true, "switch back")

    -- renamePreset validates and updates.
    test.eq(store.renamePreset(root, "titan", "ULD", p2, "普通团改"), true, "rename preset")
    test.eq(raid.presets[p2].name, "普通团改", "renamed name")

    -- copyPreset deep-copies: edits to the copy do not touch the source.
    test.eq(store.setLeaderItemPrice(root, "titan", "ULD", p2, 1004, 55), true, "seed source item")
    local p3 = store.copyPreset(root, "titan", "ULD", p2, "副本团")
    test.eq(type(p3), "string", "copy returns an id")
    test.eq(raid.presets[p3].name, "副本团", "copy name")
    test.eq(raid.presets[p3].itemPrices[1004], 55, "copy carries source items")
    test.eq(store.setLeaderItemPrice(root, "titan", "ULD", p3, 1005, 42), true, "edit copy")
    test.eq(raid.presets[p3].itemPrices[1005], 42, "copy has new item")
    test.eq(raid.presets[p2].itemPrices[1005], nil, "source untouched by copy edit")

    -- deletePreset refuses the last scheme.
    local p4 = store.createPreset(root, "titan", "ULD", "临时", 1)
    test.eq(store.deletePreset(root, "titan", "ULD", p4, active), true, "delete non-active preset")
    test.eq(raid.presets[p4], nil, "deleted preset removed")

    -- delete active requires a valid, different fallback.
    test.eq(store.deletePreset(root, "titan", "ULD", active, active), false, "fallback cannot be the deleted id")
    test.eq(store.deletePreset(root, "titan", "ULD", active, "p999"), false, "invalid fallback refused")
    test.eq(store.deletePreset(root, "titan", "ULD", active, p3), true, "delete active with valid fallback")
    test.eq(raid.activePresetId, p3, "active falls back")

    -- Price range: 0..MAX_MONEY integers only.
    test.eq(store.setBasePrice(root, "titan", "ULD", p3, -1), false, "negative base refused")
    test.eq(store.setBasePrice(root, "titan", "ULD", p3, store.MAX_MONEY + 1), false, "over-max base refused")
    test.eq(store.setBasePrice(root, "titan", "ULD", p3, 10.5), false, "non-integer base refused")
    test.eq(store.setBasePrice(root, "titan", "ULD", p3, store.MAX_MONEY), true, "max base accepted")
    test.eq(store.setLeaderItemPrice(root, "titan", "ULD", p3, 1006, store.MAX_MONEY), true, "max item price accepted")
    test.eq(store.setLeaderItemPrice(root, "titan", "ULD", p3, 1007, store.MAX_MONEY + 1), false, "over-max item price refused")

    -- Name length: 24 UTF-8 code points accepted, 25 refused.
    local name24 = string.rep("名", 24)
    local name25 = string.rep("名", 25)
    test.eq(store.renamePreset(root, "titan", "ULD", p3, name24), true, "24-char name accepted")
    test.eq(store.renamePreset(root, "titan", "ULD", p3, name25), false, "25-char name refused")
    test.eq(store.renamePreset(root, "titan", "ULD", p3, ""), false, "empty name refused")

    -- Max 20 schemes enforced.
    local familyRoot = { leaderAuctionPricePresets = {} }
    store.ensureLeaderRaid(familyRoot, "wrath", "ICC", 1000)
    for i = 2, store.MAX_PRESETS do
        local nid = store.createPreset(familyRoot, "wrath", "ICC", "方案" .. i, 100)
        test.eq(type(nid), "string", "scheme " .. i .. " created")
    end
    local over = store.createPreset(familyRoot, "wrath", "ICC", "超限", 100)
    test.eq(over, nil, "21st scheme refused")

    -- 500 item-price ceiling: a new item at the ceiling is refused.
    local capRaid = familyRoot.leaderAuctionPricePresets.wrath.ICC
    local pcap = capRaid.activePresetId
    for i = 1, store.MAX_ITEMS do
        store.setLeaderItemPrice(familyRoot, "wrath", "ICC", pcap, 100000 + i, i)
    end
    test.eq(store.setLeaderItemPrice(familyRoot, "wrath", "ICC", pcap, 999999, 1), false, "501st item refused")
    test.eq(store.setLeaderItemPrice(familyRoot, "wrath", "ICC", pcap, 100001, 77), true, "overwrite existing item allowed")

    -- Invalid keys fail closed without mutating the root.
    local before = capRaid.presets[pcap].basePrice
    test.eq(store.setBasePrice(familyRoot, "", "ICC", pcap, 5), false, "empty family refused")
    test.eq(capRaid.presets[pcap].basePrice, before, "root unchanged on bad family")

    -- Per-character personal prices
    test.eq(store.setPersonalPrice(root, "titan", "realm1", "Leader", "ULD", 1001, 900), true, "set personal price")
    test.eq(store.getPersonalPrice(root, "titan", "realm1", "Leader", "ULD", 1001), 900, "get personal price")
    test.eq(store.getPersonalPrice(root, "titan", "realm1", "Alt", "ULD", 1001), nil, "alt isolated")
    test.eq(store.getPersonalPrice(root, "wrath", "realm1", "Leader", "ULD", 1001), nil, "family isolated")
    test.eq(store.getPersonalPrice(root, "titan", "realm2", "Leader", "ULD", 1001), nil, "realm isolated")
    test.eq(store.clearPersonalPrice(root, "titan", "realm1", "Leader", "ULD", 1001), true, "clear personal price")
    test.eq(store.getPersonalPrice(root, "titan", "realm1", "Leader", "ULD", 1001), nil, "cleared personal price")

    -- Explicit zero is distinct from unset.
    test.eq(store.setPersonalPrice(root, "titan", "realm1", "Leader", "ULD", 1002, 0), true, "set zero personal price")
    test.eq(store.getPersonalPrice(root, "titan", "realm1", "Leader", "ULD", 1002), 0, "zero personal price read back")
    test.eq(store.getPersonalPrice(root, "titan", "realm1", "Leader", "ULD", 9999), nil, "unset personal price is nil")

    -- countPersonalPrices and clearPersonalRaid.
    test.eq(store.setPersonalPrice(root, "titan", "realm1", "Leader", "ULD", 1003, 10), true, "set second price")
    test.eq(store.countPersonalPrices(root, "titan", "realm1", "Leader", "ULD"), 2, "count personal prices")
    test.eq(store.clearPersonalRaid(root, "titan", "realm1", "Leader", "ULD"), true, "clear personal raid")
    test.eq(store.countPersonalPrices(root, "titan", "realm1", "Leader", "ULD"), 0, "raid cleared")

    -- Empty leaf tables are pruned after clearing.
    test.eq(root.personalAuctionExpectations.titan, nil, "empty family pruned")

    -- Invalid inputs leave the root unchanged.
    local snapshot = root.personalAuctionExpectations
    test.eq(store.setPersonalPrice(root, "titan", "", "Leader", "ULD", 1001, 5), false, "empty realm refused")
    test.eq(store.setPersonalPrice(root, "titan", "realm1", "Leader", "ULD", 0, 5), false, "zero item refused")
    test.eq(store.setPersonalPrice(root, "titan", "realm1", "Leader", "ULD", 1001, -1), false, "negative price refused")
    test.eq(root.personalAuctionExpectations, snapshot, "root unchanged on invalid personal input")

    -- 500-item ceiling on personal prices.
    test.eq(store.setPersonalPrice(root, "titan", "realm1", "Leader", "Naxx", 1, 1), true, "seed personal ceiling")
    for i = 2, store.MAX_ITEMS do
        store.setPersonalPrice(root, "titan", "realm1", "Leader", "Naxx", i, i)
    end
    test.eq(store.setPersonalPrice(root, "titan", "realm1", "Leader", "Naxx", 999999, 1), false, "501st personal item refused")
    test.eq(store.setPersonalPrice(root, "titan", "realm1", "Leader", "Naxx", 1, 77), true, "overwrite personal item allowed")
end
