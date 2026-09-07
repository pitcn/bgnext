return function(test)
    local Accounting = dofile("Core/BGNext/AuctionTradeAccounting.lua")
    local tradeFile = assert(io.open("Core/Module/Trade.lua", "rb"))
    local tradeSource = tradeFile:read("*a")
    tradeFile:close()
    test.eq(tradeSource:find("AuctionTradeAccounting.rowKind", 1, true) ~= nil, true,
        "the live trade path accepts prefilled auction rows through the accounting helper")
    test.eq(tradeSource:find("AuctionTradeAccounting.allocateDebt", 1, true) ~= nil, true,
        "the live trade path uses the unit-preserving debt allocator")

    local tocFile = assert(io.open("BGLite.toc", "rb"))
    local toc = tocFile:read("*a")
    tocFile:close()
    local helperPos = assert(toc:find("Core\\BGNext\\AuctionTradeAccounting.lua", 1, true))
    local tradePos = assert(toc:find("Core\\Module\\Trade.lua", 1, true))
    test.eq(helperPos < tradePos, true, "the accounting helper loads before the live trade module")

    local persistedRecord = { maijia = "买家甲", jine = "2500000" }
    test.eq(Accounting.linkBillRow(persistedRecord, 2, 4), true,
        "auction completion can link its exact bill row")
    local boss, slot = Accounting.billRow(persistedRecord)
    test.eq(boss, 2, "the runtime link retains the boss index")
    test.eq(slot, 4, "the runtime link retains the slot index")
    test.eq(persistedRecord.billBoss, nil, "runtime linkage never adds fields to the saved auction record")
    test.eq(persistedRecord.billSlot, nil, "runtime linkage keeps the existing saved schema unchanged")

    local function samePlayer(left, right)
        return left == right
    end
    local function sameItem(left, right)
        return left == right
    end

    local auction = {
        zhuangbei = "item:123",
        maijia = "买家甲",
        jine = "2500000",
        billBoss = 1,
        billSlot = 2,
    }
    local prefilled = {
        item = "item:123",
        buyer = "买家甲",
        amount = "2500000",
    }

    test.eq(Accounting.rowKind(auction, prefilled, sameItem, samePlayer), "prefilled",
        "a bill row filled at auction completion remains eligible for trade debt accounting")
    test.eq(Accounting.rowKind(auction, {
        item = "item:123", buyer = "", amount = "",
    }, sameItem, samePlayer), "empty",
        "an unfilled matching row keeps the original BiaoGe/BGLite fallback")
    test.eq(Accounting.rowKind(auction, {
        item = "item:123", buyer = "其他买家", amount = "2500000",
    }, sameItem, samePlayer), nil,
        "trade accounting never overwrites another buyer")
    test.eq(Accounting.rowKind(auction, {
        item = "item:123", buyer = "买家甲", amount = "2400000",
    }, sameItem, samePlayer), nil,
        "trade accounting never overwrites a manually changed amount")

    local records = {
        { money = 2500000 },
        { money = 1500000 },
    }
    Accounting.allocateDebt(records, 3700000)
    test.eq(records[1].qiankuan, 2500000,
        "an entirely unpaid first item retains its complete auction amount")
    test.eq(records[2].qiankuan, 1200000,
        "the remaining debt is assigned without changing gold units")
    test.eq(records[1].qiankuan + records[2].qiankuan, 3700000,
        "a 4000000 gold trade paid with 300000 gold preserves the full 3700000 debt")
end
