BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Reliable trade-capture state machine (issue #64).
--
-- The shared mutable BG.trade is repopulated and torn down at many points in
-- the trade-window lifecycle, so the three consumers of a completed trade
-- (settlement record, bill writer, auction "已交易" mark) can disagree or all
-- miss the same trade when they read it at different moments. This module
-- freezes one bounded, memory-only candidate snapshot the instant the trade is
-- confirmed, then commits it exactly once on the explicit client success
-- signal. The committed snapshot is what every consumer reads, so all three
-- views stay identical. Nothing is fabricated: an incomplete snapshot is
-- dropped and never promoted into a buyer, amount or delivered state.
local M = {}

local frozen, committed, outcome

local function copyItems(list)
    local out = {}
    if type(list) == "table" then
        for i = 1, #list do
            local item = list[i]
            if type(item) == "table" then
                out[i] = { itemId = item.itemId, link = item.link, count = item.count }
            end
        end
    end
    return out
end

local function snapshotOf(raw)
    if type(raw) ~= "table" then
        return nil
    end
    if type(raw.target) ~= "string" or raw.target:find("%S") == nil then
        return nil
    end
    return {
        target = raw.target,
        targetmoney = tonumber(raw.targetmoney) or 0,
        playermoney = tonumber(raw.playermoney) or 0,
        targetitems = copyItems(raw.targetitems),
        playeritems = copyItems(raw.playeritems),
    }
end

-- Publish the committed snapshot back onto the shared table so the loaded
-- baseline's bill writer and auction marker read the same frozen state the
-- settlement recorder already consumed.
local function overlayTrade(snap)
    local trade = BG.trade
    if type(trade) ~= "table" then
        trade = {}
        BG.trade = trade
    end
    trade.target = snap.target
    trade.targetmoney = snap.targetmoney
    trade.playermoney = snap.playermoney
    trade.targetitems = copyItems(snap.targetitems)
    trade.playeritems = copyItems(snap.playeritems)
end

function M.beginTrade()
    frozen = nil
    committed = nil
    outcome = nil
end

function M.onAcceptUpdate(playerAccepted, targetAccepted)
    if not (playerAccepted or targetAccepted) then
        return false
    end
    frozen = snapshotOf(BG.trade)
    return frozen ~= nil
end

-- A close does not invalidate the frozen candidate: the success message can
-- arrive after the window has shut, so the frozen snapshot must survive.
function M.onTradeClosed()
    return true
end

function M.onComplete()
    if committed then
        return committed
    end
    local snap = frozen or snapshotOf(BG.trade)
    if not snap then
        outcome = "incomplete"
        return nil
    end
    committed = snap
    outcome = "committed"
    overlayTrade(snap)
    return snap
end

function M.committed()
    return committed
end

function M.diagnostic()
    return outcome
end

if BG.Init then
    BG.Init(function()
        BG.RegisterEvent("TRADE_SHOW", function()
            M.beginTrade()
        end)
        BG.RegisterEvent("TRADE_ACCEPT_UPDATE", function(_, _, playerAccepted, targetAccepted)
            M.onAcceptUpdate(playerAccepted, targetAccepted)
        end)
        BG.RegisterEvent("UI_INFO_MESSAGE", function(_, _, _, text)
            if text == ERR_TRADE_COMPLETE then
                M.onComplete()
            end
        end)
        BG.RegisterEvent("TRADE_CLOSED", function()
            M.onTradeClosed()
        end)
    end)
end

BG.BGNext.TradeCapture = M
return M
