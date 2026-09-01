BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Deterministic plain-text codecs for exporting and importing leader starting
-- price schemes and per-character personal expectations. The format is a strict,
-- newline-delimited record: a typed prefix (BGNP-L1 / BGNP-P1), a version line,
-- a client family, a raid id, and then either preset blocks (leader) or a flat
-- item list (personal). Names are the only percent-escaped field. Parsing and
-- applying are separated so a preview is always available before any mutation;
-- apply rebuilds a fully sanitized result and writes it once, so a rejected
-- import never changes the saved root.
local M = {}

M.MAX_TEXT_BYTES = 65536
M.MAX_MONEY = 10000000
M.MAX_PRESETS = 20
M.MAX_ITEMS = 500
M.MAX_NAME_CHARS = 24

local PREFIX_LEADER = "BGNP-L1"
local PREFIX_PERSONAL = "BGNP-P1"

local function escape(value)
    value = tostring(value)
    return (value:gsub("%%", "%%25")
                 :gsub("\n", "%%0A")
                 :gsub("\r", "%%0D"))
end

-- Returns nil on a malformed escape (a "%" not followed by two hex digits) so a
-- corrupt name rejects the whole record instead of silently decoding.
local function unescape(value)
    local out, i, n = {}, 1, #value
    while i <= n do
        local c = value:sub(i, i)
        if c == "%" then
            local code = tonumber(value:sub(i + 1, i + 2), 16)
            if not code then return nil end
            out[#out + 1] = string.char(code)
            i = i + 3
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

-- Counts UTF-8 code points, rejecting malformed sequences so a name is never
-- truncated mid-character.
local function utf8CodePoints(s)
    if type(s) ~= "string" then return nil end
    local count, i, n = 0, 1, #s
    while i <= n do
        local b = s:byte(i)
        local length
        if b < 0x80 then
            length = 1
        elseif b >= 0xC0 and b <= 0xDF then
            length = 2
        elseif b >= 0xE0 and b <= 0xEF then
            length = 3
        elseif b >= 0xF0 and b <= 0xF7 then
            length = 4
        else
            return nil
        end
        if i + length - 1 > n then return nil end
        for j = 1, length - 1 do
            local c = s:byte(i + j)
            if not c or c < 0x80 or c > 0xBF then return nil end
        end
        count = count + 1
        i = i + length
    end
    return count
end

local function countKeys(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function nextPresetId(presets)
    local i = 1
    while presets["p" .. i] ~= nil do i = i + 1 end
    return "p" .. i
end

local function presetSortNumber(id)
    local n = tonumber(type(id) == "string" and id:match("p(%d+)"))
    return n or 0
end

-- Skips items not present in `knownItems` (unknown items are never written) and
-- drops any non-numeric residue.
local function sanitizeItems(itemPrices, unknownItems)
    local out = {}
    for itemId, price in pairs(itemPrices or {}) do
        if type(itemId) == "number" and type(price) == "number" then
            if not (unknownItems and unknownItems[itemId]) then
                out[itemId] = price
            end
        end
    end
    return out
end

local function collectUnknown(itemPrices, knownItemSet)
    local unknown = {}
    if type(knownItemSet) == "table" then
        for itemId in pairs(itemPrices or {}) do
            if not knownItemSet[itemId] then unknown[itemId] = true end
        end
    end
    return unknown
end

-- ---------------------------------------------------------------------------
-- Export
-- ---------------------------------------------------------------------------

function M.exportLeader(clientFamily, raidId, leaderRaid, scope)
    if type(clientFamily) ~= "string" or type(raidId) ~= "string" or type(leaderRaid) ~= "table" then
        return nil
    end
    local presets = leaderRaid.presets
    if type(presets) ~= "table" then return nil end

    local lines = { PREFIX_LEADER, "version=1", "family=" .. clientFamily, "raid=" .. raidId }

    local ids = {}
    if scope == "all" then
        for id in pairs(presets) do ids[#ids + 1] = id end
    else
        local active = leaderRaid.activePresetId
        if active ~= nil and type(presets[active]) == "table" then ids = { active } end
    end
    table.sort(ids, function(a, b) return presetSortNumber(a) < presetSortNumber(b) end)

    for _, id in ipairs(ids) do
        local preset = presets[id]
        if type(preset) == "table" then
            lines[#lines + 1] = "preset=" .. tostring(id)
            lines[#lines + 1] = "name=" .. escape(preset.name or "")
            lines[#lines + 1] = "base=" .. tostring(preset.basePrice or 0)
            local itemIds = {}
            local itemPrices = preset.itemPrices
            if type(itemPrices) == "table" then
                for itemId in pairs(itemPrices) do itemIds[#itemIds + 1] = itemId end
            end
            table.sort(itemIds)
            for _, itemId in ipairs(itemIds) do
                lines[#lines + 1] = "item=" .. tostring(itemId) .. ":" .. tostring(itemPrices[itemId])
            end
        end
    end

    return table.concat(lines, "\n")
end

function M.exportPersonal(clientFamily, raidId, itemPrices)
    if type(clientFamily) ~= "string" or type(raidId) ~= "string" then return nil end
    local lines = { PREFIX_PERSONAL, "version=1", "family=" .. clientFamily, "raid=" .. raidId }
    if type(itemPrices) == "table" then
        local itemIds = {}
        for itemId in pairs(itemPrices) do itemIds[#itemIds + 1] = itemId end
        table.sort(itemIds)
        for _, itemId in ipairs(itemIds) do
            lines[#lines + 1] = "item=" .. tostring(itemId) .. ":" .. tostring(itemPrices[itemId])
        end
    end
    return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
-- Parse
-- ---------------------------------------------------------------------------

-- Parses text into a preview descriptor. The preview carries `ok` plus either a
-- `reason` (when rejected) or the decoded type, clientFamily, raidId, presets /
-- itemPrices, item counts and the set of unknown item ids. Parsing never mutates
-- the saved root.
function M.parse(text, expectedType, knownItemSet)
    local preview = { ok = false }
    if type(text) ~= "string" then
        preview.reason = "invalid input"
        return preview
    end
    if #text > M.MAX_TEXT_BYTES then
        preview.reason = "text too long"
        return preview
    end

    local lines = {}
    for line in text:gmatch("[^\r\n]+") do
        lines[#lines + 1] = line
    end

    local kind
    local prefix = lines[1]
    if prefix == PREFIX_LEADER then
        kind = "leader"
    elseif prefix == PREFIX_PERSONAL then
        kind = "personal"
    else
        preview.reason = "unknown format"
        return preview
    end
    if expectedType ~= nil and expectedType ~= kind then
        preview.reason = "type mismatch"
        return preview
    end
    if lines[2] ~= "version=1" then
        preview.reason = "unsupported version"
        return preview
    end

    local clientFamily, raidId
    local presets, itemPrices = {}, {}
    local currentPreset

    for i = 3, #lines do
        local line = lines[i]
        local key, value = line:match("^([^=]+)=(.*)$")
        if not key then
            preview.reason = "malformed line"
            return preview
        end
        if key == "family" then
            clientFamily = value
        elseif key == "raid" then
            raidId = value
        elseif key == "preset" then
            if kind ~= "leader" then
                preview.reason = "unexpected preset in personal record"
                return preview
            end
            if presets[value] ~= nil then
                preview.reason = "duplicate preset"
                return preview
            end
            currentPreset = value
            presets[value] = { name = nil, basePrice = nil, itemPrices = {} }
        elseif key == "name" then
            if kind ~= "leader" or currentPreset == nil then
                preview.reason = "name without preset"
                return preview
            end
            local decoded = unescape(value)
            if decoded == nil then
                preview.reason = "malformed escape"
                return preview
            end
            presets[currentPreset].name = decoded
        elseif key == "base" then
            if kind ~= "leader" or currentPreset == nil then
                preview.reason = "base without preset"
                return preview
            end
            local n = tonumber(value)
            if not n or n % 1 ~= 0 or n < 0 or n > M.MAX_MONEY then
                preview.reason = "invalid base price"
                return preview
            end
            presets[currentPreset].basePrice = n
        elseif key == "item" then
            local idStr, priceStr = value:match("^(%d+):(%d+)$")
            if not idStr then
                preview.reason = "invalid item line"
                return preview
            end
            local id, price = tonumber(idStr), tonumber(priceStr)
            if id == nil or id < 1 or price == nil or price > M.MAX_MONEY then
                preview.reason = "invalid item value"
                return preview
            end
            if kind == "leader" then
                if currentPreset == nil then
                    preview.reason = "item without preset"
                    return preview
                end
                presets[currentPreset].itemPrices[id] = price
            else
                itemPrices[id] = price
            end
        else
            preview.reason = "unknown field"
            return preview
        end
    end

    if type(clientFamily) ~= "string" or clientFamily == "" then
        preview.reason = "missing family"
        return preview
    end
    if type(raidId) ~= "string" or raidId == "" then
        preview.reason = "missing raid"
        return preview
    end

    if kind == "leader" then
        local presetCount = countKeys(presets)
        if presetCount < 1 then
            preview.reason = "no presets"
            return preview
        end
        if presetCount > M.MAX_PRESETS then
            preview.reason = "too many presets"
            return preview
        end
        local itemCount = 0
        local unknown = {}
        for _, preset in pairs(presets) do
            if type(preset.name) ~= "string" or utf8CodePoints(preset.name) == nil
                or utf8CodePoints(preset.name) < 1 or utf8CodePoints(preset.name) > M.MAX_NAME_CHARS then
                preview.reason = "invalid name"
                return preview
            end
            if type(preset.basePrice) ~= "number" then
                preview.reason = "missing base price"
                return preview
            end
            local n = countKeys(preset.itemPrices)
            if n > M.MAX_ITEMS then
                preview.reason = "too many items"
                return preview
            end
            itemCount = itemCount + n
            for itemId in pairs(preset.itemPrices) do
                if type(knownItemSet) == "table" and not knownItemSet[itemId] then
                    unknown[itemId] = true
                end
            end
        end
        preview.ok = true
        preview.type = kind
        preview.clientFamily = clientFamily
        preview.raidId = raidId
        preview.presets = presets
        preview.presetCount = presetCount
        preview.itemCount = itemCount
        preview.unknownItems = unknown
    else
        local itemCount = countKeys(itemPrices)
        if itemCount > M.MAX_ITEMS then
            preview.reason = "too many items"
            return preview
        end
        preview.ok = true
        preview.type = kind
        preview.clientFamily = clientFamily
        preview.raidId = raidId
        preview.itemPrices = itemPrices
        preview.itemCount = itemCount
        preview.unknownItems = collectUnknown(itemPrices, knownItemSet)
    end

    return preview
end

-- ---------------------------------------------------------------------------
-- Apply
-- ---------------------------------------------------------------------------

local function uniqueName(base, taken)
    if not taken[base] then
        taken[base] = true
        return base
    end
    local candidate = base .. "（导入）"
    if not taken[candidate] then
        taken[candidate] = true
        return candidate
    end
    local i = 2
    while taken[candidate .. i] do i = i + 1 end
    candidate = candidate .. i
    taken[candidate] = true
    return candidate
end

-- Applies a leader preview to the saved root atomically. `options.mode` is
-- "new" (add as new schemes, renaming on name clash), "replace-current" (single
-- imported scheme overwrites the active one) or "replace-all" (imported schemes
-- replace every existing scheme). `options.clientFamily` / `options.raidId`,
-- when present, must match the preview or the apply is refused.
function M.applyLeader(root, preview, options)
    if type(root) ~= "table" or not preview or preview.ok ~= true or preview.type ~= "leader" then
        return false
    end
    options = options or {}
    if type(options.clientFamily) == "string" and options.clientFamily ~= ""
        and options.clientFamily ~= preview.clientFamily then
        return false
    end
    if type(options.raidId) == "string" and options.raidId ~= ""
        and options.raidId ~= preview.raidId then
        return false
    end
    local clientFamily = preview.clientFamily
    local raidId = preview.raidId
    if type(clientFamily) ~= "string" or clientFamily == "" or type(raidId) ~= "string" or raidId == "" then
        return false
    end

    local mode = options.mode or "new"

    -- Sanitize imported presets into a deterministic order.
    local imported = {}
    for id, preset in pairs(preview.presets or {}) do
        imported[#imported + 1] = {
            name = preset.name,
            basePrice = preset.basePrice,
            itemPrices = sanitizeItems(preset.itemPrices, preview.unknownItems),
            _id = id,
        }
    end
    table.sort(imported, function(a, b) return presetSortNumber(a._id) < presetSortNumber(b._id) end)
    if #imported == 0 then return false end

    local store = root.leaderAuctionPricePresets
    local existing
    if type(store) == "table" and type(store[clientFamily]) == "table"
        and type(store[clientFamily][raidId]) == "table" then
        existing = store[clientFamily][raidId]
    end

    local newPresets = {}
    local newActive

    if mode == "replace-all" then
        for i, preset in ipairs(imported) do
            newPresets["p" .. i] = preset
        end
        newActive = "p1"
    elseif mode == "replace-current" then
        if #imported ~= 1 then return false end
        if existing and type(existing.presets) == "table" then
            for id, preset in pairs(existing.presets) do
                newPresets[id] = preset
            end
        end
        local active = (existing and existing.activePresetId) or "p1"
        newPresets[active] = imported[1]
        newActive = active
    else -- "new"
        if existing and type(existing.presets) == "table" then
            for id, preset in pairs(existing.presets) do
                newPresets[id] = preset
            end
        end
        local taken = {}
        for _, preset in pairs(newPresets) do
            if type(preset) == "table" then taken[preset.name] = true end
        end
        for _, preset in ipairs(imported) do
            local id = nextPresetId(newPresets)
            newPresets[id] = {
                name = uniqueName(preset.name, taken),
                basePrice = preset.basePrice,
                itemPrices = preset.itemPrices,
            }
        end
        newActive = (existing and existing.activePresetId) or "p1"
    end

    -- Enforce limits over the assembled result before any write.
    local count = countKeys(newPresets)
    if count < 1 or count > M.MAX_PRESETS then return false end
    for _, preset in pairs(newPresets) do
        if type(preset) ~= "table" then return false end
        if type(preset.name) ~= "string" or type(preset.basePrice) ~= "number" then return false end
        if countKeys(preset.itemPrices) > M.MAX_ITEMS then return false end
    end

    if type(store) ~= "table" then
        store = {}
        root.leaderAuctionPricePresets = store
    end
    if type(store[clientFamily]) ~= "table" then store[clientFamily] = {} end
    if type(store[clientFamily][raidId]) ~= "table" then store[clientFamily][raidId] = {} end
    local raid = store[clientFamily][raidId]
    raid.presets = newPresets
    raid.activePresetId = newActive
    return true
end

-- Writes (or prunes) the personal itemPrices for one character/raid. Empty
-- results remove the raid record and prune every emptied ancestor.
local function writePersonal(root, clientFamily, realmId, player, raidId, itemPrices)
    local store = root.personalAuctionExpectations
    if countKeys(itemPrices) == 0 then
        if type(store) == "table" and type(store[clientFamily]) == "table"
            and type(store[clientFamily][realmId]) == "table"
            and type(store[clientFamily][realmId][player]) == "table" then
            store[clientFamily][realmId][player][raidId] = nil
            if next(store[clientFamily][realmId][player]) == nil then store[clientFamily][realmId][player] = nil end
            if next(store[clientFamily][realmId]) == nil then store[clientFamily][realmId] = nil end
            if next(store[clientFamily]) == nil then store[clientFamily] = nil end
            if next(store) == nil then root.personalAuctionExpectations = nil end
        end
        return true
    end
    if type(store) ~= "table" then
        store = {}
        root.personalAuctionExpectations = store
    end
    if type(store[clientFamily]) ~= "table" then store[clientFamily] = {} end
    if type(store[clientFamily][realmId]) ~= "table" then store[clientFamily][realmId] = {} end
    if type(store[clientFamily][realmId][player]) ~= "table" then store[clientFamily][realmId][player] = {} end
    store[clientFamily][realmId][player][raidId] = { itemPrices = itemPrices }
    return true
end

-- Applies a personal preview to the saved root for one character atomically.
-- `context` carries clientFamily, realmId, player and raidId; a client-family or
-- raid mismatch with the preview is refused. `options.mode` is "merge" (import
-- values overwrite existing) or "replace" (existing prices are cleared first).
function M.applyPersonal(root, context, preview, options)
    if type(root) ~= "table" or not preview or preview.ok ~= true or preview.type ~= "personal" then
        return false
    end
    if type(context) ~= "table" then return false end
    local clientFamily = context.clientFamily
    local realmId = context.realmId
    local player = context.player
    local raidId = context.raidId
    if type(clientFamily) ~= "string" or clientFamily == "" then return false end
    if type(realmId) ~= "string" or realmId == "" then return false end
    if type(player) ~= "string" or player == "" then return false end
    if type(raidId) ~= "string" or raidId == "" then return false end
    if preview.clientFamily ~= clientFamily then return false end
    if preview.raidId ~= raidId then return false end

    local mode = (options and options.mode) or "merge"
    local sanitized = sanitizeItems(preview.itemPrices, preview.unknownItems)

    local merged = {}
    if mode == "merge" then
        local store = root.personalAuctionExpectations
        if type(store) == "table" and type(store[clientFamily]) == "table"
            and type(store[clientFamily][realmId]) == "table"
            and type(store[clientFamily][realmId][player]) == "table"
            and type(store[clientFamily][realmId][player][raidId]) == "table"
            and type(store[clientFamily][realmId][player][raidId].itemPrices) == "table" then
            for itemId, price in pairs(store[clientFamily][realmId][player][raidId].itemPrices) do
                merged[itemId] = price
            end
        end
    end
    for itemId, price in pairs(sanitized) do
        merged[itemId] = price
    end

    if countKeys(merged) > M.MAX_ITEMS then return false end

    return writePersonal(root, clientFamily, realmId, player, raidId, merged)
end

BG.BGNext.AuctionPriceCodec = M
return M
