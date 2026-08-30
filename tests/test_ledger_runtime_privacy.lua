return function(test)
    local source = assert(io.open("Core/Module/DuiZhang.lua", "rb")):read("*a")

    test.eq(source:find("BG.sessionDuizhang = {}", 1, true) ~= nil, true,
        "reconciliation uses a runtime-only session list")
    test.eq(source:find("BiaoGe.duizhang", 1, true), nil,
        "reconciliation never reads or writes the legacy persisted ledger list")
    test.eq(source:find("msgTbl", 1, true), nil,
        "raw ledger chat is not retained")
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
    test.eq(source:find('BG.RegisterEvent("PLAYER_LOGOUT"', 1, true) ~= nil, true,
        "logout clears runtime reconciliation state")
    test.eq(source:find('BG.RegisterEvent("GROUP_ROSTER_UPDATE"', 1, true) ~= nil, true,
        "roster changes clear runtime reconciliation state")
    test.eq(source:find('L["开始对账"]', 1, true) ~= nil, true,
        "the UI exposes an explicit start action")
end
