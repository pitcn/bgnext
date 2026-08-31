return function(test)
    BG = { BGNext = {} }
    local status = dofile("Core/BGNext/RetailLootStatus.lua")

    -- Declared states: VS has shipped loot, VA is mapped but pending, anything
    -- else is hidden.
    test.eq(status.state("VS"), "available", "VS reports verified loot data")
    test.eq(status.state("VA"), "pending", "VA is mapped but not yet adapted")
    test.eq(status.state("unknown"), "hidden", "an unmapped raid is hidden")
    test.eq(status.state(nil), "hidden", "a nil raid id is safe")
    test.eq(status.isAvailable("VS"), true, "available raids are reported")
    test.eq(status.isPending("VA"), true, "pending raids are reported")
    test.eq(status.isAvailable("VA"), false, "pending is never reported as available")
    test.eq(status.isPending("VS"), false, "available is never reported as pending")

    -- A raid is populated only when every difficulty has at least one non-empty
    -- primary boss bucket. An empty bucket is never "supported".
    local populatedLoot = {
        N = { boss1 = { 1001, 1002 }, boss2 = { 2001 } },
        H = { boss1 = { 3001 } },
        M = { boss1 = { 4001 } },
    }
    test.eq(status.lootPopulated(populatedLoot, { "N", "H", "M" }), true,
        "a raid with every difficulty populated is ready")

    local emptyLoot = { N = { boss1 = {} }, H = { boss1 = {} }, M = { boss1 = {} } }
    test.eq(status.lootPopulated(emptyLoot, { "N", "H", "M" }), false,
        "empty buckets are not supported")
    test.eq(status.lootPopulated({}, { "N" }), false, "an absent raid loot table is not supported")
    test.eq(status.lootPopulated(nil, { "N" }), false, "a nil loot table is not supported")
    test.eq(status.lootPopulated(populatedLoot, nil), false, "a nil difficulty table is not supported")
    test.eq(status.lootPopulated(populatedLoot, {}), false, "no difficulties means no data")

    local otherOnly = {
        N = { boss2other = { 1001 } },
        H = { boss2other = { 1001 } },
        M = { boss2other = { 1001 } },
    }
    test.eq(status.lootPopulated(otherOnly, { "N", "H", "M" }), false,
        "exchange-only buckets are not real boss loot")

    -- The declaration must stay in step with the actual data file: DB_Loot_Retail
    -- ships VS and deliberately leaves VA empty so it stays pending.
    local file = assert(io.open("Core/DB/DB_Loot_Retail.lua", "rb"))
    local source = file:read("*a")
    file:close()
    test.eq(source:find('"VS"', 1, true) ~= nil, true, "DB_Loot_Retail ships VS loot data")
    test.eq(source:find('"VA"', 1, true), nil, "DB_Loot_Retail does not fabricate VA loot data")
end
