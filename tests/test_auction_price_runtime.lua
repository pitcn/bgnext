return function(test)
    BG = { BGNext = {} }
    local runtime = dofile("Core/BGNext/AuctionPriceRuntime.lua")

    -- chooseLeaderPrefill: only a single unanimous price is allowed to prefill.
    test.eq(runtime.chooseLeaderPrefill({ 100, 100 }), 100, "unanimous price prefills")
    test.eq(runtime.chooseLeaderPrefill({ 100, 200 }), nil, "differing prices do not prefill")
    test.eq(runtime.chooseLeaderPrefill({ 100, false }), nil, "a non-numeric entry blocks prefill")
    test.eq(runtime.chooseLeaderPrefill({ 500 }), 500, "single price prefills")
    test.eq(runtime.chooseLeaderPrefill({}), nil, "empty list does not prefill")

    -- resolveRaid: only a recognized current raid that the item does not point
    -- away from may prefill.
    test.eq(runtime.resolveRaid("ULD", { ULD = true }, nil), "ULD", "recognized raid with no override")
    test.eq(runtime.resolveRaid("ULD", { ICC = true }, "ICC"), nil, "item resolves to a different raid")
    test.eq(runtime.resolveRaid("", { ULD = true }, nil), nil, "empty raid is unresolved")
    test.eq(runtime.resolveRaid("ULD", {}, nil), nil, "unrecognized raid is unresolved")
    test.eq(runtime.resolveRaid("ULD", { ULD = true, ICC = true }, "ICC"), nil, "cross-raid override blocks prefill")

    -- The runtime wraps the existing leader hook, calls it first, and only ever
    -- touches the existing price EditBox. It must never bypass the permission
    -- gates, toggle auto-bid, or send anything itself.
    local file = assert(io.open("Core/BGNext/AuctionPriceRuntime.lua", "rb"))
    local source = file:read("*a")
    file:close()
    for _, token in ipairs({
        "BG.StartAuction",
        "prefillLeaderFrame",
        "Edit2",
        "resolveLeaderPrice",
        "if price == nil then return",
    }) do
        test.eq(source:find(token, 1, true) ~= nil, true, "leader prefill wires " .. token)
    end
    for _, forbidden in ipairs({
        "SendStartAuctionMsg",
        "SendMyMoney_OnClick",
        "SendAddonMessage",
        "C_ChatInfo.SendAddonMessage",
        "SendChatMessage",
        "ButtonSendMyMoney",
        "isAuto",
    }) do
        test.eq(source:find(forbidden, 1, true), nil, "no " .. forbidden .. " in the runtime")
    end
end
