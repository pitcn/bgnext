return function(test)
    -- Exercises the live wiring end to end: a confirmed completion message or an
    -- explicit cancel error is announced once, a repeated message is not
    -- re-sent, and a plain window close announces nothing. The trade partner is
    -- read from the authoritative current-window unit BG.GN("NPC"), never from
    -- the shared BG.trade.target snapshot, which can be blank or a previous
    -- partner when this module's TRADE_SHOW handler runs before Trade.lua.
    BG = { BGNext = {} }
    local events = {}
    local sent = {}

    BG.Init = function(callback) callback() end
    BG.RegisterEvent = function(event, handler)
        if type(event) == "table" then
            for _, e in ipairs(event) do
                events[e] = handler
            end
        else
            events[event] = handler
        end
    end
    SendChatMessage = function(message, channel, language, target)
        sent[#sent + 1] = { message = message, channel = channel, target = target }
    end

    -- Authoritative current-trade-partner source (wraps GetUnitName("NPC", true)
    -- in the live client). Returns nil when no trade window is open.
    local npcName = nil
    BG.GN = function(unit)
        if unit == "NPC" then
            return npcName
        end
        return "player"
    end

    dofile("Core/BGNext/TradeAnnouncement.lua")

    ERR_TRADE_COMPLETE = "交易完成"
    ERR_TRADE_CANCELLED = "交易取消"
    ERR_TRADE_BAG_FULL = "背包已满"
    ERR_TRADE_TARGET_BAG_FULL = "对方背包已满"

    BiaoGe = { options = {
        tradeMSG = 1,
        tradeMSG_success = 1,
        tradeMSG_false = 1,
        tradeMSG_channel = "WHISPER",
    } }
    IsInRaid = function() return false end
    IsInGroup = function() return false end
    BG.trade = { target = "旧对象" }

    test.eq(events.UI_INFO_MESSAGE ~= nil, true, "registered the message handler")
    test.eq(events.TRADE_SHOW ~= nil, true, "registered the trade-window handler")

    -- (1) The current partner comes from BG.GN("NPC"), not the stale shared target.
    npcName = "新对象"
    events.TRADE_SHOW()
    events.UI_INFO_MESSAGE(nil, nil, nil, ERR_TRADE_COMPLETE)
    test.eq(#sent, 1, "one success announcement")
    test.eq(sent[1].channel, "WHISPER", "success is whispered")
    test.eq(sent[1].target, "新对象", "whisper goes to the current NPC, not the stale target")
    test.eq(sent[1].message, "与<新对象>交易成功！", "success message")

    -- (4) A repeated completion message is not re-sent.
    events.UI_INFO_MESSAGE(nil, nil, nil, ERR_TRADE_COMPLETE)
    test.eq(#sent, 1, "repeated completion is not re-sent")

    -- (2) With no authoritative current partner, nothing is sent.
    npcName = nil
    events.TRADE_SHOW()
    events.UI_INFO_MESSAGE(nil, nil, nil, ERR_TRADE_COMPLETE)
    test.eq(#sent, 1, "no partner -> no announcement")

    -- A blank partner must also not announce.
    npcName = "   "
    events.TRADE_SHOW()
    events.UI_INFO_MESSAGE(nil, nil, nil, ERR_TRADE_COMPLETE)
    test.eq(#sent, 1, "blank partner is not announced")

    -- An explicit cancel is a reliable fail signal and is announced once.
    npcName = "甲"
    events.TRADE_SHOW()
    events.UI_INFO_MESSAGE(nil, nil, nil, ERR_TRADE_CANCELLED)
    test.eq(#sent, 2, "cancel is announced")
    test.eq(sent[2].message, "与<甲>交易失败！", "fail message")
    events.UI_INFO_MESSAGE(nil, nil, nil, ERR_TRADE_CANCELLED)
    test.eq(#sent, 2, "repeated cancel is not re-sent")

    -- A plain window close announces nothing: no TRADE_CLOSED handler exists.
    events.TRADE_SHOW()
    test.eq(#sent, 2, "window close announces nothing")

    -- (3) Consecutive trades do not cross-contaminate the partner.
    npcName = "甲"
    events.TRADE_SHOW()
    events.UI_INFO_MESSAGE(nil, nil, nil, ERR_TRADE_COMPLETE)
    test.eq(#sent, 3, "partner A announced")
    test.eq(sent[3].target, "甲", "partner A whispered")
    npcName = "乙"
    events.TRADE_SHOW()
    events.UI_INFO_MESSAGE(nil, nil, nil, ERR_TRADE_COMPLETE)
    test.eq(#sent, 4, "partner B announced")
    test.eq(sent[4].target, "乙", "partner B whispered, not A")

    -- The partner is resolved at show time; a later shared-snapshot rewrite or
    -- unit clear does not suppress a real result, and the stale target is never
    -- read back.
    npcName = "丙"
    events.TRADE_SHOW() -- captures "丙" from BG.GN("NPC")
    BG.trade.target = "旧对象" -- Trade.lua may rewrite the shared snapshot later
    npcName = nil -- model the trade unit clearing after the window closes
    events.UI_INFO_MESSAGE(nil, nil, nil, ERR_TRADE_COMPLETE)
    test.eq(#sent, 5, "the partner captured at show time is still announced")
    test.eq(sent[5].target, "丙", "show-time partner, not the stale target")
end
