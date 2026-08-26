local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

return function(test)
    local toc = readAll("BGLite.toc")
    local main = readAll("Core/BiaoGe.lua")
    local sendMail = readAll("Core/Module/SendMail.lua")

    test.eq(toc:find("Core\\Module\\TradeHistory.lua", 1, true), nil, "legacy trade history is not loaded")
    test.eq(toc:find("Core\\Module\\MailHistory.lua", 1, true), nil, "legacy mail history is not loaded")
    test.eq(main:find("TradeHistoryMainFrame", 1, true), nil, "legacy trade history frame is absent")
    test.eq(main:find("MailHistoryMainFrame", 1, true), nil, "legacy mail history frame is absent")
    test.eq(sendMail:find("MailHistoryMainFrame", 1, true), nil, "send-mail legacy history shortcut is absent")
end
