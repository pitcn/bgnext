return function(test)
    BG = { BGNext = {} }
    local Identity = dofile("Core/BGNext/PlayerIdentity.lua")

    test.eq(Identity.key("Alice", "My Realm"), "alice-myrealm",
        "a local short name gains the normalized local realm")
    test.eq(Identity.key("Alice-MyRealm", "My Realm"), "alice-myrealm",
        "a full name and local short name share one identity key")
    test.eq(Identity.key("ALICE-My-Realm", "My Realm"), "alice-myrealm",
        "case spaces and realm separators do not change identity")
    test.eq(Identity.same("Alice", "Alice-MyRealm", "My Realm"), true,
        "local short and full names identify the same player")
    test.eq(Identity.same("Alice-OtherRealm", "Alice-MyRealm", "My Realm"), false,
        "cross-realm names remain distinct")
    test.eq(Identity.same("Alice-OtherRealm", "Alice-Other Realm", "My Realm"), true,
        "the same remote realm tolerates display formatting differences")
    test.eq(Identity.same(nil, "Alice", "My Realm"), false, "a missing name fails closed")
    test.eq(Identity.same("", "Alice", "My Realm"), false, "an empty name fails closed")
    test.eq(Identity.same("Alice", "Alice", nil), false,
        "two bare names without a known realm do not create an ambiguous identity")

    local roster = {
        { name = "Alice-MyRealm", class = "MAGE", color = { 0.25, 0.78, 0.92 } },
        { name = "Alice-OtherRealm", class = "WARRIOR", color = { 0.78, 0.61, 0.43 } },
    }
    test.eq(Identity.find(roster, "Alice", "My Realm"), roster[1],
        "a local short buyer resolves to the canonical raid-roster member")
    test.eq(Identity.find(roster, "Alice-Other Realm", "My Realm"), roster[2],
        "a remote buyer resolves without merging same-name realms")
    test.eq(Identity.find(roster, "Missing", "My Realm"), nil,
        "an unknown buyer does not inherit another roster member's class")

    test.eq(Identity.shortName("Reader-时光"), "Reader", "short name drops the realm suffix")
    test.eq(Identity.shortName("Reader"), "Reader", "a bare name is already short")
    test.eq(Identity.shortName(nil), nil, "short name of a missing value fails closed")
    test.eq(Identity.shortName(""), nil, "short name of an empty value fails closed")

    test.eq(Identity.canonical("Reader", "时光"), "Reader-时光",
        "canonical form adds the local realm to a bare name")
    test.eq(Identity.canonical("Reader-时光", "时光"), "Reader-时光",
        "canonical form keeps an existing local realm")
    test.eq(Identity.canonical("Reader-OtherRealm", "时光"), "Reader-OtherRealm",
        "canonical form preserves a cross-realm suffix")
    test.eq(Identity.canonical(nil, "时光"), nil, "canonical form of a missing value fails closed")
    test.eq(Identity.canonical("Reader", nil), nil,
        "a bare name without a known realm has no canonical identity")

    for _, family in ipairs({ "vanilla", "tbc", "wrath", "titan", "cata", "mop" }) do
        test.eq(Identity.display("Reader-时光", "时光", family), "Reader",
            family .. " displays the short name only")
    end
    test.eq(Identity.display("Reader", "时光", "retail"), "Reader",
        "retail bare name stays short")
    test.eq(Identity.display("Reader-时光", "时光", "retail"), "Reader",
        "retail same-realm name is shortened")
    test.eq(Identity.display("Reader-OtherRealm", "时光", "retail"), "Reader-OtherRealm",
        "retail cross-realm name keeps its realm so it never merges")
    test.eq(Identity.display("Reader-时光", "时光", nil), "Reader",
        "an undetected family is treated as non-retail and shortened")
    test.eq(Identity.display(nil, "时光", "retail"), nil, "missing display value passes through nil")

    test.eq(Identity.display("Reader-OtherRealm", "时光", "retail"), "Reader-OtherRealm",
        "same short name on another realm stays visually distinct")
    test.eq(Identity.same("Reader-OtherRealm", "Reader-时光", "时光"), false,
        "same-name/different-realm players never merge")

    test.eq(Identity.familyFromGlobals({ IsRetail = true }), "retail", "retail flag resolves to retail")
    test.eq(Identity.familyFromGlobals({ IsVanilla = true }), nil, "vanilla flag resolves to non-retail")
    test.eq(Identity.familyFromGlobals(nil), nil, "missing globals resolve to non-retail")

    -- The legacy DuiZhang message keeps its existing message type. Non-Retail
    -- can use the unique local short name; Retail must retain a cross-realm
    -- canonical identity, and the receiver parses the item payload from the
    -- right so the buyer's own hyphen is not treated as a delimiter.
    test.eq(Identity.duiZhangName("Reader-时光", "时光", "titan"), "Reader",
        "non-retail DuiZhang keeps the legacy short-name field")
    test.eq(Identity.duiZhangName("Reader-OtherRealm", "时光", "retail"), "Reader%2DOtherRealm",
        "retail DuiZhang encodes the cross-realm separator for legacy parsing")
    test.eq(Identity.duiZhangName("Reader", "时光", "retail"), "Reader",
        "retail DuiZhang keeps an unambiguous same-realm name legacy-compatible")
    local buyer, payload = Identity.parseDuiZhang("DuiZhang-Reader-24478 10000,27854 t,")
    test.eq(buyer, "Reader", "legacy short-name DuiZhang messages still parse")
    test.eq(payload, "24478 10000,27854 t,", "legacy item payload remains unchanged")
    buyer, payload = Identity.parseDuiZhang("DuiZhang-Reader%2DOtherRealm-24478 10000,27854 t,")
    test.eq(buyer, "Reader-OtherRealm", "retail cross-realm DuiZhang identity round-trips")
    test.eq(payload, "24478 10000,27854 t,", "cross-realm item payload remains unchanged")

    local trade = assert(io.open("Core/Module/Trade.lua", "rb"))
    local tradeSource = trade:read("*a")
    trade:close()
    test.eq(tradeSource:find('maijia:GetText() == target', 1, true), nil,
        "debt lookup and clear never compare display text to a canonical target")
end
