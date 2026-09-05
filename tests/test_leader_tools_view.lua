return function(test)
    BG = { BGNext = {} }
    local view = dofile("Core/BGNext/LeaderToolsView.lua")

    local frames = {
        { auctionID = "a", itemID = 1, link = "item-a", money = 500, player = "Me", remaining = 4, IsEnd = false },
        { auctionID = "b", itemID = 1, link = "item-b", money = 800, player = "Other", remaining = 20, IsEnd = false },
        { auctionID = "c", itemID = 2, link = "item-c", money = 900, player = "Me", remaining = 1, IsEnd = true },
    }
    local all = view.projectAuctions(frames, "all", function(frame) return frame.player == "Me" end)
    test.eq(#all, 3, "same-item auctions retain independent identities")
    test.eq(all[1].urgent, true, "short active auction is urgent")
    local mine = view.projectAuctions(frames, "mine", function(frame) return frame.player == "Me" end)
    test.eq(#mine, 2, "mine filter is local projection")
    local urgent = view.projectAuctions(frames, "urgent", function(frame) return frame.player == "Me" end)
    test.eq(#urgent, 1, "ended cards are not urgent")

    test.eq(view.isRiskyBid(500, 5000), true, "tenfold and one-thousand increase is risky")
    test.eq(view.isRiskyBid(500, 4999), false, "below tenfold is normal")
    test.eq(view.isRiskyBid(100, 1000), false, "small tenfold increase below absolute threshold is normal")
    test.eq(view.isRiskyBid(nil, 5000), false, "unknown current price is not guessed")
    test.eq(view.isRiskyBid(0, 5000), false, "zero current price is not guessed")

    local bill = {
        rows = {
            { itemId = 1, item = "A", buyer = "One", amount = "500", debt = nil },
            { itemId = 2, item = "B", buyer = "Two", amount = "700", debt = nil },
        },
        expenses = { { name = "Tank subsidy", amount = "200" } },
        splitCount = "2",
    }
    local settlement = {
        trades = {
            { completed = true, status = "complete", myGold = 0, theirGold = 500,
                myItems = { { itemId = 1, quantity = 1 } }, theirItems = {} },
            { completed = true, status = "complete", myGold = 0, theirGold = 700,
                myItems = { { itemId = 2, quantity = 1 } }, theirItems = {} },
        },
    }
    local ready = view.settlementSummary(bill, settlement)
    test.eq(ready.ledgerIncome, 1200, "ledger income is explicit")
    test.eq(ready.provenReceived, 1200, "clean outgoing trades prove receipts")
    test.eq(ready.expenses, 200, "expenses are separate")
    test.eq(ready.distributable, 1000, "fully reconciled net amount can be distributed")
    test.eq(ready.wage, 500, "positive whole split count computes wage")
    local fingerprint = view.settlementFingerprint(bill, settlement)
    bill.rows[1].amount = "501"
    test.eq(view.settlementFingerprint(bill, settlement) == fingerprint, false,
        "any bill change invalidates a prior confirmation")
    bill.rows[1].amount = "500"

    settlement.trades[2].status = "pending"
    local pending = view.settlementSummary(bill, settlement)
    test.eq(pending.provenReceived, 500, "pending trade is not counted as received")
    test.eq(pending.distributable, nil, "unknown receipt blocks distributable claim")
    test.eq(pending.pendingCount > 0, true, "pending facts are visible")
    bill.rows[1].debt = 100
    test.eq(view.settlementSummary(bill, settlement).debt, 100, "debt remains separate")
    bill.splitCount = "2.5"
    test.eq(view.settlementSummary(bill, settlement).wage, nil, "fractional split count is invalid")

    bill.rows[1].debt, bill.splitCount = nil, "2"
    settlement.trades[2].status = "complete"
    settlement.trades[1].theirGold, settlement.trades[2].theirGold = 600, 600
    local wrongPairing = view.settlementSummary(bill, settlement)
    test.eq(wrongPairing.provenReceived, 1200, "actual clean receipts stay visible")
    test.eq(wrongPairing.distributable, nil, "equal totals cannot hide per-item receipt mismatches")

    local empty = view.settlementSummary({ rows = {}, expenses = {}, splitCount = 2 }, {})
    test.eq(empty.distributable, nil, "an empty bill never fabricates a confirmed zero distribution")

    settlement.trades[1].theirGold, settlement.trades[2].theirGold = 500, 700
    local malformedExpense = view.settlementSummary({
        rows = bill.rows, expenses = { { name = "", amount = 50 } }, splitCount = 2,
    }, settlement)
    test.eq(malformedExpense.distributable, nil, "an amount without an expense label remains pending")
end
