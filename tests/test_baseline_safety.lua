local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

return function(test)
    local toc = readAll("BGLite.toc")
    local main = readAll("Core/BiaoGe.lua")
    local database = readAll("Core/DB/DB.lua")
    local auction = readAll("Core/Module/Auction.lua")
    local auctionLog = readAll("Core/Module/AuctionLog.lua")
    local auctionWA = readAll("Core/Module/AuctionWA.lua")
    local wishlistReminder = readAll("Core/BGNext/WishlistReminder.lua")
    local helpers = readAll("Core/function2.lua")
    local trade = readAll("Core/Module/Trade.lua")
    local clear = readAll("Core/Module/ClearBiaoGe.lua")
    local sendMail = readAll("Core/Module/SendMail.lua")
    local settlementRuntime = readAll("Core/BGNext/CurrentSettlementRuntime.lua")
    local fbui = readAll("Core/FBUI/FBUI.xml")
    local options = readAll("Core/Options.lua")

    -- The current-raid settlement layers are loaded and wired to the confirmed
    -- BGLite success results, not to a new scan or poll.
    test.eq(toc:find("Core\\BGNext\\CurrentSettlementView.lua", 1, true) ~= nil, true,
        "settlement projection is loaded")
    test.eq(toc:find("Core\\BGNext\\CurrentSettlementRuntime.lua", 1, true) ~= nil, true,
        "settlement collector is loaded")
    test.eq(toc:find("Core\\BGNext\\CurrentSettlementUI.lua", 1, true) ~= nil, true,
        "settlement tables are loaded")
    test.eq(settlementRuntime:find("ERR_TRADE_COMPLETE", 1, true) ~= nil, true,
        "trade collection stays on the confirmed trade completion result")
    test.eq(sendMail:find("ERR_MAIL_SENT", 1, true) ~= nil, true,
        "mail collection stays on the confirmed send result")
    test.eq(sendMail:find("CurrentSettlementRuntime.notifyMailSent", 1, true) ~= nil, true,
        "batch mail reports only its own executed send result")
    test.eq(main:find("CurrentSettlementUI.installEntry", 1, true) ~= nil, true,
        "current-raid record entries are installed on the main window")

    test.eq(toc:find("Core\\Module\\TradeHistory.lua", 1, true), nil, "legacy trade history is not loaded")
    test.eq(toc:find("Core\\Module\\MailHistory.lua", 1, true), nil, "legacy mail history is not loaded")
    test.eq(main:find("TradeHistoryMainFrame", 1, true), nil, "legacy trade history frame is absent")
    test.eq(main:find("MailHistoryMainFrame", 1, true), nil, "legacy mail history frame is absent")
    test.eq(sendMail:find("MailHistoryMainFrame", 1, true), nil, "send-mail legacy history shortcut is absent")
    test.eq(toc:find("Core\\Module\\Receive.lua", 1, true), nil, "legacy whole-table receiver is not loaded")
    test.eq(main:find("BG.ReceiveUI", 1, true), nil, "startup cannot initialize the legacy receiver")
    test.eq(fbui:find("ReceiveUIfunction.lua", 1, true), nil, "legacy receiver UI is outside the load graph")
    test.eq(fbui:find("Model.lua", 1, true), nil, "decorative boss models are outside the load graph")
    test.eq(main:find("BG.CreateBossModel", 1, true), nil, "startup does not create decorative boss models")
    test.eq(options:find('local name = "model"', 1, true), nil, "boss model setting is removed")
    test.eq(options:find("显示BOSS模型", 1, true), nil, "boss model setting has no dead label")
    test.eq(auctionLog:find("if db and db[index] and db[index].type == 2 then", 1, true) ~= nil, true,
        "auction-log cleanup tolerates records disappearing during refresh")
    test.eq(auctionLog:find("for index, v in ipairs(tbl or {}) do", 1, true) ~= nil, true,
        "auction-log validation tolerates a missing log table")
    test.eq(auctionLog:find("if not BiaoGe[FB].auctionLog then return end", 1, true) ~= nil, true,
        "auction-log actions stop safely after the log is cleared")
    test.eq(database:find("BiaoGe.Hope", 1, true), nil, "legacy wishlist data is not initialized or migrated")
    test.eq(auction:find("BG.HopeFrame", 1, true), nil, "auction does not scan the removed legacy wishlist UI")
    test.eq(auction:find('WishlistReminder.notify("auction"', 1, true) ~= nil, true,
        "auction delegates to local wishlist reminder")
    test.eq(wishlistReminder:find('BG.PlaySound("hope")', 1, true) ~= nil, true,
        "wishlist reminder includes local sound")
    test.eq(helpers:find("BG.BGNext.RoleOverviewEntry.togglePinned()", 1, true), nil,
        "startup RoleOverviewUI never toggles the user-controlled window")

    -- The duplicate BGNext auto-bid stack was removed; only the retained BGLite
    -- native auto-bid path (AuctionWA/AuctionWAEvent) loads, listens, and sends.
    for _, module in ipairs({
        "AuctionNames", "AuctionPresetStore", "ControlledAutoBid",
        "AuctionBidMessage", "AuctionBidUI", "AuctionPresetRuntime",
    }) do
        test.eq(toc:find("Core\\BGNext\\" .. module .. ".lua", 1, true), nil,
            "duplicate auto-bid module " .. module .. " is not loaded")
    end
    local autoDelay = auctionWA:match("function wa%.AutoSendLate%(%)(.-)function wa%.SetEndState") or ""
    test.eq(autoDelay:find("random", 1, true), nil,
        "native auto-bid timing is deterministic and cannot become timing randomization")
    for path, content in pairs({
        ["Core/BiaoGe.lua"] = main,
        ["Core/DB/DB.lua"] = database,
        ["Core/function2.lua"] = helpers,
        ["Core/Module/Trade.lua"] = trade,
        ["Core/Module/ClearBiaoGe.lua"] = clear,
    }) do
        test.eq(content:find("BiaoGe.Hope", 1, true), nil, path .. " does not read legacy wishlist data")
        test.eq(content:find("BG.HopeFrame", 1, true), nil, path .. " does not scan legacy wishlist frames")
    end
end
