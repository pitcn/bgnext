-- Runtime integration test for the controlled auto-bid.
--
-- This test injects fake WoW APIs into _G and drives the REAL
-- Core/BGNext/AuctionPresetRuntime.lua — no source scanning. Every assertion
-- observes the state the runtime actually creates on the bid frame and the
-- messages it actually hands to C_ChatInfo.SendAddonMessage. It covers the
-- twelve review items: hook chaining (no double-wrap), fail-closed message
-- source, single active auction, precise end matching, first-price opening,
-- cancelable throttle timer + generation token, the complete stop set, no
-- gen1-on-gen2, mutual exclusion, and pcall-guarded send.
return function(test)
    local sent, timers, clock, sendError, inRaid
    local init2Callbacks, registeredEvents, probe

    -- A minimal fake UI widget: every method the runtime calls is a no-op that
    -- records just enough for assertions (text, enabled state, scripts, hooks).
    local function widget()
        local w = { text = "", enabled = true, scripts = {}, hooks = {} }
        function w:SetText(t) self.text = t end
        function w:GetText() return self.text end
        function w:SetTextColor(r, g, b) end
        function w:SetPoint(...) end
        function w:SetSize(...) end
        function w:SetNumeric(v) self.numeric = v end
        function w:SetAutoFocus(v) end
        function w:SetEnabled(v) self.enabled = v end
        function w:SetScript(k, fn) self.scripts[k] = fn end
        function w:HookScript(k, fn) self.hooks[k] = fn end
        function w:CreateFontString(...) return widget() end
        function w:Fire(hook) local f = self.hooks[hook]; if f then f(self) end end
        return w
    end

    local function resetEnv(opts)
        opts = opts or {}
        clock = 0
        sent = {}
        timers = {}
        sendError = nil
        inRaid = true
        init2Callbacks = {}
        registeredEvents = {}
        probe = { create = 0, ended = 0 }

        _G.GetTimePreciseSec = function() return clock end
        _G.GetTime = function() return clock end
        _G.GetRealmName = function() return "Test Realm" end
        _G.IsInRaid = function() return inRaid end
        _G.GetNumGroupMembers = function() return 1 end
        _G.UnitName = function(unit)
            if unit == "raid1" then return "Other" end
            if unit == "player" then return "Me" end
            return nil
        end
        _G.CreateFrame = function(frameType, name, parent, template) return widget() end

        local nextTimerId = 0
        local function newTimer(delay, fn)
            nextTimerId = nextTimerId + 1
            local t = { id = nextTimerId, delay = delay, fn = fn, canceled = false }
            function t:Cancel() self.canceled = true end
            timers[#timers + 1] = t
            return t
        end
        _G.C_Timer = { NewTimer = newTimer }

        _G.C_ChatInfo = {
            SendAddonMessage = function(prefix, msg, distribution)
                if sendError then error(sendError) end
                sent[#sent + 1] = { prefix = prefix, message = msg, distribution = distribution }
            end,
            RegisterAddonMessagePrefix = function() end,
        }

        _G.wa = {
            GN = function() return opts.selfName or "Me" end,
            GetFrameTotolHeight = function(count) return count * 110 end,
            AutoButton_OnClick = function(self) if self and self.owner then self.owner.isAuto = true end end,
        }
        _G.BGA = { Frames = { { IsSmallWindow = nil }, { IsSmallWindow = true } } }

        BG = { BGNext = {} }
        BG.Init2 = function(fn) init2Callbacks[#init2Callbacks + 1] = fn end
        BG.RegisterEvent = function(event, fn) registeredEvents[event] = fn end
        BG.realmName = "TestRealm"
        BG.BGNext.DB = { auctionPresets = {} }

        dofile("Core/BGNext/AuctionNames.lua")
        dofile("Core/BGNext/AuctionPresetStore.lua")
        dofile("Core/BGNext/ControlledAutoBid.lua")
        dofile("Core/BGNext/AuctionBidMessage.lua")
        dofile("Core/BGNext/AuctionBidUI.lua")

        BG.HookCreateAuction = function(f) probe.create = probe.create + 1 end
        BG.AuctionWAEnd = function(...) probe.ended = probe.ended + 1 end

        local RT = dofile("Core/BGNext/AuctionPresetRuntime.lua")
        for _, fn in ipairs(init2Callbacks) do fn() end
        return RT
    end

    local function newBidFrame(opts)
        opts = opts or {}
        local f = widget()
        f.auctionID = opts.auctionID or 12
        f.itemID = opts.itemID or 123
        f.link = opts.link or ("item:" .. tostring(f.itemID))
        f.money = opts.money or 100
        f.player = opts.player
        f.isGen2 = opts.isGen2 or false
        f.isAuto = opts.isAuto or false
        return f
    end

    local function armFrame(f, increment, cap)
        local st = f["BGNextAutoBid"]
        st.region.incrementEdit:SetText(increment)
        st.region.capEdit:SetText(cap)
        st.region.button.scripts.OnClick(st.region.button)
        return st
    end

    local function bidMsg(prefix, message, distribution, arg4, arg5)
        registeredEvents.CHAT_MSG_ADDON(nil, "CHAT_MSG_ADDON", prefix, message, distribution, arg4, arg5)
    end

    -- ---------------------------------------------------------------------
    -- Fix 1: hooks chain in BG.Init2, never overwrite, never double-wrap.
    -- ---------------------------------------------------------------------
    do
        local RT = resetEnv()

        test.eq(#init2Callbacks, 1, "the runtime registers exactly one Init2 callback")

        -- Before Init2 the original hooks are untouched.
        local createBefore = BG.HookCreateAuction
        local endBefore = BG.AuctionWAEnd

        -- installHooks is idempotent: running the Init2 callback again (a second
        -- PLAYER_ENTERING_WORLD) must not re-wrap.
        for _, fn in ipairs(init2Callbacks) do fn() end
        test.eq(BG.HookCreateAuction == createBefore, true, "a second Init2 never re-wraps the create hook")
        test.eq(BG.AuctionWAEnd == endBefore, true, "a second Init2 never re-wraps the end hook")

        -- The wrapped create hook calls the original first, then attaches ours.
        test.eq(BG.HookCreateAuction ~= nil, true, "the create hook is installed")
        local f = newBidFrame()
        BG.HookCreateAuction(f)
        test.eq(probe.create, 1, "the original create hook still runs")
        test.eq(f["BGNextAutoBid"] ~= nil, true, "and the runtime state is attached")

        -- The wrapped end hook calls the original first too.
        BG.AuctionWAEnd(1, "item:123", nil, nil)
        test.eq(probe.ended, 1, "the original end hook still runs")

        -- All the stop-relevant events are registered.
        test.eq(registeredEvents.CHAT_MSG_ADDON ~= nil, true, "CHAT_MSG_ADDON is observed")
        test.eq(registeredEvents.GROUP_ROSTER_UPDATE ~= nil, true, "GROUP_ROSTER_UPDATE is observed")
        test.eq(registeredEvents.PLAYER_LOGOUT ~= nil, true, "PLAYER_LOGOUT is observed")
        test.eq(registeredEvents.PLAYER_LEAVING_WORLD ~= nil, true, "PLAYER_LEAVING_WORLD is observed")

        -- Fix 10: the stack height is extended only for non-small cards, using
        -- the wrapped GetFrameTotolHeight (extra = regionHeight + gap = 58).
        local extra = BG.BGNext.AuctionBidUI.layout.regionHeight + BG.BGNext.AuctionBidUI.layout.gap
        test.eq(extra, 58, "the extension height is region + gap")
        local h = BG.BGNext.AuctionBidUI and BG.BGNext.AuctionBidUI.layout.regionHeight + BG.BGNext.AuctionBidUI.layout.gap
        test.eq(wa.GetFrameTotolHeight(3), 330 + 58, "one non-small card among the first two adds one extension")
    end

    -- ---------------------------------------------------------------------
    -- Fix 8: gen2 frames get no region, no state, and send nothing.
    -- ---------------------------------------------------------------------
    do
        local RT = resetEnv()
        local f = newBidFrame({ isGen2 = true })
        BG.HookCreateAuction(f)
        test.eq(f["BGNextAutoBid"], nil, "a gen2 frame is never given auto-bid state")
        test.eq(#sent, 0, "a gen2 frame sends nothing")
    end

    -- ---------------------------------------------------------------------
    -- Fix 5: opening bid is the start price; leadership only after my echo.
    -- ---------------------------------------------------------------------
    do
        local RT = resetEnv()
        local f = newBidFrame({ auctionID = 12, itemID = 123, money = 100, player = nil })
        BG.HookCreateAuction(f)
        local st = armFrame(f, "100", "1000")

        test.eq(st.sm.status, "armed", "arming succeeds")
        test.eq(#sent, 1, "arming sends exactly one message")
        test.eq(sent[1].message, "SendMyMoney,12,100", "the opening bid is the start price, not start+increment")
        test.eq(sent[1].distribution, "RAID", "the send goes out on the RAID distribution")
        test.eq(st.sm.leading, false, "a send alone never claims leadership")

        -- My own bid echoes back and confirms leadership without a second send.
        bidMsg("BiaoGeAuction", "SendMyMoney,12,100", "RAID", nil, "Me-TestRealm")
        test.eq(st.sm.leading, true, "my own echo confirms leadership")
        test.eq(#sent, 1, "the echo does not send another message")
        test.eq(BG.BGNext.ControlledAutoBid.statusText(st.sm), "当前本人领先", "the status reports leading")
    end

    -- ---------------------------------------------------------------------
    -- Fix 5 (cross-realm self) and Fix 2 (fail-closed sender source).
    -- ---------------------------------------------------------------------
    do
        local RT = resetEnv()
        -- Cross-realm self-leading: my own full name as current bidder holds.
        local selfFrame = newBidFrame({ auctionID = 12, itemID = 123, money = 500, player = "Me-TestRealm" })
        BG.HookCreateAuction(selfFrame)
        local selfSt = armFrame(selfFrame, "100", "1000")
        test.eq(selfSt.sm.status, "armed", "arming against my own cross-realm name is allowed")
        test.eq(selfSt.sm.leading, true, "cross-realm self is recognised as leading")
        test.eq(#sent, 0, "cross-realm self-leading never outbids itself")

        -- A different-realm lookalike is outbid, not confused with self.
        local foreign = newBidFrame({ auctionID = 12, itemID = 124, money = 500, player = "Me-OtherRealm" })
        BG.HookCreateAuction(foreign)
        local foreignSt = armFrame(foreign, "100", "1000")
        test.eq(#sent, 1, "a same short name on another realm is outbid")
        test.eq(sent[1].message, "SendMyMoney,12,600", "the counter-bid is one increment over the foreign bid")
    end

    -- ---------------------------------------------------------------------
    -- Fix 2: distribution/sender/membership all fail closed.
    -- ---------------------------------------------------------------------
    do
        local RT = resetEnv()
        local f = newBidFrame({ auctionID = 12, itemID = 123, money = 100, player = "Other-TestRealm" })
        BG.HookCreateAuction(f)
        local st = armFrame(f, "100", "1000")
        test.eq(#sent, 1, "arming against another bidder sends the counter")

        -- Non-RAID distribution stops.
        bidMsg("BiaoGeAuction", "SendMyMoney,12,300", "PARTY", nil, "Other-TestRealm")
        test.eq(st.sm.status, "protocol", "a non-RAID message stops the auto-bid")

        -- Re-arm, then a message with no sender (arg5 nil, arg4 bogus) stops.
        local f2 = newBidFrame({ auctionID = 12, itemID = 125, money = 100, player = "Other-TestRealm" })
        BG.HookCreateAuction(f2)
        local st2 = armFrame(f2, "100", "1000")
        local before = #sent
        bidMsg("BiaoGeAuction", "SendMyMoney,12,300", "RAID", "NotAPlayer", nil)
        test.eq(st2.sm.status, "protocol", "a missing sender fails closed")
        test.eq(#sent, before, "no send is attempted for an unconfirmable sender")

        -- Re-arm, then a sender who is not a raid member stops.
        local f3 = newBidFrame({ auctionID = 12, itemID = 126, money = 100, player = "Other-TestRealm" })
        BG.HookCreateAuction(f3)
        local st3 = armFrame(f3, "100", "1000")
        bidMsg("BiaoGeAuction", "SendMyMoney,12,300", "RAID", nil, "Stranger-TestRealm")
        test.eq(st3.sm.status, "protocol", "a sender outside the raid fails closed")
    end

    -- ---------------------------------------------------------------------
    -- Fix 3: single active auction — arming B atomically stops A.
    -- ---------------------------------------------------------------------
    do
        local RT = resetEnv()
        local a = newBidFrame({ auctionID = 12, itemID = 123, money = 100, player = nil })
        local b = newBidFrame({ auctionID = 13, itemID = 130, money = 100, player = nil })
        BG.HookCreateAuction(a)
        BG.HookCreateAuction(b)
        local stA = armFrame(a, "100", "1000")
        test.eq(stA.sm.status, "armed", "A is armed")

        -- Give A a pending (throttled) bid and a live timer, then arm B.
        clock = 0.5
        bidMsg("BiaoGeAuction", "SendMyMoney,12,200", "RAID", nil, "Other-TestRealm")
        test.eq(stA.pendingAmount ~= nil, true, "A holds a pending amount while throttled")
        test.eq(stA.pendingTimer ~= nil, true, "A holds a pending timer while throttled")
        local aTimer = stA.pendingTimer

        local stB = armFrame(b, "100", "1000")
        test.eq(stA.sm.status, "idle", "arming B stops A")
        test.eq(stA.pendingAmount, nil, "arming B clears A's pending amount")
        test.eq(stA.pendingTimer, nil, "arming B clears A's pending timer")
        test.eq(aTimer.canceled, true, "arming B cancels A's pending timer")
        test.eq(stB.sm.status, "armed", "B is armed")
        test.eq(sent[#sent].message, "SendMyMoney,13,100", "B opens at its own start price")
    end

    -- ---------------------------------------------------------------------
    -- Fix 4: precise end matching — wrong/nil link never stops; the right one does.
    -- ---------------------------------------------------------------------
    do
        local RT = resetEnv()
        local f = newBidFrame({ auctionID = 12, itemID = 123, link = "item:123", money = 100, player = nil })
        BG.HookCreateAuction(f)
        local st = armFrame(f, "100", "1000")

        -- A parallel end for a different item must not stop this one.
        RT.onAuctionEnd(1, "item:999", nil, nil)
        test.eq(st.sm.status, "armed", "a parallel end for another link does not stop")

        -- The active auction's own end stops it.
        RT.onAuctionEnd(1, "item:123", nil, nil)
        test.eq(st.sm.status, "ended", "the matching link ends the auction")

        -- A nil link (unconfirmable) fails closed.
        local g = newBidFrame({ auctionID = 13, itemID = 131, link = "item:131", money = 100, player = nil })
        BG.HookCreateAuction(g)
        local stG = armFrame(g, "100", "1000")
        RT.onAuctionEnd(1, nil, nil, nil)
        test.eq(stG.sm.status, "protocol", "a nil-link end fails closed")
    end

    -- ---------------------------------------------------------------------
    -- Fix 6: cancelable timer + throttle floor + coalescing + generation token.
    -- ---------------------------------------------------------------------
    do
        local RT = resetEnv()
        local f = newBidFrame({ auctionID = 12, itemID = 123, money = 100, player = nil })
        BG.HookCreateAuction(f)
        local st = armFrame(f, "100", "1000")
        test.eq(#sent, 1, "the opening bid went out at t=0")

        -- Two rapid outbids inside the throttle window coalesce into one timer.
        clock = 0.1
        bidMsg("BiaoGeAuction", "SendMyMoney,12,200", "RAID", nil, "Other-TestRealm")
        clock = 0.2
        bidMsg("BiaoGeAuction", "SendMyMoney,12,300", "RAID", nil, "Other-TestRealm")
        test.eq(#timers, 1, "rapid outbids schedule a single coalesced timer")
        test.eq(st.pendingAmount, 400, "the pending amount is the latest counter-bid")

        -- Fire the coalesced timer: only the latest amount is sent.
        clock = 1.0
        timers[1].fn()
        test.eq(#sent, 2, "the coalesced timer sends once")
        test.eq(sent[2].message, "SendMyMoney,12,400", "only the latest amount is sent, not the stale one")

        -- Generation token: a stale timer that outlived a stop never sends.
        clock = 1.1
        bidMsg("BiaoGeAuction", "SendMyMoney,12,500", "RAID", nil, "Other-TestRealm")
        test.eq(#timers, 2, "a fresh outbid schedules a new timer")
        local staleTimer = timers[2]
        local sentBefore = #sent
        RT.onLogout() -- stop + cancel + generation bump
        test.eq(staleTimer.canceled, true, "stopping cancels the pending timer")
        staleTimer.fn() -- even if it fired anyway, the token guard blocks the send
        test.eq(#sent, sentBefore, "a stale timer after stop never sends")
    end

    -- ---------------------------------------------------------------------
    -- Fix 12: pcall-guarded send — a throw stops and never claims leadership.
    -- ---------------------------------------------------------------------
    do
        local RT = resetEnv()
        local f = newBidFrame({ auctionID = 12, itemID = 123, money = 100, player = nil })
        BG.HookCreateAuction(f)
        local st = armFrame(f, "100", "1000")
        test.eq(#sent, 1, "the first send succeeds")

        -- Force the next send to throw.
        sendError = "disconnected"
        clock = 1.0
        bidMsg("BiaoGeAuction", "SendMyMoney,12,300", "RAID", nil, "Other-TestRealm")
        test.eq(st.sm.status, "send-failed", "a throwing send stops with send-failed")
        test.eq(st.sm.leading, false, "a failed send never claims leadership")
        test.eq(BG.BGNext.ControlledAutoBid.statusText(st.sm), "发送失败", "the send-failed state has its text")
    end

    -- ---------------------------------------------------------------------
    -- Fix 9: mutual exclusion with the built-in auto-bid.
    -- ---------------------------------------------------------------------
    do
        local RT = resetEnv()
        local blocked = newBidFrame({ auctionID = 12, itemID = 123, money = 100, player = nil, isAuto = true })
        BG.HookCreateAuction(blocked)
        local stBlocked = blocked["BGNextAutoBid"]
        test.eq(stBlocked.region.button.enabled, false, "the built-in auto-bid disables my arm button")
        stBlocked.region.button.scripts.OnClick(stBlocked.region.button)
        test.eq(stBlocked.sm.status, "idle", "clicking while built-in is on does not arm")
        test.eq(#sent, 0, "no message is sent while the built-in auto-bid is on")

        -- Arm normally, then the built-in toggles on and stops mine.
        local f = newBidFrame({ auctionID = 13, itemID = 130, money = 100, player = nil, isAuto = false })
        BG.HookCreateAuction(f)
        local st = armFrame(f, "100", "1000")
        test.eq(st.sm.status, "armed", "my feature arms while the built-in is off")
        wa.AutoButton_OnClick({ owner = f }) -- user clicks the built-in auto button
        test.eq(st.sm.status, "idle", "turning the built-in on stops my auto-bid")
        test.eq(f.isAuto, true, "the built-in auto-bid is now on")
    end

    -- ---------------------------------------------------------------------
    -- Fix 7: the complete stop set — manual, hidden, leave, reload.
    -- ---------------------------------------------------------------------
    do
        local RT = resetEnv()

        -- Manual stop via the toggle button.
        local manual = newBidFrame({ auctionID = 12, itemID = 123, money = 100, player = nil })
        BG.HookCreateAuction(manual)
        local stManual = armFrame(manual, "100", "1000")
        test.eq(stManual.sm.status, "armed", "manual frame arms")
        stManual.region.button.scripts.OnClick(stManual.region.button)
        test.eq(stManual.sm.status, "stopped", "a second click stops manually")

        -- Frame hidden/closes.
        local hidden = newBidFrame({ auctionID = 13, itemID = 130, money = 100, player = nil })
        BG.HookCreateAuction(hidden)
        local stHidden = armFrame(hidden, "100", "1000")
        hidden:Fire("OnHide")
        test.eq(stHidden.sm.status, "idle", "hiding the frame stops the auto-bid")

        -- Leaving the group.
        local left = newBidFrame({ auctionID = 14, itemID = 140, money = 100, player = nil })
        BG.HookCreateAuction(left)
        local stLeft = armFrame(left, "100", "1000")
        inRaid = false
        RT.onRosterUpdate()
        test.eq(stLeft.sm.status, "idle", "leaving the group stops the auto-bid")

        -- World switch / reload / logout.
        local logout = newBidFrame({ auctionID = 15, itemID = 150, money = 100, player = nil })
        BG.HookCreateAuction(logout)
        local stLogout = armFrame(logout, "100", "1000")
        RT.onLeavingWorld()
        test.eq(stLogout.sm.status, "idle", "leaving the world stops the auto-bid")

        local reload = newBidFrame({ auctionID = 16, itemID = 160, money = 100, player = nil })
        BG.HookCreateAuction(reload)
        local stReload = armFrame(reload, "100", "1000")
        RT.onLogout()
        test.eq(stReload.sm.status, "idle", "logout stops the auto-bid")
    end
end
