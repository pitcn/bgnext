return function(test)
    BG = { BGNext = {} }
    local catalog = dofile("Core/BGNext/AuctionPriceCatalog.lua")

    local function describe(id)
        return {
            itemId = id,
            name = "装备" .. id,
            equipLoc = (id == 102) and "INVTYPE_TRINKET" or "INVTYPE_HEAD",
            quality = 4,
        }
    end

    local model = catalog.build({
        raidId = "ULD",
        difficulties = { "N", "H" },
        bosses = { { id = "boss1", name = "烈焰巨兽" }, { id = "misc", name = "杂项" } },
        loot = { N = { boss1 = { 101, 102 }, boss1other = { 103 } }, H = { boss1 = { 101, 104 } } },
        describeItem = describe,
    })

    test.eq(model.raidId, "ULD", "raid id kept")
    test.eq(#model.groups, 2, "two groups")
    test.eq(model.groups[1].id, "boss1", "first group is boss1")
    test.eq(model.groups[1].name, "烈焰巨兽", "boss name kept")
    test.eq(#model.groups[1].items, 4, "boss supplementary drops stay with their boss")
    test.eq(model.groups[2].id, "misc", "second group is misc")
    test.eq(model.groups[2].name, "杂项", "misc name kept")
    test.eq(#model.groups[2].items, 0, "misc does not absorb boss supplementary drops")
    test.eq(model.groups[1].items[3].itemId, 103, "boss supplementary item remains searchable under its boss")

    test.eq(catalog.resolveRaidForItem({ ULD = model }, 104), "ULD", "resolve item to raid")
    test.eq(catalog.resolveRaidForItem({ ULD = model }, 999), nil, "unknown item resolves nil")

    local filtered = catalog.filter(model, { text = "102", equipLoc = "INVTYPE_TRINKET", quality = 4 })
    test.eq(#filtered, 1, "combined filter returns one item")
    test.eq(filtered[1].itemId, 102, "filtered item is 102")

    -- Unknown names remain searchable by item id.
    local model2 = catalog.build({
        raidId = "ICC",
        difficulties = { "N" },
        bosses = { { id = "boss1", name = "Boss" }, { id = "misc", name = "杂项" } },
        loot = { N = { boss1 = { 201 } } },
        describeItem = function() return nil end,
    })
    test.eq(#catalog.filter(model2, { text = "201" }), 1, "unknown name still searchable by id")

    -- State filtering through a supplied hasPrice callback.
    local hasPrice = function(id) return id == 101 end
    test.eq(#catalog.filter(model, { state = "set", hasPrice = hasPrice }), 1, "state set")
    test.eq(#catalog.filter(model, { state = "unset", hasPrice = hasPrice }), 3, "state unset")

    -- Keys that do not belong to a known boss (including the table's misc row)
    -- still fall back to the explicit misc group.
    local withMisc = catalog.build({
        raidId = "R2",
        difficulties = { "N" },
        bosses = { { id = "boss1", name = "b" }, { id = "misc", name = "m" } },
        loot = { N = { boss1 = { 401 }, boss2 = { 402 }, currency = { 403 } } },
        describeItem = describe,
    })
    test.eq(#withMisc.groups[1].items, 1, "known boss drop stays under boss")
    test.eq(#withMisc.groups[2].items, 2, "unknown table sections remain misc")

    -- Ambiguous cross-raid item resolution returns nil.
    local mk = function(raidId, itemId)
        return catalog.build({
            raidId = raidId,
            difficulties = { "N" },
            bosses = { { id = "boss1", name = "b" }, { id = "misc", name = "m" } },
            loot = { N = { boss1 = { itemId } } },
            describeItem = describe,
        })
    end
    local modelA = mk("A", 301)
    local modelB = mk("B", 301)
    test.eq(catalog.resolveRaidForItem({ A = modelA, B = modelB }, 301), nil, "ambiguous item resolves nil")
    test.eq(catalog.resolveRaidForItem({ A = modelA }, 301), "A", "unique item resolves")

    -- updateItemDescription fills in a missing name in place.
    test.eq(catalog.updateItemDescription(model2, 201, { name = "冰霜巨人的力量", equipLoc = "INVTYPE_HEAD", quality = 5 }), true, "description updated")
    test.eq(model2.groups[1].items[1].name, "冰霜巨人的力量", "name filled")
    test.eq(model2.groups[1].items[1].quality, 5, "quality filled")

    -- Deterministic ordering: items within a group sort by item id.
    local unordered = catalog.build({
        raidId = "R",
        difficulties = { "N" },
        bosses = { { id = "boss1", name = "b" }, { id = "misc", name = "m" } },
        loot = { N = { boss1 = { 30, 10, 20 } } },
        describeItem = describe,
    })
    local ids = {}
    for _, item in ipairs(unordered.groups[1].items) do ids[#ids + 1] = item.itemId end
    test.eq(ids[1], 10, "items sorted ascending (1)")
    test.eq(ids[2], 20, "items sorted ascending (2)")
    test.eq(ids[3], 30, "items sorted ascending (3)")
end
