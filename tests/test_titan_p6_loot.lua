return function(test)
    local path = "Core/DB/DB_Loot_Titan_P6.lua"
    local oldRaid = { N = { boss1 = { 12345 } } }
    local saved = { BGNext = { sentinel = true } }
    BiaoGe = saved
    BG = { IsTitan = true, BGNext = {}, Loot = {
        ULDtitan = { N = { Quest = {} }, ExchangeItems = {} }, SWtitan = oldRaid,
        stackItems = { [22726] = true }, zaXiangItems = { [265523] = true },
    } }
    dofile(path)
    local raid = BG.Loot.ULDtitan
    test.eq(BG.Loot.stackItems[270187], true, "current fragment uses existing stack aggregation")
    for _, id in ipairs({ 270157, 270148, 270158, 270156, 270149, 270150, 45087 }) do
        test.eq(BG.Loot.zaXiangItems[id], true, "upgrade/material item is routed to misc")
    end
    test.eq(BG.Loot.stackItems[22726], true, "old fragment handling is preserved")
    test.eq(BG.Loot.zaXiangItems[265523], true, "old upgrade handling is preserved")
    local Wishlist = dofile("Core/BGNext/Wishlist.lua")
    local Price = dofile("Core/BGNext/AuctionPriceCatalog.lua")
    local function same(a, b) return a == b end
    local function resolve(id, preferred)
        return Wishlist.resolveDrop(id, { "N" }, raid, 15, same, 1, preferred)
    end
    local counts = { 34, 22, 26, 34, 34, 25, 25, 24, 25, 25, 25, 35, 35, 33, 21 }
    local bosses = {}
    for boss = 1, 15 do
        local list = raid.N["boss" .. boss]
        test.eq(type(list), "table", "P6 catalog covers boss/misc " .. boss)
        test.eq(#list, counts[boss], "all authorized source rows retained for " .. boss)
        local seen = {}
        for _, id in ipairs(list) do
            test.eq(type(id), "number", "page markers never become items")
            test.eq(seen[id], nil, "no duplicate in a boss pool")
            seen[id] = true
            test.eq(resolve(id, boss).bossIndex, boss, "each drop resolves in its own wish cell")
        end
        bosses[#bosses + 1] = { id = "boss" .. boss, name = tostring(boss) }
    end
    local prices = Price.build({ raidId = "ULDtitan", difficulties = { "N" }, bosses = bosses, loot = raid })
    test.eq(resolve(45309).bossIndex, 3, "Ignis uses BGNext's third boss, not source order")
    test.eq(resolve(45305).bossIndex, 2, "Razorscale uses BGNext's second boss")
    test.eq(resolve(46053).bossIndex, 14, "Algalon stays last")
    test.eq(prices.byItem[45132] ~= nil, true, "second-page drop can get a starting price")
    test.eq(prices.byItem[45087] ~= nil, true, "shared material remains priceable")
    test.eq(raid.N10, nil, "no 10-player catalog")
    test.eq(raid.H25, nil, "no invented heroic difficulty")
    test.eq(raid.ExchangeItems[45632][1] ~= nil, true, "T8 token has exchange rewards")
    test.eq(raid.ExchangeItems[270157][1], 264744, "current upgrade token has current reward")
    test.eq(prices.byItem[264744], nil, "upgrade product is not sold as a boss drop")
    test.eq(prices.byItem[46154], nil, "T8 product is not a separate auction drop")
    test.eq(prices.byItem[270187] ~= nil, true, "current Valanyr fragment is catalogued")
    test.eq(prices.byItem[45038], nil, "quest chain step is not direct loot")
    local root = { wishlist = {} }
    local placed = Wishlist.placeItem(root, 1, "Fixture", "ULDtitan",
        { difficulties = 1, bosses = 15, slots = 5 }, 45132, function(id) return resolve(id) end)
    test.eq(placed.ok, true, "real P6 item can be added to local wishlist")
    test.eq(Wishlist.getSlot(root, 1, "Fixture", "ULDtitan", 1, 1, 1), 45132, "wish is stored")
    test.eq(BiaoGe, saved, "catalog load does not migrate saved data")
    test.eq(BG.Loot.SWtitan, oldRaid, "P5 catalog is untouched")
    local requested = {}
    BG.FBtable = { "ULDtitan" }
    BG.difficultyTable = { ULDtitan = { "N" } }
    BG.Init2 = function(fn) fn() end
    BG.After = function(_, fn) fn() end
    BG.OnItemLoad = function(id)
        requested[id] = (requested[id] or 0) + 1
        return { ContinueOnItemLoad = function(_, fn) fn() end }
    end
    assert(loadfile("Core/Module/ItemLib.lua"))("BGNext", {})
    for boss = 1, 15 do
        for _, id in ipairs(raid.N["boss" .. boss]) do
            test.eq(requested[id], 1, "every drop is requested once even if shared by bosses")
        end
    end
    test.eq(requested[46154], 1, "T8 reward metadata is preloaded by the actual item library")
    test.eq(requested[264744], 1, "upgrade reward metadata is preloaded")
    BG = { IsTitan = false }
    dofile(path)
    test.eq(BG.Loot, nil, "P6 data stays out of other clients")
end
