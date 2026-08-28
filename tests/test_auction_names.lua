return function(test)
    BG = { BGNext = {} }
    local Names = dofile("Core/BGNext/AuctionNames.lua")

    -- Canonical full names keep cross-realm identities distinct.
    test.eq(Names.fullName("Alice", "Realm"), "Alice-Realm", "a bare name gains the realm")
    test.eq(Names.fullName("Alice-Realm", "Realm"), "Alice-Realm", "a full name is kept verbatim")
    test.eq(Names.fullName("Alice-OtherRealm", "Realm"), "Alice-OtherRealm", "a cross-realm name is kept verbatim")
    test.eq(Names.fullName("", "Realm"), nil, "an empty name has no identity")
    test.eq(Names.fullName(nil, "Realm"), nil, "a missing name has no identity")
    test.eq(Names.fullName("Alice", ""), "Alice", "a bare name without a realm stays bare")
    test.eq(Names.fullName("Alice", nil), "Alice", "a bare name without a realm stays bare")

    -- Two names are the same player only when the full form agrees.
    test.eq(Names.isSamePlayer("Alice", "Alice-Realm", "Realm"), true, "a bare name matches its full form")
    test.eq(Names.isSamePlayer("Alice-Realm", "Alice", "Realm"), true, "matching is symmetric")
    test.eq(Names.isSamePlayer("Alice", "Alice-OtherRealm", "Realm"), false, "same short name on another realm is distinct")
    test.eq(Names.isSamePlayer("Alice-OtherRealm", "Alice-OtherRealm", "Realm"), true, "the same cross-realm name matches itself")
    test.eq(Names.isSamePlayer("", "Alice", "Realm"), false, "an empty name never matches")
    test.eq(Names.isSamePlayer(nil, "Alice", "Realm"), false, "a missing name never matches")
    test.eq(Names.isSamePlayer(nil, nil, "Realm"), false, "two missing names never match")

    -- Source-level invariants: pure string math only.
    local handle = io.open("Core/BGNext/AuctionNames.lua", "r")
    local source = handle:read("*a")
    handle:close()
    for _, forbidden in ipairs({
        "BiaoGe", "SendAddonMessage", "SendChatMessage", "C_ChatInfo",
        "CreateFrame", "RegisterEvent", "C_Timer", "random", "UnitName",
    }) do
        test.eq(string.find(source, forbidden, 1, true), nil, "names helper never uses " .. forbidden)
    end
end
