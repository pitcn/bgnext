return function(test)
    -- Forever's GetRealmName() returns "", so every normalized local realm is
    -- empty. Identity must still work by name while explicit realms stay apart.
    BG = { BGNext = {} }
    local Identity = dofile("Core/BGNext/PlayerIdentity.lua")
    local Sender = dofile("Core/BGNext/AuctionSender.lua")
    local Capture = dofile("Core/BGNext/LedgerCapture.lua")
    local Authority = dofile("Core/BGNext/RaidAuthority.lua")
    local realm = ("" ):gsub(" ", ""):gsub("%-", "")

    local leader, member, outsider = "Ann Lee", "Bo Wu", "Cy Ng"

    -- PlayerIdentity
    test.eq(Identity.key(leader, ""), "ann lee-", "bare name with empty realm keeps an empty realm component")
    test.eq(Identity.key(leader, nil), "ann lee-", "nil realm behaves like the empty realm")
    test.eq(Identity.key("  ", ""), nil, "blank name still fails closed")
    test.eq(Identity.key("", ""), nil, "empty name still fails closed")
    test.eq(Identity.key(nil, ""), nil, "missing name still fails closed")
    test.eq(Identity.key("ann lee-", ""), "ann lee-", "an empty-realm key maps to itself")
    test.eq(Identity.key(Identity.key("Alice", "My Realm"), "My Realm"), "alice-myrealm", "normal keys stay idempotent")
    test.eq(Identity.same(leader, "ANN LEE", ""), true, "same name matches on Forever")
    test.eq(Identity.same(leader, member, ""), false, "different names stay distinct")
    test.eq(Identity.same(leader, "", ""), false, "empty right side fails closed")
    test.eq(Identity.same("Alice-RealmA", "Alice-RealmB", ""), false, "explicit different realms stay distinct")
    test.eq(Identity.same("Alice-RealmA", "Alice", ""), false, "explicit realm never merges with an empty-realm name")
    test.eq(Identity.canonical(leader, ""), leader, "canonical of a bare name with empty realm is the bare name")
    test.eq(Identity.canonical(leader, nil), leader, "canonical with nil realm is the bare name")
    test.eq(Identity.canonical("", ""), nil, "canonical of empty fails closed")
    test.eq(Identity.find({ { name = member }, { name = leader } }, leader, "").name, leader, "find resolves on Forever")

    -- Non-Forever storage formats are unchanged.
    test.eq(Identity.key("Alice", "My Realm"), "alice-myrealm", "normal key format unchanged")
    test.eq(Identity.canonical("Alice", "Realm"), "Alice-Realm", "normal canonical format unchanged")
    test.eq(Identity.same("Alice-OtherRealm", "Alice", "My Realm"), false, "normal cross-realm unchanged")

    -- Live roster as Forever returns it: names with a space, no realm.
    local rows = {
        { member, 0, false }, { outsider .. "x", 1, false }, { leader, 2, false }, { "Di Ho", 1, false },
    }
    local function count() return #rows end
    local function info(i) local r = rows[i]; return r[1], r[2], nil, nil, nil, nil, nil, nil, nil, nil, r[3] end
    local roster = Sender.liveRaidRoster(count, info)
    local names = Sender.liveRaidMemberNames(count, info)

    -- Start / Cancel / Pause / Resume all use isController.
    test.eq(Sender.isController(leader, realm, roster), true, "leader's start/cancel accepted with empty realm")
    test.eq(Sender.isController(member, realm, roster), false, "member's start is rejected with empty realm")
    test.eq(Sender.isController("Di Ho", realm, roster), false, "assistant's start is rejected with empty realm")
    test.eq(Sender.isController(outsider, realm, roster), false, "outsider rejected")
    test.eq(Sender.isController("", realm, roster), false, "empty sender rejected")
    test.eq(Sender.isController(nil, realm, roster), false, "missing sender rejected")
    rows[1][3] = true
    roster = Sender.liveRaidRoster(count, info)
    test.eq(Sender.isController(member, realm, roster), true, "master looter accepted with empty realm")
    rows[1][3] = false

    -- Bids and version replies use isRaidSender + rate keys.
    test.eq(Sender.isRaidSender(member, realm, names), true, "member bid accepted")
    test.eq(Sender.isRaidSender(leader, realm, names), true, "leader bid accepted")
    test.eq(Sender.isRaidSender(outsider, realm, names), false, "outsider bid rejected")
    test.eq(Sender.isRaidSender("", realm, names), false, "empty bidder rejected")
    local rate = {}
    test.eq(Sender.shouldAcceptAuctionMessage(rate, member, realm, names, 123.5, 10, 1), true, "first bid accepted")
    test.eq(Sender.shouldAcceptAuctionMessage(rate, member, realm, names, 123.5, 10.2, 1), false, "rate limit still applies")
    test.eq(Sender.shouldAcceptAuctionMessage(rate, leader, realm, names, 123.5, 10.2, 1), true, "other bidder separate")
    test.eq(Sender.shouldRespondVersion({}, member, realm, names, 10), true, "version reply to a member")
    test.eq(Sender.shouldRespondVersion({}, outsider, realm, names, 10), false, "no version reply to an outsider")

    -- Ledger capture source binding (trade/mail capture).
    local state = Capture.new()
    Capture.start(state, 0)
    test.eq(Capture.bindSource(state, leader, realm, names, 1), true, "ledger source binds on Forever")
    test.eq(Capture.acceptSource(state, leader, realm, names, 2), true, "same source accepted")
    test.eq(Capture.acceptSource(state, member, realm, names, 2), false, "other source rejected")
    test.eq(Capture.shouldStopForRoster(state, true, realm, names), false, "source still in raid keeps capture")
    test.eq(Capture.shouldStopForRoster(state, true, realm, { member }), true, "source left raid stops capture")

    -- RaidAuthority name fallback (no UnitIsUnit) with empty realm.
    local isSelf = Authority.isSelfRow({}, 3, leader, leader, realm, Identity)
    test.eq(isSelf, true, "name fallback recognises self with empty realm")
    isSelf = Authority.isSelfRow({}, 1, member, leader, realm, Identity)
    test.eq(isSelf, false, "name fallback refuses another row")

    -- AuctionWA's own-name helper must use the same Forever form as senders so
    -- the leader's and bidders' "is this my bid" checks match.
    local f = assert(io.open("Core/Module/AuctionWA.lua", "rb")); local src = f:read("*a"); f:close()
    local gnBlock = assert(src:match("(  function wa%.GN%(unit%).-\n  end)\n"), "wa.GN present")
    local function waGN(isForever, unit)
        local env = { wa = {}, BG = { IsForever = isForever, GN = function(u) return "BG:" .. tostring(u) end },
            GetUnitName = function(u) return "GU:" .. u end }
        local fn = assert(loadstring(gnBlock)); setfenv(fn, env); fn()
        return env.wa.GN(unit)
    end
    test.eq(waGN(true), "BG:player", "Forever wa.GN uses BG.GN (First Surname)")
    test.eq(waGN(true, "t"), "BG:target", "Forever target shortcut still works")
    test.eq(waGN(false), "GU:player", "other clients keep GetUnitName(unit, true)")
end
