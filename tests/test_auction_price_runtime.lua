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

    -- choosePersonalPrefill: only a saved price at or above the current auction
    -- floor is allowed to fill the bid box.
    test.eq(runtime.choosePersonalPrefill(150, 100), 150, "saved price above floor prefills")
    test.eq(runtime.choosePersonalPrefill(100, 100), 100, "saved price equal to floor prefills")
    test.eq(runtime.choosePersonalPrefill(50, 100), nil, "saved price below floor does not prefill")
    test.eq(runtime.choosePersonalPrefill(nil, 100), nil, "missing saved price does not prefill")
    test.eq(runtime.choosePersonalPrefill(150, nil), 150, "missing floor does not restrict")

    -- prefillPersonalText: touches only myMoneyEdit:SetText, never a send or
    -- auto-bid control.
    local function fakeFrame(initialText)
        return {
            myMoneyEdit = {
                text = initialText,
                SetText = function(self, t) self.text = t end,
            },
            sendClicks = 0,
            autoToggles = 0,
        }
    end
    local frame = fakeFrame("100")
    test.eq(runtime.prefillPersonalText(frame, 150, 100), true, "prefill reports a write")
    test.eq(frame.myMoneyEdit.text, "150", "exact saved value is set")
    test.eq(frame.sendClicks, 0, "no send click")
    test.eq(frame.autoToggles, 0, "no auto toggle")

    local below = fakeFrame("100")
    test.eq(runtime.prefillPersonalText(below, 50, 100), false, "below floor reports no write")
    test.eq(below.myMoneyEdit.text, "100", "below floor leaves text untouched")

    local missing = fakeFrame("100")
    test.eq(runtime.prefillPersonalText(missing, nil, 100), false, "missing reports no write")
    test.eq(missing.myMoneyEdit.text, "100", "missing leaves text untouched")

    test.eq(runtime.prefillPersonalText({}, 150, 100), false, "frame without edit box reports no write")

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
        "prefillPersonalFrame",
        "HookCreateAuction",
        "myMoneyEdit",
        "getPersonalPrice",
        "prefillPersonalText",
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
