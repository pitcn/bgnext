return function(test)
    BG = { BGNext = {} }
    local M = dofile("Core/BGNext/OwnCharacters.lua")

    -- Whitelisted snapshot storage for the currently logged-in character only.
    local root = {}
    local saved = M.upsert(root, "titan", {
        realmId = 123,
        realmName = "时光II",
        player = "Piti",
        class = "HUNTER",
        level = 80,
        itemLevel = 230.75,
        updatedAt = 1000,
        money = 50000,
        equipment = {
            [1] = { itemId = 1001, icon = 134400 },
            [2] = { itemId = 1002, icon = "Interface\\Icons\\INV_Test" },
            [3] = { itemId = 1003, icon = { unsafe = true } },
        },
        professions = {
            [1] = { name = "工程", icon = 136243 },
        },
        raidStates = { SWtitan = { completed = true, resetsAt = 2000 } },
        unknownField = "must not persist",
    })

    test.eq(saved.player, "Piti", "stores current character")
    test.eq(saved.realmName, "时光II", "stores normalized realm name")
    test.eq(saved.unknownField, nil, "drops non-whitelisted fields")
    test.eq(saved.equipment[1].icon, 134400, "numeric Blizzard texture file IDs are preserved")
    test.eq(saved.equipment[2].icon, "Interface\\Icons\\INV_Test", "string Blizzard texture paths are preserved")
    test.eq(saved.equipment[3].icon, nil, "non-serializable texture values are rejected")
    test.eq(saved.professions[1].icon, 136243, "numeric profession texture IDs are preserved")
    test.eq(M.get(root, "titan", 123, "Piti").itemLevel, 230.75, "reads snapshot")
    M.expireRaidStates(root, 2001)
    test.eq(next(M.get(root, "titan", 123, "Piti").raidStates), nil, "expires weekly state")

    -- Fields that would build a profile or enable communication are never stored.
    local probeRoot = {}
    local rejected = M.upsert(probeRoot, "titan", {
        realmId = 123, realmName = "时光II", player = "Piti",
        guid = "Player-4395-01",
        battleTag = "user#1234",
        note = "private",
        history = { { itemLevel = 1 } },
        score = 99,
    })
    test.eq(rejected.guid, nil, "never stores a GUID")
    test.eq(rejected.battleTag, nil, "never stores an account identifier")
    test.eq(rejected.note, nil, "never stores private notes")
    test.eq(rejected.history, nil, "never stores history")
    test.eq(rejected.score, nil, "never stores a score")

    -- Same-name cross-realm characters stay independent rows.
    M.upsert(root, "titan", {
        realmId = 456, realmName = "时光III", player = "Piti",
        class = "MAGE", level = 70, itemLevel = 180, updatedAt = 1100,
    })
    test.eq(M.get(root, "titan", 123, "Piti").class, "HUNTER", "realm 123 keeps its own class")
    test.eq(M.get(root, "titan", 456, "Piti").class, "MAGE", "realm 456 keeps its own class")
    test.eq(#M.list(root, "titan"), 2, "same-name cross-realm characters are separate")

    -- Updates overwrite the last snapshot and never accumulate history.
    M.upsert(root, "titan", {
        realmId = 456, realmName = "时光III", player = "Piti",
        class = "MAGE", level = 71, itemLevel = 185, updatedAt = 1200,
    })
    local updated = M.get(root, "titan", 456, "Piti")
    test.eq(updated.level, 71, "overwrites with the newest snapshot")
    test.eq(updated.itemLevel, 185, "overwrites item level")
    test.eq(#M.list(root, "titan"), 2, "update does not add a row")
    test.eq(updated.previous, nil, "no previous-value field")
    test.eq(updated.history, nil, "no history array")

    -- Client families are isolated from each other.
    M.upsert(root, "mop", {
        realmId = 123, realmName = "时光II", player = "Piti",
        class = "PRIEST", level = 90, updatedAt = 1300,
    })
    test.eq(M.get(root, "titan", 123, "Piti").class, "HUNTER", "titan snapshot untouched by mop")
    test.eq(M.get(root, "mop", 123, "Piti").class, "PRIEST", "mop snapshot stored separately")

    -- Nested tables are deep-copied so callers cannot mutate stored state.
    local raidStates = { MCtitan = { completed = true, resetsAt = 9000 } }
    M.upsert(root, "titan", {
        realmId = 123, realmName = "时光II", player = "Piti",
        class = "HUNTER", level = 80, updatedAt = 1400, raidStates = raidStates,
    })
    raidStates.MCtitan.completed = false
    test.eq(M.get(root, "titan", 123, "Piti").raidStates.MCtitan.completed, true, "nested tables are deep-copied")

    -- Invalid input is rejected instead of creating malformed rows.
    test.eq(M.upsert(root, "titan", nil), nil, "rejects missing snapshot")
    test.eq(M.upsert(root, "titan", { realmId = 123 }), nil, "rejects missing player name")
    test.eq(M.upsert(root, "titan", { player = "Piti" }), nil, "rejects missing realm id")
    test.eq(M.upsert(root, nil, { realmId = 1, player = "Piti" }), nil, "rejects missing client family")
    test.eq(#M.list(root, "titan"), 2, "invalid input adds no rows")

    -- Expiry only clears the weekly raid state, never the character row.
    M.upsert(root, "titan", {
        realmId = 123, realmName = "时光II", player = "Piti",
        class = "HUNTER", level = 80, itemLevel = 231, updatedAt = 1500,
        raidStates = {
            MCtitan = { completed = true, resetsAt = 9000 },
            SWtitan = { completed = true, resetsAt = 3000 },
        },
    })
    M.expireRaidStates(root, 5000)
    local afterExpiry = M.get(root, "titan", 123, "Piti")
    test.eq(afterExpiry.raidStates.SWtitan, nil, "expired raid state is dropped")
    test.eq(afterExpiry.raidStates.MCtitan.completed, true, "unexpired raid state survives")
    test.eq(afterExpiry.itemLevel, 231, "expiry keeps equipment snapshot")
    test.eq(#M.list(root, "titan"), 2, "expiry keeps character rows")

    -- Deletion needs the full realm+name key.
    test.eq(M.delete(root, "titan", 999, "Piti"), false, "wrong realm deletes nothing")
    test.eq(#M.list(root, "titan"), 2, "wrong realm left both rows")
    test.eq(M.delete(root, "titan", 123, "Piti"), true, "deletes the exact character")
    test.eq(M.get(root, "titan", 123, "Piti"), nil, "deleted character is gone")
    test.eq(M.get(root, "titan", 456, "Piti").class, "MAGE", "same-name character on another realm survives")
    test.eq(M.get(root, "mop", 123, "Piti").class, "PRIEST", "other family survives a delete")

    -- Family and global clears.
    M.clearFamily(root, "titan")
    test.eq(#M.list(root, "titan"), 0, "clearFamily empties that family")
    test.eq(#M.list(root, "mop"), 1, "clearFamily keeps other families")
    M.clearAll(root)
    test.eq(#M.list(root, "mop"), 0, "clearAll empties every family")

    -- list() is deterministic and defensive.
    local fresh = {}
    M.ensureRoot(fresh)
    test.eq(type(fresh.ownCharacters), "table", "ensureRoot creates the subtree")
    test.eq(#M.list(fresh, "titan"), 0, "unknown family lists nothing")
    test.eq(M.get(fresh, "titan", 1, "Nobody"), nil, "unknown character reads nil")
    test.eq(M.delete(fresh, "titan", 1, "Nobody"), false, "deleting an unknown character is safe")

    -- Only explicit string/number/boolean types are stored. The whitelist must
    -- never accept "any": a wrong-typed scalar, frame, function or userdata is
    -- dropped instead of reaching SavedVariables.
    local typeRoot = {}
    test.eq(M.upsert(typeRoot, "titan", { realmId = "123", player = "Piti" }), nil,
        "a string realm id is rejected (realmId must be a number)")

    local typed = M.upsert(typeRoot, "titan", {
        realmId = 123, realmName = "时光II", player = "Piti",
        equipment = { [1] = { itemId = 1, icon = {} } },
        raidStates = { MCtitan = { difficulty = "normal", resetsAt = 9000 } },
        professions = { { name = "锻造", icon = function() end } },
    })
    test.eq(typed.equipment[1].icon, nil, "non-string equipment icon is dropped")
    test.eq(typed.raidStates.MCtitan.difficulty, nil, "non-number difficulty is dropped")
    test.eq(typed.professions[1].icon, nil, "non-string profession icon is dropped")

    -- Currency values may be a plain count (Titan legacy) or a capped record.
    local currencyRoot = {}
    local capped = M.upsert(currencyRoot, "mop", {
        realmId = 123, realmName = "时光II", player = "Piti",
        currencies = {
            valor = { quantity = 1000, maxQuantity = 3000, quantityEarnedThisWeek = 500, maxWeeklyQuantity = 1000 },
            honor = 25,
            broken = { quantity = "many" },
            missingQuantity = { maxQuantity = 100 },
        },
    })
    test.eq(capped.currencies.valor.quantity, 1000, "capped currency keeps its quantity")
    test.eq(capped.currencies.valor.maxQuantity, 3000, "capped currency keeps the total cap")
    test.eq(capped.currencies.valor.quantityEarnedThisWeek, 500, "capped currency keeps the weekly earned amount")
    test.eq(capped.currencies.valor.maxWeeklyQuantity, 1000, "capped currency keeps the weekly cap")
    test.eq(capped.currencies.honor, 25, "a plain numeric currency is still stored")
    test.eq(capped.currencies.broken, nil, "a currency record with a non-numeric quantity is dropped")
    test.eq(capped.currencies.missingQuantity, nil, "a currency record without a quantity is dropped")

    -- Capped currency records are deep-copied like every other nested table.
    local mutableCurrency = { quantity = 1000, maxQuantity = 3000 }
    M.upsert(currencyRoot, "mop", {
        realmId = 123, realmName = "时光II", player = "Piti",
        currencies = { valor = mutableCurrency },
    })
    mutableCurrency.quantity = 1
    test.eq(M.get(currencyRoot, "mop", 123, "Piti").currencies.valor.quantity, 1000,
        "capped currency records are deep-copied")

    -- Cap fields accept only numbers; a wrong-typed cap is dropped but quantity
    -- survives so a partial API result still shows the real amount.
    local partialCaps = M.upsert(currencyRoot, "mop", {
        realmId = 123, realmName = "时光II", player = "Piti",
        currencies = { justice = { quantity = 2000, maxQuantity = "lots", weeklyBad = true } },
    })
    test.eq(partialCaps.currencies.justice.quantity, 2000, "partial cap record keeps quantity")
    test.eq(partialCaps.currencies.justice.maxQuantity, nil, "non-numeric cap is dropped")
    test.eq(partialCaps.currencies.justice.weeklyBad, nil, "non-whitelisted cap field is dropped")

    -- Profession cooldowns store only a ready flag or a future reset timestamp.
    local cdRoot = {}
    local cds = M.upsert(cdRoot, "vanilla", {
        realmId = 123, realmName = "时光II", player = "Piti",
        professionCooldowns = {
            transmute = { ready = true },
            mooncloth = { endsAt = 9000 },
            mixed = { ready = true, endsAt = 9000 },
            empty = {},
            wrongType = { ready = "yes" },
            badEnds = { endsAt = "soon" },
        },
    })
    test.eq(cds.professionCooldowns.transmute.ready, true, "a ready cooldown is stored")
    test.eq(cds.professionCooldowns.mooncloth.endsAt, 9000, "a cooldown endsAt timestamp is stored")
    test.eq(cds.professionCooldowns.mixed.ready, true, "both cooldown fields may coexist")
    test.eq(cds.professionCooldowns.mixed.endsAt, 9000, "coexisting endsAt is retained")
    test.eq(cds.professionCooldowns.empty, nil, "an empty cooldown record is dropped")
    test.eq(cds.professionCooldowns.wrongType, nil, "a non-boolean ready flag is dropped")
    test.eq(cds.professionCooldowns.badEnds, nil, "a non-numeric endsAt is dropped")

    -- Cooldown records are deep-copied so callers cannot mutate stored state.
    local mutableCd = { ready = true }
    M.upsert(cdRoot, "vanilla", {
        realmId = 123, realmName = "时光II", player = "Piti",
        professionCooldowns = { transmute = mutableCd },
    })
    mutableCd.ready = false
    test.eq(M.get(cdRoot, "vanilla", 123, "Piti").professionCooldowns.transmute.ready, true,
        "profession cooldown records are deep-copied")

    -- Retail raid states keep their per-difficulty and per-boss breakdowns
    -- through the nested whitelist, deep-copied and stripped of junk.
    local retailRoot = {}
    local retailSaved = M.upsert(retailRoot, "retail", {
        realmId = 123, realmName = "时光II", player = "Piti",
        raidStates = {
            DR = {
                difficulty = 16, difficultyLabel = "M",
                completedParts = 6, totalParts = 6, completed = true, resetsAt = 9000,
                difficulties = {
                    { difficulty = 14, difficultyLabel = "N", completedParts = 6, totalParts = 6, resetsAt = 9000, junk = "x" },
                    { difficulty = 15, difficultyLabel = "H", completedParts = 3, totalParts = 6, resetsAt = 9000 },
                    { difficulty = 16, difficultyLabel = "M", completedParts = 6, totalParts = 6, resetsAt = 9000 },
                },
                encounters = {
                    { id = 1001, name = "首王", done = true, note = "drop me" },
                    { id = 1002, name = "次王", done = false },
                    { id = 1003, name = "末王", done = "yes" },
                },
            },
        },
    })
    local drSaved = retailSaved.raidStates.DR
    test.eq(type(drSaved.difficulties), "table", "retail difficulties array is stored")
    test.eq(#drSaved.difficulties, 3, "every difficulty is stored")
    test.eq(drSaved.difficulties[1].difficultyLabel, "N", "difficulty label survives")
    test.eq(drSaved.difficulties[1].completedParts, 6, "difficulty count survives")
    test.eq(drSaved.difficulties[1].junk, nil, "junk difficulty fields are dropped")
    test.eq(type(drSaved.encounters), "table", "retail encounters array is stored")
    test.eq(#drSaved.encounters, 3, "every boss is stored")
    test.eq(drSaved.encounters[1].done, true, "a done boss flag survives")
    test.eq(drSaved.encounters[1].name, "首王", "a boss name survives")
    test.eq(drSaved.encounters[1].note, nil, "junk encounter fields are dropped")
    test.eq(drSaved.encounters[3].done, nil, "a non-boolean done flag is dropped")

    -- The nested arrays are deep-copied so callers cannot mutate stored state.
    local mutableDifficulties = { { difficulty = 16, difficultyLabel = "M", completedParts = 6, totalParts = 6, resetsAt = 9000 } }
    M.upsert(retailRoot, "retail", {
        realmId = 123, realmName = "时光II", player = "Piti",
        raidStates = {
            DR = {
                difficulty = 16, difficultyLabel = "M", completedParts = 6, totalParts = 6,
                resetsAt = 9000, difficulties = mutableDifficulties,
            },
        },
    })
    mutableDifficulties[1].completedParts = 0
    test.eq(M.get(retailRoot, "retail", 123, "Piti").raidStates.DR.difficulties[1].completedParts, 6,
        "raid difficulty arrays are deep-copied")
end
