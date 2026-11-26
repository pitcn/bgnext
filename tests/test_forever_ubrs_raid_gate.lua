return function(test)
    local function read(path)
        local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return (s:gsub("\r\n", "\n"))
    end
    local ns = { L = setmetatable({}, { __index = function(_, k) return k end }) }

    -- The gate itself lives with the Forever raid declarations.
    BG = { IsForever = true, Init = function() end }
    assert(loadfile("Core/BGNext/ForeverRaids.lua"))("BGNext", ns)
    local forever = BG
    test.eq(type(forever.ForeverRaidActive), "function", "Forever exposes the raid-table gate")
    test.eq(forever.ForeverRaidActive("UBRSforever", false), false, "UBRS table is inactive outside a raid group")
    test.eq(forever.ForeverRaidActive("UBRSforever", true), true, "UBRS table is active in a raid group")
    test.eq(forever.ForeverRaidActive("UBRSforever", nil), false, "unknown group state does not activate UBRS")
    for _, id in ipairs({ "BDforever", "HSforever", "ONYforever" }) do
        test.eq(forever.ForeverRaidActive(id, false), true, id .. " is not gated by this fix")
    end
    test.eq(forever.ForeverRaidActive("MC", false), true, "unrelated table ids are never gated")

    BG = { IsForever = nil }
    assert(loadfile("Core/BGNext/ForeverRaids.lua"))("BGNext", ns)
    test.eq(BG.ForeverRaidActive, nil, "other clients do not load the gate")

    -- Real instance-detection ticker from BiaoGe.lua with client APIs stubbed.
    local source = read("Core/BiaoGe.lua")
    local startAt = assert(source:find("----------定时获取当前副本----------", 1, true))
    local endAt = assert(source:find("----------高亮团长发出的装备----------", 1, true))
    local block = source:sub(startAt, endAt - 1)
    local function ticker(opts)
        local state = { clicks = {}, instance = opts.instance, inRaid = opts.inRaid }
        local callback
        local env = setmetatable({
            BG = { IsForever = opts.forever, FBIDtable = opts.table, IsTBCFB = function() return false end,
                ClickFBbutton = function(fb) state.clicks[#state.clicks + 1] = fb end,
                ForeverRaidActive = opts.forever and forever.ForeverRaidActive or nil },
            ns = {},
            C_Timer = { NewTicker = function(_, fn) callback = fn end },
            GetInstanceInfo = function() return "x", "party", 1, nil, nil, nil, nil, state.instance end,
            IsInRaid = function() return state.inRaid end,
        }, { __index = _G })
        env.BG.ForeverRaidActive = opts.forever and forever.ForeverRaidActive or nil
        setfenv(assert(loadstring(block)), env)()
        state.BG = env.BG
        function state.tick() callback() end
        return state
    end

    local foreverTable = { [229] = "UBRSforever", [3052] = "BDforever" }
    local s = ticker({ forever = true, table = foreverTable, instance = 229, inRaid = false })
    s.tick()
    test.eq(s.BG.FB2, nil, "Forever: Blackrock Spire in a party records nothing")
    test.eq(#s.clicks, 0, "Forever: party in Blackrock Spire does not switch the bill tab")
    s.inRaid = true
    s.tick()
    test.eq(s.BG.FB2, "UBRSforever", "Forever: Blackrock Spire in a raid group is the current raid")
    test.eq(#s.clicks, 1, "Forever: converting the party to a raid switches the tab once")
    s.tick()
    test.eq(#s.clicks, 1, "Forever: staying in the raid does not switch the tab again")

    s = ticker({ forever = true, table = foreverTable, instance = 3052, inRaid = false })
    s.tick()
    test.eq(s.BG.FB2, "BDforever", "Forever: other tables keep their original behavior")

    s = ticker({ forever = nil, table = { [229] = "X", [409] = "MCtitan" }, instance = 409, inRaid = false })
    s.tick()
    test.eq(s.BG.FB2, "MCtitan", "other clients are unaffected outside a raid group")
    s = ticker({ forever = nil, table = { [229] = "X" }, instance = 229, inRaid = false })
    s.tick()
    test.eq(s.BG.FB2, "X", "other clients keep any table that happens to use map 229")

    -- Real Forever reset-check from ClearBiaoGe.lua.
    local clear = read("Core/Module/ClearBiaoGe.lua")
    local from = assert(clear:find("local function ForeverCheckCD%(%)"))
    local _, to = assert(clear:find("if ok and spec then EvaluateBillPrompt%(spec%) end\n%s*end", from))
    local checkSource = clear:sub(from, to)
    local function check(instance, inRaid)
        local r = { prompts = 0, clicks = 0 }
        local env = setmetatable({
            BG = { FBIDtable = foreverTable, ClickFBbutton = function() r.clicks = r.clicks + 1 end,
                ForeverRaidActive = forever.ForeverRaidActive },
            GetInstanceInfo = function() return "x", "party", 1, nil, 10, nil, nil, instance end,
            IsInInstance = function() return true end, IsInRaid = function() return inRaid end,
            GetNumSavedInstances = function() return 0 end,
            notCheckMaxPlayerF = true, notCheckDiffF = true,
            EvaluateBillPrompt = function() r.prompts = r.prompts + 1 end,
        }, { __index = _G })
        setfenv(assert(loadstring(checkSource .. "\nForeverCheckCD()")), env)()
        return r
    end
    local r = check(229, false)
    test.eq(r.prompts, 0, "Forever: Blackrock Spire party never asks to clear the bill")
    test.eq(r.clicks, 0, "Forever: Blackrock Spire party never switches the bill tab on entry")
    r = check(229, true)
    test.eq(r.prompts, 1, "Forever: Blackrock Spire raid keeps the reset question")
    test.eq(r.clicks, 1, "Forever: Blackrock Spire raid keeps the tab switch")
    r = check(3052, false)
    test.eq(r.prompts, 1, "Forever: other raids keep the reset question")
end
