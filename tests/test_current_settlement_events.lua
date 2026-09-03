return function(test)
    -- Verifies the live event wiring end to end: a confirmed completion message
    -- is turned into a quantity-aware record through the real recorder, and the
    -- memory-only booked guard still suppresses a repeated message. This is the
    -- only suite that exercises the BG.Init block, so it must define the event
    -- registrar before the runtime module is loaded.
    BG = { BGNext = {} }
    local events = {}
    local life = dofile("Core/BGNext/DataLifecycle.lua")
    dofile("Core/BGNext/CurrentTrade.lua")
    dofile("Core/BGNext/CurrentMail.lua")

    BG.Init = function(callback) callback() end
    BG.RegisterEvent = function(event, handler) events[event] = handler end
    dofile("Core/BGNext/CurrentSettlementRuntime.lua")

    BG.BGNext.DB = life.ensureRoot({})
    BG.FB2 = "ICC"
    BG.realmName = "测试服"
    BG.GSN = function(name) return name end
    BiaoGe = {
        ICC = { raidRoster = { time = 15000, realm = "测试服", roster = { "甲", "乙" } } },
    }
    IsInRaid = function() return true end
    GetServerTime = function() return 15100 end
    ERR_TRADE_COMPLETE = "交易完成"

    local root = BG.BGNext.DB
    test.eq(events.UI_INFO_MESSAGE ~= nil, true, "the runtime registered the completion handler")
    test.eq(events.TRADE_SHOW ~= nil, true, "the runtime registered the trade-window handler")

    -- One confirmed trade delivering two identical items.
    BG.trade = {
        target = "甲",
        targetmoney = 0,
        playermoney = 0,
        targetitems = {},
        playeritems = {
            { itemId = 11, count = 1 },
            { itemId = 11, count = 1 },
        },
    }
    events.UI_INFO_MESSAGE(nil, nil, nil, ERR_TRADE_COMPLETE)
    test.eq(#root.currentSettlement.trades, 1, "the completion event records the two-item trade once")
    test.eq(root.currentSettlement.trades[1].quantity, 2, "the completion event preserves the delivered count")

    -- A repeated completion message books nothing extra.
    events.UI_INFO_MESSAGE(nil, nil, nil, ERR_TRADE_COMPLETE)
    test.eq(#root.currentSettlement.trades, 1, "a repeated completion message is still deduplicated")

    -- Opening a new trade window re-arms the guard, but the identical snapshot
    -- still deduplicates on the store, so no second record appears.
    events.TRADE_SHOW()
    events.UI_INFO_MESSAGE(nil, nil, nil, ERR_TRADE_COMPLETE)
    test.eq(#root.currentSettlement.trades, 1, "re-armed completion without a new trade is ignored")
end
