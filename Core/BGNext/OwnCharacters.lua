-- BGNext own-character snapshots.
--
-- Stores only the last-seen snapshot of a character the user was actually
-- logged into, under BiaoGe.BGNext.ownCharacters[clientFamily][realmId][player].
-- This module is pure data: it never creates frames, reads Blizzard APIs or
-- sends messages, and it never records another player, an account identifier,
-- a score or any historical series.

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

-- Only these snapshot fields may reach SavedVariables. Anything else the
-- collector or a corrupted save happens to carry is dropped on write.
local SNAPSHOT_FIELDS = {
    player = "string",
    realmId = "number",
    realmName = "string",
    faction = "string",
    class = "string",
    level = "number",
    itemLevel = "number",
    money = "number",
    updatedAt = "number",
    equipment = "table",
    currencies = "table",
    items = "table",
    raidStates = "table",
    professions = "table",
    professionCooldowns = "table",
}

local TEXTURE_TYPES = { string = true, number = true }

local EQUIPMENT_FIELDS = {
    itemId = "number", itemLevel = "number", quality = "number",
    icon = TEXTURE_TYPES, count = "number", link = "string",
}

local RAID_STATE_FIELDS = {
    completed = "boolean", progress = "number", total = "number",
    completedParts = "number", totalParts = "number",
    difficulty = "number", difficultyLabel = "string", resetsAt = "number",
    difficulties = "table",
}

-- A retail lockout's per-difficulty breakdown. Every difficulty keeps its own
-- killed/total boss counts and its own per-boss list, so Normal/Heroic/Mythic
-- stay isolated.
local DIFFICULTY_STATE_FIELDS = {
    difficulty = "number", difficultyLabel = "string",
    completedParts = "number", totalParts = "number", resetsAt = "number",
}

-- A difficulty's per-boss list is whitelisted down to {name, killed}. A boss must
-- carry both a non-empty localized name and a boolean killed flag; an entry that
-- lacks either is dropped entirely, and texture ids, encounter ids and unknown
-- returns never survive.
local function copyBossEncounters(source)
    if type(source) ~= "table" then return nil end
    local copy = {}
    for index, record in ipairs(source) do
        if type(record) == "table" then
            local name, killed = record.name, record.killed
            if type(name) == "string" and name ~= "" and type(killed) == "boolean" then
                copy[#copy + 1] = { name = name, killed = killed }
            end
        end
    end
    return copy
end

local PROFESSION_FIELDS = {
    name = "string", skill = "number", maxSkill = "number",
    icon = TEXTURE_TYPES, cooldownEndsAt = "number",
}

-- A currency may carry optional cap fields; only `quantity` is required so a
-- partial API result still records the real amount. Missing caps stay nil and
-- render without a fabricated maximum.
local CURRENCY_FIELDS = {
    quantity = "number",
    maxQuantity = "number",
    quantityEarnedThisWeek = "number",
    maxWeeklyQuantity = "number",
}

-- A profession cooldown is either ready or has a future reset timestamp.
local PROFESSION_COOLDOWN_FIELDS = {
    ready = "boolean",
    endsAt = "number",
}

local function isKey(value)
    return type(value) == "number" or (type(value) == "string" and value ~= "")
end

local function accepts(expected, value)
    if type(expected) == "table" then return expected[type(value)] == true end
    return type(value) == expected
end

-- Copies only whitelisted fields of a nested record; unknown keys are dropped.
local function copyRecord(source, fields)
    if type(source) ~= "table" then return nil end
    local copy = {}
    for key, expected in pairs(fields) do
        local value = source[key]
        if value ~= nil and accepts(expected, value) then
            copy[key] = value
        end
    end
    return copy
end

-- Maps of key -> whitelisted record.
local function copyRecordMap(source, fields)
    if type(source) ~= "table" then return nil end
    local copy = {}
    for key, record in pairs(source) do
        if isKey(key) then
            local entry = copyRecord(record, fields)
            if entry and next(entry) ~= nil then
                copy[key] = entry
            end
        end
    end
    return copy
end

-- Arrays of whitelisted records, preserving order. Unknown keys and wrong-typed
-- values are dropped, so a corrupted save can never smuggle in extra fields.
local function copyArray(source, fields)
    if type(source) ~= "table" then return nil end
    local copy = {}
    for index, record in ipairs(source) do
        local entry = copyRecord(record, fields)
        if entry and next(entry) ~= nil then
            copy[#copy + 1] = entry
        end
    end
    return copy
end

-- Maps of key -> plain count/amount. Non-numeric values are discarded rather
-- than carried through as opaque data.
local function copyNumberMap(source)
    if type(source) ~= "table" then return nil end
    local copy = {}
    for key, value in pairs(source) do
        if isKey(key) and type(value) == "number" then
            copy[key] = value
        end
    end
    return copy
end

-- Maps of key -> currency amount. A currency is either a plain count (the
-- legacy Titan shape) or a record with an optional cap. A record is kept only
-- when its `quantity` is a number, so an unknown cap or a wrong-typed value can
-- never smuggle in a fabricated maximum.
local function copyCurrencyMap(source)
    if type(source) ~= "table" then return nil end
    local copy = {}
    for key, value in pairs(source) do
        if isKey(key) then
            if type(value) == "number" then
                copy[key] = value
            elseif type(value) == "table" then
                local record = copyRecord(value, CURRENCY_FIELDS)
                if record and type(record.quantity) == "number" then
                    copy[key] = record
                end
            end
        end
    end
    return copy
end

-- Copies a retail difficulty's allowed fields plus its own whitelisted per-boss
-- list. No lockout ID, GUID, raw tuple, boss texture or unknown flag survives.
local function copyDifficulties(source)
    if type(source) ~= "table" then return nil end
    local copy = {}
    for index, record in ipairs(source) do
        local entry = copyRecord(record, DIFFICULTY_STATE_FIELDS)
        if entry and next(entry) ~= nil then
            entry.encounters = copyBossEncounters(record.encounters)
            copy[#copy + 1] = entry
        end
    end
    return copy
end

-- Raid states get a nested whitelist: the flat fields plus a sanitized
-- `difficulties` array. This replaces copyRecordMap so the array is copied
-- deeply rather than carried by reference, and each difficulty's own per-boss
-- list is whitelisted the same way. Per-boss completion is never reconstructed
-- from a kill count.
local function sanitizeRaidStates(source)
    if type(source) ~= "table" then return {} end
    local copy = {}
    for key, record in pairs(source) do
        if isKey(key) then
            local entry = copyRecord(record, RAID_STATE_FIELDS)
            if entry and next(entry) ~= nil then
                entry.difficulties = copyDifficulties(record.difficulties)
                copy[key] = entry
            end
        end
    end
    return copy
end

local function sanitize(snapshot)
    if type(snapshot) ~= "table" then return nil end
    if not isKey(snapshot.realmId) then return nil end
    if type(snapshot.player) ~= "string" or snapshot.player == "" then return nil end

    local clean = {}
    for key, expected in pairs(SNAPSHOT_FIELDS) do
        local value = snapshot[key]
        if value ~= nil and accepts(expected, value) then
            clean[key] = value
        end
    end

    clean.equipment = copyRecordMap(snapshot.equipment, EQUIPMENT_FIELDS)
    clean.raidStates = sanitizeRaidStates(snapshot.raidStates)
    clean.professions = copyRecordMap(snapshot.professions, PROFESSION_FIELDS)
    clean.currencies = copyCurrencyMap(snapshot.currencies)
    clean.items = copyNumberMap(snapshot.items)
    clean.professionCooldowns = copyRecordMap(snapshot.professionCooldowns, PROFESSION_COOLDOWN_FIELDS)
    return clean
end

function M.ensureRoot(root)
    if type(root) ~= "table" then return nil end
    root.ownCharacters = type(root.ownCharacters) == "table" and root.ownCharacters or {}
    return root.ownCharacters
end

local function familyTable(root, clientFamily, create)
    if type(root) ~= "table" or not isKey(clientFamily) then return nil end
    local store = type(root.ownCharacters) == "table" and root.ownCharacters or nil
    if not store then
        if not create then return nil end
        store = M.ensureRoot(root)
    end
    local family = store[clientFamily]
    if type(family) ~= "table" then
        if not create then return nil end
        family = {}
        store[clientFamily] = family
    end
    return family
end

local function realmTable(root, clientFamily, realmId, create)
    local family = familyTable(root, clientFamily, create)
    if not family or not isKey(realmId) then return nil end
    local realm = family[realmId]
    if type(realm) ~= "table" then
        if not create then return nil end
        realm = {}
        family[realmId] = realm
    end
    return realm
end

-- Replaces the stored snapshot for one own character. Returns the stored copy,
-- or nil when the input is not a usable own-character snapshot.
function M.upsert(root, clientFamily, snapshot)
    if not isKey(clientFamily) then return nil end
    local clean = sanitize(snapshot)
    if not clean then return nil end
    local realm = realmTable(root, clientFamily, clean.realmId, true)
    if not realm then return nil end
    realm[clean.player] = clean
    return clean
end

local SECTION_FIELDS = {
    identity = { "realmName", "faction", "class", "level" },
    equipment = { "itemLevel", "equipment" },
    money = { "money" },
    raid = { "raidStates" },
    professions = { "professions" },
    currencies = { "currencies" },
    items = { "items" },
    professionCooldowns = { "professionCooldowns" },
    resources = { "currencies", "items", "professionCooldowns" },
}

-- Replaces only the fields belonging to dirty sections while preserving the
-- rest of the last-seen snapshot. The merged value still passes through the
-- same whitelist sanitizer as a full upsert.
function M.mergeSections(root, clientFamily, snapshot, sections)
    if type(snapshot) ~= "table" or type(sections) ~= "table" then return nil end
    if not isKey(snapshot.realmId) or type(snapshot.player) ~= "string" or snapshot.player == "" then return nil end

    local existing = M.get(root, clientFamily, snapshot.realmId, snapshot.player)
    local merged = {}
    for key, value in pairs(type(existing) == "table" and existing or {}) do merged[key] = value end
    merged.player = snapshot.player
    merged.realmId = snapshot.realmId
    merged.updatedAt = snapshot.updatedAt

    for section, fields in pairs(SECTION_FIELDS) do
        if sections[section] == true then
            for _, field in ipairs(fields) do merged[field] = snapshot[field] end
        end
    end
    return M.upsert(root, clientFamily, merged)
end

function M.get(root, clientFamily, realmId, player)
    local realm = realmTable(root, clientFamily, realmId, false)
    if not realm or type(player) ~= "string" then return nil end
    local stored = realm[player]
    return type(stored) == "table" and stored or nil
end

-- Returns snapshots ordered by realm then character so the table renders in a
-- stable order regardless of SavedVariables hash order.
function M.list(root, clientFamily)
    local family = familyTable(root, clientFamily, false)
    local rows = {}
    if not family then return rows end
    for realmId, realm in pairs(family) do
        if type(realm) == "table" then
            for player, snapshot in pairs(realm) do
                if type(snapshot) == "table" and type(player) == "string" then
                    rows[#rows + 1] = snapshot
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        local ra, rb = tostring(a.realmId), tostring(b.realmId)
        if ra ~= rb then return ra < rb end
        return tostring(a.player) < tostring(b.player)
    end)
    return rows
end

local function difficultyRank(label)
    if label == "M" then return 4 end
    if label == "H" then return 3 end
    if label == "N" then return 2 end
    if label == "LFR" then return 1 end
    return 0
end

-- After pruning expired difficulties, the root flat fields must describe the
-- highest remaining difficulty carrying progress (or the highest difficulty when
-- none has kills yet), never a stale representative that already expired.
local function recomputeRaidState(state, entries)
    local best
    for _, entry in ipairs(entries) do
        if type(entry) == "table" then
            if not best then
                best = entry
            else
                local entryProgress = type(entry.completedParts) == "number" and entry.completedParts > 0
                local bestProgress = type(best.completedParts) == "number" and best.completedParts > 0
                if entryProgress and not bestProgress then
                    best = entry
                elseif entryProgress == bestProgress
                    and difficultyRank(entry.difficultyLabel) > difficultyRank(best.difficultyLabel) then
                    best = entry
                end
            end
        end
    end
    if not best then return end
    state.difficulty = best.difficulty
    state.difficultyLabel = best.difficultyLabel
    state.completedParts = best.completedParts
    state.totalParts = best.totalParts
    state.progress = state.completedParts
    state.total = state.totalParts
    if state.totalParts and state.totalParts > 0 and state.completedParts == state.totalParts then
        state.completed = true
    else
        state.completed = nil
    end
end

-- Weekly state is valid only until its official reset. Expired entries are
-- deleted outright; they are never demoted into a previous-week record. A retail
-- state expires per difficulty: only the reset difficulties are pruned, and the
-- whole state is dropped once none of its difficulties remains.
function M.expireRaidStates(root, now)
    if type(now) ~= "number" then return end
    local store = type(root) == "table" and root.ownCharacters or nil
    if type(store) ~= "table" then return end
    for _, family in pairs(store) do
        if type(family) == "table" then
            for _, realm in pairs(family) do
                if type(realm) == "table" then
                    for _, snapshot in pairs(realm) do
                        local states = type(snapshot) == "table" and snapshot.raidStates or nil
                        if type(states) == "table" then
                            for id, state in pairs(states) do
                                if type(state) ~= "table" then
                                    states[id] = nil
                                elseif type(state.difficulties) == "table" then
                                    local kept = {}
                                    local resetsAt
                                    for _, entry in ipairs(state.difficulties) do
                                        local entryReset = type(entry) == "table"
                                            and type(entry.resetsAt) == "number" and entry.resetsAt or nil
                                        if entryReset == nil or now < entryReset then
                                            kept[#kept + 1] = entry
                                            if entryReset and (resetsAt == nil or entryReset < resetsAt) then
                                                resetsAt = entryReset
                                            end
                                        end
                                    end
                                    if #kept == 0 then
                                        states[id] = nil
                                    else
                                        state.difficulties = kept
                                        if resetsAt then state.resetsAt = resetsAt end
                                        recomputeRaidState(state, kept)
                                    end
                                else
                                    local resetsAt = type(state.resetsAt) == "number" and state.resetsAt or nil
                                    if resetsAt and now >= resetsAt then
                                        states[id] = nil
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Deletion requires the full family+realm+name key so that two same-name
-- characters on different realms can never be removed by one action.
function M.delete(root, clientFamily, realmId, player)
    local realm = realmTable(root, clientFamily, realmId, false)
    if not realm or type(player) ~= "string" then return false end
    if realm[player] == nil then return false end
    realm[player] = nil
    if next(realm) == nil then
        local family = familyTable(root, clientFamily, false)
        if family then family[realmId] = nil end
    end
    return true
end

function M.clearFamily(root, clientFamily)
    local store = type(root) == "table" and root.ownCharacters or nil
    if type(store) ~= "table" or not isKey(clientFamily) then return end
    store[clientFamily] = nil
end

function M.clearAll(root)
    if type(root) ~= "table" then return end
    root.ownCharacters = {}
end

BG.BGNext.OwnCharacters = M
return M
