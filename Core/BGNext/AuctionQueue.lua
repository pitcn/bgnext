BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Memory-only pending-auction queue for the current raid session. Pure helpers
-- (no WoW API): the runtime owns frames, events and the actual send. The queue
-- never touches SavedVariables, never sends a message, and is discarded on any
-- scope change (raid leave, table switch, table clear, or reload).
local M = {}

M.SOURCE_OVERRIDE = "override" -- a per-item override price from the active scheme
M.SOURCE_BASE = "base"         -- the active scheme's base price
M.SOURCE_MANUAL = "manual"     -- unresolved: the leader must type a price

M.REASON_NO_PERMISSION = "no-permission"
M.REASON_COMBAT = "combat"
M.REASON_INVALID_ITEM = "invalid-item"
M.REASON_PRICE_UNRESOLVED = "price-unresolved"
M.REASON_AUCTION_BUSY = "auction-busy"
M.REASON_PENDING_START = "pending-start"
M.REASON_SCOPE_CHANGED = "scope-changed"
M.REASON_PRICE_CHANGED = "price-changed"
M.REASON_QUEUE_FULL = "queue-full"
M.REASON_SCHEME_CHANGED = "scheme-changed"
M.REASON_FAMILY_CHANGED = "family-changed"

-- The maximum auction price matches the existing money input / protocol bound
-- (AuctionSender.M.MAX_MONEY); the queue is capped at one row per pooled row.
M.MAX_PRICE = 10000000
M.MAX_ITEMS = 40

function M.create(scopeKey)
    return { scopeKey = scopeKey, items = {}, order = {}, nextId = 1 }
end

local function validItemId(value)
    if type(value) ~= "number" then return false end
    if value ~= value or value == math.huge or value == -math.huge then return false end
    return value % 1 == 0 and value > 0
end

local function validQuantity(value)
    if value == nil then return 1 end
    if type(value) ~= "number" then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    if value % 1 ~= 0 or value < 1 or value > 100000 then return nil end
    return value
end

local function indexOf(q, id)
    for index, ordered in ipairs(q.order) do
        if ordered == id then return index end
    end
    return nil
end

-- Appends an item to the queue. `item` carries a numeric `itemId`, an optional
-- `link` (for the tooltip) and an optional positive integer `quantity` (default
-- 1). Returns the new row id, or nil plus a reason for an invalid item.
function M.add(q, item)
    if type(q) ~= "table" or type(q.order) ~= "table" or type(q.items) ~= "table"
        or type(item) ~= "table" then
        return nil, M.REASON_INVALID_ITEM
    end
    local itemId = item.itemId
    if not validItemId(itemId) then return nil, M.REASON_INVALID_ITEM end
    local quantity = validQuantity(item.quantity)
    if quantity == nil then return nil, M.REASON_INVALID_ITEM end
    local link = type(item.link) == "string" and item.link ~= "" and item.link or nil
    if #q.order >= M.MAX_ITEMS then return nil, M.REASON_QUEUE_FULL end
    local id = q.nextId
    q.nextId = q.nextId + 1
    q.items[id] = { id = id, itemId = itemId, link = link, quantity = quantity }
    q.order[#q.order + 1] = id
    return id
end

function M.remove(q, id)
    if type(q) ~= "table" or type(q.items) ~= "table" or q.items[id] == nil then
        return false
    end
    q.items[id] = nil
    for index, ordered in ipairs(q.order) do
        if ordered == id then
            table.remove(q.order, index)
            break
        end
    end
    return true
end

-- Moves a queued item one slot up (delta = -1) or down (delta = +1). Clamps at
-- the ends; an unknown id or an out-of-range target is a no-op.
function M.move(q, id, delta)
    if type(q) ~= "table" or q.items[id] == nil then return false end
    if delta ~= 1 and delta ~= -1 then return false end
    local from = indexOf(q, id)
    if not from then return false end
    local to = from + delta
    if to < 1 or to > #q.order then return false end
    q.order[from], q.order[to] = q.order[to], q.order[from]
    return true
end

-- Moves a queued item to a 1-based position, clamped to the list bounds.
function M.moveTo(q, id, position)
    if type(q) ~= "table" or q.items[id] == nil then return false end
    if type(position) ~= "number" or position ~= position or position % 1 ~= 0 then
        return false
    end
    local from = indexOf(q, id)
    if not from then return false end
    if position < 1 then position = 1 end
    if position > #q.order then position = #q.order end
    if position == from then return true end
    table.remove(q.order, from)
    table.insert(q.order, position, id)
    return true
end

function M.clear(q)
    if type(q) ~= "table" then return end
    q.items = {}
    q.order = {}
end

-- Consumes exactly one pending item from a row: a quantity of one removes the
-- row, a higher quantity decrements by one and leaves the row to be confirmed
-- again. Returns the remaining quantity, nil when the row was removed, or false
-- for an unknown id.
function M.decrement(q, id)
    if type(q) ~= "table" or type(q.items) ~= "table" or type(q.items[id]) ~= "table" then
        return false
    end
    local item = q.items[id]
    if item.quantity <= 1 then
        M.remove(q, id)
        return nil
    end
    item.quantity = item.quantity - 1
    return item.quantity
end

-- Replaces a row's quantity with an exact validated value. Returns true on
-- success, false for an unknown id or an invalid quantity.
function M.setQuantity(q, id, quantity)
    if type(q) ~= "table" or type(q.items) ~= "table" or type(q.items[id]) ~= "table" then
        return false
    end
    local value = validQuantity(quantity)
    if value == nil then return false end
    q.items[id].quantity = value
    return true
end

-- Shifts a row's quantity by `delta` and clamps to the valid range. Returns the
-- new quantity, or false for an unknown id or an out-of-range result.
function M.adjustQuantity(q, id, delta)
    if type(q) ~= "table" or type(q.items) ~= "table" or type(q.items[id]) ~= "table" then
        return false
    end
    if type(delta) ~= "number" then return false end
    local value = validQuantity(q.items[id].quantity + delta)
    if value == nil then return false end
    q.items[id].quantity = value
    return value
end

-- Records (or clears, with nil) the leader's memory-only manual starting price
-- for a row whose scheme price could not be resolved. Returns true on success,
-- false for an unknown id or a non-positive non-integer price.
function M.setPrice(q, id, price)
    if type(q) ~= "table" or type(q.items) ~= "table" or type(q.items[id]) ~= "table" then
        return false
    end
    if price == nil then
        q.items[id].manualPrice = nil
        return true
    end
    if type(price) ~= "number" or price ~= price or price % 1 ~= 0
        or price < 0 or price > M.MAX_PRICE then
        return false
    end
    q.items[id].manualPrice = price
    return true
end

function M.size(q)
    if type(q) ~= "table" or type(q.order) ~= "table" then return 0 end
    return #q.order
end

-- Projects the queue into display rows, in queue order. `resolvePrice(itemId)`
-- may return a plain number or `{ price = number, source = "override"|"base" }`;
-- a nil result (or anything else) marks the row as manual. Rows carry `id`,
-- `itemId`, `link`, `quantity`, `price` and `source`.
function M.project(q, resolvePrice)
    local rows = {}
    if type(q) ~= "table" or type(q.order) ~= "table" then return rows end
    for _, id in ipairs(q.order) do
        local item = type(q.items) == "table" and q.items[id] or nil
        if type(item) == "table" then
            local price, source
            if type(resolvePrice) == "function" then
                local resolved = resolvePrice(item.itemId)
                if type(resolved) == "number" then
                    price = resolved
                    source = M.SOURCE_BASE
                elseif type(resolved) == "table" and type(resolved.price) == "number" then
                    price = resolved.price
                    source = resolved.source
                end
            end
            if price == nil then
                source = M.SOURCE_MANUAL
                if type(item.manualPrice) == "number" then
                    price = item.manualPrice
                end
            elseif source ~= M.SOURCE_OVERRIDE and source ~= M.SOURCE_BASE then
                source = M.SOURCE_BASE
            end
            rows[#rows + 1] = {
                id = item.id,
                itemId = item.itemId,
                link = item.link,
                quantity = item.quantity,
                price = price,
                source = source,
            }
        end
    end
    return rows
end

-- Decides whether a projected row may be confirmed. Returns nil when allowed,
-- or the reason code that blocks it: no-permission, combat, invalid-item,
-- price-unresolved, or auction-busy. `ctx` carries the runtime's current
-- `isController`, `inCombat` and `auctionInProgress` flags.
function M.gate(row, ctx)
    if type(row) ~= "table" or not validItemId(row.itemId) then return M.REASON_INVALID_ITEM end
    ctx = ctx or {}
    if not ctx.isController then return M.REASON_NO_PERMISSION end
    if ctx.inCombat then return M.REASON_COMBAT end
    if ctx.auctionInProgress then return M.REASON_AUCTION_BUSY end
    if ctx.scopeChanged then return M.REASON_SCOPE_CHANGED end
    if ctx.pendingStart then return M.REASON_PENDING_START end
    if row.price == nil then return M.REASON_PRICE_UNRESOLVED end
    if type(row.price) ~= "number" or row.price ~= row.price or row.price % 1 ~= 0
        or row.price < 0 or row.price > M.MAX_PRICE then
        return M.REASON_INVALID_ITEM
    end
    return nil
end

-- True when the queue belongs to a different scope than `newScopeKey`, so the
-- runtime can drop it on raid leave, table switch, or table clear.
function M.scopeChanged(q, newScopeKey)
    if type(q) ~= "table" then return true end
    return q.scopeKey ~= newScopeKey
end

BG.BGNext.AuctionQueue = M
return M
