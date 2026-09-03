return function(test)
    -- Exercises the live wiring end to end: a confirmed completion message or an
    -- explicit cancel error is announced once, a repeated message is not
    -- re-sent, and a plain window close announces nothing. Only the UI_INFO_MESSAGE
    -- and TRADE_SHOW handlers the module registers are present here.
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
    BG.trade = { target = "甲" }

    test.eq(events.UI_INFO_MESSAGE ~= nil, true, "registered the message handler")
    test.eq(events.TRADE_SHOW ~= nil, true, "registered the trade-window handler")

    -- Success is whispered to the exact trade target.
    events.TRADE_SHOW()
    events.UI_INFO_MESSAGE(nil, nil, nil, ERR_TRADE_COMPLETE)
    test.eq(#sent, 1, "one success announcement")
    test.eq(sent[1].channel, "WHISPER", "success is whispered")
    test.eq(sent[1].target, "甲", "whisper goes to the exact target")
    test.eq(sent[1].message, "与<甲>交易成功！", "success message")

    -- A repeated completion message is not re-sent.
    events.UI_INFO_MESSAGE(nil, nil, nil, ERR_TRADE_COMPLETE)
    test.eq(#sent, 1, "repeated completion is not re-sent")

    -- A new trade window re-arms the guard.
    events.TRADE_SHOW()
    events.UI_INFO_MESSAGE(nil, nil, nil, ERR_TRADE_COMPLETE)
    test.eq(#sent, 2, "a new trade is announced again")

    -- An explicit cancel is a reliable fail signal and is announced once.
    events.TRADE_SHOW()
    events.UI_INFO_MESSAGE(nil, nil, nil, ERR_TRADE_CANCELLED)
    test.eq(#sent, 3, "cancel is announced")
    test.eq(sent[3].message, "与<甲>交易失败！", "fail message")
    events.UI_INFO_MESSAGE(nil, nil, nil, ERR_TRADE_CANCELLED)
    test.eq(#sent, 3, "repeated cancel is not re-sent")

    -- A plain window close announces nothing: no TRADE_CLOSED handler exists.
    events.TRADE_SHOW()
    test.eq(#sent, 3, "window close announces nothing")

    -- A blank target must not announce.
    BG.trade.target = "   "
    events.TRADE_SHOW()
    events.UI_INFO_MESSAGE(nil, nil, nil, ERR_TRADE_COMPLETE)
    test.eq(#sent, 3, "blank target is not announced")

    -- The partner is captured when the trade window is shown, not re-read at
    -- result time. The live Trade.lua handler clears BG.trade.target right after
    -- TRADE_SHOW; a completion before the refresh repopulates it must still
    -- whisper the partner who was visible at show time.
    BG.trade.target = "甲"
    events.TRADE_SHOW() -- captures "甲"
    BG.trade.target = nil -- models ResetTradeInfo clearing the target
    events.UI_INFO_MESSAGE(nil, nil, nil, ERR_TRADE_COMPLETE)
    test.eq(#sent, 4, "the partner captured at show time is still announced")
    test.eq(sent[4].target, "甲", "the cleared target does not suppress the announcement")

    -- A partner change between trades must not reuse the previous partner.
    BG.trade.target = "乙"
    events.TRADE_SHOW() -- captures "乙"
    events.UI_INFO_MESSAGE(nil, nil, nil, ERR_TRADE_COMPLETE)
    test.eq(#sent, 5, "the second partner is announced")
    test.eq(sent[5].target, "乙", "the second trade whispers the new partner, not the old one")
end
