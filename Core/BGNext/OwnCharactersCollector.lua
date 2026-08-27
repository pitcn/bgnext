-- BGNext own-character collector.
--
-- Reads the currently logged-in character only. Every reader is injected
-- through an environment table so the module is testable in plain Lua 5.1 and
-- so there is no parameter through which another player's name or a unit token
-- could be supplied.
--
-- This module never inspects another player, never registers a chat, combat
-- log, group roster, trade, mail, inspect or target event, and never sends an
-- addon or chat message.

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local Adapters = BG.BGNext.OwnCharactersAdapters

local M = {}

-- The complete set of events this module may ever register. Anything that
-- would observe another player, a conversation or a combat stream is
-- deliberately absent, and installEvents() refuses events outside this list.
M.allowedEvents = {
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_EQUIPMENT_CHANGED",
    "PLAYER_LEVEL_UP",
    "PLAYER_MONEY",
    "UPDATE_INSTANCE_INFO",
    "BAG_UPDATE_DELAYED",
    "CURRENCY_DISPLAY_UPDATE",
    "SKILL_LINES_CHANGED",
    "TRADE_SKILL_UPDATE",
}

local DEBOUNCE_SECONDS = 1

local function safeCall(fn)
    if type(fn) ~= "function" then return nil end
    if Adapters and Adapters.safeCall then return Adapters.safeCall(fn) end
    local ok, result = pcall(fn)
    if not ok then return nil end
    return result
end

-- Reads one optional value and keeps it only when it has the expected type.
-- A missing API, a protected value and a wrong-typed value are all treated the
-- same way: the field is simply absent.
local function read(env, key, expectedType)
    local value = safeCall(env[key])
    if value == nil then return nil end
    if type(value) ~= expectedType then return nil end
    return value
end

-- Collects a snapshot of the character the user is currently logged into.
-- Returns nil when the client cannot even identify that character.
function M.collect(env)
    if type(env) ~= "table" then return nil end

    local player = read(env, "playerName", "string")
    if not player or player == "" then return nil end

    local realmId = read(env, "realmId", "number")
    if realmId == nil then
        realmId = read(env, "realmId", "string")
        if realmId == "" then realmId = nil end
    end
    if realmId == nil then return nil end

    local snapshot = {
        player = player,
        realmId = realmId,
        realmName = read(env, "realmName", "string"),
        faction = read(env, "faction", "string"),
        class = read(env, "class", "string"),
        level = read(env, "level", "number"),
        itemLevel = read(env, "itemLevel", "number"),
        money = read(env, "money", "number"),
        updatedAt = read(env, "now", "number"),
        equipment = read(env, "equipment", "table"),
        raidStates = read(env, "raidStates", "table"),
        professions = read(env, "professions", "table"),
    }

    -- Currencies and item counts share one reader so a client family that
    -- exposes neither simply contributes nothing.
    local resources = read(env, "resources", "table")
    if resources then
        snapshot.currencies = type(resources.currencies) == "table" and resources.currencies or nil
        snapshot.items = type(resources.items) == "table" and resources.items or nil
    end

    return snapshot
end

-- Registers the own-character events and debounces bursts so that equipping a
-- full set or a bag update storm results in a single snapshot write.
function M.installEvents(env, onSnapshot)
    if type(env) ~= "table" or type(onSnapshot) ~= "function" then return nil end
    local frame = env.frame
    if type(frame) ~= "table" then return nil end

    local allowed = {}
    for _, event in ipairs(M.allowedEvents) do allowed[event] = true end

    for _, event in ipairs(M.allowedEvents) do
        if type(frame.RegisterEvent) == "function" then
            frame:RegisterEvent(event)
        end
    end

    local after = type(env.after) == "function" and env.after or nil
    local pending = false

    local function flush()
        pending = false
        onSnapshot()
    end

    if type(frame.SetScript) == "function" then
        frame:SetScript("OnEvent", function(_, event)
            if not allowed[event] then return end
            if pending then return end
            pending = true
            if after then
                after(DEBOUNCE_SECONDS, flush)
            else
                flush()
            end
        end)
    end

    return frame
end

BG.BGNext.OwnCharactersCollector = M
return M
