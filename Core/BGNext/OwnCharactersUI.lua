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
    columnGap = 8,
    sectionControlWidth = 18,
    nameColumnWidth = 120,
    sectionGap = 10,
    padding = 8,
    columnWidths = { narrow = 44, normal = 64, wide = 110 },
}

M.colors = {
    -- Alternating character rows.
    stripeDark = { r = 0.02, g = 0.04, b = 0.07, a = 0.55 },
    stripeLight = { r = 0.07, g = 0.10, b = 0.14, a = 0.55 },
    -- Brand-cyan section titles and semantic green completion marker.
    title = { r = 0, g = 0.90, b = 1, a = 1 },
    complete = { r = 0.1, g = 0.9, b = 0.1, a = 1 },
    -- Neutral hierarchy; arbitrary catalog colours do not become chrome.
    header = { r = 0.91, g = 0.91, b = 0.91, a = 1 },
    hint = { r = 0.56, g = 0.65, b = 0.73, a = 1 },
    line = { r = 0.14, g = 0.27, b = 0.37, a = 0.65 },
    text = { r = 0.91, g = 0.95, b = 0.97, a = 1 },
}

M.controls = { "settings", "refresh", "close" }

function M.headerControls(mode, hideable)
    return {
        canAdd = mode == "pinned",
    }
end

function M.rowCenterY(rowTop)
    return rowTop - M.metrics.rowHeight / 2
end

function M.fitTextWidth(region, value, maximumWidth)
    if not region or type(region.SetWidth) ~= "function"
        or type(region.SetText) ~= "function" or type(region.GetStringWidth) ~= "function" then
        return 0
    end
    local limit = type(maximumWidth) == "number" and math.max(0, maximumWidth) or 0
    region:SetWidth(limit)
    region:SetText(value or "")
    local measured = region:GetStringWidth()
    if type(measured) ~= "number" then measured = 0 end
    measured = math.min(limit, math.max(0, measured))
    region:SetWidth(measured)
    return measured
end

-- The difficulty abbreviation lives in the width remaining after the completion
-- checkmark and its 2px inset, so a three-character "LFR" label fits without
-- clipping or wrapping.
function M.difficultyLabelWidth(columnWidth)
    return math.max(0, (type(columnWidth) == "number" and columnWidth or 0)
        - M.metrics.iconSize - 2)
end

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

function M.hexColor(value)
    if type(value) ~= "string" or not value:match("^%x%x%x%x%x%x$") then
        return { r = M.colors.text.r, g = M.colors.text.g, b = M.colors.text.b }
    end
    return {
        r = tonumber(value:sub(1, 2), 16) / 255,
        g = tonumber(value:sub(3, 4), 16) / 255,
        b = tonumber(value:sub(5, 6), 16) / 255,
    }
end

function M.rowLabel(section, row)
    if type(row) ~= "table" then return "" end
    local display = type(row.display) == "string" and row.display or ""
    local trailing = section == "raid" and row.itemLevel or row.level
    if type(trailing) == "number" then
        return string.format("%s (%d)", display, math.floor(trailing))
    end
    return display
end

local function liveCurrencyInfo(currencyId)
    if type(C_CurrencyInfo) == "table" and type(C_CurrencyInfo.GetCurrencyInfo) == "function" then
        return C_CurrencyInfo.GetCurrencyInfo(currencyId)
    end
end

-- Resolves a spell's localized name from whichever spell API the client ships.
-- Returns a string name, or nil when the API is absent or the spell is unknown.
local function liveSpellInfo(spellId)
    if type(C_Spell) == "table" and type(C_Spell.GetSpellInfo) == "function" then
        local info = C_Spell.GetSpellInfo(spellId)
        if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            return info.name
        end
        return nil
    end
    if type(GetSpellInfo) == "function" then
        local name = GetSpellInfo(spellId)
        if type(name) == "string" and name ~= "" then return name end
    end
    return nil
end

function M.columnHeader(column, currencyInfo, spellInfo)
    if type(column) ~= "table" then return { text = "", tooltip = "" } end
    local rawLabel = type(column.title) == "string" and column.title or ""
    local label = L[rawLabel]
    local tooltip = type(column.fullTitle) == "string" and column.fullTitle ~= ""
        and L[column.fullTitle] or label
    local descriptor = { text = label, tooltip = tooltip }
    local source = type(column.source) == "table" and column.source or nil
    -- A profession cooldown heading keeps its compact catalog title and, when
    -- the client can name the spell, surfaces Blizzard's own localized name as
    -- the tooltip rather than a hand-written translation.
    if source and source.kind == "profession-cooldown" and type(source.spellId) == "number" then
        local resolver = type(spellInfo) == "function" and spellInfo or liveSpellInfo
        local ok, name = pcall(resolver, source.spellId)
        if ok and type(name) == "string" and name ~= "" then
            descriptor.tooltip = name
        end
        return descriptor
    end
    if not source or source.kind ~= "currency" or source.showHeaderIcon ~= true
        or type(source.currencyId) ~= "number" then
        return descriptor
    end
    local resolver = type(currencyInfo) == "function" and currencyInfo or liveCurrencyInfo
    local ok, info = pcall(resolver, source.currencyId)
    local icon = ok and type(info) == "table" and info.iconFileID or nil
    if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
        descriptor.tooltip = info.name
    end
    if type(icon) ~= "number" and type(icon) ~= "string" then return descriptor end
    descriptor.text = "|T" .. tostring(icon) .. ":20:20|t"
    descriptor.iconFileID = icon
    return descriptor
end

-- Builds the localized tooltip lines for a currency value cell. The name comes
-- from Blizzard's currency API (injected as `currencyInfo` for tests, defaulting
-- to the live API); every cap line appears only when the cell actually carries
-- it, so a missing limit never renders a fabricated zero. Returns nil when the
-- cell has no confirmed currency id — item-backed "currency" columns carry no
-- id and therefore no currency tooltip.
function M.currencyTooltip(cell, currencyInfo)
    if type(cell) ~= "table" or type(cell.currencyId) ~= "number" then return nil end
    local resolver = type(currencyInfo) == "function" and currencyInfo or liveCurrencyInfo
    local ok, info = pcall(resolver, cell.currencyId)
    local name = nil
    if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
        name = info.name
    end
    local lines = {}
    if type(cell.value) == "number" then
        lines[#lines + 1] = L["当前数量"] .. " " .. tostring(cell.value)
    end
    if type(cell.maxQuantity) == "number" then
        lines[#lines + 1] = L["总上限"] .. " " .. tostring(cell.maxQuantity)
    end
    if type(cell.quantityEarnedThisWeek) == "number" then
        lines[#lines + 1] = L["本周获得"] .. " " .. tostring(cell.quantityEarnedThisWeek)
    end
    if type(cell.maxWeeklyQuantity) == "number" and cell.maxWeeklyQuantity > 0 then
        lines[#lines + 1] = L["每周上限"] .. " " .. tostring(cell.maxWeeklyQuantity)
    end
    if #lines == 0 then return nil end
    return { name = name, lines = lines }
end

-- Populates a Blizzard tooltip with a currency cell: the official name as the
-- title, then one line per present field. Returns false when there is nothing
-- to show or the tooltip cannot take text.
function M.showCurrencyTooltip(tooltip, cell, currencyInfo)
    local info = M.currencyTooltip(cell, currencyInfo)
    if not info or not tooltip or type(tooltip.SetText) ~= "function" then return false end
    tooltip:SetText(info.name or L["货币"])
    if type(tooltip.AddLine) == "function" then
        for _, line in ipairs(info.lines) do
            tooltip:AddLine(line)
        end
    end
    return true
end

-- Builds the localized tooltip lines for a raid cell that carries per-difficulty
-- detail. Each line names its difficulty and shows only the real Blizzard count
-- pair; a difficulty without a usable count is skipped rather than rendered as a
-- fabricated 0/N. When a difficulty carries its own per-boss list, each boss is
-- listed under that difficulty with its own killed flag. A cell without a
-- breakdown surfaces nothing.
function M.raidTooltip(cell)
    if type(cell) ~= "table" then return nil end
    local difficulties = type(cell.difficulties) == "table" and cell.difficulties or nil
    local lines = {}
    if difficulties then
        for _, difficulty in ipairs(difficulties) do
            local parts = type(difficulty.completedParts) == "number" and difficulty.completedParts or nil
            local total = type(difficulty.totalParts) == "number" and difficulty.totalParts or nil
            if total ~= nil then
                local label = (type(difficulty.difficultyLabel) == "string" and difficulty.difficultyLabel ~= "")
                    and difficulty.difficultyLabel or tostring(difficulty.difficulty or "")
                if parts ~= nil then
                    lines[#lines + 1] = label .. " " .. tostring(parts) .. "/" .. tostring(total)
                else
                    -- A degraded difficulty keeps its reliable total but no
                    -- killed count, so the numerator renders as unknown rather
                    -- than a fabricated kill count.
                    lines[#lines + 1] = label .. " " .. L["未知"] .. "/" .. tostring(total)
                end
                local bosses = type(difficulty.encounters) == "table" and difficulty.encounters or nil
                if bosses then
                    for _, boss in ipairs(bosses) do
                        if type(boss) == "table" then
                            local name, killed = boss.name, boss.killed
                            if type(name) == "string" and name ~= "" and type(killed) == "boolean" then
                                lines[#lines + 1] = "    " .. name .. " " .. (killed and "✓" or "✗")
                            end
                        end
                    end
                end
            end
        end
    end
    if #lines == 0 then return nil end
    return { lines = lines }
end

-- Populates a Blizzard tooltip with a raid cell's per-boss or per-difficulty
-- detail. Returns false when there is nothing to show or the tooltip cannot
-- take text.
function M.showRaidTooltip(tooltip, cell)
    local info = M.raidTooltip(cell)
    if not info or not tooltip or type(tooltip.SetText) ~= "function" then return false end
    tooltip:SetText(info.name or "")
    if type(tooltip.AddLine) == "function" then
        for _, line in ipairs(info.lines) do
            tooltip:AddLine(line)
        end
    end
    return true
end

-- Picks the source for Blizzard's official item tooltip. A collected item link
-- is preferred (it preserves the exact item), otherwise the item id. Returning
-- nil means there is nothing safe to show.
function M.tooltipTarget(item)
    if type(item) ~= "table" then return nil end
    if type(item.link) == "string" and item.link ~= "" then
        return { kind = "link", value = item.link }
    end
    if type(item.itemId) == "number" and item.itemId > 0 then
        return { kind = "item", value = item.itemId }
    end
    return nil
end

local function columnWidth(column)
    if type(column.width) == "number" then return column.width end
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
        countdown = source.resetCountdown,
        nameHeader = source.nameHeader,
        titleY = top,
        headerY = top - metrics.sectionTitleHeight,
        columns = {},
        rows = {},
        width = source.width,
        addX = source.width - metrics.padding * 2 - metrics.sectionControlWidth + 2,
    }

    local x = metrics.nameColumnWidth
    for _, column in ipairs(source.columns or {}) do
        local width = columnWidth(column)
        section.columns[#section.columns + 1] = {
            id = column.id,
            title = column.title,
            fullTitle = column.fullTitle,
            color = column.color,
            source = column.source,
            zoneId = column.zoneId,
            kind = column.kind,
            slots = column.slots,
            total = column.total,
            x = type(column.x) == "number" and column.x or x,
            width = width,
        }
        x = (type(column.x) == "number" and column.x or x) + width + (metrics.columnGap or 0)
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
        emptyText = projection.unsupported == true
            and L["该版本角色总览适配中。"]
            or L["尚无本地角色记录，登录角色后自动记录。"],
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
local rowHandler
local settingsHandler
local renderMode = "pinned"
local pool = {
    rows = {}, texts = {}, textures = {}, buttons = {}, itemButtons = {},
    headerButtons = {}, addButtons = {}, valueButtons = {},
}

-- The entry module supplies the projection. Keeping it a callback is what
-- lets this file stay free of storage access.
function M.SetProvider(fn)
    provider = type(fn) == "function" and fn or nil
end

-- The entry module supplies the per-row right-click handler (section, row).
-- Stored as a callback so this renderer never learns how deletion works.
function M.SetRowHandler(fn)
    rowHandler = type(fn) == "function" and fn or nil
end

function M.SetSettingsHandler(fn)
    settingsHandler = type(fn) == "function" and fn or nil
end

function M.SetMode(mode)
    renderMode = mode == "preview" and "preview" or "pinned"
end

function M.GetFrame()
    return frame
end

local function acquireText(parent, index)
    local item = pool.texts[index]
    if not item then
        item = parent:CreateFontString(nil, "ARTWORK")
        pool.texts[index] = item
    end
    item:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    item:ClearAllPoints()
    item:SetWordWrap(false)
    item:SetJustifyH("LEFT")
    item:SetJustifyV("MIDDLE")
    item:SetTextColor(M.colors.text.r, M.colors.text.g, M.colors.text.b)
    item:Show()
    return item
end

local function acquireTexture(parent, index)
    local item = pool.textures[index]
    if not item then
        item = parent:CreateTexture(nil, "ARTWORK")
        pool.textures[index] = item
    end
    item:ClearAllPoints()
    item:Show()
    return item
end

local function acquireRowButton(parent, index)
    local item = pool.buttons[index]
    if not item then
        item = CreateFrame("Button", nil, parent)
        item:RegisterForClicks("RightButtonUp")
        item:SetScript("OnMouseDown", function(self, mouseButton)
            if mouseButton == "RightButton" and rowHandler then
                rowHandler(self.__section, self.__row)
            end
        end)
        pool.buttons[index] = item
    end
    item:ClearAllPoints()
    item:SetFrameLevel(parent:GetFrameLevel() + 1)
    item:Show()
    return item
end

-- Shows Blizzard's own tooltip for an item, never a hand-written summary. The
-- link is used when the collector captured one; otherwise the item id.
function M.showItemTooltip(tooltip, item, itemApi)
    local target = M.tooltipTarget(item)
    if not target or not tooltip then return false end
    if target.kind == "link" then
        if type(tooltip.SetHyperlink) ~= "function" then return false end
        tooltip:SetHyperlink(target.value)
    else
        local api = itemApi or C_Item
        if type(api) == "table" and type(api.RequestLoadItemDataByID) == "function" then
            api.RequestLoadItemDataByID(target.value)
        end
        if type(tooltip.SetItemByID) == "function" then
            tooltip:SetItemByID(target.value)
        elseif type(tooltip.SetHyperlink) == "function" then
            tooltip:SetHyperlink("item:" .. tostring(target.value))
        else
            return false
        end
    end
    return true
end

local function showItemTooltip(self)
    if not GameTooltip or type(GameTooltip.SetOwner) ~= "function" then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if M.showItemTooltip(GameTooltip, self.__item, C_Item)
        and type(GameTooltip.Show) == "function" then
        GameTooltip:Show()
    end
end

local function hideItemTooltip()
    if GameTooltip and type(GameTooltip.Hide) == "function" then GameTooltip:Hide() end
end

local function showHeaderTooltip(self)
    if type(self.__tooltip) ~= "string" or self.__tooltip == ""
        or not GameTooltip or type(GameTooltip.SetOwner) ~= "function" then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(self.__tooltip)
    GameTooltip:Show()
end

local function hideHeaderTooltip(self)
    hideItemTooltip()
end

local function showValueTooltip(self)
    if not GameTooltip or type(GameTooltip.SetOwner) ~= "function" then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local shown = M.showRaidTooltip(GameTooltip, self.__cell)
    if not shown then shown = M.showCurrencyTooltip(GameTooltip, self.__cell) end
    if not shown and self.__cell and self.__cell.activity then
        GameTooltip:SetText(L["角色活动进度"])
        if self.__cell.reason == "farm-observation-required" then
            GameTooltip:AddLine(L["当前客户端没有可靠方式判断四风农场是否已收完，暂显示未知。"], 1, 1, 1, true)
        elseif self.__cell.state == "unknown" then
            GameTooltip:AddLine(L["记录已过期或暂时无法读取，请登录该角色刷新。"], 1, 1, 1, true)
        else
            GameTooltip:AddLine(L["仅显示该角色最近一次登录时读取到的状态。"], 1, 1, 1, true)
        end
        shown = true
    end
    if shown and type(GameTooltip.Show) == "function" then
        GameTooltip:Show()
    end
end

local function acquireHeaderButton(parent, index)
    local item = pool.headerButtons[index]
    if not item then
        item = CreateFrame("Button", nil, parent)
        item:SetScript("OnEnter", showHeaderTooltip)
        item:SetScript("OnLeave", hideHeaderTooltip)
        pool.headerButtons[index] = item
    end
    item:ClearAllPoints()
    item:SetFrameLevel(parent:GetFrameLevel() + 2)
    item:Show()
    return item
end


local function acquireAddButton(parent, index)
    local item = pool.addButtons[index]
    if not item then
        item = CreateFrame("Button", nil, parent)
        item:SetNormalFontObject(BG.FontWhite15)
        item:SetText("+")
        item:SetScript("OnClick", function(self)
            if settingsHandler then settingsHandler(self.__section) end
        end)
        pool.addButtons[index] = item
    end
    item:ClearAllPoints()
    item:SetFrameLevel(parent:GetFrameLevel() + 2)
    item:Show()
    return item
end

local function acquireItemButton(parent, index)
    local item = pool.itemButtons[index]
    if not item then
        item = CreateFrame("Button", nil, parent)
        item:SetScript("OnEnter", showItemTooltip)
        item:SetScript("OnLeave", hideItemTooltip)
        item:SetScript("OnMouseDown", function(self, mouseButton)
            if mouseButton == "RightButton" and rowHandler then
                rowHandler(self.__section, self.__row)
            end
        end)
        pool.itemButtons[index] = item
    end
    item:ClearAllPoints()
    item:SetFrameLevel(parent:GetFrameLevel() + 3)
    item:Show()
    return item
end

local function acquireValueButton(parent, index)
    local item = pool.valueButtons[index]
    if not item then
        item = CreateFrame("Button", nil, parent)
        item:SetScript("OnEnter", showValueTooltip)
        item:SetScript("OnLeave", hideItemTooltip)
        item:SetScript("OnMouseDown", function(self, mouseButton)
            if mouseButton == "RightButton" and rowHandler then
                rowHandler(self.__section, self.__row)
            end
        end)
        pool.valueButtons[index] = item
    end
    item:ClearAllPoints()
    item:SetFrameLevel(parent:GetFrameLevel() + 3)
    item:Show()
    return item
end

local function resetPool()
    for _, item in ipairs(pool.texts) do item:Hide() end
    for _, item in ipairs(pool.textures) do item:Hide() end
    for _, item in ipairs(pool.buttons) do item:Hide() end
    for _, item in ipairs(pool.itemButtons) do item:Hide() end
    for _, item in ipairs(pool.headerButtons) do item:Hide() end
    for _, item in ipairs(pool.addButtons) do item:Hide() end
    for _, item in ipairs(pool.valueButtons) do item:Hide() end
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

    local textIndex, textureIndex, buttonIndex, itemButtonIndex, headerButtonIndex, addButtonIndex, valueButtonIndex = 0, 0, 0, 0, 0, 0, 0
    local function nextText()
        textIndex = textIndex + 1
        return acquireText(frame, textIndex)
    end
    local function nextTexture()
        textureIndex = textureIndex + 1
        return acquireTexture(frame, textureIndex)
    end
    local function nextButton()
        buttonIndex = buttonIndex + 1
        return acquireRowButton(frame, buttonIndex)
    end
    local function nextItemButton()
        itemButtonIndex = itemButtonIndex + 1
        return acquireItemButton(frame, itemButtonIndex)
    end
    local function nextHeaderButton()
        headerButtonIndex = headerButtonIndex + 1
        return acquireHeaderButton(frame, headerButtonIndex)
    end
    local function nextAddButton()
        addButtonIndex = addButtonIndex + 1
        return acquireAddButton(frame, addButtonIndex)
    end
    local function nextValueButton()
        valueButtonIndex = valueButtonIndex + 1
        return acquireValueButton(frame, valueButtonIndex)
    end

    if layout.isEmpty then
        local message = nextText()
        message:SetPoint("TOPLEFT", frame, M.metrics.padding, layout.sections[1].titleY)
        message:SetSize(layout.width - M.metrics.padding * 2, M.metrics.sectionTitleHeight)
        message:SetTextColor(M.colors.hint.r, M.colors.hint.g, M.colors.hint.b)
        message:SetText(layout.emptyText)
        return
    end

    for _, section in ipairs(layout.sections) do
        local title = nextText()
        title:SetPoint("TOPLEFT", frame, M.metrics.padding, section.titleY)
        title:SetTextColor(M.colors.title.r, M.colors.title.g, M.colors.title.b)
        local titleWidth = M.fitTextWidth(title, L[section.title], layout.width - M.metrics.padding * 2)
        title:SetHeight(M.metrics.sectionTitleHeight)

        local hint = nextText()
        hint:SetPoint("LEFT", title, "RIGHT", 8, 0)
        hint:SetSize(math.max(0, layout.width - M.metrics.padding * 2 - titleWidth - 8),
            M.metrics.sectionTitleHeight)
        hint:SetTextColor(M.colors.hint.r, M.colors.hint.g, M.colors.hint.b)
        local hintText = L[section.hint]
        if section.key == "raid" then
            hintText = section.countdown and (hintText .. section.countdown .. "）") or ""
        end
        hint:SetText(hintText)

        local nameHeader = nextText()
        nameHeader:SetPoint("TOPLEFT", frame, M.metrics.padding, section.headerY)
        nameHeader:SetSize(M.metrics.nameColumnWidth, M.metrics.headerHeight)
        nameHeader:SetTextColor(M.colors.hint.r, M.colors.hint.g, M.colors.hint.b)
        nameHeader:SetText(section.nameHeader)

        local sectionControls = M.headerControls(renderMode, true)
        if sectionControls.canAdd then
            local add = nextAddButton()
            add:SetPoint("TOPLEFT", frame, M.metrics.padding + section.addX, section.headerY)
            add:SetSize(M.metrics.sectionControlWidth - 2, M.metrics.headerHeight)
            add.__section = section.key
        end

        for _, column in ipairs(section.columns) do
            local descriptor = M.columnHeader(column)
            local header = nextText()
            header:SetPoint("TOPLEFT", frame, M.metrics.padding + column.x, section.headerY)
            header:SetSize(column.width, M.metrics.headerHeight)
            header:SetJustifyH("CENTER")
            header:SetTextColor(M.colors.header.r, M.colors.header.g, M.colors.header.b)
            header:SetText(descriptor.text)

            local hit = nextHeaderButton()
            hit:SetPoint("TOPLEFT", frame, M.metrics.padding + column.x, section.headerY)
            hit:SetSize(column.width, M.metrics.headerHeight)
            hit.__tooltip = descriptor.tooltip
            hit.__section = section.key
            hit.__columnId = column.id
        end

        for _, row in ipairs(section.rows) do
            local stripe = nextTexture()
            local color = M.colors[row.stripe == "dark" and "stripeDark" or "stripeLight"]
            stripe:SetTexture(M.textures.background)
            stripe:SetVertexColor(color.r, color.g, color.b, color.a)
            stripe:SetPoint("TOPLEFT", frame, M.metrics.padding, row.y)
            stripe:SetSize(layout.width - M.metrics.padding * 2, M.metrics.rowHeight)

            -- Invisible full-row hit area. Textures and font strings do not
            -- capture the mouse, so this button receives every click over the
            -- row and forwards only right-clicks to the entry's handler.
            if rowHandler then
                local hit = nextButton()
                hit:SetPoint("TOPLEFT", frame, M.metrics.padding, row.y)
                hit:SetSize(layout.width - M.metrics.padding * 2, M.metrics.rowHeight)
                hit.__section = section.key
                hit.__row = row
            end

            local name = nextText()
            name:SetPoint("LEFT", frame, "TOPLEFT", M.metrics.padding, M.rowCenterY(row.y))
            name:SetSize(M.metrics.nameColumnWidth, M.metrics.rowHeight)
            name:SetWordWrap(false)
            local classColor = M.classColor(row.class)
            name:SetTextColor(classColor.r, classColor.g, classColor.b)
            name:SetText(M.rowLabel(section.key, row))

            for index, column in ipairs(section.columns) do
                local cell = row.cells[index]
                if cell then
                    if cell.state == "complete" then
                        local check = nextTexture()
                        check:SetTexture(M.textures.complete)
                        check:SetVertexColor(M.colors.complete.r, M.colors.complete.g, M.colors.complete.b)
                        check:SetSize(M.metrics.iconSize, M.metrics.iconSize)
                        check:SetPoint("LEFT", frame, "TOPLEFT", M.metrics.padding + column.x,
                            M.rowCenterY(row.y))
                        if cell.difficultyLabel then
                            local label = nextText()
                            label:SetPoint("LEFT", check, "RIGHT", 2, 0)
                            label:SetSize(M.difficultyLabelWidth(column.width), M.metrics.iconSize)
                            label:SetJustifyH("LEFT")
                            label:SetTextColor(M.colors.complete.r, M.colors.complete.g, M.colors.complete.b)
                            label:SetText(cell.difficultyLabel)
                        end
                        if cell.difficulties or cell.activity then
                            local valueButton = nextValueButton()
                            valueButton:SetPoint("CENTER", frame, "TOPLEFT",
                                M.metrics.padding + column.x + column.width / 2, M.rowCenterY(row.y))
                            valueButton:SetSize(column.width, M.metrics.rowHeight)
                            valueButton.__cell = cell
                            valueButton.__section = section.key
                            valueButton.__row = row
                        end
                    elseif cell.state == "items" then
                        for slot, item in ipairs(cell.items) do
                            local icon = nextItemButton()
                            icon:SetNormalTexture(item.icon or (type(GetItemIcon) == "function" and GetItemIcon(item.itemId)))
                            icon:SetSize(M.metrics.iconSize, M.metrics.iconSize)
                            icon:SetPoint("LEFT", frame, "TOPLEFT",
                                M.metrics.padding + column.x + (slot - 1) * (M.metrics.iconSize + M.metrics.iconGap),
                                M.rowCenterY(row.y))
                            icon.__item = item
                            icon.__section = section.key
                            icon.__row = row
                            if item.itemLevel or (type(item.count) == "number" and item.count > 1) then
                                local overlay = nextText()
                                overlay:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
                                overlay:SetSize(M.metrics.iconSize, M.metrics.iconSize)
                                overlay:SetFont(BIAOGE_TEXT_FONT, 10, "OUTLINE")
                                overlay:SetJustifyH("RIGHT")
                                overlay:SetJustifyV("BOTTOM")
                                overlay:SetText(tostring(math.floor(item.itemLevel or item.count)))
                            end
                        end
                    elseif cell.state == "professions" then
                        local offset = 0
                        for _, profession in ipairs(cell.entries or {}) do
                            local skill = nextText()
                            skill:SetPoint("LEFT", frame, "TOPLEFT", M.metrics.padding + column.x + offset,
                                M.rowCenterY(row.y))
                            skill:SetSize(28, M.metrics.rowHeight)
                            skill:SetJustifyH("RIGHT")
                            skill:SetText(tostring(math.floor(profession.skill or 0)))
                            offset = offset + 28
                            local icon = nextTexture()
                            icon:SetTexture(profession.icon)
                            icon:SetSize(M.metrics.iconSize, M.metrics.iconSize)
                            icon:SetPoint("LEFT", frame, "TOPLEFT", M.metrics.padding + column.x + offset,
                                M.rowCenterY(row.y))
                            offset = offset + M.metrics.iconSize + M.metrics.iconGap
                        end
                    else
                        local text = cellText(cell, column)
                        if text ~= "" then
                            local value = nextText()
                            value:SetPoint("CENTER", frame, "TOPLEFT",
                                M.metrics.padding + column.x + column.width / 2, M.rowCenterY(row.y))
                            value:SetSize(column.width, M.metrics.rowHeight)
                            value:SetJustifyH("CENTER")
                            value:SetTextColor(M.colors.text.r, M.colors.text.g, M.colors.text.b)
                            value:SetText(text)
                        end
                        -- A currency value with a confirmed id gets a hover
                        -- surface so its caps can surface as a tooltip without
                        -- crowding the cell body.
                        if type(cell.currencyId) == "number" or cell.difficulties or cell.activity then
                            local valueButton = nextValueButton()
                            valueButton:SetPoint("CENTER", frame, "TOPLEFT",
                                M.metrics.padding + column.x + column.width / 2, M.rowCenterY(row.y))
                            valueButton:SetSize(column.width, M.metrics.rowHeight)
                            valueButton.__cell = cell
                            valueButton.__section = section.key
                            valueButton.__row = row
                        end
                    end
                end
            end
        end

        -- Totals only where the column declared one; status and item columns
        -- deliberately show nothing rather than a meaningless sum.
        if section.totalsY and section.totals then
            local label = nextText()
            label:SetPoint("LEFT", frame, "TOPLEFT", M.metrics.padding,
                M.rowCenterY(section.totalsY))
            label:SetSize(M.metrics.nameColumnWidth, M.metrics.totalsRowHeight)
            label:SetTextColor(M.colors.hint.r, M.colors.hint.g, M.colors.hint.b)
            label:SetText(L["合计"])
            for _, column in ipairs(section.columns) do
                local total = section.totals[column.id]
                if type(total) == "number" then
                    local value = nextText()
                    value:SetPoint("CENTER", frame, "TOPLEFT",
                        M.metrics.padding + column.x + column.width / 2, M.rowCenterY(section.totalsY))
                    value:SetSize(column.width, M.metrics.totalsRowHeight)
                    value:SetJustifyH("CENTER")
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

function M.IsVisible()
    if not frame then return false end
    if type(frame.IsShown) == "function" then return frame:IsShown() == true end
    if type(frame.IsVisible) == "function" then return frame:IsVisible() == true end
    return false
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
