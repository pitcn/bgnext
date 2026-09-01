BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Page state, fixed layout rules, and the reusable-row contract for the price
-- preset page. Everything above the runtime guard is pure and must stay loadable
-- with no WoW globals present. The frame hierarchy that builds on these rules
-- lives below the guard and reads prices only through the store/catalog/codec
-- modules, never from BiaoGe or a third-party source.
local M = {}

M.tabNumber = 2
M.ROW_CAPACITY = 12

M.LABELS = {
    leader = "团长起拍价",
    personal = "我的心理价",
}

M.DESCRIPTIONS = {
    leader = "用于团长开团时自动填入自定义装备起拍价，最终仍由团长确认。",
    personal = "用于参团时自动填入已保存的心理价，不会自动启用或发送。",
}

local LEADER_ACTIONS = { "preset", "basePrice", "active", "new", "copy", "rename", "delete", "import", "export" }
local PERSONAL_ACTIONS = { "itemCount", "import", "export", "clear" }

local function validMode(mode)
    if mode == "leader" or mode == "personal" then return mode end
    return nil
end

local function emptyFilters()
    return { text = "", equipLoc = nil, quality = nil, state = nil }
end

-- Creates a fresh page state for one raid. The default mode is leader.
function M.newState(raidId)
    return {
        raidId = raidId,
        mode = "leader",
        bossId = nil,
        savedBossId = nil,
        filters = emptyFilters(),
    }
end

-- Switches the price mode while preserving the current raid, boss, search and
-- scroll position.
function M.setMode(state, mode)
    mode = validMode(mode)
    if not mode or type(state) ~= "table" then return false end
    state.mode = mode
    return true
end

-- Selects another raid and resets the boss/search position to the raid's start.
function M.selectRaid(state, raidId)
    if type(state) ~= "table" then return false end
    state.raidId = raidId
    state.bossId = nil
    state.savedBossId = nil
    state.filters = emptyFilters()
    return true
end

-- Selects a Boss or misc group. The saved boss tracks where to return after a
-- raid-wide search is cleared.
function M.selectBoss(state, bossId)
    if type(state) ~= "table" then return false end
    state.bossId = bossId
    state.savedBossId = bossId
    return true
end

-- Sets one filter field. Starting a text search remembers the current boss so it
-- can be restored on clear.
function M.setFilter(state, key, value)
    if type(state) ~= "table" or type(key) ~= "string" then return false end
    if type(state.filters) ~= "table" then state.filters = emptyFilters() end
    if key == "text" and state.filters.text == "" and value ~= nil and value ~= "" then
        state.savedBossId = state.bossId
    end
    state.filters[key] = value
    return true
end

-- Clears every filter and returns to the boss position in place before the
-- search began.
function M.clearFilters(state)
    if type(state) ~= "table" then return false end
    state.filters = emptyFilters()
    if state.savedBossId ~= nil then
        state.bossId = state.savedBossId
    end
    return true
end

-- Returns the index after the currently focused one within the visible results,
-- wrapping to the first. nil when the list is empty; 1 when nothing is focused.
function M.nextVisibleIndex(filteredItems, currentIndex)
    local total = type(filteredItems) == "table" and #filteredItems or 0
    if total <= 0 then return nil end
    if type(currentIndex) ~= "number" then return 1 end
    local next = math.floor(currentIndex) + 1
    if next > total then next = 1 end
    if next < 1 then next = 1 end
    return next
end

-- The number of reusable rows actually needed for a result list: never more than
-- the fixed capacity, so large raids keep a constant object count.
function M.visibleRowCount(total, capacity)
    total = tonumber(total) or 0
    capacity = tonumber(capacity) or 0
    if total < 0 then total = 0 end
    if capacity < 0 then capacity = 0 end
    return total < capacity and total or capacity
end

-- Ordered toolbar action keys for a mode. Leader keeps the full scheme toolbar;
-- personal has a single set of prices and only import/export/clear.
function M.toolbarActions(mode)
    if mode == "leader" then return LEADER_ACTIONS end
    if mode == "personal" then return PERSONAL_ACTIONS end
    return nil
end

-- One-line description shown only on this page, never in the auction window.
function M.description(mode)
    return M.DESCRIPTIONS[mode]
end

BG.BGNext.AuctionPriceUI = M
return M
