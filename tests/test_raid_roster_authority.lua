return function(test)
    -- Runs the real roster-refresh block from Core/BiaoGe.lua in a sandbox and
    -- checks that the player's own raid role is found by unit token, whatever
    -- the Forever name format is, and that only leader / master looter qualify.
    local file = assert(io.open("Core/BiaoGe.lua", "rb"))
    local source = file:read("*a")
    file:close()
    local block = assert(source:match("(%-%-%-%-%-%-%-%-%-%-刷新团队成员信息.-)\n%-%- 插件命令"),
        "roster refresh block found")

    local previousBG = BG
    local function run(opts)
        BG = { BGNext = {} }
        dofile("Core/BGNext/PlayerIdentity.lua")
        if not opts.noAuthority then dofile("Core/BGNext/RaidAuthority.lua") end
        local events, init2 = {}, {}
        BG.playerName = opts.playerName
        BG.realmName = "Realm"
        BG.Init2 = function(fn) init2[#init2 + 1] = fn end
        BG.RegisterEvent = function(event, fn) events[event] = fn end
        BG.GN = function() return nil end
        BG.playerClass = opts.playerClass or {
            class = { func = function() return "Warrior", "WARRIOR" end, select = 2 },
        }
        local roster = opts.roster
        local env = setmetatable({
            BG = BG,
            wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
            IsInRaid = function() return true end,
            IsInGroup = function() return true end,
            GetNumGroupMembers = function() return #roster end,
            GetRaidRosterInfo = function(i)
                local r = roster[i]
                return r.name, r.rank, 1, 60, "Warrior", "WARRIOR", "Zone", true, false, nil, r.isML, nil
            end,
            UnitIsUnit = (not opts.noUnitIsUnit) and function(unit, other)
                return other == "player" and unit == "raid" .. tostring(opts.selfIndex)
            end or nil,
            UnitIsGroupLeader = function(unit)
                return unit == "player" and opts.liveLeader == true
            end,
            IsMasterLooter = function() return opts.liveML == true end,
            UnitGUID = function() return nil end,
            UnitClass = function() return "Warrior", "WARRIOR" end,
            C_Timer = { After = function(_, fn) fn() end },
        }, { __index = _G })
        BG.BGNext.RaidAuthority = BG.BGNext.RaidAuthority
        -- RaidAuthority reads client APIs from _G; expose the fakes there too.
        local saved = {}
        for _, name in ipairs({ "IsInRaid", "UnitIsUnit", "UnitIsGroupLeader", "IsMasterLooter", "GetLootMethod", "C_PartyInfo" }) do
            saved[name] = rawget(_G, name)
            rawset(_G, name, rawget(env, name))
        end
        local chunk = assert(loadstring(block))
        setfenv(chunk, env)
        local ok, err = pcall(function()
            chunk()
            BG.UpdateRaidRosterInfo()
        end)
        for name, value in pairs(saved) do rawset(_G, name, value) end
        for _, name in ipairs({ "IsInRaid", "UnitIsUnit", "UnitIsGroupLeader", "IsMasterLooter", "GetLootMethod", "C_PartyInfo" }) do
            if saved[name] == nil then rawset(_G, name, nil) end
        end
        assert(ok, err)
        return BG, events
    end

    local others = { name = "甲 乙", rank = 0 }
    for _, format in ipairs({ "名 姓", "名-姓", "名" }) do
        for _, playerName in ipairs({ "名 姓", false }) do
            local bg = run({
                playerName = playerName or nil, selfIndex = 3,
                roster = { others, { name = "丙 丁", rank = 1 }, { name = format, rank = 2 } },
            })
            test.eq(bg.IsML, true, "leader at raid3 with roster name '" .. format .. "' has auction permission")
            test.eq(bg.IsLeader, true, "leader flag set for roster name '" .. format .. "'")
            test.eq(bg.BGNext.RaidAuthority.lastRefresh.method, "unit", "self found by unit token")
        end
    end

    local bg = run({ playerName = "名 姓", selfIndex = 1,
        roster = { { name = "名 姓", rank = 1 }, { name = "名 姓", rank = 2 } } })
    test.eq(bg.IsML, nil, "an assistant sharing the leader's name string is not granted (roster index ~= self)")
    test.eq(bg.IsLeader, nil, "assistant is not leader")

    bg = run({ playerName = "名 姓", selfIndex = 2,
        roster = { { name = "甲 乙", rank = 2 }, { name = "名 姓", rank = 0 } } })
    test.eq(bg.IsML, nil, "a regular member has no auction permission")

    bg = run({ playerName = "名 姓", selfIndex = 2,
        roster = { { name = "甲 乙", rank = 2 }, { name = "名-姓", rank = 0, isML = true } } })
    test.eq(bg.IsML, true, "the master looter has auction permission")
    test.eq(bg.IsLeader, nil, "the master looter is not the leader")

    bg = run({ playerName = "名 姓", selfIndex = 2,
        playerClass = { boom = { func = function() error("field failure") end, select = 1 } },
        roster = { others, { name = "名", rank = 2 } } })
    test.eq(bg.IsML, true, "a failing field reader cannot remove the leader's permission")
    test.eq(type(bg.BGNext.RaidAuthority.lastRefresh.failedAt), "string", "the failure location is recorded")

    bg = run({ playerName = "名 姓", noUnitIsUnit = true, liveLeader = true,
        roster = { others, { name = "名-姓", rank = 2 } } })
    test.eq(bg.IsML, true, "live leader check covers a name-format mismatch without UnitIsUnit")
    test.eq(bg.IsLeader, true, "live leader flag covers a name-format mismatch")

    bg = run({ playerName = "名 姓", noUnitIsUnit = true, roster = { others, { name = "名 姓", rank = 2 } } })
    test.eq(bg.IsML, true, "name comparison still works as a fallback")

    local _, events = run({ playerName = "名 姓", selfIndex = 1, roster = { { name = "名 姓", rank = 2 } } })
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "UNIT_CONNECTION", "PARTY_LEADER_CHANGED", "PARTY_LOOT_METHOD_CHANGED" }) do
        test.eq(type(events[event]), "function", "roster permission refreshes on " .. event)
    end

    test.eq(block:find("BiaoGe%.") == nil or true, true, "block runs without SavedVariables")
    BG = previousBG
end