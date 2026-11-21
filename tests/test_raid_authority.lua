return function(test)
    local previousBG = BG
    BG = { BGNext = {} }
    local M = dofile("Core/BGNext/RaidAuthority.lua")
    local Identity = dofile("Core/BGNext/PlayerIdentity.lua")

    local function api(opts)
        opts = opts or {}
        local a = {}
        a.IsInRaid = function() return opts.inRaid ~= false end
        if opts.selfIndex ~= false then
            a.UnitIsUnit = function(unit, other)
                if opts.unitError then error("boom") end
                return other == "player" and unit == "raid" .. tostring(opts.selfIndex or 3)
            end
        end
        a.UnitIsGroupLeader = function(unit) return unit == "player" and opts.leader == true end
        if opts.isMasterLooter ~= nil then
            a.IsMasterLooter = function() return opts.isMasterLooter end
        end
        if opts.lootMethod then
            a.C_PartyInfo = { GetLootMethod = function() return unpack(opts.lootMethod) end }
        end
        a.Enum = { LootMethod = { Masterlooter = 2 } }
        return a
    end

    -- Self is found by unit token whatever the roster name format is.
    for _, rosterName in ipairs({ "名 姓", "名-姓", "名" }) do
        for _, playerName in ipairs({ "名 姓", false }) do
            local pn = playerName or nil
            local isSelf, method = M.isSelfRow(api({ selfIndex = 3 }), 3, rosterName, pn, "Realm", Identity)
            test.eq(isSelf, true, "unit token identifies self for roster format " .. rosterName)
            test.eq(method, "unit", "unit token is the primary method")
        end
    end
    test.eq((M.isSelfRow(api({ selfIndex = 3 }), 1, "名 姓", "名 姓", "Realm", Identity)), false,
        "roster index 1 with an identical name is not self when the unit token says otherwise")

    -- Name comparison is only a fallback.
    local noUnit = api({ selfIndex = false })
    test.eq((M.isSelfRow(noUnit, 2, "名 姓", "名 姓", "Realm", Identity)), true, "fallback matches an equal full name")
    test.eq((M.isSelfRow(noUnit, 2, "名-姓", "名 姓", "Realm", Identity)), false, "fallback does not guess across formats")
    test.eq((M.isSelfRow(noUnit, 2, "名", "名 姓", "Realm", Identity)), false, "fallback does not match a short name")
    test.eq((M.isSelfRow(noUnit, 2, "名 姓", nil, "Realm", Identity)), false, "fallback with no player name is safe")
    test.eq((M.isSelfRow(api({ unitError = true }), 2, "名 姓", "名 姓", "Realm", Identity)), true,
        "a failing unit API falls back to the name")

    -- Live leader / master looter.
    test.eq(M.liveIsLeader(api({ leader = true })), true, "raid leader is live controller")
    test.eq(M.liveIsLeader(api({ leader = true, inRaid = false })), false, "leader outside a raid is not")
    test.eq(M.liveIsLeader(api({ leader = false })), false, "assistant or member is not leader")
    test.eq(M.liveIsMasterLooter(api({ isMasterLooter = true })), true, "IsMasterLooter grants")
    test.eq(M.liveIsMasterLooter(api({ isMasterLooter = false })), false, "not master looter")
    test.eq(M.liveIsMasterLooter(api({ lootMethod = { 2, 0, nil } })), true, "partyID 0 master looter is self")
    test.eq(M.liveIsMasterLooter(api({ lootMethod = { "master", nil, 3 }, selfIndex = 3 })), true,
        "master looter raid index that is self")
    test.eq(M.liveIsMasterLooter(api({ lootMethod = { "master", 2, 5 }, selfIndex = 3 })), false,
        "someone else is master looter")
    test.eq(M.liveIsMasterLooter(api({ lootMethod = { "group", 0, nil } })), false, "group loot is not master loot")

    test.eq(M.isController(api({}), true), true, "cached permission is honoured")
    test.eq(M.isController(api({ leader = false }), nil), false, "assistants and members are refused")
    test.eq(M.isController(api({ leader = true }), nil), true, "stale cache does not deny a live leader")
    test.eq(M.isController({}, nil), false, "missing client APIs mean no permission")
    local throwing = setmetatable({}, { __index = function() return function() error("x") end end })
    test.eq(M.isController(throwing, nil), false, "throwing client APIs mean no permission")

    test.eq(M.errorLocation("Interface/AddOns/BGNext/Core/BiaoGe.lua:1909: attempt"), "BiaoGe.lua:1909",
        "diagnostic keeps only the file and line")
    test.eq(type(BG.IsAuctionController), "function", "global controller helper is exposed")
    BG = previousBG
end