return function(test)
    -- =====================================================================
    -- issue #64: reliable trade capture.
    --
    -- A single auctioned item that was actually traded can lose all three
    -- views at once (settlement record, bill line, auction "已交易" mark)
    -- because each consumer reads the shared mutable BG.trade at a different
    -- moment. This suite proves the fix: a bounded, memory-only snapshot is
    -- frozen at accept, committed exactly once on the explicit success signal,
    -- and that one committed snapshot drives all three consumers.
    -- =====================================================================

    local function newHarness()
        BG = { BGNext = {} }
        -- Load modules that carry no BG.Init/RegisterEvent wiring first, so
        -- their init blocks (DataLifecycle) are skipped exactly like a live
        -- load would skip a nil registrar.
        dofile("Core/BGNext/DataLifecycle.lua")
        dofile("Core/BGNext/CurrentTrade.lua")
        dofile("Core/BGNext/CurrentMail.lua")
        dofile("Core/BGNext/PlayerIdentity.lua")
        dofile("Core/BGNext/TradeAuctionState.lua")

        local initQueue = {}
        BG.Init = function(callback) initQueue[#initQueue + 1] = callback end
        local events = {}
        BG.RegisterEvent = function(event, handler)
            events[event] = events[event] or {}
            table.insert(events[event], handler)
        end

        dofile("Core/BGNext/TradeCapture.lua")
        dofile("Core/BGNext/CurrentSettlementRuntime.lua")

        -- Flush init callbacks in load order, matching production ADDON_LOADED:
        -- TradeCapture registers its events before the settlement runtime, so a
        -- success message commits before the recorder reads the snapshot.
        for _, callback in ipairs(initQueue) do
            callback()
        end

        local function fire(event, ...)
            for _, handler in ipairs(events[event] or {}) do
                handler(nil, event, ...)
            end
        end

        return BG, fire
    end

    local function settle(BG, rosterTime, now, members, auctionLog)
        local root = BG.BGNext.DataLifecycle.ensureRoot({})
        BG.BGNext.DB = root
        BG.FB2 = "ICC"
        BG.realmName = "测试服"
        BG.GSN = function(name) return name end
        BiaoGe = {
            ICC = {
                raidRoster = { time = rosterTime, realm = "测试服", roster = members },
                auctionLog = auctionLog or {},
            },
        }
        IsInRaid = function() return true end
        GetServerTime = function() return now end
        InCombatLockdown = function() return true end
        ERR_TRADE_COMPLETE = "交易完成"
        return root
    end

    -- =====================================================================
    -- 1. Snapshot state machine (unit).
    -- =====================================================================
    do
        BG = { BGNext = {} }
        local capture = dofile("Core/BGNext/TradeCapture.lua")

        local function trade()
            return {
                target = "甲",
                targetmoney = 100,
                playermoney = 0,
                targetitems = {},
                playeritems = { { itemId = 11, link = "item:11", count = 1 } },
            }
        end

        -- Nothing committed before any window/accept/success.
        test.eq(capture.committed(), nil, "no committed snapshot before a trade")

        -- TRADE_ACCEPT_UPDATE supplies numeric 0/1, and 0 is truthy in Lua, so
        -- the handler must never test the raw args as booleans.
        capture.beginTrade()
        BG.trade = trade()
        test.eq(capture.onAcceptUpdate(0, 0), false, "(0,0) freezes nothing")
        test.eq(capture.onComplete(), nil, "a (0,0) accept leaves nothing to commit")
        test.eq(capture.committed(), nil, "a (0,0) accept never commits")

        capture.beginTrade()
        BG.trade = trade()
        test.eq(capture.onAcceptUpdate(1, 0), true, "(1,0) freezes a candidate")
        capture.beginTrade()
        BG.trade = trade()
        test.eq(capture.onAcceptUpdate(0, 1), true, "(0,1) freezes a candidate")
        capture.beginTrade()
        BG.trade = trade()
        test.eq(capture.onAcceptUpdate(1, 1), true, "(1,1) freezes a candidate")

        -- An absent shared table never becomes a snapshot.
        capture.beginTrade()
        BG.trade = nil
        test.eq(capture.onAcceptUpdate(1, 0), false, "accept without a trade table freezes nothing")

        -- The last shared table is cleared before the success handler runs, but
        -- the already-frozen snapshot survives and commits exactly once.
        BG.trade = trade()
        capture.beginTrade()
        test.eq(capture.onAcceptUpdate(0, 1), true, "a single-side accept freezes a candidate")
        BG.trade = nil
        local snap = capture.onComplete()
        test.eq(snap ~= nil, true, "the frozen snapshot survives a cleared shared table")
        test.eq(snap.target, "甲", "frozen counterparty is retained")
        test.eq(snap.targetmoney, 100, "frozen amount is retained")
        test.eq(snap.playeritems[1].link, "item:11", "frozen item is retained")
        test.eq(snap.playeritems[1].itemId, 11, "frozen item id is retained")
        test.eq(capture.committed(), snap, "the committed snapshot is exposed to consumers")
        test.eq(capture.diagnostic(), "committed", "a committed trade surfaces its diagnostic")

        -- A repeated success message returns the same snapshot (commit once).
        BG.trade = { target = "路人", targetmoney = 0, playermoney = 0, targetitems = {}, playeritems = {} }
        test.eq(capture.onComplete() == snap, true, "a repeated success returns the same committed snapshot")
        test.eq(capture.committed(), snap, "a repeated success does not replace the committed snapshot")

        -- A new window resets; a close alone never commits; a success that
        -- arrives after close still commits the frozen snapshot.
        capture.beginTrade()
        test.eq(capture.committed(), nil, "a new window forgets the previous commit")
        BG.trade = trade()
        test.eq(capture.onAcceptUpdate(1, 1), true, "both sides confirm freeze a candidate")
        capture.onTradeClosed()
        test.eq(capture.committed(), nil, "close alone never commits")
        test.eq(capture.onComplete() ~= nil, true, "a success that arrives after close still commits the frozen snapshot")

        -- Money normalization: unknown stays nil; an explicit 0 stays 0.
        capture.beginTrade()
        BG.trade = { target = "甲", targetmoney = nil, playermoney = nil, targetitems = {}, playeritems = {} }
        test.eq(capture.onAcceptUpdate(1, 1), true, "accept freezes a candidate with unknown money")
        local unknown = capture.onComplete()
        test.eq(unknown.targetmoney, nil, "unknown target money stays nil, never fabricated as 0")
        test.eq(unknown.playermoney, nil, "unknown player money stays nil, never fabricated as 0")

        capture.beginTrade()
        BG.trade = { target = "甲", targetmoney = 0, playermoney = 0, targetitems = {}, playeritems = {} }
        test.eq(capture.onAcceptUpdate(1, 1), true, "accept freezes a candidate with explicit zero money")
        local zero = capture.onComplete()
        test.eq(zero.targetmoney, 0, "an explicit API 0 target money is stored as 0")
        test.eq(zero.playermoney, 0, "an explicit API 0 player money is stored as 0")

        -- Fail closed: an incomplete snapshot fabricates nothing and surfaces a
        -- local diagnostic instead.
        capture.beginTrade()
        BG.trade = { target = "", targetmoney = 0, playermoney = 0, targetitems = {}, playeritems = {} }
        test.eq(capture.onComplete(), nil, "an incomplete trade is dropped, never fabricated")
        test.eq(capture.diagnostic(), "incomplete", "an incomplete trade surfaces a local diagnostic")
        test.eq(capture.committed(), nil, "an incomplete trade leaves no committed snapshot")
    end

    -- =====================================================================
    -- 2. Integration: normal single item + gold, driven through the real
    --    event registration, records the settlement row, feeds the bill
    --    writer's shared table, and marks the auction log — all from one
    --    committed snapshot.
    -- =====================================================================
    do
        local BG, fire = newHarness()
        local root = settle(BG, 20000, 20100, { "甲", "乙" }, {
            { type = 1, maijia = "甲", zhuangbei = "item:11", jine = 100 },
        })

        fire("TRADE_SHOW")
        BG.trade = {
            target = "甲", targetmoney = 100, playermoney = 0, targetitems = {},
            playeritems = { { itemId = 11, link = "item:11", count = 1 } },
        }
        fire("TRADE_ACCEPT_UPDATE", 1, 1)
        fire("UI_INFO_MESSAGE", nil, ERR_TRADE_COMPLETE)
        fire("TRADE_CLOSED")

        test.eq(#root.currentSettlement.trades, 1, "the completion event records the trade once")
        local row = root.currentSettlement.trades[1]
        test.eq(row.player, "甲", "settlement record keeps the counterparty")
        test.eq(row.myItems[1].itemId, 11, "settlement record keeps the delivered item")
        test.eq(row.theirGold, 100, "settlement record keeps the received gold")
        test.eq(row.completed, true, "settlement record keeps the completed fact")
        test.eq(row.status, "complete", "settlement record is complete")
        test.eq(row.myItems[1].quantity, 1, "settlement record keeps the delivered count")

        -- The bill writer reads BG.trade; after commit it holds the committed
        -- snapshot, so the bill buyer/amount/item come from the frozen state.
        test.eq(BG.trade.target, "甲", "bill buyer input is the committed counterparty")
        test.eq(BG.trade.targetmoney, 100, "bill amount input is the committed amount")
        test.eq(BG.trade.playeritems[1].link, "item:11", "bill item input is the committed item")

        -- The auction-log marker consumes the same committed snapshot.
        local committed = BG.BGNext.TradeCapture.committed()
        local marked = BG.BGNext.TradeAuctionState.markDelivered(
            BiaoGe.ICC.auctionLog, "甲", "测试服", committed.playeritems,
            function(link) return tonumber(link:match("item:(%d+)")) end)
        test.eq(marked, 1, "the auction-log delivery mark is applied from the committed snapshot")
        test.eq(BiaoGe.ICC.auctionLog[1].trade, true, "the auction record is marked 已交易")

        -- A duplicate success message commits/marks nothing new.
        fire("UI_INFO_MESSAGE", nil, ERR_TRADE_COMPLETE)
        test.eq(#root.currentSettlement.trades, 1, "a repeated success message books nothing extra")
    end

    -- =====================================================================
    -- 3. Integration: the last shared BG.trade is cleared before the success
    --    handler runs, but the frozen snapshot still records the trade.
    -- =====================================================================
    do
        local BG, fire = newHarness()
        local root = settle(BG, 21000, 21100, { "甲" })

        fire("TRADE_SHOW")
        BG.trade = {
            target = "甲", targetmoney = 50, playermoney = 0, targetitems = {},
            playeritems = { { itemId = 22, link = "item:22", count = 1 } },
        }
        fire("TRADE_ACCEPT_UPDATE", 1, 1)
        BG.trade = nil -- the shared mutable table is cleared before success
        fire("UI_INFO_MESSAGE", nil, ERR_TRADE_COMPLETE)
        fire("TRADE_CLOSED")

        test.eq(#root.currentSettlement.trades, 1, "a cleared shared table before success still records the frozen trade")
        test.eq(root.currentSettlement.trades[1].myItems[1].itemId, 22, "the frozen item survives the cleared shared table")
    end

    -- =====================================================================
    -- 4. Integration: close-before-success ordering still commits exactly once.
    -- =====================================================================
    do
        local BG, fire = newHarness()
        local root = settle(BG, 22000, 22100, { "甲" })

        fire("TRADE_SHOW")
        BG.trade = {
            target = "甲", targetmoney = 30, playermoney = 0, targetitems = {},
            playeritems = { { itemId = 33, link = "item:33", count = 1 } },
        }
        fire("TRADE_ACCEPT_UPDATE", 1, 1)
        fire("TRADE_CLOSED") -- close arrives first
        fire("UI_INFO_MESSAGE", nil, ERR_TRADE_COMPLETE) -- success arrives after

        test.eq(#root.currentSettlement.trades, 1, "close-before-success still records the frozen trade")
        test.eq(root.currentSettlement.trades[1].myItems[1].itemId, 33, "close-before-success keeps the item")
    end

    -- =====================================================================
    -- 5. Integration: clients may report the two acceptance changes in separate
    --    events before closing the trade window. The explicit success result must
    --    still commit the frozen trade exactly once.
    -- =====================================================================
    do
        local BG, fire = newHarness()
        local root = settle(BG, 22500, 22600, { "甲" })

        fire("TRADE_SHOW")
        BG.trade = {
            target = "甲", targetmoney = 80, playermoney = 0, targetitems = {},
            playeritems = { { itemId = 34, link = "item:34", count = 1 } },
        }
        fire("TRADE_ACCEPT_UPDATE", 1, 0)
        fire("TRADE_ACCEPT_UPDATE", 0, 1)
        fire("TRADE_CLOSED")
        fire("UI_INFO_MESSAGE", nil, ERR_TRADE_COMPLETE)

        test.eq(#root.currentSettlement.trades, 1,
            "separate acceptance updates followed by success record the trade")
        test.eq(root.currentSettlement.trades[1].myItems[1].itemId, 34,
            "the separately accepted trade keeps its item")
    end

    -- =====================================================================
    -- 6. Integration: item link/quantity temporarily empty at an early change
    --    event becomes available around confirm and is captured at accept.
    -- =====================================================================
    do
        local BG, fire = newHarness()
        local root = settle(BG, 23000, 23100, { "甲" })

        fire("TRADE_SHOW")
        -- Early change event: the shared table still has no item link.
        BG.trade = { target = "甲", targetmoney = 100, playermoney = 0, targetitems = {}, playeritems = {} }
        -- The item becomes available around confirm.
        BG.trade.playeritems = { { itemId = 44, link = "item:44", count = 1 } }
        fire("TRADE_ACCEPT_UPDATE", 1, 1)
        fire("UI_INFO_MESSAGE", nil, ERR_TRADE_COMPLETE)

        test.eq(#root.currentSettlement.trades, 1, "an item that appears around confirm is captured at accept")
        test.eq(root.currentSettlement.trades[1].myItems[1].itemId, 44, "the confirm-time item link is recorded")
    end

    -- =====================================================================
    -- 7. Integration: item-shape matrix (two identical, one stack, multiple
    --    distinct, 0 gold, with gold) through the same event chain.
    -- =====================================================================
    do
        local BG, fire = newHarness()
        local root = settle(BG, 24000, 24100, { "甲", "乙", "丙" })

        local function runTrade(target, money, items, now)
            GetServerTime = function() return now end
            fire("TRADE_SHOW")
            BG.trade = {
                target = target, targetmoney = money, playermoney = 0,
                targetitems = {}, playeritems = items,
            }
            fire("TRADE_ACCEPT_UPDATE", 1, 1)
            fire("UI_INFO_MESSAGE", nil, ERR_TRADE_COMPLETE)
            fire("TRADE_CLOSED")
        end

        runTrade("甲", 100, { { itemId = 1, link = "item:1", count = 1 } }, 24101)
        runTrade("乙", 200, { { itemId = 2, link = "item:2", count = 1 }, { itemId = 2, link = "item:2", count = 1 } }, 24102)
        runTrade("丙", 300, { { itemId = 3, link = "item:3", count = 2 } }, 24103)

        local trades = root.currentSettlement.trades
        test.eq(#trades, 3, "single, two-identical and stacked trades each record correctly")

        local byTarget = {}
        for _, t in ipairs(trades) do byTarget[t.player] = byTarget[t.player] or {}; table.insert(byTarget[t.player], t) end

        test.eq(byTarget["甲"][1].myItems[1].quantity, 1, "a single item keeps quantity 1")
        test.eq(byTarget["甲"][1].status, "complete", "a single item with gold is complete")

        test.eq(#byTarget["乙"], 1, "two identical items collapse into one record")
        test.eq(byTarget["乙"][1].myItems[1].quantity, 2, "two identical items keep the summed quantity")
        test.eq(byTarget["乙"][1].status, "complete", "two identical single units stay complete")

        test.eq(byTarget["丙"][1].myItems[1].quantity, 2, "a stack preserves its count")
        test.eq(byTarget["丙"][1].status, "pending", "a stack cannot prove a single bill sale")

        -- Multiple distinct items in one trade project one grouped record, with
        -- the shared gold stored once on the transaction, never per item.
        local distinctRoot = BG.BGNext.DataLifecycle.ensureRoot({})
        BG.BGNext.DB = distinctRoot
        GetServerTime = function() return 24110 end
        fire("TRADE_SHOW")
        BG.trade = {
            target = "甲", targetmoney = 400, playermoney = 0, targetitems = {},
            playeritems = { { itemId = 5, link = "item:5", count = 1 }, { itemId = 6, link = "item:6", count = 1 } },
        }
        fire("TRADE_ACCEPT_UPDATE", 1, 1)
        fire("UI_INFO_MESSAGE", nil, ERR_TRADE_COMPLETE)
        test.eq(#distinctRoot.currentSettlement.trades, 1, "two distinct items project one grouped record")
        test.eq(distinctRoot.currentSettlement.trades[1].theirGold, 400, "the shared gold is stored once on the transaction")
        test.eq(distinctRoot.currentSettlement.trades[1].myItems[1].itemId, 5, "the first delivered item is kept")
        test.eq(distinctRoot.currentSettlement.trades[1].myItems[2].itemId, 6, "the second delivered item is kept")
        test.eq(distinctRoot.currentSettlement.trades[1].status, "complete", "a two-item clean delivery reconciles as one transaction")

        -- 0 gold: an item-only trade stays pending and never proves a sale.
        local zeroRoot = BG.BGNext.DataLifecycle.ensureRoot({})
        BG.BGNext.DB = zeroRoot
        GetServerTime = function() return 24120 end
        fire("TRADE_SHOW")
        BG.trade = {
            target = "乙", targetmoney = 0, playermoney = 0, targetitems = {},
            playeritems = { { itemId = 7, link = "item:7", count = 1 } },
        }
        fire("TRADE_ACCEPT_UPDATE", 1, 1)
        fire("UI_INFO_MESSAGE", nil, ERR_TRADE_COMPLETE)
        test.eq(#zeroRoot.currentSettlement.trades, 1, "a 0-gold trade still records for manual reconciliation")
        test.eq(zeroRoot.currentSettlement.trades[1].status, "pending", "a 0-gold trade is pending, never complete")
        test.eq(zeroRoot.currentSettlement.trades[1].myGold, 0, "a 0-gold trade keeps its explicit 0 gold")
        test.eq(zeroRoot.currentSettlement.trades[1].theirGold, 0, "a 0-gold trade keeps its explicit 0 gold")
    end

    -- =====================================================================
    -- 8. Integration: fail-closed — cancel, no-confirm, and a target outside
    --    the current raid write nothing and mark nothing.
    -- =====================================================================
    do
        local BG, fire = newHarness()
        local root = settle(BG, 25000, 25100, { "甲" }, {
            { type = 1, maijia = "路人", zhuangbei = "item:88", jine = 100 },
        })

        -- Cancel: window closes without a success signal.
        fire("TRADE_SHOW")
        BG.trade = {
            target = "甲", targetmoney = 100, playermoney = 0, targetitems = {},
            playeritems = { { itemId = 8, link = "item:8", count = 1 } },
        }
        fire("TRADE_ACCEPT_UPDATE", 1, 0)
        fire("TRADE_CLOSED")
        test.eq(#root.currentSettlement.trades, 0, "a cancelled trade writes nothing")

        -- No-confirm: no side accepts, so nothing is frozen and nothing commits.
        fire("TRADE_SHOW")
        BG.trade = {
            target = "甲", targetmoney = 100, playermoney = 0, targetitems = {},
            playeritems = { { itemId = 9, link = "item:9", count = 1 } },
        }
        fire("TRADE_ACCEPT_UPDATE", 0, 0)
        fire("TRADE_CLOSED")
        test.eq(#root.currentSettlement.trades, 0, "a trade with neither side confirmed writes nothing")

        -- Target outside the current raid: the recorder rejects attribution and
        -- the auction log has no matching row to mark.
        fire("TRADE_SHOW")
        BG.trade = {
            target = "路人", targetmoney = 100, playermoney = 0, targetitems = {},
            playeritems = { { itemId = 88, link = "item:88", count = 1 } },
        }
        fire("TRADE_ACCEPT_UPDATE", 1, 1)
        fire("UI_INFO_MESSAGE", nil, ERR_TRADE_COMPLETE)
        test.eq(#root.currentSettlement.trades, 0, "a trade to a non-roster target writes nothing")
        test.eq(BiaoGe.ICC.auctionLog[1].trade, nil, "a non-roster target is never marked 已交易")
    end

    -- =====================================================================
    -- 9. In-combat recording uses the same event chain; the capture module
    --    adds no polling, no timers, no protected actions and no messaging.
    -- =====================================================================
    do
        local BG, fire = newHarness()
        local root = settle(BG, 26000, 26100, { "甲" })

        fire("TRADE_SHOW")
        BG.trade = {
            target = "甲", targetmoney = 60, playermoney = 0, targetitems = {},
            playeritems = { { itemId = 10, link = "item:10", count = 1 } },
        }
        fire("TRADE_ACCEPT_UPDATE", 1, 1)
        fire("UI_INFO_MESSAGE", nil, ERR_TRADE_COMPLETE)
        test.eq(#root.currentSettlement.trades, 1, "an in-combat trade still records through the same event chain")

        local file = assert(io.open("Core/BGNext/TradeCapture.lua", "rb"))
        local source = file:read("*a")
        file:close()
        for _, forbidden in ipairs({
            "OnUpdate", "NewTicker", "C_Timer", "BG.After", "AcceptTrade",
            "ClickTradeButton", "SetTradeMoney", "SendAddonMessage", "SendChatMessage",
        }) do
            test.eq(source:find(forbidden, 1, true), nil, "TradeCapture never references " .. forbidden)
        end
    end

    -- =====================================================================
    -- 10. Integration: the shared BG.trade is still empty/stale at accept
    --    (BGLite's deferred BG.After(0, BG.TradeUpdate) has not run), but the
    --    live trade API already returns the final items and money. The accept
    --    handler must read the API synchronously, not the stale table.
    -- =====================================================================
    do
        local BG, fire = newHarness()
        local root = settle(BG, 27000, 27100, { "甲" })

        fire("TRADE_SHOW")
        BG.trade = { target = "", targetmoney = 0, playermoney = 0, targetitems = {}, playeritems = {} }
        GetUnitName = function(unit, includeRealm) return "甲" end
        GetTargetTradeMoney = function() return 55 * 10000 end
        GetPlayerTradeMoney = function() return 0 end
        GetTradeTargetItemLink = function() return nil end
        GetTradeTargetItemInfo = function() return nil end
        GetTradePlayerItemLink = function(i) if i == 1 then return "item:55" end return nil end
        GetTradePlayerItemInfo = function(i) if i == 1 then return nil, nil, 1 end return nil end

        fire("TRADE_ACCEPT_UPDATE", 1, 1)
        fire("UI_INFO_MESSAGE", nil, ERR_TRADE_COMPLETE)
        fire("TRADE_CLOSED")

        test.eq(#root.currentSettlement.trades, 1, "a stale shared table at accept still records from the live API")
        test.eq(root.currentSettlement.trades[1].myItems[1].itemId, 55, "the API item is captured at accept")
        test.eq(root.currentSettlement.trades[1].theirGold, 55, "the API money is captured at accept")

        GetUnitName = nil
        GetTargetTradeMoney = nil
        GetPlayerTradeMoney = nil
        GetTradeTargetItemLink = nil
        GetTradeTargetItemInfo = nil
        GetTradePlayerItemLink = nil
        GetTradePlayerItemInfo = nil
    end

    -- =====================================================================
    -- 11. Integration: a cancelled trade (one side accepted, never both)
    --     followed by a stale success message commits nothing.
    -- =====================================================================
    do
        local BG, fire = newHarness()
        local root = settle(BG, 28000, 28100, { "甲" })

        fire("TRADE_SHOW")
        BG.trade = {
            target = "甲", targetmoney = 70, playermoney = 0, targetitems = {},
            playeritems = { { itemId = 12, link = "item:12", count = 1 } },
        }
        fire("TRADE_ACCEPT_UPDATE", 1, 0)
        fire("TRADE_CLOSED")
        fire("UI_INFO_MESSAGE", nil, ERR_TRADE_COMPLETE)

        test.eq(#root.currentSettlement.trades, 0, "a cancelled trade followed by a success writes nothing")
        test.eq(BG.BGNext.TradeCapture.committed(), nil, "a cancelled trade leaves no committed snapshot")
    end

    -- =====================================================================
    -- 12. Integration: a late legitimate success (close arrives first) commits
    --     exactly once and is idempotent across duplicate success messages.
    -- =====================================================================
    do
        local BG, fire = newHarness()
        local root = settle(BG, 29000, 29100, { "甲" })

        fire("TRADE_SHOW")
        BG.trade = {
            target = "甲", targetmoney = 40, playermoney = 0, targetitems = {},
            playeritems = { { itemId = 14, link = "item:14", count = 1 } },
        }
        fire("TRADE_ACCEPT_UPDATE", 1, 1)
        fire("TRADE_CLOSED")
        fire("UI_INFO_MESSAGE", nil, ERR_TRADE_COMPLETE)
        fire("UI_INFO_MESSAGE", nil, ERR_TRADE_COMPLETE)

        test.eq(#root.currentSettlement.trades, 1, "a late legitimate success commits exactly once")
        test.eq(root.currentSettlement.trades[1].myItems[1].itemId, 14, "the late success keeps the frozen item")
    end
end
