BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Bounded, local-only storage shared by the leader tools. The module accepts
-- plain tables so validation and import preview never need the WoW UI.
local M = {}

local MAX_TEMPLATES, MAX_ITEMS, MAX_HISTORY = 12, 20, 500
local MAX_NAME, MAX_AMOUNT, MAX_IMPORT = 48, 1000000000, 8000
local RETENTION = { [30] = true, [90] = true, [180] = true }

local function trim(value)
    return type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
end

local function name(value)
    local result = trim(value)
    if result == "" or #result > MAX_NAME or result:find("[\r\n\t]") then return nil end
    return result
end

local function amount(value)
    local result = tonumber(value)
    if type(result) ~= "number" or result < 0 or result > MAX_AMOUNT or result % 1 ~= 0
        or result ~= result or result == math.huge then return nil end
    return result
end

local function copyTemplate(value)
    if type(value) ~= "table" then return nil end
    local templateName = name(value.name)
    if not templateName or type(value.items) ~= "table" or #value.items < 1 or #value.items > MAX_ITEMS then return nil end
    local result, seen = { name = templateName, items = {} }, {}
    for _, entry in ipairs(value.items) do
        local itemName = type(entry) == "table" and name(entry.name) or nil
        local itemAmount = type(entry) == "table" and amount(entry.amount) or nil
        local key = itemName and string.lower(itemName) or nil
        if not itemName or itemAmount == nil or seen[key] then return nil end
        seen[key] = true
        result.items[#result.items + 1] = { name = itemName, amount = itemAmount }
    end
    return result
end

local function ensureContainer(root)
    if type(root) ~= "table" then return nil end
    root.leaderTools = type(root.leaderTools) == "table" and root.leaderTools or {}
    local data = root.leaderTools
    data.expenseTemplates = type(data.expenseTemplates) == "table" and data.expenseTemplates or {}
    data.localHistory = type(data.localHistory) == "table" and data.localHistory or {}
    if not RETENTION[data.historyRetentionDays] then data.historyRetentionDays = 90 end
    return data
end

local function sanitizeHistory(entry)
    if type(entry) ~= "table" then return nil end
    local itemId, entryAmount, at = tonumber(entry.itemId), amount(entry.amount), tonumber(entry.time)
    local sourceFb = name(entry.sourceFb)
    if not itemId or itemId < 1 or itemId % 1 ~= 0 or entryAmount == nil
        or entryAmount <= 0 or not at or at < 0 or not sourceFb then return nil end
    return { itemId = itemId, amount = entryAmount, sourceFb = sourceFb,
        time = at, mine = entry.mine == true }
end

function M.ensure(root, now)
    local data = ensureContainer(root)
    if not data then return nil end
    local templates, seen = {}, {}
    for _, template in ipairs(data.expenseTemplates) do
        local clean = copyTemplate(template)
        local key = clean and string.lower(clean.name) or nil
        if clean and not seen[key] and #templates < MAX_TEMPLATES then
            templates[#templates + 1], seen[key] = clean, true
        end
    end
    data.expenseTemplates = templates
    local history = {}
    for _, entry in ipairs(data.localHistory) do
        local clean = sanitizeHistory(entry)
        if clean then history[#history + 1] = clean end
    end
    table.sort(history, function(a, b) return a.time > b.time end)
    while #history > MAX_HISTORY do table.remove(history) end
    data.localHistory = history
    if type(now) == "number" then M.purgeHistory(root, now) end
    return data
end

function M.listTemplates(root)
    local data = M.ensure(root)
    local result = {}
    for index, template in ipairs(data and data.expenseTemplates or {}) do
        result[index] = copyTemplate(template)
    end
    return result
end

function M.upsertTemplate(root, template, replace)
    local clean, data = copyTemplate(template), M.ensure(root)
    if not clean or not data then return false, "invalid" end
    local found
    for index, existing in ipairs(data.expenseTemplates) do
        if string.lower(existing.name) == string.lower(clean.name) then found = index break end
    end
    if found and replace ~= true then return false, "duplicate" end
    if not found and #data.expenseTemplates >= MAX_TEMPLATES then return false, "capacity" end
    if found then data.expenseTemplates[found] = clean else data.expenseTemplates[#data.expenseTemplates + 1] = clean end
    return true
end

function M.copyTemplate(root, index, newName)
    local templates = M.listTemplates(root)
    local source = templates[tonumber(index)]
    if not source then return false, "missing" end
    source.name = newName
    return M.upsertTemplate(root, source, false)
end

function M.replaceTemplate(root, index, template)
    local data, clean = M.ensure(root), copyTemplate(template)
    index = tonumber(index)
    if not data or not clean or not data.expenseTemplates[index] then return false, "invalid" end
    for other, existing in ipairs(data.expenseTemplates) do
        if other ~= index and string.lower(existing.name) == string.lower(clean.name) then return false, "duplicate" end
    end
    data.expenseTemplates[index] = clean
    return true
end

function M.renameTemplate(root, index, newName)
    local data, cleanName = M.ensure(root), name(newName)
    index = tonumber(index)
    if not data or not data.expenseTemplates[index] or not cleanName then return false, "invalid" end
    for other, existing in ipairs(data.expenseTemplates) do
        if other ~= index and string.lower(existing.name) == string.lower(cleanName) then return false, "duplicate" end
    end
    data.expenseTemplates[index].name = cleanName
    return true
end

function M.deleteTemplate(root, index, confirmed)
    local data = M.ensure(root)
    index = tonumber(index)
    if confirmed ~= true or not data or not data.expenseTemplates[index] then return false end
    table.remove(data.expenseTemplates, index)
    return true
end

function M.clearTemplates(root, confirmed)
    local data = M.ensure(root)
    if confirmed ~= true or not data then return false end
    data.expenseTemplates = {}
    return true
end

function M.planExpenseApply(template, rows)
    local clean = copyTemplate(template)
    if not clean or type(rows) ~= "table" then return nil, "invalid" end
    local empty = {}
    for index, row in ipairs(rows) do
        local rowName = type(row) == "table" and trim(row.name) or ""
        local rowAmount = type(row) == "table" and trim(tostring(row.amount or "")) or ""
        if rowName == "" and rowAmount == "" then empty[#empty + 1] = index end
    end
    if #empty < #clean.items then return nil, "insufficient-space" end
    local plan = {}
    for index, item in ipairs(clean.items) do
        plan[index] = { row = empty[index], name = item.name, amount = item.amount }
    end
    return plan
end

local function escape(value)
    return tostring(value):gsub("([^%w%-%._~])", function(char) return string.format("%%%02X", string.byte(char)) end)
end

local function unescape(value)
    if type(value) ~= "string" or value:find("%%[^%x]") or value:find("%%.$") then return nil end
    return (value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

function M.exportTemplates(root)
    local lines = { "BGNT-E1" }
    for _, template in ipairs(M.listTemplates(root)) do
        lines[#lines + 1] = "T\t" .. escape(template.name)
        for _, item in ipairs(template.items) do
            lines[#lines + 1] = "I\t" .. escape(item.name) .. "\t" .. tostring(item.amount)
        end
        lines[#lines + 1] = "E"
    end
    return table.concat(lines, "\n")
end

function M.previewImport(text)
    if type(text) ~= "string" or #text > MAX_IMPORT then return nil, "invalid" end
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = line end
    if lines[1] ~= "BGNT-E1" then return nil, "format" end
    local templates, current, seen = {}, nil, {}
    for index = 2, #lines do
        local line = lines[index]
        local kind, a, b = line:match("^([^\t]+)\t?([^\t]*)\t?([^\t]*)$")
        if kind == "T" and current == nil then
            local templateName = unescape(a)
            current = { name = templateName, items = {} }
        elseif kind == "I" and current ~= nil then
            current.items[#current.items + 1] = { name = unescape(a), amount = tonumber(b) }
        elseif line == "E" and current ~= nil then
            local clean = copyTemplate(current)
            local key = clean and string.lower(clean.name) or nil
            if not clean or seen[key] or #templates >= MAX_TEMPLATES then return nil, "invalid" end
            seen[key], templates[#templates + 1], current = true, clean, nil
        elseif line ~= "" then
            return nil, "format"
        end
    end
    if current ~= nil or #templates < 1 then return nil, "invalid" end
    return templates
end

function M.importTemplates(root, text, commit)
    local templates, reason = M.previewImport(text)
    if not templates then return false, reason end
    if commit ~= true then return true, templates end
    local data = M.ensure(root)
    if not data then return false, "invalid-root" end
    -- Atomic replacement: no mutation occurs until the whole text validates.
    data.expenseTemplates = templates
    return true
end

function M.purgeHistory(root, now)
    local data = ensureContainer(root)
    if not data or type(now) ~= "number" then return false end
    local cutoff, result = now - data.historyRetentionDays * 86400, {}
    for _, entry in ipairs(data.localHistory) do
        local clean = sanitizeHistory(entry)
        if clean and clean.time >= cutoff and clean.time <= now + 86400 then result[#result + 1] = clean end
    end
    table.sort(result, function(a, b) return a.time > b.time end)
    while #result > MAX_HISTORY do table.remove(result) end
    local changed = #result ~= #data.localHistory
    data.localHistory = result
    return changed
end

function M.setHistoryRetention(root, days, now)
    local data = M.ensure(root)
    days = tonumber(days)
    if not data or not RETENTION[days] then return false end
    data.historyRetentionDays = days
    if type(now) == "number" then M.purgeHistory(root, now) end
    return true
end

function M.appendHistory(root, entry, enabled, now)
    if enabled ~= true then return false, "disabled" end
    local data, clean = M.ensure(root, now), sanitizeHistory(entry)
    if not data or not clean then return false, "invalid" end
    for _, existing in ipairs(data.localHistory) do
        if existing.itemId == clean.itemId and existing.amount == clean.amount
            and existing.sourceFb == clean.sourceFb and existing.time == clean.time
            and existing.mine == clean.mine then return false, "duplicate" end
    end
    table.insert(data.localHistory, 1, clean)
    while #data.localHistory > MAX_HISTORY do table.remove(data.localHistory) end
    return true
end

function M.summarizeHistory(root, now)
    local data = M.ensure(root, now)
    local result = { count = 0, mineTotal = 0, items = {}, retentionDays = data.historyRetentionDays }
    for _, entry in ipairs(data.localHistory) do
        result.count = result.count + 1
        if entry.mine then result.mineTotal = result.mineTotal + entry.amount end
        local item = result.items[entry.itemId]
        if not item then
            item = { count = 0, min = entry.amount, max = entry.amount, recent = entry.amount, recentAt = entry.time }
            result.items[entry.itemId] = item
        end
        item.count = item.count + 1
        if entry.amount < item.min then item.min = entry.amount end
        if entry.amount > item.max then item.max = entry.amount end
        if entry.time > item.recentAt then item.recent, item.recentAt = entry.amount, entry.time end
    end
    return result
end

function M.clearHistory(root, confirmed)
    local data = M.ensure(root)
    if confirmed ~= true or not data then return false end
    data.localHistory = {}
    return true
end

BG.BGNext.LeaderToolsStore = M
return M
