BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Controlled auto-bid: a pure state machine and money calculator.
--
-- This module knows nothing about frames, SavedVariables, or the chat/addon
-- message layer. It is driven from the outside: the message adapter feeds it
-- validated price events, and the runtime turns a returned `{ bid = amount }`
-- into a single SendMyMoney message. All state lives in the table returned by
-- new() and is discarded on reload — it is never persisted.
local M = {}

M.MIN_INTERVAL = 1 -- seconds between actually sending bids

local STATUS_TEXT = {
    idle = "未启用",
    cap = "已达心理价位",
    stopped = "已手动停止",
    ended = "拍卖已结束",
    invalid = "当前拍卖数据无效",
}

local STOP_STATUS = {
    user = "stopped",
    success = "ended",
    unsold = "ended",
    cancel = "ended",
    change = "idle",
    leave = "idle",
    reload = "idle",
    disabled = "idle",
    invalid = "invalid",
}

local function validAmount(v)
    return type(v) == "number" and v >= 1 and v % 1 == 0
end

local function clearRuntime(state)
    state.auctionId = nil
    state.itemId = nil
    state.selfName = nil
    state.increment = nil
    state.cap = nil
    state.currentPrice = nil
    state.pendingBid = nil
    state.pendingRespondTo = nil
    state.lastPrice = nil
    state.lastBidAt = nil
    state.leading = false
end

local function terminal(state, status, reason)
    clearRuntime(state)
    state.status = status
    state.stopReason = reason
    return nil
end

function M.new()
    return {
        status = "idle",
        leading = false,
        stopReason = nil,
        auctionId = nil,
        itemId = nil,
        selfName = nil,
        increment = nil,
        cap = nil,
        currentPrice = nil,
        pendingBid = nil,
        pendingRespondTo = nil,
        lastPrice = nil,
        lastBidAt = nil,
    }
end

-- Pure amount calculation: one increment over the current highest bid, or nil
-- once that would exceed the cap.
function M.nextBid(current, increment, cap)
    if type(current) ~= "number" or type(increment) ~= "number" or type(cap) ~= "number" then
        return nil
    end
    if current < 0 or increment < 1 then
        return nil
    end
    local amount = current + increment
    if amount > cap then
        return nil
    end
    return amount
end

-- Arm the auto-bid for one auction. Returns the first decision:
--   { bid = amount }  the runtime should send this bid
--   { hold = true }   already the highest bidder, nothing to send
--   nil               invalid configuration or cap reached (see state.status)
function M.arm(state, cfg)
    if type(state) ~= "table" then
        state = M.new()
    end
    cfg = cfg or {}

    local increment, cap = cfg.increment, cfg.cap
    if not validAmount(increment) or not validAmount(cap) or cap < increment then
        return terminal(state, "invalid", "invalid")
    end
    local auctionId = cfg.auctionId
    if type(auctionId) ~= "string" or auctionId == "" then
        return terminal(state, "invalid", "invalid")
    end

    state.status = "armed"
    state.leading = false
    state.stopReason = nil
    state.auctionId = auctionId
    state.itemId = cfg.itemId
    state.selfName = cfg.selfName
    state.increment = increment
    state.cap = cap
    state.currentPrice = nil
    state.pendingBid = nil
    state.pendingRespondTo = nil
    state.lastPrice = nil
    state.lastBidAt = nil

    local currentPrice, currentBidder = cfg.currentPrice, cfg.currentBidder

    -- Nobody has bid yet: open at the starting price.
    if type(currentPrice) ~= "number" or currentBidder == nil then
        local startPrice = cfg.currentPrice
        if not validAmount(startPrice) then
            return terminal(state, "invalid", "invalid")
        end
        if startPrice > cap then
            return terminal(state, "cap", "cap")
        end
        state.pendingBid = startPrice
        return { bid = startPrice }
    end

    -- Already the highest bidder: hold.
    if cfg.selfName ~= nil and currentBidder == cfg.selfName then
        state.currentPrice = currentPrice
        state.leading = true
        state.lastPrice = currentPrice
        return { hold = true }
    end

    -- Someone else is highest: counter one increment.
    local amount = M.nextBid(currentPrice, increment, cap)
    if amount == nil then
        return terminal(state, "cap", "cap")
    end
    state.currentPrice = currentPrice
    state.pendingBid = amount
    state.pendingRespondTo = currentPrice
    return { bid = amount }
end

-- Feed a validated new-price event. Returns `{ bid = amount }`, `{ hold = true }`,
-- or nil (ignored, or a terminal state was reached — see state.status).
function M.onPrice(state, cfg, now)
    if type(state) ~= "table" or state.status ~= "armed" then
        return nil
    end
    cfg = cfg or {}

    if type(cfg.auctionId) == "string" and cfg.auctionId ~= "" and cfg.auctionId ~= state.auctionId then
        return nil
    end
    local price = cfg.price
    if not validAmount(price) then
        return nil
    end
    if price == state.lastPrice then
        return nil
    end
    if state.currentPrice ~= nil and price <= state.currentPrice then
        return nil
    end

    -- My own bid echoing back (or a defensive self-lead): never outbid myself.
    if state.selfName ~= nil and cfg.bidder == state.selfName then
        state.currentPrice = price
        state.leading = true
        state.lastPrice = price
        return { hold = true }
    end

    local amount = M.nextBid(price, state.increment, state.cap)
    if amount == nil then
        state.currentPrice = price
        state.leading = false
        return terminal(state, "cap", "cap")
    end

    state.currentPrice = price
    state.leading = false
    state.pendingBid = amount
    state.pendingRespondTo = price
    return { bid = amount }
end

-- The runtime calls this once its SendMyMoney actually went out, so the state
-- machine can treat the pending bid as the new current price.
function M.markSent(state, now)
    if type(state) ~= "table" then
        return state
    end
    if state.pendingBid ~= nil then
        state.currentPrice = state.pendingBid
        state.leading = true
        state.lastPrice = state.pendingRespondTo
        state.lastBidAt = now
        state.pendingBid = nil
        state.pendingRespondTo = nil
    end
    return state
end

-- True when enough time has passed since the last send to send again.
function M.canSend(state, now)
    if type(state) ~= "table" then
        return true
    end
    if state.lastBidAt == nil then
        return true
    end
    return now - state.lastBidAt >= M.MIN_INTERVAL
end

function M.stop(state, reason)
    if type(state) ~= "table" then
        return nil
    end
    local status = STOP_STATUS[reason] or "idle"
    terminal(state, status, reason)
    return state
end

function M.statusText(state)
    if type(state) ~= "table" then
        return STATUS_TEXT.idle
    end
    local status = state.status or "idle"
    if status == "armed" then
        return state.leading and "当前本人领先" or "自动出价中"
    end
    return STATUS_TEXT[status] or STATUS_TEXT.idle
end

BG.BGNext.ControlledAutoBid = M

return M
