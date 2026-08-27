BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Runtime wiring for the controlled auto-bid — the only layer that touches WoW
-- APIs. It chains the existing BGLite hooks and registers a CHAT_MSG_ADDON
-- observer, feeding the pure state machine and turning each `{ bid = amount }`
-- decision into a single gen1 SendMyMoney message.
--
-- All state lives on the bid frame (memory-only) and is lost on reload. This
-- file is NOT unit-tested — it is the thin, unverified glue that must be
-- validated in a real client.
local M = {}

local Store = BG.BGNext.AuctionPresetStore
local SM = BG.BGNext.ControlledAutoBid
local Msg = BG.BGNext.AuctionBidMessage
local UI = BG.BGNext.AuctionBidUI

local ACTIVE_KEY = "BGNextAutoBid"

-- The frame whose auto-bid is currently armed (nil when nothing is armed).
local activeFrame = nil

local function now()
    return time()
end

local function shortName(name)
    if type(name) ~= "string" then return name end
    return name:match("^([^%-]+)") or name
end

local function selfName()
    if wa and wa.GN then return shortName(wa.GN()) end
    return shortName(UnitName("player"))
end

local function raidMemberSet()
    local set = {}
    if not IsInRaid() then return set end
    for i = 1, GetNumGroupMembers() do
        local name = UnitName("raid" .. i)
        if name then
            set[shortName(name)] = true
            set[name] = true
        end
    end
    local me = UnitName("player")
    if me then
        set[shortName(me)] = true
        set[me] = true
    end
    return set
end

local function freshState()
    return {
        sm = SM.new(),
        pendingAmount = nil,
        pendingTimer = nil,
        region = nil,
    }
end

local function refresh(bidFrame, st)
    local region = st.region
    if not region then return end
    local status = st.sm.status
    region.statusText:SetText(SM.statusText(st.sm))
    region.statusText:SetTextColor(0.8, 0.8, 0.8)
    region.button:SetText(UI.buttonText(status))
    local locked = UI.inputsLocked(status)
    region.incrementEdit:SetEnabled(not locked)
    region.capEdit:SetEnabled(not locked)
end

local function makeRegion(bidFrame)
    local L = UI.layout
    local region = CreateFrame("Frame", nil, bidFrame)
    region:SetSize(L.regionWidth, L.regionHeight)
    region:SetPoint("TOP", bidFrame, "BOTTOM", 0, -L.gap)

    local incLabel = region:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    incLabel:SetText(UI.LABELS.increment)
    incLabel:SetPoint("TOPLEFT", region, "TOPLEFT", L.margin, -L.margin)

    local incEdit = CreateFrame("EditBox", nil, region, "InputBoxTemplate")
    incEdit:SetSize(L.editWidth, L.editHeight)
    incEdit:SetPoint("LEFT", incLabel, "RIGHT", L.gap, 0)
    incEdit:SetNumeric(true)
    incEdit:SetAutoFocus(false)

    local capLabel = region:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    capLabel:SetText(UI.LABELS.cap)
    capLabel:SetPoint("LEFT", incEdit, "RIGHT", L.gap * 2, 0)

    local capEdit = CreateFrame("EditBox", nil, region, "InputBoxTemplate")
    capEdit:SetSize(L.editWidth, L.editHeight)
    capEdit:SetPoint("LEFT", capLabel, "RIGHT", L.gap, 0)
    capEdit:SetNumeric(true)
    capEdit:SetAutoFocus(false)

    local button = CreateFrame("Button", nil, region, "UIPanelButtonTemplate")
    button:SetSize(L.buttonWidth, L.buttonHeight)
    button:SetPoint("RIGHT", region, "RIGHT", -L.margin, 0)
    button:SetText(UI.LABELS.arm)

    local status = region:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetPoint("TOPLEFT", region, "TOPLEFT", L.margin, -(L.margin + L.editHeight + L.gap))
    status:SetText("未启用")
    status:SetTextColor(0.8, 0.8, 0.8)

    region.incrementEdit = incEdit
    region.capEdit = capEdit
    region.button = button
    region.statusText = status
    return region
end

local function doSend(bidFrame, st, amount)
    local msg = Msg.buildBidMessage(st.sm.auctionId, amount)
    C_ChatInfo.SendAddonMessage(Msg.ADDON_PREFIX, msg, "RAID")
    SM.markSent(st.sm, now())
    st.pendingAmount = nil
    refresh(bidFrame, st)
end

local function sendBid(bidFrame, st, amount)
    local s = st.sm
    if SM.canSend(s, now()) then
        doSend(bidFrame, st, amount)
    else
        -- Coalesce rapid outbids into one send after the 1s floor (a single
        -- deterministic delay, never a poll loop or randomised sniping delay).
        st.pendingAmount = amount
        if not st.pendingTimer then
            local remaining = math.max(0.05, SM.MIN_INTERVAL - (now() - (s.lastBidAt or 0)))
            st.pendingTimer = C_Timer.After(remaining, function()
                st.pendingTimer = nil
                if st.sm.status == "armed" and st.pendingAmount ~= nil then
                    doSend(bidFrame, st, st.pendingAmount)
                end
            end)
        end
    end
end

local function arm(bidFrame, st)
    local region = st.region
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

    local decision = SM.arm(st.sm, {
        auctionId = tostring(bidFrame.auctionID),
        itemId = bidFrame.itemID,
        increment = cfg.increment,
        cap = cfg.cap,
        currentPrice = bidFrame.money,
        currentBidder = bidFrame.player,
        selfName = selfName(),
    }, now())

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

local function stopFrame(bidFrame, reason)
    local st = bidFrame and bidFrame[ACTIVE_KEY]
    if not st then return end
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

local function toggle(bidFrame)
    local st = bidFrame[ACTIVE_KEY]
    if not st then return end
    if st.sm.status == "armed" then
        stopFrame(bidFrame, "user")
    else
        arm(bidFrame, st)
    end
end

function M.attach(bidFrame)
    if not bidFrame or bidFrame.auctionID == nil then return end

    -- Starting to interact with a different auction stops any armed auto-bid.
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
        if p.increment then st.region.incrementEdit:SetText(tostring(p.increment)) end
        if p.cap then st.region.capEdit:SetText(tostring(p.cap)) end
    end

    st.region.button:SetScript("OnClick", function()
        toggle(bidFrame)
    end)
end

function M.onAddonMessage(self, event, prefix, message, distribution, a4, a5)
    if not activeFrame then return end
    local st = activeFrame[ACTIVE_KEY]
    if not st or st.sm.status ~= "armed" then return end

    local parsed = Msg.parse(prefix, message)
    if not parsed then return end

    -- CHAT_MSG_ADDON carries the sender as its last arg on this server family
    -- (BGLite reads it from a fifth arg); fall back to the standard fourth arg.
    local sender = a5 or a4
    local reason = Msg.validateBidEvent(parsed, {
        sender = sender,
        raidMembers = raidMemberSet(),
        auctionId = st.sm.auctionId,
    })
    if reason then return end

    local decision = SM.onPrice(st.sm, {
        auctionId = parsed.auctionId,
        price = parsed.money,
        bidder = shortName(sender),
    }, now())

    if decision and decision.bid then
        sendBid(activeFrame, st, decision.bid)
    else
        refresh(activeFrame, st)
    end
end

function M.onAuctionEnd(endType, link, player, money, logs)
    if not activeFrame then return end
    local reason = ({ [1] = "success", [2] = "unsold", [3] = "cancel" })[endType]
    if reason then
        stopFrame(activeFrame, reason)
    end
end

function M.onRosterUpdate()
    if activeFrame and not IsInRaid() then
        stopFrame(activeFrame, "leave")
    end
end

BG.Init(function()
    C_ChatInfo.RegisterAddonMessagePrefix(Msg.ADDON_PREFIX)

    local origCreateAuction = BG.HookCreateAuction
    BG.HookCreateAuction = function(bidFrame)
        if origCreateAuction then origCreateAuction(bidFrame) end
        M.attach(bidFrame)
    end

    local origAuctionEnd = BG.AuctionWAEnd
    BG.AuctionWAEnd = function(endType, ...)
        if origAuctionEnd then origAuctionEnd(endType, ...) end
        M.onAuctionEnd(endType, ...)
    end

    BG.RegisterEvent("CHAT_MSG_ADDON", M.onAddonMessage)
    BG.RegisterEvent("GROUP_ROSTER_UPDATE", M.onRosterUpdate)
end)

BG.BGNext.AuctionPresetRuntime = M

return M
