return function(test)
    -- Verifies the live event wiring end to end: a confirmed completion message
    -- is first committed by the trade-capture state machine, then read by the
    -- real recorder. This is the only suite that exercises the BG.Init block of
    -- the settlement runtime, so it must define the event registrar before the
    -- runtime module is loaded, and must flush init callbacks in load order so
    -- the capture module commits before the recorder reads the snapshot.
    BG = { BGNext = {} }
    dofile("Core/BGNext/DataLifecycle.lua")
    dofile("Core/BGNext/CurrentTrade.lua")
    dofile("Core/BGNext/CurrentMail.lua")

    local initQueue = {}
    BG.Init = function(callback) initQueue[#initQueue + 1] = callback end
    local events = {}
    BG.RegisterEvent = function(event, handler)
        events[event] = events[event] or {}
        table.insert(events[event], handler)
    end

    dofile("Core/BGNext/TradeCapture.lua")
    dofile("Core/BGNext/CurrentSettlementRuntime.lua")
    for _, callback in ipairs(initQueue) do
        callback()
    end

    local life = BG.BGNext.DataLifecycle
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
    test.eq(events.TRADE_SHOW ~= nil, true, "the capture module registered the trade-window handler")
    test.eq(events.TRADE_ACCEPT_UPDATE ~= nil, true, "the capture module registered the accept handler")

    local function fire(event, ...)
        for _, handler in ipairs(events[event] or {}) do
            handler(nil, event, ...)
        end
    end

    -- One confirmed trade delivering two identical items.
    fire("TRADE_SHOW")
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
    fire("TRADE_ACCEPT_UPDATE", true, true)
    fire("UI_INFO_MESSAGE", nil, ERR_TRADE_COMPLETE)
    test.eq(#root.currentSettlement.trades, 1, "the completion event records the two-item trade once")
    test.eq(root.currentSettlement.trades[1].myItems[1].quantity, 2, "the completion event preserves the delivered count")

    -- A repeated completion message books nothing extra: the capture module
    -- commits once, and the store deduplicates the identical snapshot.
    fire("UI_INFO_MESSAGE", nil, ERR_TRADE_COMPLETE)
    test.eq(#root.currentSettlement.trades, 1, "a repeated completion message is still deduplicated")

    -- Opening a new window resets the capture state; a completion message with
    -- no accepted trade commits nothing, so no second record appears.
    fire("TRADE_SHOW")
    BG.trade = nil
    fire("UI_INFO_MESSAGE", nil, ERR_TRADE_COMPLETE)
    test.eq(#root.currentSettlement.trades, 1, "a completion without an accepted trade is ignored")
end
