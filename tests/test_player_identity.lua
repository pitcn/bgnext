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
end
