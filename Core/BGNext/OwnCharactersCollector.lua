-- BGNext own-character collector.
--
-- Reads the currently logged-in character only. Every reader is injected
-- through an environment table so the module is testable in plain Lua 5.1 and
-- so there is no parameter through which another player's name or a unit token
-- could be supplied.
--
-- This module never inspects another player, combat log, group roster, trade,
-- mail, inspect or target data, and never sends an addon or chat message. Its
-- sole chat-event exception is MoP CHAT_MSG_LOOT: a caller-supplied observer
-- accepts only the current player's localized self-loot format and returns a
-- section flag; raw text is discarded before collection or storage.

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
    "QUEST_TURNED_IN",
    "QUEST_LOG_UPDATE",
    "LFG_UPDATE_RANDOM_INFO",
    "CHAT_MSG_LOOT",
}

local DEBOUNCE_SECONDS = 1

local EVENT_SECTIONS = {
    PLAYER_LOGIN = { full = true },
    PLAYER_ENTERING_WORLD = { full = true },
    PLAYER_EQUIPMENT_CHANGED = { equipment = true },
    PLAYER_LEVEL_UP = { identity = true },
    PLAYER_MONEY = { money = true },
    UPDATE_INSTANCE_INFO = { raid = true },
    BAG_UPDATE_DELAYED = { items = true },
    CURRENCY_DISPLAY_UPDATE = { currencies = true },
    SKILL_LINES_CHANGED = { professions = true, professionCooldowns = true },
    TRADE_SKILL_UPDATE = { professions = true, professionCooldowns = true },
    QUEST_TURNED_IN = { activities = true },
    QUEST_LOG_UPDATE = { activities = true },
    LFG_UPDATE_RANDOM_INFO = { activities = true },
}

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    if Adapters and Adapters.safeCall then return Adapters.safeCall(fn, ...) end
    local ok, result = pcall(fn, ...)
    if not ok then return nil end
    return result
end

-- Reads one optional value and keeps it only when it has the expected type.
-- A missing API, a protected value and a wrong-typed value are all treated the
-- same way: the field is simply absent.
local function read(env, key, expectedType, ...)
    local value = safeCall(env[key], ...)
    if value == nil then return nil end
    if type(value) ~= expectedType then return nil end
    return value
end

-- Collects a snapshot of the character the user is currently logged into.
-- Returns nil when the client cannot even identify that character.
function M.collect(env, sections)
    if type(env) ~= "table" then return nil end

    local full = type(sections) ~= "table" or sections.full == true
    local function wants(section)
        return full or sections[section] == true
    end

    local player = read(env, "playerName", "string")
    if not player or player == "" then return nil end

    local realmId = read(env, "realmId", "number")
    if realmId == nil then return nil end

    local snapshot = {
        player = player,
        realmId = realmId,
        updatedAt = read(env, "now", "number"),
    }

    if wants("identity") then
        snapshot.realmName = read(env, "realmName", "string")
        snapshot.faction = read(env, "faction", "string")
        snapshot.class = read(env, "class", "string")
        snapshot.level = read(env, "level", "number")
    end
    if wants("equipment") then
        snapshot.itemLevel = read(env, "itemLevel", "number")
        snapshot.equipment = read(env, "equipment", "table")
    end
    if wants("money") then snapshot.money = read(env, "money", "number") end
    if wants("raid") then snapshot.raidStates = read(env, "raidStates", "table") end
    if wants("professions") then snapshot.professions = read(env, "professions", "table") end
    if wants("activities") then snapshot.activityStates = read(env, "activities", "table") end

    -- Currencies and item counts share one reader so a client family that
    -- exposes neither simply contributes nothing.
    local resourceSelection
    if not full then
        resourceSelection = {}
        if sections.currencies == true or sections.resources == true then resourceSelection.currencies = true end
        if sections.items == true or sections.resources == true then resourceSelection.items = true end
        if sections.professionCooldowns == true or sections.resources == true then
            resourceSelection.professionCooldowns = true
        end
    end
    local resources = (full or resourceSelection.currencies or resourceSelection.items
        or resourceSelection.professionCooldowns)
        and read(env, "resources", "table", resourceSelection) or nil
    if resources then
        if full or resourceSelection.currencies then
            snapshot.currencies = type(resources.currencies) == "table" and resources.currencies or nil
        end
        if full or resourceSelection.items then
            snapshot.items = type(resources.items) == "table" and resources.items or nil
        end
        if full or resourceSelection.professionCooldowns then
            snapshot.professionCooldowns = type(resources.professionCooldowns) == "table"
            and resources.professionCooldowns or nil
        end
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
        local relevant = event ~= "CHAT_MSG_LOOT" or env.family == "mop"
        if relevant and type(frame.RegisterEvent) == "function" then
            -- Blizzard's client families do not expose an identical event set.
            -- An unsupported allowlisted event must not abort the remaining
            -- registrations or the immediate own-character collection.
            pcall(frame.RegisterEvent, frame, event)
        end
    end

    local after = type(env.after) == "function" and env.after or nil
    local pending = false
    local dirty = {}

    local function flush()
        pending = false
        local sections = dirty
        dirty = {}
        onSnapshot(sections)
    end

    if type(frame.SetScript) == "function" then
        frame:SetScript("OnEvent", function(_, event, ...)
            if not allowed[event] then return end
            local observedSections = safeCall(env.observeEvent, event, ...)
            if EVENT_SECTIONS[event] == nil and type(observedSections) ~= "table" then return end
            for section in pairs(EVENT_SECTIONS[event] or {}) do
                dirty[section] = true
            end
            for section, changed in pairs(type(observedSections) == "table" and observedSections or {}) do
                if changed == true then dirty[section] = true end
            end
            if next(dirty) == nil then return end
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
