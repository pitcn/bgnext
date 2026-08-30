BG = BG or {}
BG.BGNext = BG.BGNext or {}

local PlayerIdentity = assert(BG.BGNext.PlayerIdentity, "BGNext PlayerIdentity must load before LedgerCapture")
local M = {}
M.MAX_ITEM_ID = 2147483647
M.MAX_MONEY = 10000000

local DEFAULTS = {
    maxLines = 200,
    maxEntries = 200,
    maxLineBytes = 255,
    timeout = 50,
}

local function positiveInteger(value, fallback)
    if type(value) ~= "number" or value % 1 ~= 0 or value <= 0 then return fallback end
    return value
end

local function boundedInteger(value, minimum, maximum)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
    if number % 1 ~= 0 or number < minimum or number > maximum then return nil end
    return number
end

function M.parseMoney(value)
    return boundedInteger(value, 0, M.MAX_MONEY)
end

function M.parseItemID(value)
    return boundedInteger(value, 1, M.MAX_ITEM_ID)
end

local function reset(state)
    state.active = false
    state.startedAt = nil
    state.expiresAt = nil
    state.sourceKey = nil
    state.lineCount = 0
    state.entryCount = 0
end

local function isRaidMember(sender, realm, memberNames)
    for _, memberName in ipairs(memberNames or {}) do
        if PlayerIdentity.same(sender, memberName, realm) then return true end
    end
    return false
end

function M.new(options)
    options = options or {}
    local state = {
        maxLines = positiveInteger(options.maxLines, DEFAULTS.maxLines),
        maxEntries = positiveInteger(options.maxEntries, DEFAULTS.maxEntries),
        maxLineBytes = positiveInteger(options.maxLineBytes, DEFAULTS.maxLineBytes),
        timeout = positiveInteger(options.timeout, DEFAULTS.timeout),
    }
    reset(state)
    return state
end

function M.stop(state)
    if type(state) ~= "table" then return end
    reset(state)
end

function M.start(state, now)
    if type(state) ~= "table" or type(now) ~= "number" then return false end
    reset(state)
    state.active = true
    state.startedAt = now
    state.expiresAt = now + state.timeout
    return true
end

function M.isActive(state, now)
    if type(state) ~= "table" or state.active ~= true or type(now) ~= "number" then return false end
    if type(state.expiresAt) ~= "number" or now < state.startedAt or now >= state.expiresAt then
        reset(state)
        return false
    end
    return true
end

function M.bindSource(state, sender, realm, memberNames, now)
    if not M.isActive(state, now) or state.sourceKey then return false end
    if not isRaidMember(sender, realm, memberNames) then return false end
    state.sourceKey = PlayerIdentity.key(sender, realm)
    return state.sourceKey ~= nil
end

function M.acceptSource(state, sender, realm, memberNames, now)
    if not M.isActive(state, now) or not state.sourceKey then return false end
    if not isRaidMember(sender, realm, memberNames) then return false end
    return state.sourceKey == PlayerIdentity.key(sender, realm)
end

function M.appendLine(state, line, now)
    if not M.isActive(state, now) or type(line) ~= "string" then return false end
    if #line > state.maxLineBytes or state.lineCount >= state.maxLines then
        reset(state)
        return false
    end
    state.lineCount = state.lineCount + 1
    return true
end

function M.appendEntry(state, entry, now)
    if not M.isActive(state, now) or type(entry) ~= "table" then return false end
    if state.entryCount >= state.maxEntries then
        reset(state)
        return false
    end
    state.entryCount = state.entryCount + 1
    return true
end

BG.BGNext.LedgerCapture = M
return M
