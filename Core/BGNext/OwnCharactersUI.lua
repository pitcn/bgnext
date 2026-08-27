-- BGNext own-character overview renderer.
--
-- Draws the approved two-section horizontal table: characters are rows, raids
-- and resources are columns. It is handed a finished projection and never
-- reaches into storage, so client differences and retention rules stay out of
-- the drawing code.
--
-- There is deliberately no per-character card and no vertical equipment wall:
-- the layout below is row-per-character, column-per-category.

local AddonName, ns = ...
local L = ns and ns.L or setmetatable({}, { __index = function(_, key) return tostring(key) end })

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local View = BG.BGNext.OwnCharactersView

local M = {}

-- Geometry is shared with the projection so the computed window size and the
-- drawn contents can never drift apart. These are the constants in-game
-- screenshot calibration adjusts.
M.metrics = View and View.metrics or {
    rowHeight = 20,
    headerHeight = 22,
    sectionTitleHeight = 24,
    totalsRowHeight = 20,
    iconSize = 19,
    iconGap = 1,
    nameColumnWidth = 120,
    sectionGap = 10,
    padding = 8,
    columnWidths = { narrow = 44, normal = 64, wide = 90 },
}

M.colors = {
    -- Alternating character rows.
    stripeDark = { r = 0, g = 0, b = 0, a = 0.55 },
    stripeLight = { r = 0.25, g = 0.25, b = 0.25, a = 0.55 },
    -- Green section titles and green completion marker.
    title = { r = 0, g = 1, b = 0, a = 1 },
    complete = { r = 0.1, g = 0.9, b = 0.1, a = 1 },
    -- Grey hints and separators.
    hint = { r = 0.5, g = 0.5, b = 0.5, a = 1 },
    line = { r = 0.5, g = 0.5, b = 0.5, a = 0.5 },
    text = { r = 1, g = 1, b = 1, a = 1 },
}

M.controls = { "settings", "refresh", "close" }

M.textures = {
    complete = "Interface\\RaidFrame\\ReadyCheck-Ready",
    settings = "Interface\\GossipFrame\\BinderGossipIcon",
    refresh = "Interface\\Buttons\\UI-RefreshButton",
    background = "Interface\\Buttons\\WHITE8x8",
}

local FALLBACK_CLASS_COLOR = { r = 0.8, g = 0.8, b = 0.8 }

-- Blizzard ships the class colour table; BGNext only falls back when the
-- client does not expose it (or the class is unknown).
function M.classColor(classToken)
    local source = _G and (_G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS)
    local color = source and classToken and source[classToken] or nil
    if color and type(color.r) == "number" then
        return { r = color.r, g = color.g, b = color.b }
    end
    return { r = FALLBACK_CLASS_COLOR.r, g = FALLBACK_CLASS_COLOR.g, b = FALLBACK_CLASS_COLOR.b }
end

local function columnWidth(column)
    if column.width == "dynamic-items" then
        local slots = column.slots or 0
        if slots <= 0 then slots = 1 end
        return slots * (M.metrics.iconSize + M.metrics.iconGap)
    end
    return M.metrics.columnWidths[column.width] or M.metrics.columnWidths.normal
end

-- Places one section: a green title, a header row, then one row per
-- character, and for the resource section a totals row underneath.
local function layoutSection(source, key, top)
    local metrics = M.metrics
    local section = {
        key = key,
        title = source.title,
        hint = source.hint,
        nameHeader = source.nameHeader,
        titleY = top,
        headerY = top - metrics.sectionTitleHeight,
        columns = {},
        rows = {},
        width = source.width,
    }

    local x = metrics.nameColumnWidth
    for _, column in ipairs(source.columns or {}) do
        local width = columnWidth(column)
        section.columns[#section.columns + 1] = {
            id = column.id,
            title = column.title,
            zoneId = column.zoneId,
            kind = column.kind,
            slots = column.slots,
            total = column.total,
            x = x,
            width = width,
        }
        x = x + width
    end

    local rowTop = section.headerY - metrics.headerHeight
    for index, row in ipairs(source.rows or {}) do
        section.rows[#section.rows + 1] = {
            key = row.key,
            player = row.player,
            realmId = row.realmId,
            display = row.display,
            prefix = row.prefix,
            class = row.class,
            level = row.level,
            itemLevel = row.itemLevel,
            stripe = row.stripe,
            cells = row.cells,
            y = rowTop - (index - 1) * metrics.rowHeight,
        }
    end

    local bottom = rowTop - #section.rows * metrics.rowHeight
    if key == "resource" then
        section.totalsY = bottom
        section.totals = source.totals
        bottom = bottom - metrics.totalsRowHeight
    end
    section.bottom = bottom
    return section
end

-- Turns a projection into absolute positions. Pure: no frames, no storage.
function M.layout(projection)
    if type(projection) ~= "table" then return nil end
    if type(projection.raid) ~= "table" or type(projection.resource) ~= "table" then return nil end

    local metrics = M.metrics
    local top = -metrics.padding

    local raid = layoutSection(projection.raid, "raid", top)
    local resource = layoutSection(projection.resource, "resource", raid.bottom - metrics.sectionGap)

    return {
        width = projection.width,
        height = projection.height,
        isEmpty = projection.isEmpty == true,
        emptyText = L["尚无本地角色记录，登录角色后自动记录。"],
        characterCount = projection.characterCount,
        sections = { raid, resource },
    }
end

--------------------------------------------------------------------------
-- Frame rendering. Everything below runs only inside the game; the helpers
-- above stay exercisable in plain Lua.
--------------------------------------------------------------------------

local frame
local provider
local pool = { rows = {}, texts = {}, textures = {} }

-- The entry module supplies the projection. Keeping it a callback is what
-- lets this file stay free of storage access.
function M.SetProvider(fn)
    provider = type(fn) == "function" and fn or nil
end

function M.GetFrame()
    return frame
end

local function acquireText(parent, index)
    local item = pool.texts[index]
    if not item then
        item = parent:CreateFontString(nil, "ARTWORK")
        item:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        pool.texts[index] = item
    end
    item:Show()
    return item
end

local function acquireTexture(parent, index)
    local item = pool.textures[index]
    if not item then
        item = parent:CreateTexture(nil, "ARTWORK")
        pool.textures[index] = item
    end
    item:Show()
    return item
end

local function resetPool()
    for _, item in ipairs(pool.texts) do item:Hide() end
    for _, item in ipairs(pool.textures) do item:Hide() end
end

local function cellText(cell, column)
    if cell.state == "empty" then return "" end
    if column.kind == "money" and type(cell.value) == "number" then
        return cell.text .. "g"
    end
    return cell.text or ""
end

-- Rebuilds the whole table from a layout. Reuses pooled regions so repeated
-- refreshes do not leak frames.
function M.Draw(layout)
    if not frame or type(layout) ~= "table" then return end
    resetPool()

    frame:SetSize(layout.width, layout.height)

    local textIndex, textureIndex = 0, 0
    local function nextText()
        textIndex = textIndex + 1
        return acquireText(frame, textIndex)
    end
    local function nextTexture()
        textureIndex = textureIndex + 1
        return acquireTexture(frame, textureIndex)
    end

    if layout.isEmpty then
        local message = nextText()
        message:SetPoint("TOPLEFT", frame, M.metrics.padding, layout.sections[1].titleY)
        message:SetTextColor(M.colors.hint.r, M.colors.hint.g, M.colors.hint.b)
        message:SetText(layout.emptyText)
        return
    end

    for _, section in ipairs(layout.sections) do
        local title = nextText()
        title:SetPoint("TOPLEFT", frame, M.metrics.padding, section.titleY)
        title:SetTextColor(M.colors.title.r, M.colors.title.g, M.colors.title.b)
        title:SetText(L[section.title])

        local hint = nextText()
        hint:SetPoint("LEFT", title, "RIGHT", 8, 0)
        hint:SetTextColor(M.colors.hint.r, M.colors.hint.g, M.colors.hint.b)
        hint:SetText(L[section.hint])

        local nameHeader = nextText()
        nameHeader:SetPoint("TOPLEFT", frame, M.metrics.padding, section.headerY)
        nameHeader:SetTextColor(M.colors.hint.r, M.colors.hint.g, M.colors.hint.b)
        nameHeader:SetText(section.nameHeader)

        for _, column in ipairs(section.columns) do
            local header = nextText()
            header:SetPoint("TOPLEFT", frame, M.metrics.padding + column.x, section.headerY)
            header:SetWidth(column.width)
            header:SetTextColor(M.colors.text.r, M.colors.text.g, M.colors.text.b)
            local label = column.title
            if column.zoneId and type(GetRealZoneText) == "function" then
                local zoneName = GetRealZoneText(column.zoneId)
                if type(zoneName) == "string" and zoneName ~= "" then label = zoneName end
            end
            header:SetText(L[label or ""])
        end

        for _, row in ipairs(section.rows) do
            local stripe = nextTexture()
            local color = M.colors[row.stripe == "dark" and "stripeDark" or "stripeLight"]
            stripe:SetTexture(M.textures.background)
            stripe:SetVertexColor(color.r, color.g, color.b, color.a)
            stripe:SetPoint("TOPLEFT", frame, M.metrics.padding, row.y)
            stripe:SetSize(layout.width - M.metrics.padding * 2, M.metrics.rowHeight)

            local name = nextText()
            name:SetPoint("TOPLEFT", frame, M.metrics.padding, row.y)
            local classColor = M.classColor(row.class)
            name:SetTextColor(classColor.r, classColor.g, classColor.b)
            local trailing = section.key == "raid" and row.itemLevel or row.level
            name:SetText(trailing and (row.display .. " " .. tostring(math.floor(trailing))) or row.display)

            for index, column in ipairs(section.columns) do
                local cell = row.cells[index]
                if cell then
                    if cell.state == "complete" then
                        local check = nextTexture()
                        check:SetTexture(M.textures.complete)
                        check:SetVertexColor(M.colors.complete.r, M.colors.complete.g, M.colors.complete.b)
                        check:SetSize(M.metrics.iconSize, M.metrics.iconSize)
                        check:SetPoint("TOPLEFT", frame, M.metrics.padding + column.x, row.y)
                    elseif cell.state == "items" then
                        for slot, item in ipairs(cell.items) do
                            local icon = nextTexture()
                            icon:SetTexture(item.icon or (type(GetItemIcon) == "function" and GetItemIcon(item.itemId)))
                            icon:SetSize(M.metrics.iconSize, M.metrics.iconSize)
                            icon:SetPoint("TOPLEFT", frame,
                                M.metrics.padding + column.x + (slot - 1) * (M.metrics.iconSize + M.metrics.iconGap),
                                row.y)
                            if item.itemLevel then
                                local overlay = nextText()
                                overlay:SetPoint("BOTTOMRIGHT", icon, 1, -1)
                                overlay:SetText(tostring(math.floor(item.itemLevel)))
                            end
                        end
                    else
                        local text = cellText(cell, column)
                        if text ~= "" then
                            local value = nextText()
                            value:SetPoint("TOPLEFT", frame, M.metrics.padding + column.x, row.y)
                            value:SetWidth(column.width)
                            value:SetTextColor(M.colors.text.r, M.colors.text.g, M.colors.text.b)
                            value:SetText(text)
                        end
                    end
                end
            end
        end

        -- Totals only where the column declared one; status and item columns
        -- deliberately show nothing rather than a meaningless sum.
        if section.totalsY and section.totals then
            local label = nextText()
            label:SetPoint("TOPLEFT", frame, M.metrics.padding, section.totalsY)
            label:SetTextColor(M.colors.hint.r, M.colors.hint.g, M.colors.hint.b)
            label:SetText(L["合计"])
            for _, column in ipairs(section.columns) do
                local total = section.totals[column.id]
                if type(total) == "number" then
                    local value = nextText()
                    value:SetPoint("TOPLEFT", frame, M.metrics.padding + column.x, section.totalsY)
                    value:SetWidth(column.width)
                    value:SetTextColor(M.colors.text.r, M.colors.text.g, M.colors.text.b)
                    value:SetText(column.kind == "money"
                        and tostring(math.floor(total / 10000)) .. "g"
                        or tostring(total))
                end
            end
        end
    end
end

function M.SetFrame(target)
    frame = target
end

-- Rebuilds from the current provider. Safe to call after a settings change,
-- a Shift toggle, a refresh click or a new snapshot.
function M.Refresh()
    if not frame or not provider then return end
    local projection = provider()
    local layout = M.layout(projection)
    if layout then M.Draw(layout) end
end

BG.BGNext.OwnCharactersUI = M
return M
