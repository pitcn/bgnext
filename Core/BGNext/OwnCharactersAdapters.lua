-- BGNext own-character client adapters.
--
-- Isolates every client-version difference behind a read-only declaration so
-- the projection and renderer stay version-agnostic. This module never stores
-- data, never creates frames and never communicates.
--
-- Capabilities and currency IDs are declared only where they are actually
-- verifiable. A field with no verified reader resolves to nil, which hides its
-- column instead of showing a fabricated value.

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

M.families = { "vanilla", "tbc", "wrath", "titan", "cata", "mop", "retail" }

-- Ordered because BGLite sets several flags at once: the anniversary client
-- sets both IsWLK and IsTitan, and SoD sets both IsVanilla and IsVanilla_Sod.
local FAMILY_ORDER = {
    { flag = "IsRetail", family = "retail" },
    { flag = "IsMOP", family = "mop" },
    { flag = "IsCTM", family = "cata" },
    { flag = "IsTitan", family = "titan" },
    { flag = "IsWLK", family = "wrath" },
    { flag = "IsTBC", family = "tbc" },
    { flag = "IsVanilla", family = "vanilla" },
}

-- Declared per family. `false` means BGNext must not render that column group
-- on this client, even if a catalog entry exists.
local CAPABILITIES = {
    vanilla = { hasCurrencyApi = false, hasProfessionApi = true, hasItemLevelApi = true, hasHonorApi = true },
    tbc     = { hasCurrencyApi = false, hasProfessionApi = true, hasItemLevelApi = true, hasHonorApi = true },
    wrath   = { hasCurrencyApi = true, hasProfessionApi = true, hasItemLevelApi = true, hasHonorApi = true },
    titan   = { hasCurrencyApi = true, hasProfessionApi = true, hasItemLevelApi = true, hasHonorApi = true },
    cata    = { hasCurrencyApi = true, hasProfessionApi = true, hasItemLevelApi = true, hasHonorApi = true },
    mop     = { hasCurrencyApi = true, hasProfessionApi = true, hasItemLevelApi = true, hasHonorApi = true },
    retail  = { hasCurrencyApi = true, hasProfessionApi = true, hasItemLevelApi = true, hasHonorApi = true },
}

-- Stable BGNext column key -> numeric currency ID, per family.
--
-- Only entries confirmed against a live client belong here. Keys that are not
-- listed are reported as unverified by isVerifiedColumn() and produce no value,
-- so their column stays hidden. Do not guess IDs to "fill in" a family: an
-- unverified column must render blank, never wrong.
local CURRENCY_IDS = {
    vanilla = {},
    tbc = {
        arenaPoints = 1900,
    },
    wrath = {},
    titan = {
        titanEmber = 3403,
        titanShard = 3406,
        jewelcraftingToken = 61,
        cookingToken = 81,
        championSeal = 241,
        stoneKeeper = 161,
        arena = 1900,
        honor = 1901,
    },
    cata = {},
    mop = {
        valor = 396,
        justice = 395,
        roll = 776,
        conquest = 390,
        honor = 1901,
        ironpawToken = 402,
        darkmoonTicket = 515,
        elderCharm = 697,
        lesserCharm = 738,
        moguRune = 752,
        timelessCoin = 777,
    },
    retail = {},
}

-- Stable BGNext column key -> numeric item ID, per family. Like CURRENCY_IDS,
-- only a verified in-game ID belongs here; an unlisted key resolves to nil and
-- its column stays hidden.
local ITEM_IDS = {
    vanilla = {
        atieshFragment = 22726,
    },
    tbc = {
        badgeOfJustice = 29434,
    },
    wrath = {},
    titan = {},
    cata = {},
    mop = {},
    retail = {},
}

-- Public game item IDs used by the Titan legendary summary. Each inner
-- legendary group represents upgrade variants of one item family; only the
-- first owned variant is displayed so upgrades never appear as duplicates.
local TITAN_LEGENDARY_GROUPS = {
    { 255103, 260344, 257606, 260346, 264750, 264779, 264759, 264769,
      264751, 264780, 264760, 264770, 264752, 264781, 264761, 264771,
      264753, 264782, 264762, 264772, 264754, 264783, 264763, 264773,
      264755, 264784, 264764, 264774, 264789, 264785, 264765, 264775,
      264756, 264786, 264766, 264776, 264757, 264787, 264767, 264777,
      264758, 264788, 264768, 264778 },
    { 263264, 17203 },
    { 257605 },
    { 264749, 264936, 264748, 264935, 264746, 264934, 264933, 264745,
      264932, 264744, 264931, 264743, 264930, 264742, 264929, 264741,
      264928, 264731, 264927, 259908, 264926 },
    { 265522, 265521, 265520, 265519, 265518, 265517, 265516, 265515,
      265514, 19019, 19018 },
    { 265570, 265569, 265568, 265567, 265566, 265565, 265564, 265563,
      22632, 265841 },
    { 17142, 269677, 269675, 269672, 269679, 269676, 269680, 269674, 272955 },
    { 34334 },
}

local TITAN_UPGRADE_ITEMS = {
    265340, 265524, 267339, 269664, 265335, 265523, 267338, 269667,
    265526, 267335, 269669, 267340, 269665, 269670,
}

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[clone(key, seen)] = clone(child, seen)
    end
    return copy
end

M.clone = clone

function M.familyFromFlags(flags)
    if type(flags) ~= "table" then return nil end
    -- Season of Discovery intentionally has no own-character overview. Check
    -- this before IsVanilla because BGLite sets both flags on that client.
    if flags.IsVanilla_Sod then return nil end
    for _, entry in ipairs(FAMILY_ORDER) do
        if flags[entry.flag] then return entry.family end
    end
    return nil
end

-- Detects the family from the live BGLite globals. Kept separate from
-- familyFromFlags so tests never need WoW globals.
function M.detect(globals)
    return M.familyFromFlags(globals or BG)
end

function M.isFamily(family)
    return CAPABILITIES[family] ~= nil
end

function M.capabilities(family)
    local caps = CAPABILITIES[family]
    if not caps then return nil end
    return clone(caps)
end

-- Calls an optional Blizzard API. Returns nil when the API is absent on this
-- client, is not callable, or throws because the value is protected.
function M.safeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if not ok then return nil end
    return result
end

-- Calls an optional Blizzard API and returns ok plus every result, or ok=false
-- when the API is absent or throws. Several item/lockout/profession APIs return
-- tuples rather than a single value, so this is kept separate from safeCall().
local function callAll(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

--------------------------------------------------------------------------
-- Current-character readers
--
-- Each reader reads only the logged-in player (or the player's own currencies
-- and saved instances) and returns plain string/number/boolean/table data. A
-- missing or protected API, or a wrong-typed value, degrades to nil rather than
-- throwing or fabricating a value. None of these readers accepts a unit token,
-- a player name, or any parameter that could address another player.
--------------------------------------------------------------------------

function M.readPlayerName(api)
    local name = M.safeCall(api and api.UnitName, "player")
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

function M.readRealmId(api)
    local id = M.safeCall(api and api.GetRealmID)
    if type(id) ~= "number" then return nil end
    return id
end

function M.readRealmName(api)
    local name = M.safeCall(api and api.GetRealmName)
    if type(name) ~= "string" or name == "" then return nil end
    return name:gsub(" ", ""):gsub("%-", "")
end

-- Reports whether a value is a protected (secret) value on this client.
-- BG.IsSecret (function1.lua) wraps the retail issecretvalue() guard; when it
-- is absent the raw global is the fallback, and otherwise a value is assumed
-- readable. A secret value must never be compared, concatenated or used as a
-- SavedVariables key.
function M.isSecretValue(globals, value)
    local isSecret = type(globals) == "table" and globals.IsSecret or nil
    if type(isSecret) == "function" then
        return isSecret(value) == true
    end
    local raw = type(globals) == "table" and globals.issecretvalue or nil
    if type(raw) == "function" then
        return value ~= nil and raw(value) == true
    end
    return false
end

-- Validates the init-time current-character identity captured by Core/DB/Init.lua
-- (BG.playerName / BG.realmID / BG.realmName). Retail 12.x can keep the live
-- UnitName/GetRealmID calls secret-protected even though these init globals
-- already hold the real logged-in character. Returns nil unless both a readable
-- player name and a numeric realm id are present, so an empty string, a secret
-- value or a wrong-typed value can never become a snapshot key.
function M.validatedIdentity(globals)
    if type(globals) ~= "table" then return nil end

    local name = globals.playerName
    if type(name) ~= "string" or name == "" or M.isSecretValue(globals, name) then
        name = nil
    end

    local realmId = globals.realmID
    if type(realmId) ~= "number" or M.isSecretValue(globals, realmId) then
        realmId = nil
    end

    local realmName = globals.realmName
    if type(realmName) ~= "string" or realmName == "" or M.isSecretValue(globals, realmName) then
        realmName = nil
    end

    if not name or not realmId then return nil end
    return { playerName = name, realmId = realmId, realmName = realmName }
end

function M.readFaction(api)
    local faction = M.safeCall(api and api.UnitFactionGroup, "player")
    if type(faction) ~= "string" or faction == "" then return nil end
    return faction
end

function M.readClass(api)
    local fn = api and api.UnitClass
    if type(fn) ~= "function" then return nil end
    local ok, classFile = pcall(function() return select(2, fn("player")) end)
    if not ok or type(classFile) ~= "string" or classFile == "" then return nil end
    return classFile
end

function M.readLevel(api)
    local level = M.safeCall(api and api.UnitLevel, "player")
    if type(level) ~= "number" then return nil end
    return level
end

function M.readItemLevel(api)
    local fn = api and api.GetAverageItemLevel
    if type(fn) ~= "function" then return nil end
    local ok, overall, equipped = pcall(fn)
    if not ok then return nil end
    local value = type(equipped) == "number" and equipped
        or (type(overall) == "number" and overall or nil)
    return value
end

function M.readMoney(api)
    local money = M.safeCall(api and api.GetMoney)
    if type(money) ~= "number" then return nil end
    return money
end

-- Reads the logged-in character's rested XP amount. The Classic-family client
-- exposes GetXPExhaustion; modern clients use C_PlayerInfo.GetRestExperience.
-- Either way only the amount is recorded, never the level-split maximum, and a
-- missing or protected API degrades to nil instead of a fabricated zero.
function M.readRestExperience(api)
    if type(api) ~= "table" then return nil end
    local xp
    local legacy = api.GetXPExhaustion
    if type(legacy) == "function" then
        xp = M.safeCall(legacy)
    else
        local playerInfo = api.C_PlayerInfo
        local modern = type(playerInfo) == "table" and playerInfo.GetRestExperience or nil
        if type(modern) == "function" then
            local ok, restXp = callAll(modern)
            if ok then xp = restXp end
        end
    end
    if type(xp) ~= "number" then return nil end
    return xp
end

-- Reads one profession cooldown spell for the logged-in character. The modern
-- C_Spell table API is preferred; the legacy GetSpellCooldown form is the
-- fallback. A spell with no active cooldown reports duration zero, which is
-- recorded as ready; a spell still cooling records only the time it ends.
-- A missing API or a wrong-typed result yields nil so the column hides.
function M.readProfessionCooldown(api, spellId)
    if type(api) ~= "table" or type(spellId) ~= "number" then return nil end
    local start, duration

    local spellApi = api.C_Spell
    local modern = type(spellApi) == "table" and spellApi.GetSpellCooldown or nil
    if type(modern) == "function" then
        local ok, info = callAll(modern, spellId)
        if ok and type(info) == "table" then
            start = info.startTime
            duration = info.duration
        end
    end

    if type(start) ~= "number" or type(duration) ~= "number" then
        local legacy = api.GetSpellCooldown
        if type(legacy) ~= "function" then return nil end
        local ok, s, d = callAll(legacy, spellId)
        if not ok then return nil end
        start, duration = s, d
    end

    if type(start) ~= "number" or type(duration) ~= "number" then return nil end
    if duration <= 0 then return { ready = true } end
    return { endsAt = start + duration }
end

-- Resolves a spell ID to a non-empty localized name via the Blizzard spell
-- APIs, or nil when the name cannot be confirmed. A profession cooldown is
-- only offered when its spell resolves, so a bare cooldown API surface alone
-- never surfaces an unresolvable cooldown.
local function resolveSpellName(api, spellId)
    if type(api) ~= "table" or type(spellId) ~= "number" then return nil end

    local spellApi = api.C_Spell
    local modern = type(spellApi) == "table" and spellApi.GetSpellInfo or nil
    if type(modern) == "function" then
        local ok, info = callAll(modern, spellId)
        if ok and type(info) == "table" and type(info.name) == "string"
            and info.name ~= "" then
            return info.name
        end
    end

    local legacy = api.GetSpellInfo
    if type(legacy) == "function" then
        local ok, name = callAll(legacy, spellId)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end

    return nil
end

function M.readNow(api)
    local clock = (api and api.time) or time
    local now = M.safeCall(clock)
    if type(now) ~= "number" then return nil end
    return now
end

-- Reads the currently equipped items into a slot-keyed table. Each entry is
-- only the plain data the whitelist allows; nothing else reaches storage.
function M.readEquipment(api)
    local getLink = api and api.GetInventoryItemLink
    if type(getLink) ~= "function" then return nil end
    local getInstant = api and api.GetItemInfoInstant
    local getInfo = api and api.GetItemInfo
    local getIcon = api and api.GetItemIcon

    local slots = {}
    for slot = 1, 19 do
        local link = M.safeCall(getLink, "player", slot)
        if type(link) == "string" and link ~= "" then
            local itemId
            if type(getInstant) == "function" then
                local id = M.safeCall(getInstant, link)
                if type(id) == "number" then itemId = id end
            end

            local itemLevel, quality, icon
            if type(getInfo) == "function" then
                local ok, name, itemLink, itemQuality, itemLvl, _, _, _, _, _, itemTexture =
                    pcall(getInfo, link)
                if ok then
                    quality = type(itemQuality) == "number" and itemQuality or nil
                    itemLevel = type(itemLvl) == "number" and itemLvl or nil
                    if type(itemTexture) == "number" then
                        icon = itemTexture
                    elseif type(itemTexture) == "string" and itemTexture ~= "" then
                        icon = itemTexture
                    end
                end
            end

            if not icon and itemId and type(getIcon) == "function" then
                local iconPath = M.safeCall(getIcon, itemId)
                if type(iconPath) == "number" or (type(iconPath) == "string" and iconPath ~= "") then
                    icon = iconPath
                end
            end

            if itemId or itemLevel or quality or icon then
                slots[slot] = {
                    itemId = itemId,
                    itemLevel = itemLevel,
                    quality = quality,
                    icon = icon,
                    count = 1,
                    link = link,
                }
            end
        end
    end
    if next(slots) == nil then return nil end
    return slots
end

-- Verified retail difficulty IDs from BGLite's BG.diffIDTbl (Core/DB/DB.lua):
-- the modern client reports Raid Finder/Normal/Heroic/Mythic as 17/14/15/16.
-- Any other difficulty ID stays numeric and renders without a letter, so a
-- classic or private-server lockout can never be mislabelled as Mythic.
local DIFFICULTY_LABELS = { [14] = "N", [15] = "H", [16] = "M", [17] = "LFR" }

local function difficultyRank(label)
    if label == "M" then return 4 end
    if label == "H" then return 3 end
    if label == "N" then return 2 end
    if label == "LFR" then return 1 end
    return 0
end

-- A saved-instance boss count is usable only as a whole number of at least one
-- boss, and its kill count must be a whole number inside that total. The two
-- values are validated together as one pair so a missing, protected or
-- wrong-typed progress can never fabricate a "0/N" state.
local function validEncounterPair(numEncounters, encounterProgress)
    if type(numEncounters) ~= "number" or numEncounters < 1
        or math.floor(numEncounters) ~= numEncounters then
        return false
    end
    if type(encounterProgress) ~= "number" or encounterProgress < 0
        or encounterProgress > numEncounters
        or math.floor(encounterProgress) ~= encounterProgress then
        return false
    end
    return true
end

-- Reads the real saved-instance per-boss status. GetSavedInstanceEncounterInfo
-- returns (bossName, fileDataID, isKilled, unknown4) for a locked instance; only
-- the localized name and the boss's own killed flag are kept, never the texture
-- id or the unknown fourth return. The whole list is dropped (nil) when the API
-- is missing or any boss tuple is abnormal, so a missing name or a non-boolean
-- kill flag can never be fabricated into a boss state.
local function readBossEncounters(api, instanceIndex, numEncounters)
    local getEncounter = api and api.GetSavedInstanceEncounterInfo
    if type(getEncounter) ~= "function" or type(instanceIndex) ~= "number"
        or type(numEncounters) ~= "number" or numEncounters < 1 then
        return nil
    end
    local bosses = {}
    for encounterIndex = 1, numEncounters do
        local ok, bossName, _, isKilled = callAll(getEncounter, instanceIndex, encounterIndex)
        if not ok or type(isKilled) ~= "boolean"
            or type(bossName) ~= "string" or bossName == "" then
            return nil
        end
        bosses[#bosses + 1] = { name = bossName, killed = isKilled }
    end
    return bosses
end

-- Reads the saved-instance lockouts for the raids this family renders. Only
-- columns whose zoneId matches a saved instance produce a state; a lockout with
-- no reset time still records progress/completion but not a countdown.
--
-- Retail raids are locked separately per difficulty, so a retail column keeps
-- one cell whose flat fields (difficulty, completedParts, totalParts, completed)
-- describe the highest difficulty carrying progress (M > H > N > LFR), and whose
-- `difficulties` array carries every difficulty's own killed/total boss count and
-- reset timestamp so no two difficulties ever merge or share an expiry. A retail
-- difficulty is published only when its numEncounters and encounterProgress form
-- one valid pair, so a missing, protected or out-of-range progress leaves the
-- difficulty absent instead of a fabricated 0/N. Each retail difficulty also
-- carries its own `encounters` array of {name, killed} records read from the real
-- GetSavedInstanceEncounterInfo API; the whole list fails closed to nil when the
-- API is missing or any boss tuple is abnormal, so per-boss completion is never
-- reconstructed from the aggregate kill count or the encounter-journal ordering.
-- Every other family keeps the first
-- matching lockout per instance, so classic and private-server behaviour is
-- unchanged.
function M.readRaidStates(api, raidColumns, family)
    local getNum = api and api.GetNumSavedInstances
    local getInfo = api and api.GetSavedInstanceInfo
    if type(getNum) ~= "function" or type(getInfo) ~= "function" then return nil end

    local count = M.safeCall(getNum)
    if type(count) ~= "number" or count <= 0 then return nil end

    local byInstance = {}
    for _, column in ipairs(raidColumns or {}) do
        local source = type(column) == "table" and column.source or nil
        local instanceIds = type(source) == "table" and source.instanceIds or nil
        if type(column) == "table" and type(column.id) == "string" and type(instanceIds) == "table" then
            for _, instanceId in ipairs(instanceIds) do
                if type(instanceId) == "number" then
                    byInstance[instanceId] = { columnId = column.id, totalParts = #instanceIds }
                end
            end
        end
    end

    local now = (api and api.time) or time
    local nowValue = M.safeCall(now)

    local states = {}
    local seenInstances = {}
    local byDifficulty = {}
    for index = 1, count do
        local ok, name, lockoutId, reset, difficulty, locked, extended, mostSig, isRaid,
            maxPlayers, difficultyName, numEncounters, encounterProgress, _, instanceId = callAll(getInfo, index)
        local mapping = byInstance[instanceId]
        if ok and locked == true and isRaid == true and mapping then
            local label = type(difficulty) == "number" and DIFFICULTY_LABELS[difficulty] or nil
            if family == "retail" and label then
                -- Publish a difficulty only when its boss total and kill count are
                -- one valid pair; otherwise the difficulty is absent, never a
                -- fabricated 0/N.
                if validEncounterPair(numEncounters, encounterProgress) then
                    local rank = difficultyRank(label)
                    local ranked = byDifficulty[mapping.columnId]
                    if not ranked then
                        ranked = {}
                        byDifficulty[mapping.columnId] = ranked
                    end
                    local state = ranked[rank]
                    if not state then
                        local encounters = readBossEncounters(api, index, numEncounters)
                        -- Fail closed: the killed count exists only when the real
                        -- per-boss list was read. Without it the aggregate farthest
                        -- index is never exposed as a killed count, so a degraded
                        -- difficulty keeps its reliable total but a blank numerator.
                        local completedParts
                        local completed
                        if encounters then
                            -- The real per-boss list is authoritative. Progress is
                            -- the number of bosses whose own isKilled flag is true,
                            -- never the farthest-reached encounter index.
                            local killedCount = 0
                            for _, boss in ipairs(encounters) do
                                if boss.killed == true then killedCount = killedCount + 1 end
                            end
                            completedParts = killedCount
                            if killedCount == numEncounters then completed = true end
                        end
                        state = {
                            completedParts = completedParts,
                            totalParts = numEncounters,
                            difficulty = type(difficulty) == "number" and difficulty or nil,
                            difficultyLabel = label,
                            encounters = encounters,
                            -- Only a reliable per-boss list can prove a full clear;
                            -- the aggregate farthest index is never a killed count.
                            completed = completed,
                        }
                        ranked[rank] = state
                    end
                    -- A retail lockout is reported once per difficulty; taking the
                    -- max guards against any duplicate row without over-counting.
                    if numEncounters > state.totalParts then state.totalParts = numEncounters end
                    if type(reset) == "number" and reset >= 0 and type(nowValue) == "number" then
                        local resetsAt = nowValue + reset
                        if state.resetsAt == nil or resetsAt < state.resetsAt then state.resetsAt = resetsAt end
                    end
                end
            elseif not seenInstances[instanceId] then
                seenInstances[instanceId] = true
                local state = states[mapping.columnId] or {
                    progress = 0,
                    total = 0,
                    completedParts = 0,
                    totalParts = mapping.totalParts,
                }
                if type(difficulty) == "number" then state.difficulty = difficulty end
                if type(numEncounters) == "number" and type(encounterProgress) == "number" then
                    state.total = state.total + numEncounters
                    state.progress = state.progress + encounterProgress
                    if numEncounters > 0 and encounterProgress >= numEncounters then
                        state.completedParts = state.completedParts + 1
                    end
                end
                if type(reset) == "number" and reset >= 0 and type(nowValue) == "number" then
                    local resetsAt = nowValue + reset
                    if state.resetsAt == nil or resetsAt < state.resetsAt then state.resetsAt = resetsAt end
                end
                states[mapping.columnId] = state
            end
        end
    end

    -- Collapse each retail column to its representative difficulty while keeping
    -- every difficulty's own count in a sorted `difficulties` array. The
    -- representative is the highest difficulty carrying progress; when none has
    -- any kills yet it falls back to the highest difficulty so a fresh lockout
    -- still renders as 0/N instead of disappearing. The column keeps the nearest
    -- difficulty reset, so each difficulty still expires on its own timestamp.
    for columnId, ranked in pairs(byDifficulty) do
        local difficulties = {}
        local best
        for _, entry in pairs(ranked) do
            difficulties[#difficulties + 1] = entry
            if not best then
                best = entry
            else
                local entryProgress = type(entry.completedParts) == "number" and entry.completedParts > 0
                local bestProgress = type(best.completedParts) == "number" and best.completedParts > 0
                local entryRank = difficultyRank(entry.difficultyLabel)
                local bestRank = difficultyRank(best.difficultyLabel)
                if entryProgress and not bestProgress then
                    best = entry
                elseif entryProgress == bestProgress and entryRank > bestRank then
                    best = entry
                end
            end
        end
        table.sort(difficulties, function(a, b)
            return difficultyRank(a.difficultyLabel) < difficultyRank(b.difficultyLabel)
        end)
        if best then
            local resetsAt
            for _, entry in ipairs(difficulties) do
                if type(entry.resetsAt) == "number" and (resetsAt == nil or entry.resetsAt < resetsAt) then
                    resetsAt = entry.resetsAt
                end
            end
            states[columnId] = {
                difficulty = best.difficulty,
                difficultyLabel = best.difficultyLabel,
                completedParts = best.completedParts,
                totalParts = best.totalParts,
                progress = best.completedParts,
                total = best.totalParts,
                resetsAt = resetsAt,
                difficulties = difficulties,
                completed = best.completed,
            }
        end
    end

    for _, state in pairs(states) do
        -- Retail (per-difficulty) states already carry their representative's
        -- reliable completion above; this flat aggregate is the classic family's
        -- "every mapped instance cleared" check.
        if type(state.difficulties) ~= "table" then
            if state.totalParts > 0 and state.completedParts == state.totalParts then
                state.completed = true
            end
        end
    end
    if next(states) == nil then return nil end
    return states
end

local function professionTexture(api, name)
    local texture = M.safeCall(api and api.GetSpellTexture, name)
    if type(texture) == "number" or (type(texture) == "string" and texture ~= "") then
        return texture
    end
    local spellApi = api and api.C_Spell
    texture = M.safeCall(type(spellApi) == "table" and spellApi.GetSpellTexture or nil, name)
    if type(texture) == "number" or (type(texture) == "string" and texture ~= "") then
        return texture
    end
    local ok, _, _, legacyTexture = callAll(api and api.GetSpellInfo, name)
    if ok and (type(legacyTexture) == "number"
        or (type(legacyTexture) == "string" and legacyTexture ~= "")) then
        return legacyTexture
    end
end

-- Some Classic-family clients expose GetProfessions but return no primary
-- profession indexes. Their own skill-line list still marks primary skills as
-- abandonable, which lets us read the logged-in character without a localized
-- profession-name table or access to another player.
local function readSkillLineProfessions(api)
    local ok, count = callAll(api and api.GetNumSkillLines)
    if not ok or type(count) ~= "number" then return nil end
    local result = {}
    for index = 1, count do
        local infoOk, name, isHeader, _, rank, _, _, maxRank, isAbandonable =
            callAll(api.GetSkillLineInfo, index)
        if infoOk and isHeader ~= true and (isAbandonable == true or isAbandonable == 1)
            and type(name) == "string" and name ~= "" then
            result[#result + 1] = {
                name = name,
                skill = type(rank) == "number" and rank or nil,
                maxSkill = type(maxRank) == "number" and maxRank or nil,
                icon = professionTexture(api, name),
            }
            if #result == 2 then break end
        end
    end
    if #result == 0 then return nil end
    return result
end

-- Reads the two primary professions into an index-keyed table (position 1 and
-- 2 only; secondary skills are intentionally not part of this overview).
function M.readProfessions(api)
    local getProfs = api and api.GetProfessions
    local getInfo = api and api.GetProfessionInfo
    local result = {}
    if type(getProfs) == "function" and type(getInfo) == "function" then
        local _, prof1, prof2 = callAll(getProfs)
        for position, index in ipairs({ prof1, prof2 }) do
            if type(index) == "number" then
                local ok, name, texture, rank, maxRank = callAll(getInfo, index)
                if ok and type(name) == "string" and name ~= "" then
                    result[position] = {
                        name = name,
                        skill = type(rank) == "number" and rank or nil,
                        maxSkill = type(maxRank) == "number" and maxRank or nil,
                        icon = (type(texture) == "number" or (type(texture) == "string" and texture ~= ""))
                            and texture or nil,
                    }
                end
            end
        end
    end
    if next(result) ~= nil then return result end
    return readSkillLineProfessions(api)
end

local function resourceWhitelist(columns)
    local keys, prefixes, cooldownSpells = {}, {}, {}
    for _, column in ipairs(columns or {}) do
        local source = type(column) == "table" and column.source or nil
        if type(source) == "table" then
            if source.kind == "currency" then
                keys[source.key or column.id] = true
            elseif source.kind == "tracked-items" and type(source.prefix) == "string" then
                prefixes[source.prefix] = true
            elseif source.kind == "profession-cooldown" and type(source.spellId) == "number" then
                cooldownSpells[source.key or column.id] = source.spellId
            end
        end
    end
    return keys, prefixes, cooldownSpells
end

local function normalizeCurrencyRecord(family, key, record)
    -- The currency API uses zero when a weekly limit is unavailable or not
    -- represented by the client. Zero is not a usable cap and must not be
    -- presented as one.
    if type(record.maxWeeklyQuantity) == "number" and record.maxWeeklyQuantity <= 0 then
        record.maxWeeklyQuantity = nil
    end
    if family ~= "mop" or key ~= "valor" then return record end
    local weekly = record.quantityEarnedThisWeek
    local maximum = record.maxQuantity
    if type(weekly) ~= "number" or type(maximum) ~= "number" or maximum <= 0 then return record end

    -- Some Mists Classic clients report Valor earned in hundredths while the
    -- other fields use whole points. Only correct the value when the raw amount
    -- is impossible against the total cap and the scaled value fits that cap.
    if weekly > maximum and weekly % 100 == 0 and weekly / 100 <= maximum then
        record.quantityEarnedThisWeek = weekly / 100
    end
    return record
end

-- Reads only resources that the current family's explicit catalog declares.
-- A readable API alone is not permission to collect a value: absent and
-- pending columns stay absent from the snapshot as well as the UI.
function M.readResources(api, family, resourceColumns, selection)
    local scoped = type(selection) == "table"
    local wantCurrencies = not scoped or selection.currencies == true
    local wantItems = not scoped or selection.items == true
    local wantCooldowns = not scoped or selection.professionCooldowns == true
    local result = {}
    if wantCurrencies then result.currencies = {} end
    if wantItems then result.items = {} end
    local allowedKeys, allowedPrefixes, allowedCooldowns = resourceWhitelist(resourceColumns)

    local getHonor = api and api.UnitHonor
    if wantCurrencies and allowedKeys.honor and type(getHonor) == "function" then
        local honor = M.safeCall(getHonor, "player")
        if type(honor) == "number" then result.currencies.honor = honor end
    end

    local getRest = api and api.GetXPExhaustion
    local getRestModern = api and api.C_PlayerInfo and api.C_PlayerInfo.GetRestExperience or nil
    if wantCurrencies and allowedKeys.restXp and (type(getRest) == "function" or type(getRestModern) == "function") then
        local restXp = M.readRestExperience(api)
        if type(restXp) == "number" then result.currencies.restXp = restXp end
    end

    local ids = CURRENCY_IDS[family]
    local getCurrency = api and api.GetCurrencyInfo
    if type(getCurrency) ~= "function" and type(api and api.C_CurrencyInfo) == "table" then
        getCurrency = api.C_CurrencyInfo.GetCurrencyInfo
    end
    -- MoP and Retail currencies carry weekly caps; their snapshots record the
    -- cap fields alongside the amount. Legacy families keep a plain count.
    local readCaps = family == "mop" or family == "retail"
    if wantCurrencies and ids and type(getCurrency) == "function" then
        for key, id in pairs(ids) do
            if allowedKeys[key] and type(id) == "number" then
                local ok, first, amount = callAll(getCurrency, id)
                if ok and type(first) == "table" then
                    if readCaps then
                        local record = {}
                        for _, field in ipairs({ "quantity", "maxQuantity", "quantityEarnedThisWeek", "maxWeeklyQuantity" }) do
                            if type(first[field]) == "number" then record[field] = first[field] end
                        end
                        normalizeCurrencyRecord(family, key, record)
                        if type(record.quantity) == "number" then result.currencies[key] = record end
                    else
                        amount = first.quantity
                    end
                end
                if not readCaps and ok and type(amount) == "number" then
                    result.currencies[key] = amount
                end
            end
        end
    end

    local itemIds = ITEM_IDS[family]
    local getCount = api and api.GetItemCount
    if wantItems and itemIds and type(getCount) == "function" then
        for key, itemId in pairs(itemIds) do
            if allowedKeys[key] and type(itemId) == "number" then
                local count = M.safeCall(getCount, itemId, true)
                if type(count) == "number" then
                    result.items[key] = count
                end
            end
        end
    end

    if wantItems and family == "titan" and allowedPrefixes["legendary:"] and type(getCount) == "function" then
        for _, group in ipairs(TITAN_LEGENDARY_GROUPS) do
            for _, itemId in ipairs(group) do
                local count = M.safeCall(getCount, itemId, true)
                if type(count) == "number" and count > 0 then
                    result.items["legendary:" .. tostring(itemId)] = count
                    break
                end
            end
        end
    end
    if wantItems and family == "titan" and allowedPrefixes["upgrade:"] and type(getCount) == "function" then
        for _, itemId in ipairs(TITAN_UPGRADE_ITEMS) do
            local count = M.safeCall(getCount, itemId, true)
            if type(count) == "number" and count > 0 then
                result.items["upgrade:" .. tostring(itemId)] = count
            end
        end
    end

    if wantCooldowns then
        local cooldowns = {}
        for key, spellId in pairs(allowedCooldowns) do
            local entry = M.readProfessionCooldown(api, spellId)
            if type(entry) == "table" and next(entry) ~= nil then
                cooldowns[key] = entry
            end
        end
        if next(cooldowns) ~= nil then result.professionCooldowns = cooldowns end
    end

    if next(result.currencies or {}) == nil and next(result.items or {}) == nil
        and next(result.professionCooldowns or {}) == nil then return nil end
    return result
end

-- Builds the environment the collector consumes. Every entry is a zero-argument
-- reader so the collector can treat missing APIs and protected values uniformly.
function M.readers(family, api, raidColumns, resourceColumns)
    return {
        playerName = function() return M.readPlayerName(api) end,
        realmId = function() return M.readRealmId(api) end,
        realmName = function() return M.readRealmName(api) end,
        faction = function() return M.readFaction(api) end,
        class = function() return M.readClass(api) end,
        level = function() return M.readLevel(api) end,
        itemLevel = function() return M.readItemLevel(api) end,
        money = function() return M.readMoney(api) end,
        now = function() return M.readNow(api) end,
        equipment = function() return M.readEquipment(api) end,
        raidStates = function() return M.readRaidStates(api, raidColumns, family) end,
        professions = function() return M.readProfessions(api) end,
        resources = function(selection) return M.readResources(api, family, resourceColumns, selection) end,
    }
end

function M.currencyId(family, columnId)
    local ids = CURRENCY_IDS[family]
    if not ids or type(columnId) ~= "string" then return nil end
    return ids[columnId]
end

-- A column is verified only when this client family has a confirmed reader for
-- it. Unverified columns must be hidden rather than rendered with a guess.
function M.isVerifiedColumn(family, columnId)
    return M.currencyId(family, columnId) ~= nil
end

-- Reports whether the current client exposes every API needed to populate one
-- declared column. Catalog presence alone is never treated as runtime support.
function M.canReadColumn(family, api, column)
    if not M.isFamily(family) or type(api) ~= "table" or type(column) ~= "table" then return false end
    local source = column.source or {}
    if source.kind == "raid" then
        return source.readable == true and type(source.instanceIds) == "table" and #source.instanceIds > 0
            and type(api.GetNumSavedInstances) == "function"
            and type(api.GetSavedInstanceInfo) == "function"
    end
    if source.kind == "money" then return type(api.GetMoney) == "function" end
    if source.kind == "equipment" then
        return type(api.GetInventoryItemLink) == "function"
            and (type(api.GetItemInfoInstant) == "function"
                or type(api.GetItemInfo) == "function" or type(api.GetItemIcon) == "function")
    end
    if source.kind == "profession" or source.kind == "profession-summary" then
        return (type(api.GetProfessions) == "function" and type(api.GetProfessionInfo) == "function")
            or (type(api.GetNumSkillLines) == "function" and type(api.GetSkillLineInfo) == "function")
    end
    if source.kind == "currency" then
        local key = source.key or column.id
        local currencyId = CURRENCY_IDS[family] and CURRENCY_IDS[family][key]
        if type(currencyId) == "number" then
            return type(api.GetCurrencyInfo) == "function"
                or (type(api.C_CurrencyInfo) == "table" and type(api.C_CurrencyInfo.GetCurrencyInfo) == "function")
        end
        if key == "honor" then return type(api.UnitHonor) == "function" end
        if key == "restXp" then
            return type(api.GetXPExhaustion) == "function"
                or (type(api.C_PlayerInfo) == "table" and type(api.C_PlayerInfo.GetRestExperience) == "function")
        end
        local itemId = ITEM_IDS[family] and ITEM_IDS[family][key]
        if type(itemId) == "number" then return type(api.GetItemCount) == "function" end
        return false
    end
    if source.kind == "profession-cooldown" then
        return type(source.spellId) == "number"
            and (type(api.GetSpellCooldown) == "function"
                or (type(api.C_Spell) == "table" and type(api.C_Spell.GetSpellCooldown) == "function"))
            and resolveSpellName(api, source.spellId) ~= nil
    end
    if source.kind == "tracked-items" then return type(api.GetItemCount) == "function" end
    return false
end

BG.BGNext.OwnCharactersAdapters = M
return M
