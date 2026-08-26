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
    local helpers = readAll("Core/function2.lua")
    local trade = readAll("Core/Module/Trade.lua")
    local clear = readAll("Core/Module/ClearBiaoGe.lua")
    local sendMail = readAll("Core/Module/SendMail.lua")

    test.eq(toc:find("Core\\Module\\TradeHistory.lua", 1, true), nil, "legacy trade history is not loaded")
    test.eq(toc:find("Core\\Module\\MailHistory.lua", 1, true), nil, "legacy mail history is not loaded")
    test.eq(main:find("TradeHistoryMainFrame", 1, true), nil, "legacy trade history frame is absent")
    test.eq(main:find("MailHistoryMainFrame", 1, true), nil, "legacy mail history frame is absent")
    test.eq(sendMail:find("MailHistoryMainFrame", 1, true), nil, "send-mail legacy history shortcut is absent")
    test.eq(database:find("BiaoGe.Hope", 1, true), nil, "legacy wishlist data is not initialized or migrated")
    test.eq(auction:find("BG.HopeFrame", 1, true), nil, "auction does not scan the removed legacy wishlist UI")
    test.eq(auction:find('BG.PlaySound("hope")', 1, true) ~= nil, true, "auction wishlist reminder includes local sound")
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
