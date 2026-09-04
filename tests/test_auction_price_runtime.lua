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

    -- resolveEntryRaid: the entry's explicit provenance wins over the catalog so
    -- a cross-raid-duplicate item still resolves; unproven sources fall back to a
    -- catalog-unique raid only.
    local function uniqueRaid(itemId)
        if itemId == 1001 then return nil end -- duplicated across raids
        if itemId == 2001 then return "ULD" end
        return nil
    end
    test.eq(runtime.resolveEntryRaid({ source = "table", raidId = "ULD" }, "ULD", { ULD = true, ICC = true }, 1001, uniqueRaid), "ULD", "explicit raid wins for a duplicate item")
    test.eq(runtime.resolveEntryRaid({ source = "loot" }, "ULD", { ULD = true }, 1001, uniqueRaid), "ULD", "loot source proves the current raid")
    test.eq(runtime.resolveEntryRaid({ source = "auctionlog" }, "ULD", { ULD = true }, 1001, uniqueRaid), "ULD", "auctionlog source proves the current raid")
    local _, reason = runtime.resolveEntryRaid({ source = "backpack" }, "ULD", { ULD = true }, 1001, uniqueRaid)
    test.eq(reason, "no-raid", "unproven duplicate source is refused, not guessed")
    test.eq(runtime.resolveEntryRaid({ source = "backpack" }, "ULD", { ULD = true }, 2001, uniqueRaid), "ULD", "catalog-unique item still resolves")
    test.eq(runtime.resolveEntryRaid({ source = "table", raidId = "NAXX" }, "ULD", { ULD = true }, 1001, uniqueRaid), nil, "inactive explicit raid is refused")
    test.eq(runtime.resolveEntryRaid({ source = "table", raidId = "ICC" }, "ULD", { ULD = true }, 2001, uniqueRaid), nil, "explicit raid outside the active set is refused")

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

    -- The leader action writes the resolved price before optionally invoking
    -- the existing start button. An ordinary open remains manual; Alt+right is
    -- the explicit direct-start gesture.
    local function fakeLeaderFrame(initialText)
        local frame = { starts = 0 }
        frame.Edit2 = {
            text = initialText,
            SetText = function(self, text) self.text = text end,
        }
        frame.bt = {
            GetScript = function(_, script)
                if script ~= "OnClick" then return nil end
                return function() frame.starts = frame.starts + 1 end
            end,
        }
        return frame
    end
    local leaderEdit = fakeLeaderFrame("1000")
    test.eq(runtime.applyLeaderPrefill(leaderEdit, 500, false), true, "resolved price fills the auction editor")
    test.eq(leaderEdit.Edit2.text, "500", "leader editor receives the saved price")
    test.eq(leaderEdit.starts, 0, "ordinary open remains manual")
    test.eq(leaderEdit.bt.money, nil, "ordinary open does not bind money")

    local leaderDirect = fakeLeaderFrame("1000")
    test.eq(runtime.applyLeaderPrefill(leaderDirect, 500, true), true, "direct start accepts a resolved price")
    test.eq(leaderDirect.Edit2.text, "500", "direct start writes the preset before starting")
    test.eq(leaderDirect.starts, 0, "direct start never clicks from the inner wrapper")
    test.eq(leaderDirect.bt.money, 500, "direct start binds the approved amount to the send button")

    local unresolvedDirect = fakeLeaderFrame("1000")
    test.eq(runtime.applyLeaderPrefill(unresolvedDirect, nil, true), false, "unresolved price cannot direct start")
    test.eq(unresolvedDirect.starts, 0, "unresolved price stays manual")

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
        "resolveLeaderApproval",
        "bgnextDirectApproval",
        "resolveEntryRaid",
        "AuctionPreSend",
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
