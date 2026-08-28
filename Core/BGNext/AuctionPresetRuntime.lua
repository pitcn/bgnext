BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Runtime wiring for the controlled auto-bid — the only layer that touches WoW
-- APIs. It chains the existing BGLite hooks (installed in BG.Init2, after the
-- auction modules have defined BG.HookCreateAuction / BG.AuctionWAEnd) and
-- registers a CHAT_MSG_ADDON observer. It feeds the pure state machine and turns
-- each `{ bid = amount }` decision into a single gen1 SendMyMoney message.
--
-- All state lives on the bid frame (memory-only) and is lost on reload. Every
-- WoW API is read through the global scope at call time so the unit test can
-- inject fakes and drive this exact file.
local M = {}

local Store = BG.BGNext.AuctionPresetStore
local SM = BG.BGNext.ControlledAutoBid
local Msg = BG.BGNext.AuctionBidMessage
local UI = BG.BGNext.AuctionBidUI
local Names = BG.BGNext.AuctionNames

local ACTIVE_KEY = "BGNextAutoBid"

local activeFrame = nil
local installed = false

-- ---------------------------------------------------------------------------
-- WoW API accessors (call-time lookups, so the tests can swap in fakes)
-- ---------------------------------------------------------------------------

local function now()
    if GetTimePreciseSec then
        return GetTimePreciseSec()
    end
    return GetTime()
end

local function selfRealm()
    if BG and BG.realmName then
        return BG.realmName
    end
    if GetRealmName then
        return GetRealmName():gsub(" ", ""):gsub("-", "")
    end
    return ""
end

local function selfNameRaw()
    if wa and wa.GN then
        return wa.GN()
    end
    if UnitName then
        return UnitName("player")
    end
    return nil
end

local function raidMemberSet()
    local set = {}
    local realm = selfRealm()
    local function add(name)
        local full = Names.fullName(name, realm)
        if full then
            set[full] = true
        end
    end
    if not IsInRaid or not IsInRaid() then
        return set
    end
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    for i = 1, n do
        add(UnitName and UnitName("raid" .. i))
    end
    add(selfNameRaw())
    return set
end

-- ---------------------------------------------------------------------------
-- Per-frame state and UI
-- ---------------------------------------------------------------------------

local function freshState()
    return {
        sm = SM.new(),
        pendingAmount = nil,
        pendingTimer = nil,
        region = nil,
        gen = 0,
    }
end

local function refresh(bidFrame, st)
    local region = st.region
    if not region or not region.button then
        return
    end
    local status = st.sm.status
    region.statusText:SetText(SM.statusText(st.sm))
    region.statusText:SetTextColor(0.8, 0.8, 0.8)
    region.button:SetText(UI.buttonText(status))
    -- Mutual exclusion: my arm button is disabled while the built-in auto-bid is on.
    region.button:SetEnabled(UI.armBlocked(bidFrame) == nil)
    local locked = UI.inputsLocked(status)
    region.incrementEdit:SetEnabled(not locked)
    region.capEdit:SetEnabled(not locked)
end

local function makeRegion(bidFrame)
    local L = UI.layout
    local R = UI.rects()
    local region = CreateFrame("Frame", nil, bidFrame)
    region:SetSize(L.regionWidth, L.regionHeight)
    region:SetPoint("TOP", bidFrame, "BOTTOM", 0, -L.gap)

    local incLabel = region:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    incLabel:SetText(UI.LABELS.increment)
    incLabel:SetPoint("TOPLEFT", region, "TOPLEFT", R.incrementLabel.x, -R.incrementLabel.y)

    local incEdit = CreateFrame("EditBox", nil, region, "InputBoxTemplate")
    incEdit:SetSize(R.incrementEdit.w, R.incrementEdit.h)
    incEdit:SetPoint("TOPLEFT", region, "TOPLEFT", R.incrementEdit.x, -R.incrementEdit.y)
    incEdit:SetNumeric(true)
    incEdit:SetAutoFocus(false)

    local capLabel = region:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    capLabel:SetText(UI.LABELS.cap)
    capLabel:SetPoint("TOPLEFT", region, "TOPLEFT", R.capLabel.x, -R.capLabel.y)

    local capEdit = CreateFrame("EditBox", nil, region, "InputBoxTemplate")
    capEdit:SetSize(R.capEdit.w, R.capEdit.h)
    capEdit:SetPoint("TOPLEFT", region, "TOPLEFT", R.capEdit.x, -R.capEdit.y)
    capEdit:SetNumeric(true)
    capEdit:SetAutoFocus(false)

    local button = CreateFrame("Button", nil, region, "UIPanelButtonTemplate")
    button:SetSize(R.button.w, R.button.h)
    button:SetPoint("TOPLEFT", region, "TOPLEFT", R.button.x, -R.button.y)

    local status = region:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetPoint("TOPLEFT", region, "TOPLEFT", R.status.x, -R.status.y)
    status:SetText("未启用")
    status:SetTextColor(0.8, 0.8, 0.8)

    region.incrementEdit = incEdit
    region.capEdit = capEdit
    region.button = button
    region.statusText = status
    return region
end

-- ---------------------------------------------------------------------------
-- Sending (single coalesced SendMyMoney, cancelable timer, generation guard)
-- ---------------------------------------------------------------------------

local function stopFrame(bidFrame, reason)
    local st = bidFrame and bidFrame[ACTIVE_KEY]
    if not st then
        return
    end
    st.gen = st.gen + 1
    if st.pendingTimer then
        st.pendingTimer:Cancel()
        st.pendingTimer = nil
    end
    st.pendingAmount = nil
    SM.stop(st.sm, reason)
    if activeFrame == bidFrame then
        activeFrame = nil
    end
    refresh(bidFrame, st)
end

local function doSend(bidFrame, st, amount)
    local msg = Msg.buildBidMessage(st.sm.auctionId, amount)
    local ok = pcall(function()
        C_ChatInfo.SendAddonMessage(Msg.ADDON_PREFIX, msg, "RAID")
    end)
    if not ok then
        -- SendAddonMessage threw: fail closed and show an explicit state.
        stopFrame(bidFrame, "send-failed")
        return
    end
    -- The send went out, but SendAddonMessage returns no success signal, so this
    -- only advances the current price for throttle/dedup; leadership is not
    -- claimed until my own bid echoes back.
    SM.markSent(st.sm, now())
    st.pendingAmount = nil
    refresh(bidFrame, st)
end

local function scheduleSend(bidFrame, st, delay)
    st.gen = st.gen + 1
    local myGen = st.gen
    st.pendingTimer = C_Timer.NewTimer(delay, function()
        st.pendingTimer = nil
        if st.gen == myGen and st.sm.status == "armed" and st.pendingAmount ~= nil then
            local amount = st.pendingAmount
            st.pendingAmount = nil
            doSend(bidFrame, st, amount)
        end
    end)
end

local function sendBid(bidFrame, st, amount)
    local s = st.sm
    if SM.canSend(s, now()) then
        doSend(bidFrame, st, amount)
    else
        -- Coalesce rapid outbids into one latest send after the 1s floor (a
        -- single deterministic delay, never a poll loop or randomised sniping).
        st.pendingAmount = amount
        if not st.pendingTimer then
            local remaining = math.max(0.05, SM.MIN_INTERVAL - (now() - (s.lastBidAt or 0)))
            scheduleSend(bidFrame, st, remaining)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Arming / toggling
-- ---------------------------------------------------------------------------

local function arm(bidFrame, st)
    local region = st.region
    if UI.armBlocked(bidFrame) then
        return
    end
    local cfg = UI.readConfig(region.incrementEdit:GetText(), region.capEdit:GetText())
    if cfg.error then
        region.statusText:SetText(UI.errorText(cfg.error))
        region.statusText:SetTextColor(1, 0.3, 0.3)
        return
    end

    -- Persist only the two local config values under BiaoGe.BGNext.auctionPresets.
    if BG.BGNext.DB then
        Store.set(BG.BGNext.DB.auctionPresets, cfg)
    end

    -- Atomic multi-auction switch: stop the previously armed frame first.
    if activeFrame and activeFrame ~= bidFrame then
        stopFrame(activeFrame, "change")
    end

    local decision = SM.arm(st.sm, {
        auctionId = tostring(bidFrame.auctionID),
        itemId = bidFrame.itemID,
        increment = cfg.increment,
        cap = cfg.cap,
        currentPrice = bidFrame.money,
        currentBidder = bidFrame.player,
        selfName = selfNameRaw(),
        realm = selfRealm(),
    })

    if st.sm.status == "invalid" then
        region.statusText:SetText(SM.statusText(st.sm))
        region.statusText:SetTextColor(1, 0.3, 0.3)
        refresh(bidFrame, st)
        return
    end

    activeFrame = bidFrame
    refresh(bidFrame, st)
    if decision and decision.bid then
        sendBid(bidFrame, st, decision.bid)
    end
end

local function toggle(bidFrame)
    local st = bidFrame[ACTIVE_KEY]
    if not st then
        return
    end
    if st.sm.status == "armed" then
        stopFrame(bidFrame, "user")
    else
        arm(bidFrame, st)
    end
end

-- ---------------------------------------------------------------------------
-- Attach a bid frame (chained from BG.HookCreateAuction)
-- ---------------------------------------------------------------------------

function M.attach(bidFrame)
    if not bidFrame or bidFrame.auctionID == nil then
        return
    end
    -- Gen2 rotating channels are out of scope: no region, no state, no gen1 fallback.
    if bidFrame.isGen2 then
        return
    end

    -- Interacting with a different auction stops any armed auto-bid.
    if activeFrame and activeFrame ~= bidFrame then
        local old = activeFrame[ACTIVE_KEY]
        if old and old.sm.status == "armed" then
            stopFrame(activeFrame, "change")
        end
    end

    local st = freshState()
    st.region = makeRegion(bidFrame)
    bidFrame[ACTIVE_KEY] = st

    if BG.BGNext.DB and BG.BGNext.DB.auctionPresets then
        local p = Store.get(BG.BGNext.DB.auctionPresets)
        if p.increment then
            st.region.incrementEdit:SetText(tostring(p.increment))
        end
        if p.cap then
            st.region.capEdit:SetText(tostring(p.cap))
        end
    end

    st.region.button:SetScript("OnClick", function()
        toggle(bidFrame)
    end)

    -- Stop as soon as the auction frame hides/closes (the user can no longer see
    -- the status, so the auto-bid must not keep running).
    bidFrame:HookScript("OnHide", function()
        stopFrame(bidFrame, "hidden")
    end)

    refresh(bidFrame, st)
end

-- ---------------------------------------------------------------------------
-- Event handlers
-- ---------------------------------------------------------------------------

function M.onAddonMessage(self, event, prefix, message, distribution, arg4, arg5)
    if not activeFrame then
        return
    end
    local st = activeFrame[ACTIVE_KEY]
    if not st or st.sm.status ~= "armed" then
        return
    end

    local classified = Msg.classify(nil, prefix, message, distribution, arg4, arg5, st.sm.auctionId)
    if classified.kind == "stop" then
        stopFrame(activeFrame, classified.reason)
        return
    end
    if classified.kind ~= "bid" then
        return
    end

    local fullSender = Names.fullName(classified.sender, selfRealm())
    local reason = Msg.validateBidEvent(classified.parsed, {
        sender = fullSender,
        raidMembers = raidMemberSet(),
        auctionId = st.sm.auctionId,
    })
    if reason then
        stopFrame(activeFrame, reason == "not-raid" and "invalid-sender" or "protocol")
        return
    end

    local decision = SM.onPrice(st.sm, {
        auctionId = classified.parsed.auctionId,
        price = classified.parsed.money,
        bidder = fullSender,
    }, now())

    if decision and decision.bid then
        sendBid(activeFrame, st, decision.bid)
    else
        refresh(activeFrame, st)
    end
end

function M.onAuctionEnd(endType, link, player, money, logs)
    if not activeFrame then
        return
    end
    local reason = ({ [1] = "success", [2] = "unsold", [3] = "cancel" })[endType]
    if not reason then
        return
    end
    -- Precise matching: only the active auction's own end stops it. When the end
    -- event cannot be tied to the active auction (no item link), fail closed.
    if link == nil or link == "" then
        stopFrame(activeFrame, "protocol")
        return
    end
    if link ~= activeFrame.link then
        return
    end
    stopFrame(activeFrame, reason)
end

function M.onRosterUpdate(self, event)
    if activeFrame and not IsInRaid() then
        stopFrame(activeFrame, "leave")
    end
end

function M.onLogout(self, event)
    if activeFrame then
        stopFrame(activeFrame, "reload")
    end
end

function M.onLeavingWorld(self, event)
    if activeFrame then
        stopFrame(activeFrame, "leave")
    end
end

-- ---------------------------------------------------------------------------
-- Hook installation (BG.Init2 — after the auction modules define their hooks)
-- ---------------------------------------------------------------------------

local function wrapStackHeight()
    if not wa or not wa.GetFrameTotolHeight or wa._bgnextWrapped then
        return
    end
    wa._bgnextWrapped = true
    local orig = wa.GetFrameTotolHeight
    local extra = UI.layout.regionHeight + UI.layout.gap
    wa.GetFrameTotolHeight = function(count)
        local height = orig(count)
        for i = 1, (count or 1) - 1 do
            local f = BGA and BGA.Frames and BGA.Frames[i]
            if f and not f.IsSmallWindow then
                height = height + extra
            end
        end
        return height
    end
end

local function wrapAutoButton()
    if not wa or not wa.AutoButton_OnClick or wa._bgnextAutoWrapped then
        return
    end
    wa._bgnextAutoWrapped = true
    local orig = wa.AutoButton_OnClick
    wa.AutoButton_OnClick = function(self, ...)
        orig(self, ...)
        local bidFrame = self and self.owner
        if bidFrame and bidFrame.isAuto then
            stopFrame(bidFrame, "disabled")
        end
        local st = bidFrame and bidFrame[ACTIVE_KEY]
        if st then
            refresh(bidFrame, st)
        end
    end
end

function M.installHooks()
    if installed then
        return
    end
    installed = true

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(Msg.ADDON_PREFIX)
    end

    -- Chain the hooks defined by the auction modules during ADDON_LOADED. Doing
    -- this in BG.Init2 guarantees they already exist, so the original hook is
    -- always called before our own and nothing is overwritten.
    local origCreateAuction = BG.HookCreateAuction
    BG.HookCreateAuction = function(bidFrame)
        if origCreateAuction then
            origCreateAuction(bidFrame)
        end
        M.attach(bidFrame)
    end

    local origAuctionEnd = BG.AuctionWAEnd
    BG.AuctionWAEnd = function(endType, ...)
        if origAuctionEnd then
            origAuctionEnd(endType, ...)
        end
        M.onAuctionEnd(endType, ...)
    end

    wrapStackHeight()
    wrapAutoButton()

    BG.RegisterEvent("CHAT_MSG_ADDON", M.onAddonMessage)
    BG.RegisterEvent("GROUP_ROSTER_UPDATE", M.onRosterUpdate)
    BG.RegisterEvent("PLAYER_LOGOUT", M.onLogout)
    BG.RegisterEvent("PLAYER_LEAVING_WORLD", M.onLeavingWorld)
end

BG.Init2(function()
    M.installHooks()
end)

BG.BGNext.AuctionPresetRuntime = M

return M
