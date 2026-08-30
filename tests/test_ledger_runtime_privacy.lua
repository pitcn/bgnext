return function(test)
    local source = assert(io.open("Core/Module/DuiZhang.lua", "rb")):read("*a")

    test.eq(source:find("BG.sessionDuizhang = {}", 1, true) ~= nil, true,
        "reconciliation uses a runtime-only session list")
    test.eq(source:find("BiaoGe.duizhang", 1, true), nil,
        "reconciliation never reads or writes the legacy persisted ledger list")
    test.eq(source:find("msgTbl", 1, true), nil,
        "raw ledger chat is not retained")
    test.eq(source:find("DuiZhangMainFrame.msgFrame", 1, true), nil,
        "the removed raw-chat panel is not accessed")
    test.eq(source:find("SaveRaidMember", 1, true), nil,
        "the other raid roster is not copied into reconciliation state")
    test.eq(source:find("tinsert(bigfoot, msg)", 1, true), nil,
        "temporary BigFoot parsing does not retain raw chat lines")
    test.eq(source:find("Capture.isActive(captureState, GetTime())", 1, true) ~= nil, true,
        "chat parsing is gated by explicit active capture state")
    test.eq(source:find("Capture.bindSource(captureState, sender, realm, members, GetTime())", 1, true) ~= nil,
        true, "the first accepted ledger header binds its sender")
    test.eq(source:find("Capture.acceptSource(captureState, sender, realm, members, GetTime())", 1, true) ~= nil,
        true, "subsequent chat and addon fragments require the bound sender")
    test.eq(source:find("Capture.parseMoney", 1, true) ~= nil, true,
        "reconciliation amounts use bounded numeric parsing")
    test.eq(source:find("Capture.parseItemID", 1, true) ~= nil, true,
        "reconciliation addon item ids use bounded numeric parsing")
    test.eq(source:find('BG.RegisterEvent("PLAYER_LOGOUT"', 1, true) ~= nil, true,
        "logout clears runtime reconciliation state")
    test.eq(source:find('BG.RegisterEvent("GROUP_ROSTER_UPDATE"', 1, true) ~= nil, true,
        "roster changes clear runtime reconciliation state")
    test.eq(source:find('L["开始对账"]', 1, true) ~= nil, true,
        "the UI exposes an explicit start action")

    local zhCNSource = assert(io.open("Locales/zhCN.lua", "rb")):read("*a")
    for _, key in ipairs({
        "开始对账",
        "停止对账",
        "当前团队临时对账",
        "只有点击开始后才会读取账单；数据不会写入插件保存文件，重载、离团或停止后立即清空。",
        "已停止对账并清空本次临时数据。",
        "已开始对账：仅临时读取当前团队接下来通报的一份账单。",
        "对账数据超出安全限制或等待超时，已停止本次对账。",
    }) do
        test.eq(zhCNSource:find('L["' .. key .. '"] = "' .. key .. '"', 1, true) ~= nil, true,
            "Simplified Chinese reconciliation label is a string: " .. key)
    end

    local optionsSource = assert(io.open("Core/Options.lua", "rb")):read("*a")
    test.eq(optionsSource:find("ReceiveMainFrame", 1, true), nil,
        "settings do not access the retired receive window")

    local mainSource = assert(io.open("Core/BiaoGe.lua", "rb")):read("*a")
    test.eq(mainSource:find("ReceiveMainFrame", 1, true), nil,
        "opening the main table does not access the retired receive window")
    test.eq(mainSource:find("if BG.DuiZhangMainFrame.msgBg then", 1, true) ~= nil, true,
        "the shared frame tolerates the removed raw-chat panel")

    local auctionLogSource = assert(io.open("Core/Module/AuctionLog.lua", "rb")):read("*a")
    test.eq(auctionLogSource:find("tinsert(BiaoGe.duizhang", 1, true), nil,
        "manual auction-log reconciliation does not restore persisted ledger history")
    test.eq(auctionLogSource:find("tinsert(BG.sessionDuizhang, duizhang)", 1, true) ~= nil, true,
        "manual auction-log reconciliation remains available in the current session")
    test.eq(auctionLogSource:find("duizhang.msgTbl", 1, true), nil,
        "manual auction-log reconciliation does not create a raw-chat field")

    local databaseSource = assert(io.open("Core/DB/DB.lua", "rb")):read("*a")
    test.eq(databaseSource:find("BiaoGe.duizhang", 1, true), nil,
        "new installs do not initialize the retired persisted ledger field")
end
