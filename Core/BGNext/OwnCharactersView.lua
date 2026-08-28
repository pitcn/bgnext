-- BGNext own-character projection.
--
-- Turns stored snapshots plus column settings into a pure table model:
-- characters are rows, catalog descriptors are columns. Loadable with plain
-- Lua 5.1 — it must never call CreateFrame, touch SavedVariables, read item or
-- time APIs, or mutate the snapshots it is given.
--
-- The renderer consumes this projection and nothing else, which is what keeps
-- client differences out of the drawing code.

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local AddonName, ns = ...
local L = ns and ns.L or setmetatable({}, { __index = function(_, key) return tostring(key) end })

local M = {}

-- Geometry constants. These are the calibration surface for in-game screenshot
-- review; the renderer must not invent its own sizes.
M.metrics = {
    rowHeight = 20,
    headerHeight = 22,
    sectionTitleHeight = 24,
    totalsRowHeight = 20,
    iconSize = 19,
    iconGap = 1,
    columnGap = 8,
    sectionControlWidth = 18,
    nameColumnWidth = 120,
    sectionGap = 10,
    padding = 8,
    columnWidths = { narrow = 44, normal = 64, wide = 110 },
}

M.titles = {
    raid = "< 角色团本完成总览 >",
    resource = "< 角色货币总览 >",
}

M.hints = {
    raid = "（团本重置时间：",
    resource = "（鼠标中键固定显示，长按SHIFT显示全服务器角色）",
}

local EQUIPMENT_SLOTS = 19

local function isNonEmptyString(value)
    return type(value) == "string" and value ~= ""
end

-- Returns the first `count` UTF-8 codepoints of a string. Realm names are
-- Chinese on the target clients, so a byte-wise substring would split a
-- character in half.
local function utf8Prefix(text, count)
    if type(text) ~= "string" then return "" end
    local taken, index = 0, 1
    local length = #text
    while index <= length and taken < count do
        local byte = string.byte(text, index)
        local size = 1
        if byte >= 240 then size = 4
        elseif byte >= 224 then size = 3
        elseif byte >= 192 then size = 2 end
        index = index + size
        taken = taken + 1
    end
    return string.sub(text, 1, index - 1)
end

local SHORT_REALM_CODEPOINTS = 2
local MAX_REALM_CODEPOINTS = 24

local function realmLabel(snapshot)
    if isNonEmptyString(snapshot.realmName) then return snapshot.realmName end
    return tostring(snapshot.realmId)
end

-- Picks the shortest realm prefix that is still unique among the colliding
-- realms. Two anniversary realms such as "时光II" and "时光III" share their
-- leading characters, so a fixed-length prefix would render two same-name
-- characters identically.
local function shortRealmPrefixes(realmNames)
    for length = SHORT_REALM_CODEPOINTS, MAX_REALM_CODEPOINTS do
        local prefixes, seen, collision = {}, {}, false
        for _, name in ipairs(realmNames) do
            local prefix = utf8Prefix(name, length)
            if seen[prefix] then collision = true break end
            seen[prefix] = true
            prefixes[name] = prefix
        end
        if not collision then return prefixes end
    end
    local full = {}
    for _, name in ipairs(realmNames) do full[name] = name end
    return full
end

local function isValidSnapshot(snapshot)
    if type(snapshot) ~= "table" then return false end
    if not isNonEmptyString(snapshot.player) then return false end
    if snapshot.realmId == nil then return false end
    return true
end

-- Column visibility: an explicit setting wins, otherwise the catalog default.
-- An unavailable column is dropped regardless, so a field this client cannot
-- read is never rendered.
local function visibleColumns(columns, section, visibility, available)
    local result = {}
    local overrides = (type(visibility) == "table" and type(visibility[section]) == "table")
        and visibility[section] or {}
    for _, column in ipairs(columns or {}) do
        if not available or available(section, column.id) ~= false then
            local override = overrides[column.id]
            local shown = override
            if override == nil then shown = column.defaultVisible == true end
            if shown then result[#result + 1] = column end
        end
    end
    return result
end

local function columnWidth(column)
    if type(column.width) == "number" then return column.width end
    if column.width == "dynamic-items" then
        local slots = column.slots or EQUIPMENT_SLOTS
        return slots * M.metrics.iconSize
            + math.max(0, slots - 1) * M.metrics.iconGap + 8
    end
    return M.metrics.columnWidths[column.width] or M.metrics.columnWidths.normal
end

local function sectionWidth(columns)
    local width = M.metrics.nameColumnWidth
    for index, column in ipairs(columns) do
        if index > 1 then width = width + M.metrics.columnGap end
        width = width + columnWidth(column)
    end
    return width + M.metrics.sectionControlWidth + M.metrics.padding * 2
end

function M.measureNumber(value)
    return math.max(24, #tostring(value or "") * 8 + 8)
end

local function totalText(column, totals)
    local total = totals and totals[column.id]
    if type(total) ~= "number" then return "" end
    if column.kind == "money" then return tostring(math.floor(total / 10000)) end
    return tostring(total)
end

local function measureColumns(columns, rows, totals)
    local x = M.metrics.nameColumnWidth
    for index, column in ipairs(columns) do
        local widthClass = column.width
        local width
        if widthClass == "dynamic-items" then
            width = math.max(M.metrics.columnWidths.narrow, columnWidth(column))
        elseif column.kind == "number" or column.kind == "money" then
            width = M.metrics.columnWidths.narrow
            for _, row in ipairs(rows or {}) do
                local cell = row.cells and row.cells[index]
                width = math.max(width, M.measureNumber(cell and cell.text or ""))
            end
            width = math.max(width, M.measureNumber(totalText(column, totals)))
        else
            width = columnWidth(column)
        end
        if index > 1 then x = x + M.metrics.columnGap end
        column.widthClass = widthClass
        column.width = width
        column.x = x
        x = x + width
    end
end

-- A weekly raid state is meaningful only until its official reset. Past that
-- it renders blank; it is never demoted into a previous-week record.
local function raidCell(column, snapshot, now)
    local cell = { columnId = column.id, state = "empty", text = "" }
    local states = type(snapshot.raidStates) == "table" and snapshot.raidStates or nil
    local state = states and states[column.id] or nil
    if type(state) ~= "table" then return cell end
    if type(state.resetsAt) == "number" then cell.resetsAt = state.resetsAt end
    if type(state.difficultyLabel) == "string" then cell.difficultyLabel = state.difficultyLabel end
    if type(state.resetsAt) == "number" and type(now) == "number" and now >= state.resetsAt then
        return cell
    end
    if type(state.totalParts) == "number" and state.totalParts > 1
        and type(state.completedParts) == "number" and state.completedParts < state.totalParts then
        cell.state = "progress"
        cell.progress = state.completedParts
        cell.total = state.totalParts
        cell.text = string.format("%d/%d", state.completedParts, state.totalParts)
        return cell
    end
    if type(state.progress) == "number" and type(state.total) == "number" and state.total > 0
        and state.progress < state.total then
        cell.state = "progress"
        cell.progress = state.progress
        cell.total = state.total
        cell.text = string.format("%d/%d", state.progress, state.total)
        return cell
    end
    if state.completed == true then
        cell.state = "complete"
        cell.text = ""
        return cell
    end
    if type(state.progress) == "number" and type(state.total) == "number" and state.total > 0 then
        cell.state = "complete"
        return cell
    end
    return cell
end

-- Renders the remaining time until a raid reset as a short, human-readable
-- string. Past or missing timestamps yield nil so the caller can fall back to
-- the static hint instead of showing a nonsense countdown.
function M.formatCountdown(now, resetsAt)
    if type(now) ~= "number" or type(resetsAt) ~= "number" then return nil end
    local remaining = resetsAt - now
    if remaining <= 0 then return nil end
    local days = math.floor(remaining / 86400)
    local hours = math.floor((remaining % 86400) / 3600)
    local minutes = math.floor((remaining % 3600) / 60)
    if days > 0 then
        return string.format("%d天%d小时", days, hours)
    end
    if hours > 0 then
        return string.format("%d小时%d分", hours, minutes)
    end
    if minutes > 0 then
        return string.format("%d分", minutes)
    end
    return L["不足1分钟"]
end

-- The nearest future reset across the laid-out rows. Weekly locks all reset at
-- the same maintenance, so a single countdown is meaningful; expired states
-- are ignored rather than shown as a negative countdown.
function M.nearestReset(rows, now)
    local nearest
    for _, row in ipairs(rows or {}) do
        for _, cell in ipairs(row.cells or {}) do
            local resetsAt = cell.resetsAt
            if type(resetsAt) == "number" and (type(now) ~= "number" or now < resetsAt) then
                if nearest == nil or resetsAt < nearest then nearest = resetsAt end
            end
        end
    end
    return nearest
end

local function equipmentCell(column, snapshot)
    local cell = { columnId = column.id, state = "empty", items = {} }
    local equipment = type(snapshot.equipment) == "table" and snapshot.equipment or nil
    if not equipment then return cell end
    local allowed
    if type(column.source) == "table" and type(column.source.slots) == "table" then
        allowed = {}
        for _, slot in ipairs(column.source.slots) do allowed[slot] = true end
    end
    local slots = {}
    for slot in pairs(equipment) do
        if type(slot) == "number" and (not allowed or allowed[slot]) then slots[#slots + 1] = slot end
    end
    table.sort(slots)
    for _, slot in ipairs(slots) do
        local item = equipment[slot]
        if type(item) == "table" then
            cell.items[#cell.items + 1] = {
                slot = slot,
                itemId = item.itemId,
                itemLevel = item.itemLevel,
                quality = item.quality,
                icon = item.icon,
                count = item.count,
                link = item.link,
            }
        end
    end
    if #cell.items > 0 then cell.state = "items" end
    return cell
end

local function trackedItemsCell(column, snapshot)
    local cell = { columnId = column.id, state = "empty", items = {} }
    local items = type(snapshot.items) == "table" and snapshot.items or nil
    local prefix = type(column.source) == "table" and column.source.prefix or nil
    if not items or type(prefix) ~= "string" then return cell end
    for key, count in pairs(items) do
        if type(key) == "string" and type(count) == "number" and count > 0
            and key:sub(1, #prefix) == prefix then
            local itemId = tonumber(key:sub(#prefix + 1))
            if itemId then
                cell.items[#cell.items + 1] = { itemId = itemId, count = count }
            end
        end
    end
    table.sort(cell.items, function(a, b) return a.itemId < b.itemId end)
    if #cell.items > 0 then cell.state = "items" end
    return cell
end

local function resourceCell(column, snapshot, now)
    local source = column.source or {}
    if source.kind == "equipment" then
        return equipmentCell(column, snapshot)
    end
    if source.kind == "tracked-items" then
        return trackedItemsCell(column, snapshot)
    end

    local cell = { columnId = column.id, state = "empty", text = "" }

    if source.kind == "money" then
        if type(snapshot.money) == "number" then
            cell.state = "value"
            cell.value = snapshot.money
            cell.text = tostring(math.floor(snapshot.money / 10000))
        end
        return cell
    end

    if source.kind == "profession-cooldown" then
        local key = source.key or column.id
        local cooldowns = type(snapshot.professionCooldowns) == "table" and snapshot.professionCooldowns or nil
        local entry = cooldowns and cooldowns[key] or nil
        if type(entry) == "table" then
            if entry.ready == true then
                cell.state = "complete"
                cell.ready = true
            elseif type(entry.endsAt) == "number" then
                local remaining = M.formatCountdown(now, entry.endsAt)
                if remaining then
                    cell.state = "cooldown"
                    cell.endsAt = entry.endsAt
                    cell.text = remaining
                else
                    cell.state = "complete"
                    cell.ready = true
                end
            end
        end
        return cell
    end

    if source.kind == "currency" then
        local key = source.key or column.id
        local currencies = type(snapshot.currencies) == "table" and snapshot.currencies or nil
        local value = currencies and currencies[key] or nil
        if value == nil then
            local items = type(snapshot.items) == "table" and snapshot.items or nil
            value = items and items[key] or nil
        end
        if type(value) == "table" then value = value.quantity end
        if type(value) == "number" then
            cell.state = "value"
            cell.value = value
            cell.text = tostring(value)
        end
        return cell
    end

    if source.kind == "profession" then
        local professions = type(snapshot.professions) == "table" and snapshot.professions or nil
        local entry = professions and professions[source.index or 1] or nil
        if type(entry) == "table" then
            cell.state = "profession"
            cell.name = entry.name
            cell.skill = entry.skill
            cell.maxSkill = entry.maxSkill
            cell.icon = entry.icon
            cell.cooldownEndsAt = entry.cooldownEndsAt
            if isNonEmptyString(entry.name) then
                cell.text = type(entry.skill) == "number"
                    and string.format("%s %d", entry.name, entry.skill)
                    or entry.name
            end
        end
        return cell
    end

    if source.kind == "profession-summary" then
        local professions = type(snapshot.professions) == "table" and snapshot.professions or nil
        local entries = {}
        for index = 1, 2 do
            local entry = professions and professions[index] or nil
            if type(entry) == "table" and isNonEmptyString(entry.name) then
                entries[#entries + 1] = {
                    name = entry.name,
                    skill = entry.skill,
                    maxSkill = entry.maxSkill,
                    icon = entry.icon,
                }
            end
        end
        if #entries > 0 then
            cell.state = "professions"
            cell.entries = entries
        end
        return cell
    end

    return cell
end

-- Rows are ordered current realm first, then realm, then character name, so
-- the table does not reshuffle between logins.
local function buildRows(snapshots, currentRealmId, showAllRealms)
    local rows = {}
    for _, snapshot in ipairs(snapshots or {}) do
        if isValidSnapshot(snapshot) then
            local isCurrentRealm = snapshot.realmId == currentRealmId
            if showAllRealms or isCurrentRealm then
                rows[#rows + 1] = {
                    snapshot = snapshot,
                    isCurrentRealm = isCurrentRealm,
                }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.isCurrentRealm ~= b.isCurrentRealm then return a.isCurrentRealm end
        local ra, rb = tostring(a.snapshot.realmId), tostring(b.snapshot.realmId)
        if ra ~= rb then return ra < rb end
        return tostring(a.snapshot.player) < tostring(b.snapshot.player)
    end)
    return rows
end

-- A short realm prefix appears only where a character name is ambiguous, so
-- two same-name cross-realm characters stay readable as two separate rows.
local function markAmbiguousNames(rows)
    local realmsByName = {}
    for _, row in ipairs(rows) do
        local name = row.snapshot.player
        realmsByName[name] = realmsByName[name] or { order = {}, seen = {} }
        local bucket = realmsByName[name]
        local label = realmLabel(row.snapshot)
        if not bucket.seen[label] then
            bucket.seen[label] = true
            bucket.order[#bucket.order + 1] = label
        end
    end

    local prefixesByName = {}
    for name, bucket in pairs(realmsByName) do
        if #bucket.order > 1 then
            prefixesByName[name] = shortRealmPrefixes(bucket.order)
        end
    end

    for _, row in ipairs(rows) do
        local prefixes = prefixesByName[row.snapshot.player]
        row.ambiguous = prefixes ~= nil
        row.realmPrefix = prefixes and prefixes[realmLabel(row.snapshot)] or ""
    end
end

local function baseRow(entry, family, index)
    local snapshot = entry.snapshot
    local prefix = entry.ambiguous and (entry.realmPrefix or "") or ""
    return {
        key = string.format("%s:%s:%s", tostring(family), tostring(snapshot.realmId), snapshot.player),
        player = snapshot.player,
        realmId = snapshot.realmId,
        realmName = snapshot.realmName,
        prefix = prefix,
        display = prefix ~= "" and (prefix .. "-" .. snapshot.player) or snapshot.player,
        class = snapshot.class,
        faction = snapshot.faction,
        level = snapshot.level,
        itemLevel = snapshot.itemLevel,
        stripe = (index % 2 == 1) and "dark" or "light",
        cells = {},
    }
end

function M.project(input)
    if type(input) ~= "table" then return nil end
    local catalog = input.catalog
    if type(catalog) ~= "table" then return nil end

    if catalog.status ~= "tested-in-game"
        and catalog.status ~= "pending-in-game-verification" then
        local width = 360
        local count = 0
        local raidHeight = M.metrics.sectionTitleHeight + M.metrics.headerHeight
        local resourceHeight = M.metrics.sectionTitleHeight + M.metrics.headerHeight + M.metrics.totalsRowHeight
        return {
            family = input.family,
            verificationStatus = catalog.status or "unverified",
            unsupported = true,
            isEmpty = true,
            characterCount = count,
            showAllRealms = input.showAllRealms == true,
            raid = {
                title = M.titles.raid, hint = M.hints.raid,
                nameHeader = "0个角色（装等）", characterCount = count,
                columns = {}, rows = {}, width = width,
            },
            resource = {
                title = M.titles.resource, hint = M.hints.resource,
                nameHeader = "0个角色（等级）", characterCount = count,
                columns = {}, rows = {}, totals = {}, width = width,
            },
            width = width,
            height = raidHeight + resourceHeight + M.metrics.sectionGap + M.metrics.padding * 2,
        }
    end

    local family = input.family
    local now = input.now
    local available = type(input.available) == "function" and input.available or nil

    local raidColumns = visibleColumns(catalog.raidColumns, "raid", input.visibility, available)
    local resourceColumns = visibleColumns(catalog.resourceColumns, "resource", input.visibility, available)

    local entries = buildRows(input.snapshots, input.currentRealmId, input.showAllRealms == true)
    markAmbiguousNames(entries)

    local raidRows, resourceRows = {}, {}
    local totals = {}
    local iconColumns = {}

    for index, entry in ipairs(entries) do
        local snapshot = entry.snapshot

        local raidRow = baseRow(entry, family, index)
        for _, column in ipairs(raidColumns) do
            raidRow.cells[#raidRow.cells + 1] = raidCell(column, snapshot, now)
        end
        raidRows[#raidRows + 1] = raidRow

        local resourceRow = baseRow(entry, family, index)
        for position, column in ipairs(resourceColumns) do
            local cell = resourceCell(column, snapshot, now)
            resourceRow.cells[#resourceRow.cells + 1] = cell
            if column.total == true and type(cell.value) == "number" then
                totals[column.id] = (totals[column.id] or 0) + cell.value
            end
            if column.width == "dynamic-items" then
                local drawn = #(cell.items or {})
                if drawn > (column.slots or 0) then column.slots = drawn end
                iconColumns[position] = column
            end
        end
        resourceRows[#resourceRows + 1] = resourceRow
    end

    -- An icon column is only as wide as the icons it actually draws. Empty
    -- weapon/trinket columns reserve their configured slots; other summaries
    -- reserve one icon so the compact original table does not become a wall.
    for _, column in pairs(iconColumns) do
        if (column.slots or 0) <= 0 then
            local configured = type(column.source) == "table" and column.source.slots or nil
            column.slots = type(configured) == "table" and #configured or 1
        end
    end


    measureColumns(raidColumns, raidRows, nil)
    measureColumns(resourceColumns, resourceRows, totals)

    local count = #entries
    local resetCountdown = M.formatCountdown(now, M.nearestReset(raidRows, now))
    -- Both sections share one window, so the window is as wide as the wider
    -- section. Each section also reports its own width so the renderer can
    -- lay out its header and separators without re-deriving them.
    local raidWidth = sectionWidth(raidColumns)
    local resourceWidth = sectionWidth(resourceColumns)
    local width = math.max(raidWidth, resourceWidth)

    local metrics = M.metrics
    local raidHeight = metrics.sectionTitleHeight + metrics.headerHeight + count * metrics.rowHeight
    local resourceHeight = metrics.sectionTitleHeight + metrics.headerHeight
        + count * metrics.rowHeight + metrics.totalsRowHeight
    local height = raidHeight + resourceHeight + metrics.sectionGap + metrics.padding * 2

    return {
        family = family,
        verificationStatus = catalog.status,
        isEmpty = count == 0,
        characterCount = count,
        showAllRealms = input.showAllRealms == true,
        raid = {
            title = M.titles.raid,
            hint = M.hints.raid,
            resetCountdown = resetCountdown,
            nameHeader = string.format("%d个角色（装等）", count),
            characterCount = count,
            columns = raidColumns,
            rows = raidRows,
            width = raidWidth,
        },
        resource = {
            title = M.titles.resource,
            hint = M.hints.resource,
            nameHeader = string.format("%d个角色（等级）", count),
            characterCount = count,
            columns = resourceColumns,
            rows = resourceRows,
            totals = totals,
            width = resourceWidth,
        },
        width = width,
        height = height,
    }
end

BG.BGNext.OwnCharactersView = M
return M
