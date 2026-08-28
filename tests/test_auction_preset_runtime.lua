-- Runtime integration test for the controlled auto-bid (second review round).
--
-- This test injects fake WoW APIs into _G and drives the REAL
-- Core/BGNext/AuctionPresetRuntime.lua — no source scanning. Every assertion
-- observes the state the runtime actually creates on the bid frame and the
-- messages it actually hands to C_ChatInfo.SendAddonMessage. It covers the eight
-- second-round items: (1) CHAT_MSG_ADDON sender = 4th arg, (2) the
-- SendAddonMessage result enum, (3) cross-realm team names via GetUnitName,
-- (4) creating a new auction never stops the current one, (5) AuctionEnd matched
-- by auctionID not link, (6) collapse/Gen2 layout, (7) unrelated addon messages
-- ignored, (8) FontString sizes applied — plus the retained regressions (hook
-- chaining, throttle, mutual exclusion, stop set).
return function(test)
    local sent, timers, clock, sendError, sendResult, inRaid
    local init2Callbacks, registeredEvents, probe

    -- A minimal fake UI widget: every method the runtime calls records just
    -- enough for assertions (text, enabled state, size/justify, scripts, hooks,
    -- show/hide).
    local function widget()
        local w = {
            text = "", enabled = true, scripts = {}, hooks = {},
            size = nil, justifyH = nil, justifyV = nil, hidden = false,
        }
        function w:SetText(t) self.text = t end
        function w:GetText() return self.text end
        function w:SetTextColor(r, g, b) end
        function w:SetPoint(...) end
        function w:SetSize(w_, h) self.size = { w = w_, h = h } end
        function w:SetWidth(w_) self.size = self.size or {}; self.size.w = w_ end
        function w:SetHeight(h) self.size = self.size or {}; self.size.h = h end
        function w:SetJustifyH(h) self.justifyH = h end
        function w:SetJustifyV(v) self.justifyV = v end
        function w:SetNumeric(v) self.numeric = v end
        function w:SetAutoFocus(v) end
        function w:SetEnabled(v) self.enabled = v end
        function w:IsEnabled() return self.enabled end
        function w:Enable() self.enabled = true end
        function w:Disable() self.enabled = false end
        function w:Show() self.hidden = false end
        function w:Hide() self.hidden = true end
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
        sendResult = opts.sendResult -- nil = old-client (returns nothing)
        inRaid = true
        init2Callbacks = {}
        registeredEvents = {}
        probe = { create = 0, ended = 0 }

        _G.GetTimePreciseSec = function() return clock end
        _G.GetTime = function() return clock end
        _G.GetRealmName = function() return "Test Realm" end
        _G.IsInRaid = function() return inRaid end
        _G.GetNumGroupMembers = function() return 3 end
        if opts.noGetUnitName then
            _G.GetUnitName = nil
        else
            _G.GetUnitName = function(unit, includeRealm)
                if unit == "player" then return "Me-TestRealm" end
                if unit == "raid1" then return "Other-TestRealm" end
                if unit == "raid2" then return "Alice-OtherRealm" end
                return nil
            end
        end
        _G.UnitName = function(unit)
            if unit == "player" then return "Me", "TestRealm" end
            if unit == "raid1" then return "Other", "TestRealm" end
            if unit == "raid2" then return "Alice", "OtherRealm" end
            return nil, nil
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
                return sendResult
            end,
            RegisterAddonMessagePrefix = function() end,
        }

        _G.wa = {
            GN = function() return opts.selfName or "Me" end,
            GetFrameTotolHeight = function(count) return count * 110 end,
            AutoButton_OnClick = function(self)
                if self and self.owner then
                    self.owner.isAuto = true
                    self.owner.hide:Disable()
                end
            end,
            Hide_OnClick = function(self)
                local f = self and self.owner
                if f and f.hide and f.hide:IsEnabled() then
                    f.IsSmallWindow = not f.IsSmallWindow
                end
            end,
        }
        _G.BGA = { Frames = {} }

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
        f.IsSmallWindow = opts.IsSmallWindow or false
        f.hide = widget()
        BGA.Frames[#BGA.Frames + 1] = f
        return f
    end

    local function attachFrame(f)
        BG.HookCreateAuction(f)
        return f["BGNextAutoBid"]
    end

    local function armFrame(f, increment, cap)
        local st = f["BGNextAutoBid"]
        st.region.incrementEdit:SetText(increment)
        st.region.capEdit:SetText(cap)
        st.region.button.scripts.OnClick(st.region.button)
        return st
    end

    -- CHAT_MSG_ADDON payload: prefix, text, channel, sender (4th), target (5th).
    local function bidMsg(prefix, message, distribution, sender, target)
        registeredEvents.CHAT_MSG_ADDON(nil, "CHAT_MSG_ADDON", prefix, message, distribution, sender, target)
    end

    -- ---------------------------------------------------------------------
    -- Regression: hooks chain in BG.Init2, never overwrite, never double-wrap.
    -- ---------------------------------------------------------------------
    do
        resetEnv()
        test.eq(#init2Callbacks, 1, "the runtime registers exactly one Init2 callback")

        local createBefore = BG.HookCreateAuction
        local endBefore = BG.AuctionWAEnd
        for _, fn in ipairs(init2Callbacks) do fn() end
        test.eq(BG.HookCreateAuction == createBefore, true, "a second Init2 never re-wraps the create hook")
        test.eq(BG.AuctionWAEnd == endBefore, true, "a second Init2 never re-wraps the end hook")

        local f = newBidFrame()
        BG.HookCreateAuction(f)
        test.eq(probe.create, 1, "the original create hook still runs")
        test.eq(f["BGNextAutoBid"] ~= nil, true, "and the runtime state is attached")

        BG.AuctionWAEnd(1, "item:123", nil, nil)
        test.eq(probe.ended, 1, "the original end hook still runs")
    end

    -- ---------------------------------------------------------------------
    -- Fix 1: the sender is the FOURTH CHAT_MSG_ADDON argument.
    -- ---------------------------------------------------------------------
    do
        resetEnv()
        local f = newBidFrame({ auctionID = 12, money = 100, player = nil })
        attachFrame(f)
        local st = armFrame(f, "100", "1000")
        test.eq(st.sm.status, "armed", "arming sends the opening bid")
        test.eq(#sent, 1, "one message was sent")

        -- My own echo: sender in the 4th position confirms leadership; the 5th
        -- (target) is ignored.
        bidMsg("BiaoGeAuction", "SendMyMoney,12,100", "RAID", "Me-TestRealm", "SomeTarget")
        test.eq(st.sm.leading, true, "the sender (4th arg) echo confirms leadership")
        test.eq(#sent, 1, "my own echo never re-sends")
    end

    -- ---------------------------------------------------------------------
    -- Fix 2: SendAddonMessage result enum — Success / non-Success / throw / old nil.
    -- ---------------------------------------------------------------------
    do
        -- (a) new-client Success (enum value 0) → markSent, still armed.
        resetEnv({ sendResult = 0 })
        _G.Enum = { SendAddonMessageResult = { Success = 0, Failure = 1 } }
        local fa = newBidFrame({ auctionID = 12, money = 100, player = nil })
        attachFrame(fa)
        local stA = armFrame(fa, "100", "1000")
        test.eq(stA.sm.status, "armed", "a Success result keeps the auto-bid armed")
        test.eq(stA.sm.lastBidAt, 0, "a Success result advances the send time (markSent)")

        -- (b) non-Success (enum value 1) → send-failed, no markSent.
        resetEnv({ sendResult = 1 })
        _G.Enum = { SendAddonMessageResult = { Success = 0, Failure = 1 } }
        local fb = newBidFrame({ auctionID = 12, money = 100, player = nil })
        attachFrame(fb)
        local stB = armFrame(fb, "100", "1000")
        test.eq(stB.sm.status, "send-failed", "a non-Success result stops with send-failed")
        test.eq(stB.sm.lastBidAt, nil, "a non-Success result never claims a send (no markSent)")
        test.eq(stB.sm.leading, false, "a non-Success result never claims leadership")

        -- (c) throw → send-failed.
        resetEnv()
        sendError = "disconnected"
        local fc = newBidFrame({ auctionID = 12, money = 100, player = nil })
        attachFrame(fc)
        local stC = armFrame(fc, "100", "1000")
        test.eq(stC.sm.status, "send-failed", "a throwing send stops with send-failed")
        test.eq(stC.sm.lastBidAt, nil, "a throwing send never claims a send (no markSent)")

        -- (d) old client returns nil → treated as legacy success, not an error.
        resetEnv() -- no Enum, sendResult nil
        _G.Enum = nil
        local fd = newBidFrame({ auctionID = 12, money = 100, player = nil })
        attachFrame(fd)
        local stD = armFrame(fd, "100", "1000")
        test.eq(stD.sm.status, "armed", "an old-client nil return is a legacy success")
        test.eq(stD.sm.lastBidAt, 0, "an old-client nil return still advances the send time")
    end

    -- ---------------------------------------------------------------------
    -- Fix 3: cross-realm team names — GetUnitName(unit, true) + UnitName fallback.
    -- ---------------------------------------------------------------------
    do
        -- GetUnitName path: "Alice-OtherRealm" is a distinct raid member; the bare
        -- "Alice" (my realm) is a different player and fails closed.
        resetEnv()
        local f = newBidFrame({ auctionID = 12, money = 500, player = "Alice-OtherRealm" })
        attachFrame(f)
        local st = armFrame(f, "100", "1000")
        test.eq(st.sm.status, "armed", "arming against a cross-realm member is allowed")

        -- "Alice" (same short name, my realm) is NOT the raid member "Alice-OtherRealm".
        local before = #sent
        bidMsg("BiaoGeAuction", "SendMyMoney,12,600", "RAID", "Alice-TestRealm", nil)
        test.eq(st.sm.status, "protocol", "a same-short-name different-realm sender fails closed")
        test.eq(#sent, before, "no send for a sender not in the raid")

        -- UnitName double-return fallback: GetUnitName absent, realm combined from
        -- the second return value (empty realm → own realm).
        resetEnv({ noGetUnitName = true })
        local g = newBidFrame({ auctionID = 12, money = 500, player = "Alice-OtherRealm" })
        attachFrame(g)
        local stG = armFrame(g, "100", "1000")
        bidMsg("BiaoGeAuction", "SendMyMoney,12,600", "RAID", "Alice-OtherRealm", nil)
        test.eq(stG.sm.status, "armed", "the UnitName double-return fallback recognises the cross-realm member")
    end

    -- ---------------------------------------------------------------------
    -- Fix 4: creating a new auction must NOT stop the current one; only arming B stops A.
    -- ---------------------------------------------------------------------
    do
        resetEnv()
        local a = newBidFrame({ auctionID = 12, money = 100, player = nil })
        local b = newBidFrame({ auctionID = 13, money = 100, player = nil })
        attachFrame(a)
        local stA = armFrame(a, "100", "1000")
        test.eq(stA.sm.status, "armed", "A is armed")

        -- Merely creating (attaching) B leaves A armed.
        attachFrame(b)
        test.eq(stA.sm.status, "armed", "creating B does not stop A")
        test.eq(b["BGNextAutoBid"] ~= nil, true, "B got its own state")

        -- Arming B atomically stops A.
        local stB = armFrame(b, "100", "1000")
        test.eq(stA.sm.status, "idle", "arming B stops A")
        test.eq(stB.sm.status, "armed", "B is armed")
        test.eq(sent[#sent].message, "SendMyMoney,13,100", "B opens at its own start price")
    end

    -- ---------------------------------------------------------------------
    -- Fix 5: AuctionEnd is matched by auctionID, not by item link.
    -- ---------------------------------------------------------------------
    do
        resetEnv()
        -- Two frames share a link but have different auction ids (parallel auctions
        -- of the same item).
        local f = newBidFrame({ auctionID = 12, link = "item:999", money = 100, player = nil })
        attachFrame(f)
        local st = armFrame(f, "100", "1000")
        test.eq(st.sm.status, "armed", "the active auction is armed")

        -- Same link, different auctionID → must not stop.
        local RT = BG.BGNext.AuctionPresetRuntime
        RT.onAuctionEnd(1, "item:999", nil, nil, nil, 99)
        test.eq(st.sm.status, "armed", "an end for the same link but a different auctionID does not stop")

        -- The exact auctionID stops it.
        RT.onAuctionEnd(1, "item:999", nil, nil, nil, 12)
        test.eq(st.sm.status, "ended", "the matching auctionID ends the auction")

        -- A nil auctionID (unconfirmable) fails closed.
        local g = newBidFrame({ auctionID = 13, link = "item:131", money = 100, player = nil })
        attachFrame(g)
        local stG = armFrame(g, "100", "1000")
        RT.onAuctionEnd(1, "item:131", nil, nil, nil, nil)
        test.eq(stG.sm.status, "protocol", "a nil-auctionID end fails closed")
    end

    -- ---------------------------------------------------------------------
    -- Fix 6: collapse & Gen2 layout — collapse lock, region visibility, stack height.
    -- ---------------------------------------------------------------------
    do
        -- (a) while armed the collapse button is disabled; on stop it is restored.
        resetEnv()
        local f = newBidFrame({ auctionID = 12, money = 100, player = nil })
        attachFrame(f)
        local st = armFrame(f, "100", "1000")
        test.eq(f.hide.enabled, false, "arming disables the collapse button")
        test.eq(st.region.hidden, false, "the region is shown while armed (expanded)")

        -- The disabled collapse button blocks the collapse (fake Hide_OnClick no-ops).
        wa.Hide_OnClick({ owner = f })
        test.eq(f.IsSmallWindow, false, "a disabled collapse button cannot collapse the card")
        test.eq(st.region.hidden, false, "the region stays visible while armed")

        -- Manual stop restores the collapse button.
        st.region.button.scripts.OnClick(st.region.button)
        test.eq(f.hide.enabled, true, "stopping restores the collapse button")

        -- Now the collapse button works and hides the region; expand re-shows it.
        wa.Hide_OnClick({ owner = f })
        test.eq(f.IsSmallWindow, true, "collapse toggles the card to small")
        test.eq(st.region.hidden, true, "collapsing hides the region")
        wa.Hide_OnClick({ owner = f })
        test.eq(f.IsSmallWindow, false, "expand toggles the card back")
        test.eq(st.region.hidden, false, "expanding re-shows the region")

        -- (b) stack height: only an EXPANDED Gen1 card with a region adds height.
        local RT = resetEnv()
        local expanded = newBidFrame({ auctionID = 12 })
        attachFrame(expanded) -- IsSmallWindow = false, has region
        local collapsed = newBidFrame({ auctionID = 13 })
        attachFrame(collapsed)
        collapsed.IsSmallWindow = true -- still has a region, but collapsed
        local gen2 = newBidFrame({ auctionID = 14, isGen2 = true })
        attachFrame(gen2) -- no region

        local extra = BG.BGNext.AuctionBidUI.layout.regionHeight + BG.BGNext.AuctionBidUI.layout.gap
        test.eq(extra, 58, "the extension height is region + gap")
        -- count=4 iterates frames 1..3; only the expanded Gen1 frame adds extra.
        test.eq(wa.GetFrameTotolHeight(4), 4 * 110 + 58, "only the expanded Gen1 card adds height")
        test.eq(gen2["BGNextAutoBid"], nil, "a gen2 frame has no region/state")
        test.eq(wa.GetFrameTotolHeight(1), 110, "a single frame (no prior cards) adds nothing")
    end

    -- ---------------------------------------------------------------------
    -- Regression: reaching the cap is terminal and releases runtime resources
    -- without overwriting the visible `cap` status.
    -- ---------------------------------------------------------------------
    do
        -- The starting price is already above the cap: never become the active
        -- frame and never acquire the collapse lock.
        resetEnv()
        local atArm = newBidFrame({ auctionID = 12, money = 1100, player = nil })
        attachFrame(atArm)
        local armState = armFrame(atArm, "100", "1000")
        test.eq(armState.sm.status, "cap", "arming above the cap preserves the cap terminal state")
        test.eq(atArm.hide.enabled, true, "arming above the cap never leaves a collapse lock")
        inRaid = false
        BG.BGNext.AuctionPresetRuntime.onRosterUpdate()
        test.eq(armState.sm.status, "cap", "a cap-at-arm frame is no longer the active runtime frame")

        -- A queued counter-bid exists, then a newer price makes the next bid
        -- exceed the cap. The queued timer must be cancelled and the active
        -- runtime ownership released while status remains `cap`.
        resetEnv()
        local afterPrice = newBidFrame({ auctionID = 12, money = 100, player = nil })
        attachFrame(afterPrice)
        local priceState = armFrame(afterPrice, "100", "1000")
        clock = 0.1
        bidMsg("BiaoGeAuction", "SendMyMoney,12,200", "RAID", "Other-TestRealm", nil)
        test.eq(#timers, 1, "an early counter-bid is queued before the cap event")
        clock = 0.2
        bidMsg("BiaoGeAuction", "SendMyMoney,12,950", "RAID", "Other-TestRealm", nil)
        test.eq(priceState.sm.status, "cap", "an outbid beyond the next allowed amount reaches cap")
        test.eq(timers[1].canceled, true, "reaching cap cancels the queued send")
        test.eq(priceState.pendingTimer, nil, "reaching cap clears the queued timer reference")
        test.eq(priceState.pendingAmount, nil, "reaching cap clears the queued amount")
        test.eq(afterPrice.hide.enabled, true, "reaching cap releases the BGNext collapse lock")
        inRaid = false
        BG.BGNext.AuctionPresetRuntime.onRosterUpdate()
        test.eq(priceState.sm.status, "cap", "later runtime stop events do not overwrite the cap status")
    end

    -- ---------------------------------------------------------------------
    -- Fix 7: unrelated addon messages are ignored before any fail-closed check.
    -- ---------------------------------------------------------------------
    do
        resetEnv()
        local f = newBidFrame({ auctionID = 12, money = 100, player = "Other-TestRealm" })
        attachFrame(f)
        local st = armFrame(f, "100", "1000")
        test.eq(st.sm.status, "armed", "the auto-bid is armed")

        -- A foreign addon's PARTY/WHISPER message must NOT stop the auto-bid.
        bidMsg("OtherAddon", "SendMyMoney,12,300", "PARTY", "Other-TestRealm", nil)
        test.eq(st.sm.status, "armed", "an unrelated prefix on PARTY is ignored")
        bidMsg("OtherAddon", "SendMyMoney,12,300", "WHISPER", "Other-TestRealm", nil)
        test.eq(st.sm.status, "armed", "an unrelated prefix on WHISPER is ignored")

        -- A BiaoGeAuction message that is not SendMyMoney is ignored too.
        bidMsg("BiaoGeAuction", "VersionCheck,12,300", "PARTY", nil, nil)
        test.eq(st.sm.status, "armed", "a VersionCheck opcode is ignored even on PARTY")

        -- But a real SendMyMoney on a non-RAID distribution fails closed.
        bidMsg("BiaoGeAuction", "SendMyMoney,12,300", "PARTY", "Other-TestRealm", nil)
        test.eq(st.sm.status, "protocol", "a BiaoGeAuction SendMyMoney on PARTY stops")

        -- And a SendMyMoney with no sender fails closed.
        resetEnv()
        local g = newBidFrame({ auctionID = 12, money = 100, player = "Other-TestRealm" })
        attachFrame(g)
        local stG = armFrame(g, "100", "1000")
        bidMsg("BiaoGeAuction", "SendMyMoney,12,300", "RAID", nil, nil)
        test.eq(stG.sm.status, "protocol", "a SendMyMoney with a missing sender fails closed")
    end

    -- ---------------------------------------------------------------------
    -- Fix 8: the label/status FontStrings actually receive their rect sizes + justify.
    -- ---------------------------------------------------------------------
    do
        resetEnv()
        local f = newBidFrame({ auctionID = 12, money = 100, player = nil })
        attachFrame(f)
        local st = f["BGNextAutoBid"]
        local L = BG.BGNext.AuctionBidUI.layout
        local R = BG.BGNext.AuctionBidUI.rects()

        test.eq(st.region.incrementLabel.size ~= nil, true, "the increment label got a SetSize")
        test.eq(st.region.incrementLabel.size.w, R.incrementLabel.w, "the increment label uses its rect width")
        test.eq(st.region.incrementLabel.size.h, R.incrementLabel.h, "the increment label uses its rect height")
        test.eq(st.region.incrementLabel.justifyH, "LEFT", "the increment label is left-justified")
        test.eq(st.region.incrementLabel.justifyV, "MIDDLE", "the increment label is middle-justified")

        test.eq(st.region.capLabel.size.w, R.capLabel.w, "the cap label uses its rect width")
        test.eq(st.region.capLabel.size.h, R.capLabel.h, "the cap label uses its rect height")
        test.eq(st.region.capLabel.justifyH, "LEFT", "the cap label is left-justified")

        test.eq(st.region.statusText.size.w, R.status.w, "the status text uses its rect width")
        test.eq(st.region.statusText.size.h, R.status.h, "the status text uses its rect height")
        test.eq(st.region.statusText.justifyH, "LEFT", "the status text is left-justified")
        test.eq(st.region.statusText.justifyV, "MIDDLE", "the status text is middle-justified")

        test.eq(L.labelWidth, 64, "the label width is explicit")
    end

    -- ---------------------------------------------------------------------
    -- Regression: throttle floor + coalescing + generation token.
    -- ---------------------------------------------------------------------
    do
        resetEnv()
        local f = newBidFrame({ auctionID = 12, money = 100, player = nil })
        attachFrame(f)
        local st = armFrame(f, "100", "1000")
        test.eq(#sent, 1, "the opening bid went out at t=0")

        clock = 0.1
        bidMsg("BiaoGeAuction", "SendMyMoney,12,200", "RAID", "Other-TestRealm", nil)
        clock = 0.2
        bidMsg("BiaoGeAuction", "SendMyMoney,12,300", "RAID", "Other-TestRealm", nil)
        test.eq(#timers, 1, "rapid outbids schedule a single coalesced timer")
        test.eq(st.pendingAmount, 400, "the pending amount is the latest counter-bid")

        clock = 1.0
        timers[1].fn()
        test.eq(#sent, 2, "the coalesced timer sends once")
        test.eq(sent[2].message, "SendMyMoney,12,400", "only the latest amount is sent")

        clock = 1.1
        bidMsg("BiaoGeAuction", "SendMyMoney,12,500", "RAID", "Other-TestRealm", nil)
        local staleTimer = timers[2]
        local sentBefore = #sent
        BG.BGNext.AuctionPresetRuntime.onLogout()
        test.eq(staleTimer.canceled, true, "stopping cancels the pending timer")
        staleTimer.fn()
        test.eq(#sent, sentBefore, "a stale timer after stop never sends")
    end

    -- ---------------------------------------------------------------------
    -- Regression: mutual exclusion with the built-in auto-bid.
    -- ---------------------------------------------------------------------
    do
        resetEnv()
        local blocked = newBidFrame({ auctionID = 12, money = 100, player = nil, isAuto = true })
        attachFrame(blocked)
        local stBlocked = blocked["BGNextAutoBid"]
        test.eq(stBlocked.region.button.enabled, false, "the built-in auto-bid disables my arm button")
        stBlocked.region.button.scripts.OnClick(stBlocked.region.button)
        test.eq(stBlocked.sm.status, "idle", "clicking while built-in is on does not arm")

        local f = newBidFrame({ auctionID = 13, money = 100, player = nil, isAuto = false })
        attachFrame(f)
        local st = armFrame(f, "100", "1000")
        test.eq(st.sm.status, "armed", "my feature arms while the built-in is off")
        wa.AutoButton_OnClick({ owner = f })
        test.eq(st.sm.status, "idle", "turning the built-in on stops my auto-bid")
        test.eq(f.hide.enabled, false, "the built-in auto-bid retains ownership of the collapse lock")
    end

    -- ---------------------------------------------------------------------
    -- Regression: gen2 frames get no region, no state, and send nothing.
    -- ---------------------------------------------------------------------
    do
        resetEnv()
        local f = newBidFrame({ isGen2 = true })
        attachFrame(f)
        test.eq(f["BGNextAutoBid"], nil, "a gen2 frame is never given auto-bid state")
        test.eq(#sent, 0, "a gen2 frame sends nothing")
    end

    -- ---------------------------------------------------------------------
    -- Regression: the complete stop set — manual, hidden, leave, reload.
    -- ---------------------------------------------------------------------
    do
        resetEnv()
        local manual = newBidFrame({ auctionID = 12, money = 100, player = nil })
        attachFrame(manual)
        local stManual = armFrame(manual, "100", "1000")
        stManual.region.button.scripts.OnClick(stManual.region.button)
        test.eq(stManual.sm.status, "stopped", "a second click stops manually")

        local hidden = newBidFrame({ auctionID = 13, money = 100, player = nil })
        attachFrame(hidden)
        local stHidden = armFrame(hidden, "100", "1000")
        hidden:Fire("OnHide")
        test.eq(stHidden.sm.status, "idle", "hiding the frame stops the auto-bid")

        local left = newBidFrame({ auctionID = 14, money = 100, player = nil })
        attachFrame(left)
        local stLeft = armFrame(left, "100", "1000")
        inRaid = false
        BG.BGNext.AuctionPresetRuntime.onRosterUpdate()
        test.eq(stLeft.sm.status, "idle", "leaving the group stops the auto-bid")

        local logout = newBidFrame({ auctionID = 15, money = 100, player = nil })
        attachFrame(logout)
        local stLogout = armFrame(logout, "100", "1000")
        BG.BGNext.AuctionPresetRuntime.onLogout()
        test.eq(stLogout.sm.status, "idle", "logout stops the auto-bid")
    end
end
