return function(test)
    -- Pure decision logic for the in-game trade-result announcement. Loading the
    -- module with no BG.Init defined keeps the live wiring dormant, so only the
    -- resolveChannel/decide/render functions are exercised here.
    BG = { BGNext = {} }
    local M = dofile("Core/BGNext/TradeAnnouncement.lua")
    test.eq(BG.BGNext.TradeAnnouncement, M, "the module registers itself")

    -- resolveChannel: the settings UI only accepts WHISPER or RAID.
    test.eq(M.resolveChannel("WHISPER", false, false), "WHISPER", "whisper preference always whispers")
    test.eq(M.resolveChannel("RAID", true, false), "RAID", "raid preference in a raid")
    test.eq(M.resolveChannel("RAID", false, true), "PARTY", "raid preference in a party")
    test.eq(M.resolveChannel("RAID", false, false), nil, "raid preference solo sends nowhere")
    test.eq(M.resolveChannel("PARTY", false, true), nil, "unknown preference sends nowhere")
    test.eq(M.resolveChannel(nil, true, false), nil, "nil preference sends nowhere")

    local function options(overrides)
        local o = {
            master = true,
            success = true,
            fail = true,
            channel = "WHISPER",
            inRaid = false,
            inGroup = false,
        }
        for k, v in pairs(overrides or {}) do
            o[k] = v
        end
        return o
    end

    -- decide: the master switch gates every announcement.
    test.eq(M.decide(options({ master = false }), { kind = "success", target = "甲" }), nil, "master off blocks success")
    test.eq(M.decide(options({ master = false }), { kind = "fail", target = "甲" }), nil, "master off blocks fail")

    -- decide: the success/fail sub-switches gate their own result.
    test.eq(M.decide(options({ success = false }), { kind = "success", target = "甲" }), nil, "success sub-switch off blocks success")
    local failOnly = M.decide(options({ success = false }), { kind = "fail", target = "甲" })
    test.eq(failOnly and failOnly.kind, "fail", "fail still announced when success sub-switch off")
    test.eq(M.decide(options({ fail = false }), { kind = "fail", target = "甲" }), nil, "fail sub-switch off blocks fail")

    -- decide: an unusable target must never announce.
    test.eq(M.decide(options(), { kind = "success", target = nil }), nil, "nil target blocked")
    test.eq(M.decide(options(), { kind = "success", target = "   " }), nil, "blank target blocked")

    -- decide: channel resolution and the whisper target.
    local whisper = M.decide(options(), { kind = "success", target = "甲" })
    test.eq(whisper.channel, "WHISPER", "whisper decision channel")
    test.eq(whisper.target, "甲", "whisper decision keeps the exact target")
    test.eq(M.decide(options({ channel = "RAID", inRaid = false, inGroup = false }), { kind = "success", target = "甲" }), nil,
        "raid channel solo is not announced")
    local raid = M.decide(options({ channel = "RAID", inRaid = true }), { kind = "fail", target = "乙" })
    test.eq(raid.channel, "RAID", "raid decision channel in a raid")
    local party = M.decide(options({ channel = "RAID", inRaid = false, inGroup = true }), { kind = "success", target = "丙" })
    test.eq(party.channel, "PARTY", "raid preference falls back to party")

    -- decide: an unknown result kind is never announced.
    test.eq(M.decide(options(), { kind = "bogus", target = "甲" }), nil, "unknown kind blocked")

    -- render: reuses the strings the settings already localize.
    local success = { kind = "success", target = "甲", channel = "WHISPER" }
    local failure = { kind = "fail", target = "乙", channel = "RAID" }
    test.eq(M.render(success), "与<甲>交易成功！", "success render fallback (zhCN key)")
    test.eq(M.render(failure), "与<乙>交易失败！", "fail render fallback (zhCN key)")
    local en = setmetatable({}, { __index = function(_, key) return key end })
    en["与<%s>交易成功！%s"] = "Trade with <%s> succeeded! %s"
    en["与<%s>交易失败！"] = "Trade with <%s> failed!"
    test.eq(M.render(success, en), "Trade with <甲> succeeded! ", "success render english")
    test.eq(M.render(failure, en), "Trade with <乙> failed!", "fail render english")
end
