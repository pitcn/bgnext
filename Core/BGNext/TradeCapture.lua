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

local frozen, committed, outcome, fullyAccepted

-- TRADE_ACCEPT_UPDATE supplies numeric 0/1 (WoW never sends Lua booleans), and
-- 0 is truthy in Lua, so the handler must never test the raw event args with
-- `if not (a or b)`. Normalize to a boolean so 0/false/nil mean "not accepted".
local function acceptedFlag(value)
    return value == true or value == 1
end

-- Only an explicit number (or numeric string) becomes money; an unknown value
-- (nil or non-numeric) stays nil so consumers can tell "unknown" from an
-- explicit 0. `tonumber(x) or 0` would fabricate an observed zero.
local function normalizeMoney(value)
    if value == nil then
        return nil
    end
    return tonumber(value)
end

local function itemIdOfLink(link)
    if type(link) ~= "string" then
        return nil
    end
    local id = link:match("item:(%d+)")
    if id then
        return tonumber(id)
    end
    return nil
end

local function copyItems(list)
    local out = {}
    if type(list) == "table" then
        for i = 1, #list do
            local item = list[i]
            if type(item) == "table" then
                out[i] = {
                    itemId = type(item.itemId) == "number" and item.itemId or itemIdOfLink(item.link),
                    link = item.link,
                    count = item.count,
                }
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
        targetmoney = normalizeMoney(raw.targetmoney),
        playermoney = normalizeMoney(raw.playermoney),
        targetitems = copyItems(raw.targetitems),
        playeritems = copyItems(raw.playeritems),
    }
end

-- Minimal read-only collector for the accept-time refresh (issue #64).
--
-- The loaded baseline refreshes trade contents through a deferred zero-delay
-- refresh of `BG.TradeUpdate`, so the accept event can arrive while BG.trade
-- is still empty/stale. BG.GetTradeInfo() was evaluated and rejected as the
-- refresh source: it is not read-only (it ends in BG.TradeIsAutoAuction(),
-- which rebuilds BG.trade.autoAuction and reads/writes trade UI frames) and it
-- depends on frames unrelated to freezing a snapshot. This collector instead
-- reads the same Blizzard trade API synchronously, with no UI side effects.
local function readTradeTarget()
    if type(GetUnitName) == "function" then
        local ok, name = pcall(GetUnitName, "NPC", true)
        if ok and type(name) == "string" and name:find("%S") then
            return name
        end
    end
    if type(UnitName) == "function" then
        local name = UnitName("NPC")
        if type(name) == "string" and name:find("%S") then
            return name
        end
    end
    return nil
end

local function readTradeMoney(fn)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, copper = pcall(fn)
    if not ok or type(copper) ~= "number" then
        return nil
    end
    return math.floor(copper / 10000)
end

local function readTradeItems(linkFn, infoFn)
    local items = {}
    if type(linkFn) ~= "function" then
        return items
    end
    for i = 1, 6 do
        local ok, link = pcall(linkFn, i)
        if ok and type(link) == "string" and link:find("%S") then
            local count
            if type(infoFn) == "function" then
                local okInfo, _, _, quantity = pcall(infoFn, i)
                if okInfo then
                    count = quantity
                end
            end
            items[#items + 1] = { link = link, count = count }
        end
    end
    return items
end

local function refreshFromApi()
    local target = readTradeTarget()
    local targetmoney = readTradeMoney(GetTargetTradeMoney)
    local playermoney = readTradeMoney(GetPlayerTradeMoney)
    local targetitems = readTradeItems(GetTradeTargetItemLink, GetTradeTargetItemInfo)
    local playeritems = readTradeItems(GetTradePlayerItemLink, GetTradePlayerItemInfo)
    if not target then
        return nil
    end
    if targetmoney == nil and playermoney == nil and #targetitems == 0 and #playeritems == 0 then
        return nil
    end
    return {
        target = target,
        targetmoney = targetmoney,
        playermoney = playermoney,
        targetitems = targetitems,
        playeritems = playeritems,
    }
end

-- Synchronously refresh from the live trade API, then deep-copy. Only when the
-- API yields nothing does the caller fall back to the already-known BG.trade
-- (the last complete state the baseline refreshed), so a collect failure never
-- produces a partial/empty snapshot in place of a complete candidate.
local function collectSnapshot()
    local snap = snapshotOf(refreshFromApi())
    if not snap then
        snap = snapshotOf(BG.trade)
    end
    return snap
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
    fullyAccepted = nil
end

function M.onAcceptUpdate(playerAccepted, targetAccepted)
    local playerOk = acceptedFlag(playerAccepted)
    local targetOk = acceptedFlag(targetAccepted)
    if not (playerOk or targetOk) then
        return false
    end
    if playerOk and targetOk then
        fullyAccepted = true
    end
    local snap = collectSnapshot()
    if snap then
        frozen = snap
    end
    return frozen ~= nil
end

-- A close after a full (1,1) accept keeps the frozen candidate: the success
-- message can arrive after the window has shut. A close without a full accept
-- is a cancel/failure, so the candidate is dropped and a late success message
-- cannot commit it (bounded, idempotent lifecycle).
function M.onTradeClosed()
    if not fullyAccepted then
        frozen = nil
    end
    return true
end

function M.onComplete()
    if committed then
        return committed
    end
    local snap = frozen
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
