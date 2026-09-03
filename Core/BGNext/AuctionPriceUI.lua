local _, ns = ...

BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Page state, fixed layout rules, and the reusable-row contract for the price
-- preset page. Everything above the runtime guard is pure and must stay loadable
-- with no WoW globals present. The frame hierarchy that builds on these rules
-- lives below the guard and reads prices only through the store/catalog/codec
-- modules, never from BiaoGe or a third-party source.
local M = {}

M.tabNumber = 2
M.COLUMN_COUNT = 2
M.MIN_ROWS_PER_COLUMN = 12
M.MAX_ROWS_PER_COLUMN = 30
M.ROW_HEIGHT = 24
M.ROW_CAPACITY = M.COLUMN_COUNT * M.MAX_ROWS_PER_COLUMN
M.DECORATIVE_REGION_COUNT = 1
M.ITEM_FONT_SIZE = 13
M.PRICE_FONT_SIZE = 13
-- Vertical space reserved at the bottom of the main frame for the fixed
-- bottom-right entries (角色总览, 交易记录, 邮件记录, 结算前检查) plus a small
-- margin, so the item list never covers those buttons.
M.BOTTOM_RESERVE = 34

-- Height of the fixed controls above the item rows (raid bar, mode bar,
-- description, toolbar, boss picker, filter bar and their gaps). Combined with
-- BOTTOM_RESERVE it separates the reusable list from the frame's fixed chrome.
M.TOP_CHROME = 190

-- Available vertical space for the item list: the main frame height minus the
-- fixed controls above and the fixed bottom entries below.
function M.contentHeight(mainHeight)
    mainHeight = math.max(tonumber(mainHeight) or 0, 0)
    return math.max(mainHeight - M.TOP_CHROME - M.BOTTOM_RESERVE, 0)
end

-- Computes the reusable viewport from the content area. The left margin, 230px
-- Boss picker, inter-panel gap and slim slider/right margin are fixed
-- deductions; the row count derives from the actual content height, so a
-- shorter main frame or a taller locale/tooltip line yields fewer rows instead
-- of overflowing the bottom of the frame.
function M.viewportLayout(width, contentHeight)
    width = math.max(tonumber(width) or 0, 0)
    contentHeight = math.max(tonumber(contentHeight) or 0, 0)
    local availableWidth = math.max(width - 292, 652)
    local columnWidth = math.max(math.floor((availableWidth - 12) / M.COLUMN_COUNT), 320)
    local rows = math.floor(contentHeight / M.ROW_HEIGHT)
    if rows < M.MIN_ROWS_PER_COLUMN then rows = M.MIN_ROWS_PER_COLUMN end
    if rows > M.MAX_ROWS_PER_COLUMN then rows = M.MAX_ROWS_PER_COLUMN end
    return {
        columns = M.COLUMN_COUNT,
        rowsPerColumn = rows,
        capacity = rows * M.COLUMN_COUNT,
        columnWidth = columnWidth,
        columnGap = 12,
        rowHeight = M.ROW_HEIGHT,
        itemHeight = rows * M.ROW_HEIGHT,
    }
end

M.LABELS = {
    leader = "团长起拍价",
    personal = "我的心理价",
}

M.DESCRIPTIONS = {
    leader = "用于团长开团时自动填入起拍价；单件价优先，修改基础价只影响未单独设置的装备。",
    personal = "用于参团时自动填入已保存的心理价，不会自动启用或发送。",
}

function M.buttonWidth(textWidth, padding, minimum, maximum)
    textWidth = type(textWidth) == "number" and textWidth or 0
    padding = type(padding) == "number" and padding or 0
    local width = textWidth + padding
    if type(minimum) == "number" and width < minimum then width = minimum end
    if type(maximum) == "number" and width > maximum then width = maximum end
    return width
end

function M.popupEditBox(popup)
    if not popup then return nil end
    return popup.EditBox or popup.editBox
end

-- BG.Boss is the canonical loot-owner registry. Its final four entries are the
-- ledger-only misc/fine/expense/overview sections added by DB_BossName.lua.
-- ns.Maxb cannot be used here: it describes the visual ledger layout and is
-- intentionally smaller than the boss registry for several combined raids.
function M.bossDefinitions(registry)
    if type(registry) ~= "table" then return {} end
    local count = 0
    while type(registry["boss" .. (count + 1)]) == "table" do
        count = count + 1
    end
    count = math.max(count - 4, 0)

    local bosses = {}
    for i = 1, count do
        local info = registry["boss" .. i]
        bosses[#bosses + 1] = { id = "boss" .. i, name = info and info.name2 or nil }
    end
    return bosses
end

function M.bossCountLabel(name, count)
    return tostring(name or "") .. "（" .. tostring(math.max(math.floor(tonumber(count) or 0), 0)) .. "件）"
end

function M.itemTooltipLink(itemId)
    if type(itemId) ~= "number" then return nil end
    return "item:" .. tostring(itemId)
end

-- Reduces each item row to one value and one semantic state. `explicitValue`
-- is nil only when the row inherits the leader base price or has no personal
-- expectation, which also means there is nothing for the clear action to do.
function M.priceDisplay(mode, explicitValue, baseValue)
    if type(explicitValue) == "number" then
        return tostring(explicitValue) .. " G", true, "primary"
    end
    if mode == "leader" then
        return tostring(type(baseValue) == "number" and baseValue or 0) .. " G", false, "secondary"
    end
    return "—", false, "secondary"
end

local LEADER_ACTIONS = { "preset", "basePrice", "active", "new", "copy", "rename", "delete", "import", "export" }
local PERSONAL_ACTIONS = { "itemCount", "import", "export", "clear" }

local function validMode(mode)
    if mode == "leader" or mode == "personal" then return mode end
    return nil
end

local function emptyFilters()
    return { text = "", equipLoc = nil, quality = nil, state = nil }
end

-- Creates a fresh page state for one raid. The default mode is leader.
function M.newState(raidId)
    return {
        raidId = raidId,
        mode = "leader",
        bossId = nil,
        savedBossId = nil,
        itemOffset = 0,
        filters = emptyFilters(),
    }
end

-- Switches the price mode while preserving the current raid, boss, search and
-- scroll position.
function M.setMode(state, mode)
    mode = validMode(mode)
    if not mode or type(state) ~= "table" then return false end
    state.mode = mode
    return true
end

-- Selects another raid and resets the boss/search position to the raid's start.
function M.selectRaid(state, raidId)
    if type(state) ~= "table" then return false end
    state.raidId = raidId
    state.bossId = nil
    state.savedBossId = nil
    state.itemOffset = 0
    state.filters = emptyFilters()
    return true
end

-- Selects a Boss or misc group. The saved boss tracks where to return after a
-- raid-wide search is cleared.
function M.selectBoss(state, bossId)
    if type(state) ~= "table" then return false end
    state.bossId = bossId
    state.savedBossId = bossId
    state.itemOffset = 0
    return true
end

-- Sets one filter field. Starting a text search remembers the current boss so it
-- can be restored on clear.
function M.setFilter(state, key, value)
    if type(state) ~= "table" or type(key) ~= "string" then return false end
    if type(state.filters) ~= "table" then state.filters = emptyFilters() end
    if key == "text" and state.filters.text == "" and value ~= nil and value ~= "" then
        state.savedBossId = state.bossId
    end
    state.filters[key] = value
    state.itemOffset = 0
    return true
end

-- Clears every filter and returns to the boss position in place before the
-- search began.
function M.clearFilters(state)
    if type(state) ~= "table" then return false end
    state.filters = emptyFilters()
    state.itemOffset = 0
    if state.savedBossId ~= nil then
        state.bossId = state.savedBossId
    end
    return true
end

-- Returns the index after the currently focused one within the visible results,
-- wrapping to the first. nil when the list is empty; 1 when nothing is focused.
function M.nextVisibleIndex(filteredItems, currentIndex)
    local total = type(filteredItems) == "table" and #filteredItems or 0
    if total <= 0 then return nil end
    if type(currentIndex) ~= "number" then return 1 end
    local next = math.floor(currentIndex) + 1
    if next > total then next = 1 end
    if next < 1 then next = 1 end
    return next
end

-- The number of reusable rows actually needed for a result list: never more than
-- the fixed capacity, so large raids keep a constant object count.
function M.visibleRowCount(total, capacity)
    total = tonumber(total) or 0
    capacity = tonumber(capacity) or 0
    if total < 0 then total = 0 end
    if capacity < 0 then capacity = 0 end
    return total < capacity and total or capacity
end

-- Returns the slice rendered by the reusable-row viewport, together with the
-- clamped zero-based offset and its maximum. Keeping this pure makes it
-- impossible for a long loot list to silently strand items after row twelve.
function M.visibleWindow(items, offset, capacity)
    items = type(items) == "table" and items or {}
    capacity = math.max(math.floor(tonumber(capacity) or 0), 0)
    local maxOffset = math.max(#items - capacity, 0)
    offset = math.floor(tonumber(offset) or 0)
    if offset < 0 then offset = 0 end
    if offset > maxOffset then offset = maxOffset end

    local visible = {}
    for i = 1, capacity do
        local item = items[offset + i]
        if item == nil then break end
        visible[#visible + 1] = item
    end
    return visible, offset, maxOffset
end

-- Ordered toolbar action keys for a mode. Leader keeps the full scheme toolbar;
-- personal has a single set of prices and only import/export/clear.
function M.toolbarActions(mode)
    if mode == "leader" then return LEADER_ACTIONS end
    if mode == "personal" then return PERSONAL_ACTIONS end
    return nil
end

-- One-line description shown only on this page, never in the auction window.
function M.description(mode)
    return M.DESCRIPTIONS[mode]
end

-- Import/export choices. Leader schemes export by "current" (active only) or
-- "all"; personal expectations have no scope and always export the current raid.
-- Leader imports add "new" schemes or "replace" the whole set; personal imports
-- "merge" (overwrite matching items) or "replace" (clear then import). Any mode
-- that overwrites saved data ("replace") requires an explicit confirmation.
M.EXPORT_SCOPES = {
    leader = { "current", "all" },
    personal = {},
}

M.IMPORT_MODES = {
    leader = { "new", "replace" },
    personal = { "merge", "replace" },
}

function M.importRequiresConfirmation(mode)
    return mode == "replace"
end

local function runtimeReady()
    return ns ~= nil
        and BG.Init2 ~= nil
        and BG.BGNext.AuctionPriceStore ~= nil
        and BG.BGNext.AuctionPriceCatalog ~= nil
        and BG.BGNext.AuctionPriceCodec ~= nil
        and BG.BGNext.UIStyle ~= nil
end

-- The frame tree is built once, late, inside BG.Init2 (PLAYER_ENTERING_WORLD).
-- AuctionPriceUI registers before BiaoGe.lua, so BG.MainFrame and
-- BG.Create_TabButton do not exist yet at BG.Init (ADDON_LOADED) time; the page
-- must wait until the main frame and tab system are assembled.
if runtimeReady() then
    local Store = BG.BGNext.AuctionPriceStore
    local Catalog = BG.BGNext.AuctionPriceCatalog
    local Codec = BG.BGNext.AuctionPriceCodec
    local Style = BG.BGNext.UIStyle
    local L = ns.L or setmetatable({}, { __index = function(_, k) return tostring(k) end })

    -- Canonical client families, ordered so that flags which imply a weaker one
    -- (Titan also sets IsWLK, Season of Discovery also sets IsVanilla) resolve to
    -- the stronger family first.
    local FAMILY_ORDER = {
        { flag = "IsRetail", family = "retail" },
        { flag = "IsMOP", family = "mop" },
        { flag = "IsCTM", family = "cata" },
        { flag = "IsTitan", family = "titan" },
        { flag = "IsWLK", family = "wrath" },
        { flag = "IsTBC", family = "tbc" },
        { flag = "IsVanilla", family = "vanilla" },
    }

    local function clientFamily()
        for _, entry in ipairs(FAMILY_ORDER) do
            if BG[entry.flag] then return entry.family end
        end
        return nil
    end

    local function context(raidId)
        return BG.BGNext.DB, clientFamily(), BG.realmID, BG.playerName, raidId
    end

    -- Read the player's current global starting price lazily; BiaoGe.Auction is
    -- not available at BG.Init time because Auction.lua loads after this file.
    local function globalMoney()
        if type(BiaoGe) == "table" and type(BiaoGe.Auction) == "table" then
            return BiaoGe.Auction.money
        end
        return nil
    end

    local function localMessage(message)
        if BG.SendSystemMessage then BG.SendSystemMessage(message) else print("<BGNext> " .. message) end
    end

    local function describeItem(itemId)
        if type(GetItemInfo) ~= "function" then return nil end
        local name, _, quality, _, _, _, _, _, equipLoc = GetItemInfo(itemId)
        return { name = name, equipLoc = equipLoc, quality = quality }
    end

    -- Projects the approved BG loot catalog for every known raid. Unknown boss
    -- keys (Team/World/Currency/…) are auto-routed to the misc group by the
    -- catalog.
    local function buildCatalog()
        local models = {}
        for _, raidId in ipairs(BG.FBtable or {}) do
            local bosses = M.bossDefinitions(BG.Boss and BG.Boss[raidId])
            local model = Catalog.build({
                raidId = raidId,
                difficulties = (BG.difficultyTable and BG.difficultyTable[raidId]) or nil,
                bosses = bosses,
                loot = (BG.Loot and BG.Loot[raidId]) or {},
                describeItem = describeItem,
            })
            if model then models[raidId] = model end
        end
        return models
    end

    local function leaderRaid(raidId)
        local root, family = context(raidId)
        if not root or not family then return nil end
        return Store.ensureLeaderRaid(root, family, raidId, globalMoney())
    end

    local function activePresetId(raidId)
        local raid = leaderRaid(raidId)
        return raid and raid.activePresetId
    end

    BG.Init2(function()
        if not BG.MainFrame or not BG.Create_TabButton or not BG.BGNext.DB then return end
        if BG.PricePresetMainFrame then return end

        local models = buildCatalog()
        local pageState = M.newState(BG.FB1 or (BG.FBtable and BG.FBtable[1]))

        -- The import preview only accepts items the page actually knows, so an
        -- unknown item id is always surfaced (and skipped) rather than stored.
        local knownItems = {}
        for _, model in pairs(models) do
            for itemId in pairs(model.byItem or {}) do knownItems[itemId] = true end
        end

        -- Forward declarations: several of these call each other, so they are
        -- declared up front and assigned below before any script can fire.
        local refreshRows, refreshRaidBar, refreshModeBar, refreshToolbar
        local refreshBossBar, refreshFilterBar, refreshAll
        local clearRow, cyclePreset
        local newScheme, copyScheme, renameScheme, deleteScheme, confirmClearPersonal
        local showExportPanel, showImportPanel, refreshImportPreview, exportText, applyImport

        -- ---- Fixed control frames (scripts are wired at the end) ----
        local main = CreateFrame("Frame", nil, BG.MainFrame)
        main:SetAllPoints(BG.MainFrame)
        main:Hide()
        BG.PricePresetMainFrame = main
        local layout = M.viewportLayout(BG.MainFrame:GetWidth(), M.contentHeight(BG.MainFrame:GetHeight()))
        local pageCapacity = layout.capacity

        main.raidBar = CreateFrame("Frame", nil, main)
        main.raidBar:SetPoint("TOPLEFT", 12, -30)
        main.raidBar:SetSize(1, 24)

        main.modeBar = CreateFrame("Frame", nil, main)
        main.modeBar:SetPoint("TOPLEFT", main.raidBar, "BOTTOMLEFT", 0, -6)
        main.modeBar:SetSize(1, 26)

        main.description = main:CreateFontString(nil, "OVERLAY")
        main.description:SetPoint("TOPLEFT", main.modeBar, "BOTTOMLEFT", 2, -6)
        main.description:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        main.description:SetTextColor(1, 0.82, 0)
        main.description:SetWidth(560)

        main.toolbar = CreateFrame("Frame", nil, main)
        main.toolbar:SetPoint("TOPLEFT", main.description, "BOTTOMLEFT", 0, -6)
        main.toolbar:SetSize(1, 24)

        main.bossScroll = CreateFrame("Frame", nil, main, "BackdropTemplate")
        main.bossScroll:SetPoint("TOPLEFT", main.toolbar, "BOTTOMLEFT", 0, -8)
        main.bossScroll:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 0, M.BOTTOM_RESERVE)
        main.bossScroll:SetWidth(230)
        Style.applySurface(main.bossScroll, "surface", 0.44)

        main.filterBar = CreateFrame("Frame", nil, main)
        main.filterBar:SetPoint("TOPLEFT", main.bossScroll, "TOPRIGHT", 14, 0)
        main.filterBar:SetSize(1, 24)

        main.itemScroll = CreateFrame("Frame", nil, main, "BackdropTemplate")
        main.itemScroll:SetPoint("TOPLEFT", main.filterBar, "BOTTOMLEFT", 0, -8)
        main.itemScroll:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 0, M.BOTTOM_RESERVE)
        main.itemScroll:SetWidth(layout.columnWidth * layout.columns + layout.columnGap * (layout.columns - 1))
        main.itemScroll:EnableMouseWheel(true)
        Style.applySurface(main.itemScroll, "surface", 0.44)

        main.columnDivider = main.itemScroll:CreateTexture(nil, "BORDER")
        main.columnDivider:SetPoint("TOP", main.itemScroll, "TOPLEFT",
            layout.columnWidth + layout.columnGap / 2, -4)
        main.columnDivider:SetPoint("BOTTOM", main.itemScroll, "BOTTOMLEFT",
            layout.columnWidth + layout.columnGap / 2, 4)
        main.columnDivider:SetWidth(1)
        main.columnDivider:SetColorTexture(0.141, 0.267, 0.369, 0.55)

        -- A plain slider is intentional here. Blizzard's framed scrollbar
        -- assumes a compatible ScrollFrame parent and crashes when this page
        -- sets the value on a normal Frame.
        main.itemSlider = CreateFrame("Slider", nil, main)
        main.itemSlider:SetOrientation("VERTICAL")
        main.itemSlider:SetPoint("TOPLEFT", main.itemScroll, "TOPRIGHT", 4, 0)
        main.itemSlider:SetPoint("BOTTOMLEFT", main.itemScroll, "BOTTOMRIGHT", 4, 0)
        main.itemSlider:SetWidth(12)
        main.itemSlider:SetMinMaxValues(0, 0)
        main.itemSlider:SetValueStep(1)
        local sliderTrack = main.itemSlider:CreateTexture(nil, "BACKGROUND")
        sliderTrack:SetPoint("TOP", 0, 0)
        sliderTrack:SetPoint("BOTTOM", 0, 0)
        sliderTrack:SetWidth(3)
        sliderTrack:SetColorTexture(0.2, 0.2, 0.2, 0.65)
        main.itemSlider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        local sliderThumb = main.itemSlider:GetThumbTexture()
        sliderThumb:SetSize(10, 28)
        sliderThumb:SetVertexColor(0.15, 0.75, 0.95, 0.9)

        -- Reusable rows fill two columns and are created once. Even the largest
        -- layout is capped at sixty row objects; their position is (re)applied by
        -- positionRows whenever the content area changes, so a resize never
        -- leaves rows stranded outside the scrolled region.
        local function positionRows()
            for i = 1, pageCapacity do
                local row = main.rows[i]
                if not row then return end
                local column = math.floor((i - 1) / layout.rowsPerColumn)
                local rowInColumn = (i - 1) % layout.rowsPerColumn
                row:ClearAllPoints()
                row:SetPoint(
                    "TOPLEFT",
                    main.itemScroll,
                    "TOPLEFT",
                    column * (layout.columnWidth + layout.columnGap),
                    -rowInColumn * layout.rowHeight
                )
                row:SetWidth(layout.columnWidth)
            end
        end

        main.rows = {}
        for i = 1, pageCapacity do
            local row = CreateFrame("Frame", nil, main.itemScroll)
            row:SetSize(layout.columnWidth, 22)
            row.index = i
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetPoint("LEFT", 0, 0)
            row.icon:SetSize(18, 18)
            row.name = row:CreateFontString(nil, "OVERLAY")
            row.name:SetFont(BIAOGE_TEXT_FONT, M.ITEM_FONT_SIZE, "OUTLINE")
            row.price = row:CreateFontString(nil, "OVERLAY")
            row.price:SetFont(BIAOGE_TEXT_FONT, M.PRICE_FONT_SIZE, "OUTLINE")
            row.price:SetTextColor(1, 0.82, 0)
            row.price:SetWidth(110)
            row.edit = CreateFrame("EditBox", nil, row, BG.editTemplate or "InputBoxTemplate")
            row.edit:SetSize(58, 20)
            row.edit:SetAutoFocus(false)
            row.edit:SetNumeric(true)
            row.edit:SetTextColor(1, 1, 1)
            row.clear = CreateFrame("Button", nil, row)
            row.clear:SetSize(16, 16)
            row.clear:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            row.edit:SetPoint("RIGHT", row.clear, "LEFT", -4, 0)
            row.price:SetPoint("RIGHT", row.edit, "LEFT", -6, 0)
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
            row.name:SetPoint("RIGHT", row.price, "LEFT", -6, 0)
            local cx = row.clear:CreateFontString(nil, "OVERLAY")
            cx:SetAllPoints()
            cx:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
            cx:SetTextColor(1, 0.3, 0.3)
            cx:SetText("X")
            row:EnableMouse(true)
            row:EnableMouseWheel(true)
            row:SetScript("OnMouseWheel", function(_, delta)
                local offset = tonumber(pageState.itemOffset) or 0
                main.itemSlider:SetValue(offset - (tonumber(delta) or 0) * 3)
            end)
            row:SetScript("OnEnter", function(self)
                local link = M.itemTooltipLink(self.itemId)
                if not link or not GameTooltip then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(link)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)
            main.rows[i] = row
        end
        positionRows()

        -- Mode buttons.
        local leaderButton = BG.CreateButton(main.modeBar)
        leaderButton:SetPoint("TOPLEFT", main.modeBar, "TOPLEFT", 0, 0)
        leaderButton:SetSize(110, 24)
        local personalButton = BG.CreateButton(main.modeBar)
        personalButton:SetPoint("LEFT", leaderButton, "RIGHT", 6, 0)
        personalButton:SetSize(110, 24)

        -- Leader scheme toolbar controls.
        local presetButton = BG.CreateButton(main.toolbar)
        presetButton:SetPoint("TOPLEFT", main.toolbar, "TOPLEFT", 0, 0)
        presetButton:SetSize(120, 22)
        local activeLabel = main.toolbar:CreateFontString(nil, "OVERLAY")
        activeLabel:SetPoint("LEFT", presetButton, "RIGHT", 8, 0)
        activeLabel:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        activeLabel:SetTextColor(0.6, 1, 0.6)
        local basePriceEdit = CreateFrame("EditBox", nil, main.toolbar, BG.editTemplate or "InputBoxTemplate")
        basePriceEdit:SetPoint("LEFT", activeLabel, "RIGHT", 8, 0)
        basePriceEdit:SetSize(70, 20)
        basePriceEdit:SetAutoFocus(false)
        basePriceEdit:SetNumeric(true)
        basePriceEdit:SetTextColor(1, 1, 1)
        local newButton = BG.CreateButton(main.toolbar)
        newButton:SetPoint("LEFT", basePriceEdit, "RIGHT", 8, 0)
        newButton:SetSize(52, 22)
        local copyButton = BG.CreateButton(main.toolbar)
        copyButton:SetPoint("LEFT", newButton, "RIGHT", 4, 0)
        copyButton:SetSize(52, 22)
        local renameButton = BG.CreateButton(main.toolbar)
        renameButton:SetPoint("LEFT", copyButton, "RIGHT", 4, 0)
        renameButton:SetSize(66, 22)
        local deleteButton = BG.CreateButton(main.toolbar)
        deleteButton:SetPoint("LEFT", renameButton, "RIGHT", 4, 0)
        deleteButton:SetSize(52, 22)
        local importButton = BG.CreateButton(main.toolbar)
        importButton:SetPoint("LEFT", deleteButton, "RIGHT", 8, 0)
        importButton:SetSize(52, 22)
        local exportButton = BG.CreateButton(main.toolbar)
        exportButton:SetPoint("LEFT", importButton, "RIGHT", 4, 0)
        exportButton:SetSize(52, 22)
        if Style.isPreviewEnabled(BiaoGe and BiaoGe.BGNext) then
            Style.setButtonState(deleteButton, "danger", BiaoGe.options.alpha)
        end

        -- Personal toolbar controls.
        local countLabel = main.toolbar:CreateFontString(nil, "OVERLAY")
        countLabel:SetPoint("TOPLEFT", main.toolbar, "TOPLEFT", 0, 0)
        countLabel:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        countLabel:SetTextColor(0.6, 1, 0.6)
        local clearPersonalButton = BG.CreateButton(main.toolbar)
        clearPersonalButton:SetPoint("LEFT", countLabel, "RIGHT", 8, 0)
        clearPersonalButton:SetSize(120, 22)
        local importPersonalButton = BG.CreateButton(main.toolbar)
        importPersonalButton:SetPoint("LEFT", clearPersonalButton, "RIGHT", 8, 0)
        importPersonalButton:SetSize(52, 22)
        local exportPersonalButton = BG.CreateButton(main.toolbar)
        exportPersonalButton:SetPoint("LEFT", importPersonalButton, "RIGHT", 4, 0)
        exportPersonalButton:SetSize(52, 22)
        if Style.isPreviewEnabled(BiaoGe and BiaoGe.BGNext) then
            Style.setButtonState(clearPersonalButton, "danger", BiaoGe.options.alpha)
        end

        local leaderControls = { presetButton, activeLabel, basePriceEdit, newButton, copyButton, renameButton, deleteButton, importButton, exportButton }
        local personalControls = { countLabel, clearPersonalButton, importPersonalButton, exportPersonalButton }

        local function applySelection(bt, selected)
            if not Style.isPreviewEnabled(BiaoGe and BiaoGe.BGNext) then return end
            if selected then
                Style.setButtonState(bt, "selected", BiaoGe.options.alpha)
            else
                Style.setButtonState(bt, "normal", BiaoGe.options.alpha)
            end
        end

        local function applyBossSelection(bt, selected)
            if not Style.isPreviewEnabled(BiaoGe and BiaoGe.BGNext) then return end
            Style.setButtonState(bt, selected and "listSelected" or "listNormal", BiaoGe.options.alpha)
        end

        -- Locale strings vary substantially in width. Measure the current label
        -- instead of assuming Chinese-sized controls so English and fallback
        -- locales remain readable without changing the surrounding layout model.
        local function fitButtonToText(button, minimum, maximum, padding)
            local fontString = button and button:GetFontString()
            if fontString then
                button:SetWidth(M.buttonWidth(fontString:GetStringWidth(), padding or 18, minimum, maximum))
            end
        end

        -- Filter bar: search box, set/unset/all state toggle, clear.
        local searchBox = CreateFrame("EditBox", nil, main.filterBar, BG.editTemplate or "InputBoxTemplate")
        searchBox:SetPoint("TOPLEFT", main.filterBar, "TOPLEFT", 0, 0)
        searchBox:SetSize(140, 20)
        searchBox:SetAutoFocus(false)
        searchBox:SetTextColor(1, 1, 1)
        local stateButton = BG.CreateButton(main.filterBar)
        stateButton:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)
        stateButton:SetSize(70, 20)
        local clearFiltersButton = BG.CreateButton(main.filterBar)
        clearFiltersButton:SetPoint("LEFT", stateButton, "RIGHT", 6, 0)
        clearFiltersButton:SetSize(70, 20)

        -- ---- Query helpers ----
        local function hasPriceFor(itemId)
            local root, family, realmId, player = context(pageState.raidId)
            if pageState.mode == "leader" then
                local raid = root and root.leaderAuctionPricePresets and root.leaderAuctionPricePresets[family] and root.leaderAuctionPricePresets[family][pageState.raidId]
                local presetId = raid and raid.activePresetId
                local preset = raid and raid.presets and raid.presets[presetId]
                return preset and type(preset.itemPrices) == "table" and preset.itemPrices[itemId] ~= nil
            end
            return Store.getPersonalPrice(root, family, realmId, player, pageState.raidId, itemId) ~= nil
        end

        local function filteredItems()
            local model = models[pageState.raidId]
            if not model then return {} end
            local results = Catalog.filter(model, {
                text = pageState.filters.text,
                equipLoc = pageState.filters.equipLoc,
                quality = pageState.filters.quality,
                state = pageState.filters.state,
                hasPrice = hasPriceFor,
            })
            local searching = pageState.filters.text and pageState.filters.text ~= ""
            local bossId = pageState.bossId
            if not searching and bossId and bossId ~= "all" then
                local scoped = {}
                for _, item in ipairs(results) do
                    if item.groupId == bossId then scoped[#scoped + 1] = item end
                end
                return scoped
            end
            return results
        end

        local function validateEdit(row)
            local text = row.edit:GetText()
            if text == nil or text == "" then
                row.edit:SetTextColor(1, 1, 1)
                return true
            end
            local money = tonumber(text)
            if not money or money % 1 ~= 0 or money < 0 or money > Store.MAX_MONEY then
                row.edit:SetTextColor(1, 0.3, 0.3)
                return false
            end
            row.edit:SetTextColor(1, 1, 1)
            return true
        end

        local function saveEdit(row)
            local itemId = row.itemId
            if not itemId then return true end
            local text = row.edit:GetText()
            if text == nil or text == "" then return true end
            local money = tonumber(text)
            if not money then return false end
            local root, family, realmId, player = context(pageState.raidId)
            if pageState.mode == "leader" then
                local presetId = activePresetId(pageState.raidId)
                if not presetId then return false end
                return Store.setLeaderItemPrice(root, family, pageState.raidId, presetId, itemId, money)
            end
            return Store.setPersonalPrice(root, family, realmId, player, pageState.raidId, itemId, money)
        end

        -- Sorted preset ids (numerically, so p2 sorts before p10).
        local function presetIds()
            local root, family = context(pageState.raidId)
            local raid = root and root.leaderAuctionPricePresets and root.leaderAuctionPricePresets[family] and root.leaderAuctionPricePresets[family][pageState.raidId]
            if not raid or type(raid.presets) ~= "table" then return {} end
            local ids = {}
            for id in pairs(raid.presets) do ids[#ids + 1] = id end
            table.sort(ids, function(a, b)
                return (tonumber(string.match(a, "p(%d+)")) or 0) < (tonumber(string.match(b, "p(%d+)")) or 0)
            end)
            return ids
        end

        -- Reused StaticPopup with an edit box, whose OnAccept captures the current
        -- action each time it is shown.
        local function showEditPopup(title, defaultText, onAccept)
            local popupName = "BGNEXT_AUCTION_PRICE_EDIT"
            StaticPopupDialogs[popupName] = StaticPopupDialogs[popupName] or {
                button1 = OKAY or "确定",
                button2 = CANCEL or "取消",
                hasEditBox = true,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            local dialog = StaticPopupDialogs[popupName]
            dialog.text = title
            dialog.OnAccept = function(self)
                local editBox = M.popupEditBox(self)
                local value = editBox and editBox:GetText() or ""
                onAccept(value)
            end
            dialog.OnShow = function(self)
                local editBox = M.popupEditBox(self)
                if not editBox then return end
                if defaultText then editBox:SetText(defaultText) end
                editBox:SetFocus()
            end
            StaticPopup_Show(popupName)
        end

        -- ---- Scheme operations (leader mode) ----
        function cyclePreset(dir)
            local ids = presetIds()
            if #ids == 0 then return end
            local current = activePresetId(pageState.raidId)
            local index = 1
            for i, id in ipairs(ids) do
                if id == current then index = i break end
            end
            index = index + (dir or 1)
            if index > #ids then index = 1 end
            if index < 1 then index = #ids end
            local root, family = context(pageState.raidId)
            if Store.selectPreset(root, family, pageState.raidId, ids[index]) then
                refreshToolbar()
                refreshRows()
            end
        end

        function newScheme()
            local root, family = context(pageState.raidId)
            if #presetIds() >= Store.MAX_PRESETS then
                localMessage((L["最多"] or "最多") .. " " .. tostring(Store.MAX_PRESETS) .. " " .. (L["套方案。"] or "套方案。"))
                return
            end
            local base = globalMoney() or Store.defaultGlobalPrice(family) or 0
            showEditPopup(L["新方案名称"] or "新方案名称", "", function(name)
                local id = Store.createPreset(root, family, pageState.raidId, name, base)
                if not id then
                    localMessage(L["无法创建方案。"] or "无法创建方案。")
                else
                    Store.selectPreset(root, family, pageState.raidId, id)
                    refreshToolbar()
                    refreshRows()
                end
            end)
        end

        function copyScheme()
            local root, family = context(pageState.raidId)
            local presetId = activePresetId(pageState.raidId)
            if not presetId then return end
            if #presetIds() >= Store.MAX_PRESETS then
                localMessage((L["最多"] or "最多") .. " " .. tostring(Store.MAX_PRESETS) .. " " .. (L["套方案。"] or "套方案。"))
                return
            end
            local id = Store.copyPreset(root, family, pageState.raidId, presetId, nil)
            if id then
                Store.selectPreset(root, family, pageState.raidId, id)
                refreshToolbar()
                refreshRows()
            else
                localMessage(L["无法复制方案。"] or "无法复制方案。")
            end
        end

        function renameScheme()
            local root, family = context(pageState.raidId)
            local presetId = activePresetId(pageState.raidId)
            if not presetId then return end
            local raid = root and root.leaderAuctionPricePresets and root.leaderAuctionPricePresets[family] and root.leaderAuctionPricePresets[family][pageState.raidId]
            local preset = raid and raid.presets and raid.presets[presetId]
            local current = preset and preset.name or ""
            showEditPopup(L["重命名方案"] or "重命名方案", current, function(name)
                if Store.renamePreset(root, family, pageState.raidId, presetId, name) then
                    refreshToolbar()
                else
                    localMessage(L["名称无效。"] or "名称无效。")
                end
            end)
        end

        -- Opens the same validated editor from a bill-table Ctrl+right-click.
        -- The shortcut saves only a local per-item override in the active leader
        -- scheme; it never starts an auction or sends a message.
        function M.openLeaderPriceEditor(itemId, raidId)
            raidId = raidId or BG.FB1
            if type(itemId) ~= "number" or type(raidId) ~= "string" or raidId == "" then return false end
            local root, family = context(raidId)
            local raid = root and family and Store.ensureLeaderRaid(root, family, raidId, globalMoney())
            local presetId = raid and raid.activePresetId
            local preset = presetId and raid.presets and raid.presets[presetId]
            if type(preset) ~= "table" then return false end
            local current = type(preset.itemPrices) == "table" and preset.itemPrices[itemId]
            if type(current) ~= "number" then current = preset.basePrice end
            showEditPopup(L["修改预设起拍价"] or "修改预设起拍价", tostring(current or ""), function(text)
                local money = tonumber(text)
                if not money or money % 1 ~= 0 or money < 0 or money > Store.MAX_MONEY then
                    localMessage(L["价格无效。"] or "价格无效。")
                    return
                end
                if Store.setLeaderItemPrice(root, family, raidId, presetId, itemId, money) then
                    if pageState.raidId == raidId then
                        refreshToolbar()
                        refreshRows()
                    end
                    localMessage(L["预设起拍价已保存。"] or "预设起拍价已保存。")
                end
            end)
            return true
        end

        function deleteScheme()
            local root, family = context(pageState.raidId)
            local presetId = activePresetId(pageState.raidId)
            if not presetId then return end
            local ids = presetIds()
            if #ids <= 1 then
                localMessage(L["至少保留一套方案。"] or "至少保留一套方案。")
                return
            end
            local fallback
            for _, id in ipairs(ids) do
                if id ~= presetId then fallback = id break end
            end
            local popupName = "BGNEXT_DELETE_AUCTION_SCHEME"
            StaticPopupDialogs[popupName] = StaticPopupDialogs[popupName] or {
                button1 = YES or "是",
                button2 = NO or "否",
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            local dialog = StaticPopupDialogs[popupName]
            dialog.text = L["确定删除当前方案？"] or "确定删除当前方案？"
            dialog.OnAccept = function()
                if Store.deletePreset(root, family, pageState.raidId, presetId, fallback) then
                    refreshToolbar()
                    refreshRows()
                end
            end
            StaticPopup_Show(popupName)
        end

        function confirmClearPersonal()
            local popupName = "BGNEXT_CLEAR_AUCTION_EXPECTATIONS"
            StaticPopupDialogs[popupName] = StaticPopupDialogs[popupName] or {
                button1 = YES or "是",
                button2 = NO or "否",
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            local dialog = StaticPopupDialogs[popupName]
            dialog.text = L["确定清除本团本心理价？"] or "确定清除本团本心理价？"
            dialog.OnAccept = function()
                local root, family, realmId, player = context(pageState.raidId)
                Store.clearPersonalRaid(root, family, realmId, player, pageState.raidId)
                refreshToolbar()
                refreshRows()
            end
            StaticPopup_Show(popupName)
        end

        -- ---- Refresh functions ----
        function refreshRows()
            local allItems = filteredItems()
            local items, offset, maxOffset = M.visibleWindow(allItems, pageState.itemOffset, pageCapacity)
            pageState.itemOffset = offset
            main.itemSlider._refreshing = true
            main.itemSlider:SetMinMaxValues(0, maxOffset)
            main.itemSlider:SetValue(offset)
            main.itemSlider._refreshing = nil
            main.itemSlider:SetShown(maxOffset > 0)
            for i = 1, pageCapacity do
                local row = main.rows[i]
                local item = items[i]
                if item then
                    row:Show()
                    row.itemId = item.itemId
                    row.absoluteIndex = offset + i
                    local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(item.itemId)
                    if texture then row.icon:SetTexture(texture) else row.icon:SetTexture(nil) end
                    if name then item.name = name end
                    local displayName = name or item.name or tostring(item.itemId)
                    row.name:SetText(displayName)
                    local qr, qg, qb
                    if type(GetItemQualityColor) == "function" and type(quality or item.quality) == "number" then
                        qr, qg, qb = GetItemQualityColor(quality or item.quality)
                    else
                        qr, qg, qb = 1, 1, 1
                    end
                    row.name:SetTextColor(qr, qg, qb)
                    local displayText, canClear, textRole
                    if pageState.mode == "leader" then
                        local root, family = context(pageState.raidId)
                        local presetId = activePresetId(pageState.raidId)
                        local raid = root and root.leaderAuctionPricePresets and root.leaderAuctionPricePresets[family] and root.leaderAuctionPricePresets[family][pageState.raidId]
                        local preset = raid and raid.presets and raid.presets[presetId]
                        local override = preset and type(preset.itemPrices) == "table" and preset.itemPrices[item.itemId]
                        local base = preset and type(preset.basePrice) == "number" and preset.basePrice or 0
                        displayText, canClear, textRole = M.priceDisplay("leader", override, base)
                        row.edit._refreshing = true
                        row.edit:SetText(type(override) == "number" and tostring(override) or "")
                        row.edit._refreshing = nil
                    else
                        local root, family, realmId, player = context(pageState.raidId)
                        local value = Store.getPersonalPrice(root, family, realmId, player, pageState.raidId, item.itemId)
                        displayText, canClear, textRole = M.priceDisplay("personal", value)
                        row.edit._refreshing = true
                        row.edit:SetText(type(value) == "number" and tostring(value) or "")
                        row.edit._refreshing = nil
                    end
                    row.price:SetText(displayText)
                    row.clear:SetShown(canClear)
                    if Style.isPreviewEnabled(BiaoGe and BiaoGe.BGNext) then
                        Style.applyText(row.price, textRole)
                    end
                else
                    row:Hide()
                    row.itemId = nil
                    row.absoluteIndex = nil
                end
            end
        end

        function clearRow(row)
            local itemId = row.itemId
            if not itemId then return end
            local root, family, realmId, player = context(pageState.raidId)
            if pageState.mode == "leader" then
                local presetId = activePresetId(pageState.raidId)
                if presetId then
                    Store.clearLeaderItemPrice(root, family, pageState.raidId, presetId, itemId)
                end
            else
                Store.clearPersonalPrice(root, family, realmId, player, pageState.raidId, itemId)
            end
            refreshRows()
            refreshToolbar()
        end

        local raidButtons = {}
        function refreshRaidBar()
            for _, bt in ipairs(raidButtons) do bt:Hide() end
            local raidIds = BG.FBtable or {}
            for idx, raidId in ipairs(raidIds) do
                local bt = raidButtons[idx]
                if not bt then
                    bt = BG.CreateButton(main.raidBar)
                    bt:SetScript("OnClick", function(self)
                        M.selectRaid(pageState, self.raidId)
                        refreshAll()
                    end)
                    raidButtons[idx] = bt
                end
                bt.raidId = raidId
                local label = (BG.GetFBinfo and BG.GetFBinfo(raidId, "shortName")) or raidId
                bt:SetText(label or raidId)
                local f = bt:GetFontString()
                if f then bt:SetSize(M.buttonWidth(f:GetStringWidth(), 14, 80, 145), 22) end
                if idx == 1 then
                    bt:SetPoint("TOPLEFT", main.raidBar, "TOPLEFT", 0, 0)
                else
                    bt:SetPoint("LEFT", raidButtons[idx - 1], "RIGHT", 4, 0)
                end
                local selected = raidId == pageState.raidId
                if selected then bt:Disable() else bt:Enable() end
                applySelection(bt, selected)
                bt:Show()
            end
        end

        function refreshModeBar()
            leaderButton:SetText(L[M.LABELS.leader])
            personalButton:SetText(L[M.LABELS.personal])
            fitButtonToText(leaderButton, 110, 165)
            fitButtonToText(personalButton, 110, 165)
            if pageState.mode == "leader" then leaderButton:Disable() else leaderButton:Enable() end
            if pageState.mode == "personal" then personalButton:Disable() else personalButton:Enable() end
            applySelection(leaderButton, pageState.mode == "leader")
            applySelection(personalButton, pageState.mode == "personal")
            main.description:SetText(L[M.description(pageState.mode)] or "")
        end

        function refreshToolbar()
            if pageState.mode == "leader" then
                for _, c in ipairs(leaderControls) do c:Show() end
                for _, c in ipairs(personalControls) do c:Hide() end
                local presetId = activePresetId(pageState.raidId)
                local root, family = context(pageState.raidId)
                local raid = root and root.leaderAuctionPricePresets and root.leaderAuctionPricePresets[family] and root.leaderAuctionPricePresets[family][pageState.raidId]
                local preset = raid and raid.presets and raid.presets[presetId]
                local name = preset and preset.name or "默认方案"
                presetButton:SetText((L["方案"] or "方案") .. "：" .. name)
                activeLabel:SetText(L["基础价"] or "基础价")
                if preset and type(preset.basePrice) == "number" then
                    basePriceEdit:SetText(tostring(preset.basePrice))
                else
                    basePriceEdit:SetText("")
                end
                newButton:SetText(L["新建"] or "新建")
                copyButton:SetText(L["复制"] or "复制")
                renameButton:SetText(L["重命名"] or "重命名")
                deleteButton:SetText(L["删除"] or "删除")
                importButton:SetText(L["导入"] or "导入")
                exportButton:SetText(L["导出"] or "导出")
                fitButtonToText(newButton, 52, 82)
                fitButtonToText(copyButton, 52, 82)
                fitButtonToText(renameButton, 66, 98)
                fitButtonToText(deleteButton, 52, 82)
                fitButtonToText(importButton, 52, 82)
                fitButtonToText(exportButton, 52, 82)
            else
                for _, c in ipairs(leaderControls) do c:Hide() end
                for _, c in ipairs(personalControls) do c:Show() end
                local root, family, realmId, player = context(pageState.raidId)
                local count = Store.countPersonalPrices(root, family, realmId, player, pageState.raidId)
                countLabel:SetText((L["已设置"] or "已设置") .. " " .. tostring(count) .. " " .. (L["件装备"] or "件装备"))
                clearPersonalButton:SetText(L["清除本团本心理价"] or "清除本团本心理价")
                importPersonalButton:SetText(L["导入"] or "导入")
                exportPersonalButton:SetText(L["导出"] or "导出")
                fitButtonToText(clearPersonalButton, 120, 190)
                fitButtonToText(importPersonalButton, 52, 82)
                fitButtonToText(exportPersonalButton, 52, 82)
            end
        end

        local bossButtons = {}
        function refreshBossBar()
            for _, bt in ipairs(bossButtons) do bt:Hide() end
            local model = models[pageState.raidId]
            if not model then return end
            local allCount = 0
            for _, group in ipairs(model.groups) do allCount = allCount + #group.items end
            local nodes = { { id = "all", name = L["全部装备"] or "全部装备", count = allCount } }
            for _, group in ipairs(model.groups) do
                local name = group.id == "misc" and (L["杂项"] or "杂项") or group.name or tostring(group.id)
                nodes[#nodes + 1] = { id = group.id, name = name, count = #group.items }
            end
            for idx, node in ipairs(nodes) do
                local bt = bossButtons[idx]
                if not bt then
                    bt = BG.CreateButton(main.bossScroll)
                    bt:SetScript("OnClick", function(self)
                        M.selectBoss(pageState, self.nodeId)
                        refreshBossBar()
                        refreshRows()
                    end)
                    bossButtons[idx] = bt
                end
                bt.nodeId = node.id
                bt:SetText(M.bossCountLabel(node.name, node.count))
                bt:SetSize(220, 20)
                bt:SetPoint("TOPLEFT", main.bossScroll, "TOPLEFT", 0, -(idx - 1) * 22)
                local selected = (pageState.bossId == node.id) or (pageState.bossId == nil and node.id == "all")
                if selected then bt:Disable() else bt:Enable() end
                applyBossSelection(bt, selected)
                bt:Show()
            end
        end

        function refreshFilterBar()
            searchBox._refreshing = true
            searchBox:SetText(pageState.filters.text or "")
            searchBox._refreshing = nil
            local s = pageState.filters.state
            if s == "set" then stateButton:SetText(L["已设置"] or "已设置")
            elseif s == "unset" then stateButton:SetText(L["未设置"] or "未设置")
            else stateButton:SetText(L["全部"] or "全部") end
            clearFiltersButton:SetText(L["清除筛选"] or "清除筛选")
        end

        function refreshAll()
            refreshRaidBar()
            refreshModeBar()
            refreshToolbar()
            refreshBossBar()
            refreshFilterBar()
            refreshRows()
        end

        -- Re-derives the reusable viewport from the actual content area (the
        -- itemScroll region between the filter bar and the fixed bottom reserve),
        -- repositions the reusable rows and refreshes what is visible. Called
        -- once after the frame tree exists and again when the main frame resizes.
        local function relayout()
            local contentHeight = main.itemScroll and main.itemScroll:GetHeight()
            if type(contentHeight) ~= "number" or contentHeight <= 0 then return end
            local w = BG.MainFrame and BG.MainFrame:GetWidth()
            layout = M.viewportLayout(type(w) == "number" and w or layout.columnWidth, contentHeight)
            pageCapacity = layout.capacity
            main.itemScroll:SetWidth(layout.columnWidth * layout.columns + layout.columnGap * (layout.columns - 1))
            positionRows()
            refreshRows()
        end

        -- ---- Import/export panels ----
        -- Export never touches the clipboard or chat; it only fills an editable
        -- box and selects the text so the player can copy it manually.
        local exportPanel, importPanel
        local exportScope = "current"

        function exportText()
            local root, family, realmId, player = context(pageState.raidId)
            if not root or not family then return "" end
            if pageState.mode == "leader" then
                local raid = leaderRaid(pageState.raidId)
                if not raid then return "" end
                return Codec.exportLeader(family, pageState.raidId, raid, exportScope) or ""
            end
            local model = models[pageState.raidId]
            local itemPrices = {}
            if model then
                for _, group in ipairs(model.groups) do
                    for _, item in ipairs(group.items) do
                        local value = Store.getPersonalPrice(root, family, realmId, player, pageState.raidId, item.itemId)
                        if type(value) == "number" then itemPrices[item.itemId] = value end
                    end
                end
            end
            return Codec.exportPersonal(family, pageState.raidId, itemPrices) or ""
        end

        local function createExportPanel()
            local panel = CreateFrame("Frame", nil, main, "BackdropTemplate")
            panel:SetBackdrop({
                bgFile = "Interface/ChatFrame/ChatFrameBackground",
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                edgeSize = 10,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            panel:SetBackdropColor(0, 0, 0, 0.8)
            panel:SetPoint("CENTER", main, "CENTER", 0, 0)
            panel:SetSize(280, 300)
            panel:SetFrameLevel(140)
            panel:EnableMouse(true)
            panel:Hide()

            local heading = panel:CreateFontString(nil, "OVERLAY")
            heading:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
            heading:SetPoint("TOP", 0, -8)
            heading:SetTextColor(1, 1, 1)
            heading:SetText(L["导出价格"] or "导出价格")

            local scopeLabel = panel:CreateFontString(nil, "OVERLAY")
            scopeLabel:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
            scopeLabel:SetPoint("TOPLEFT", 10, -34)
            scopeLabel:SetTextColor(1, 1, 1)
            scopeLabel:SetText(L["导出范围"] or "导出范围")

            local scopeButton = BG.CreateButton(panel)
            scopeButton:SetPoint("LEFT", scopeLabel, "RIGHT", 6, 0)
            scopeButton:SetSize(100, 20)
            scopeButton:SetScript("OnClick", function()
                exportScope = (exportScope == "current") and "all" or "current"
                scopeButton:SetText(exportScope == "current" and (L["当前方案"] or "当前方案") or (L["全部方案"] or "全部方案"))
                local text = exportText()
                panel.edit:SetText(text ~= "" and text or (L["当前没有可导出的价格。"] or "当前没有可导出的价格。"))
                panel.edit:HighlightText()
            end)

            local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
            box:SetBackdrop({
                bgFile = "Interface/ChatFrame/ChatFrameBackground",
                edgeFile = "Interface/ChatFrame/ChatFrameBackground",
                edgeSize = 1,
            })
            box:SetBackdropColor(0, 0, 0, 0.8)
            box:SetBackdropBorderColor(1, 1, 1, 0.5)
            box:SetPoint("TOPLEFT", 8, -60)
            box:SetSize(264, 190)

            local scroll = CreateFrame("ScrollFrame", nil, box, BG.scrollTemplate)
            scroll:SetPoint("TOPLEFT", 5, -4)
            scroll:SetPoint("BOTTOMRIGHT", -27, 4)
            local edit = CreateFrame("EditBox", nil, scroll)
            edit:SetWidth(232)
            edit:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
            edit:SetMultiLine(true)
            edit:SetAutoFocus(false)
            edit:EnableMouse(true)
            edit:SetTextInsets(5, 5, 5, 10)
            scroll:SetScrollChild(edit)
            edit:SetScript("OnEscapePressed", function() panel:Hide() end)
            panel.edit, panel.scroll = edit, scroll

            local close = BG.CreateButton(panel)
            close:SetSize(110, 25)
            close:SetPoint("BOTTOMRIGHT", -8, 10)
            close:SetText(CANCEL or "取消")
            close:SetScript("OnClick", function() panel:Hide() end)

            panel.scopeLabel = scopeLabel
            panel.scopeButton = scopeButton
            return panel
        end

        function showExportPanel()
            if importPanel then importPanel:Hide() end
            if not exportPanel then exportPanel = createExportPanel() end
            exportPanel:SetShown(not exportPanel:IsShown())
            if not exportPanel:IsShown() then return end
            if pageState.mode == "leader" then
                exportScope = "current"
                exportPanel.scopeLabel:Show()
                exportPanel.scopeButton:Show()
                exportPanel.scopeButton:SetText(L["当前方案"] or "当前方案")
            else
                exportPanel.scopeLabel:Hide()
                exportPanel.scopeButton:Hide()
            end
            local text = exportText()
            exportPanel.edit:SetText(text ~= "" and text or (L["当前没有可导出的价格。"] or "当前没有可导出的价格。"))
            exportPanel.edit:HighlightText()
            exportPanel.edit:SetFocus()
        end

        local function createImportPanel()
            local panel = CreateFrame("Frame", nil, main, "BackdropTemplate")
            panel:SetBackdrop({
                bgFile = "Interface/ChatFrame/ChatFrameBackground",
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                edgeSize = 10,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            panel:SetBackdropColor(0, 0, 0, 0.8)
            panel:SetPoint("CENTER", main, "CENTER", 0, 0)
            panel:SetSize(280, 340)
            panel:SetFrameLevel(140)
            panel:EnableMouse(true)
            panel:Hide()

            local heading = panel:CreateFontString(nil, "OVERLAY")
            heading:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
            heading:SetPoint("TOP", 0, -8)
            heading:SetTextColor(1, 1, 1)
            heading:SetText(L["导入价格"] or "导入价格")

            local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
            box:SetBackdrop({
                bgFile = "Interface/ChatFrame/ChatFrameBackground",
                edgeFile = "Interface/ChatFrame/ChatFrameBackground",
                edgeSize = 1,
            })
            box:SetBackdropColor(0, 0, 0, 0.8)
            box:SetBackdropBorderColor(1, 1, 1, 0.5)
            box:SetPoint("TOPLEFT", 8, -28)
            box:SetSize(264, 190)

            local scroll = CreateFrame("ScrollFrame", nil, box, BG.scrollTemplate)
            scroll:SetPoint("TOPLEFT", 5, -4)
            scroll:SetPoint("BOTTOMRIGHT", -27, 4)
            local edit = CreateFrame("EditBox", nil, scroll)
            edit:SetWidth(232)
            edit:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
            edit:SetMultiLine(true)
            edit:SetAutoFocus(false)
            edit:EnableMouse(true)
            edit:SetTextInsets(5, 5, 5, 10)
            scroll:SetScrollChild(edit)
            edit:SetScript("OnEscapePressed", function() panel:Hide() end)
            edit:SetScript("OnTextChanged", function() refreshImportPreview(panel) end)
            panel.edit, panel.scroll = edit, scroll

            local summary = panel:CreateFontString(nil, "OVERLAY")
            summary:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
            summary:SetPoint("TOPLEFT", 8, -224)
            summary:SetTextColor(0.6, 1, 0.6)
            summary:SetWidth(264)
            panel.summary = summary

            local modeLabel = panel:CreateFontString(nil, "OVERLAY")
            modeLabel:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
            modeLabel:SetPoint("TOPLEFT", 8, -250)
            modeLabel:SetTextColor(1, 1, 1)
            modeLabel:SetText(L["导入方式"] or "导入方式")

            local mode1 = BG.CreateButton(panel)
            mode1:SetPoint("LEFT", modeLabel, "RIGHT", 6, 0)
            mode1:SetSize(70, 20)
            local mode2 = BG.CreateButton(panel)
            mode2:SetPoint("LEFT", mode1, "RIGHT", 4, 0)
            mode2:SetSize(70, 20)
            panel.modeButtons = { mode1, mode2 }
            panel.mode = nil

            local function chooseMode(self)
                panel.mode = self.modeKey
                refreshImportPreview(panel)
            end
            mode1:SetScript("OnClick", chooseMode)
            mode2:SetScript("OnClick", chooseMode)

            local commit = BG.CreateButton(panel)
            commit:SetSize(110, 25)
            commit:SetPoint("BOTTOMLEFT", 8, 10)
            commit:SetText(L["导入"] or "导入")
            commit:SetScript("OnClick", function() applyImport(panel) end)
            panel.commit = commit

            local cancel = BG.CreateButton(panel)
            cancel:SetSize(110, 25)
            cancel:SetPoint("BOTTOMRIGHT", -8, 10)
            cancel:SetText(CANCEL or "取消")
            cancel:SetScript("OnClick", function() panel:Hide() end)

            return panel
        end

        -- Recomputes the parse preview and enables the commit button only once the
        -- preview is valid and an import mode has been explicitly chosen. The
        -- "replace" mode is confirmed separately at commit time.
        function refreshImportPreview(panel)
            local parseOptions
            if pageState.mode == "leader" then
                local root, family = context(pageState.raidId)
                local raid = root and family and Store.ensureLeaderRaid(root, family, pageState.raidId, globalMoney())
                local preset = raid and raid.presets and raid.presets[raid.activePresetId]
                parseOptions = {
                    clientFamily = family,
                    raidId = pageState.raidId,
                    defaultBasePrice = preset and preset.basePrice or globalMoney(),
                    decodeBase64 = ns.Decode,
                    isBase64 = ns.IsBase64,
                }
            end
            local preview = Codec.parse(panel.edit:GetText(), pageState.mode, knownItems, parseOptions)
            panel.preview = preview
            if not preview.ok then
                panel.summary:SetText((L["无法导入："] or "无法导入：") .. tostring(preview.reason or "未知错误"))
                panel.summary:SetTextColor(1, 0.4, 0.4)
            else
                local typeLabel = preview.type == "leader" and (L["团长起拍价"] or "团长起拍价") or (L["我的心理价"] or "我的心理价")
                local parts = { typeLabel }
                if preview.type == "leader" then
                    parts[#parts + 1] = (L["方案"] or "方案") .. " " .. tostring(preview.presetCount)
                    parts[#parts + 1] = (L["装备"] or "装备") .. " " .. tostring(preview.itemCount)
                    if preview.sourceFormat == "bglite-legacy" then
                        parts[#parts + 1] = L["旧版价格字符串"] or "旧版价格字符串"
                    end
                else
                    parts[#parts + 1] = (L["装备"] or "装备") .. " " .. tostring(preview.itemCount)
                end
                if next(preview.unknownItems or {}) ~= nil then
                    parts[#parts + 1] = (L["未知装备将被跳过"] or "未知装备将被跳过")
                end
                panel.summary:SetText(table.concat(parts, "  "))
                panel.summary:SetTextColor(0.6, 1, 0.6)
            end
            panel.choiceIsExplicit = preview.ok and panel.mode ~= nil
            panel.commit:SetEnabled(panel.preview.ok and panel.choiceIsExplicit)
        end

        -- Applies a validated preview. Leader imports map the UI "replace" onto
        -- the codec's "replace-all"; personal imports pass merge/replace straight
        -- through. Either "replace" is destructive, so it asks for confirmation.
        function applyImport(panel)
            local preview = panel.preview
            if not preview or preview.ok ~= true or not panel.mode then return end
            local root, family, realmId, player = context(pageState.raidId)
            if not root or not family then
                localMessage(L["导入失败：角色信息不可用。"] or "导入失败：角色信息不可用。")
                return
            end
            local replace = (panel.mode == "replace")
            local codecMode = panel.mode
            local apply
            if pageState.mode == "leader" then
                if panel.mode == "replace" then codecMode = "replace-all" end
                apply = function()
                    return Codec.applyLeader(root, preview, {
                        mode = codecMode,
                        clientFamily = family,
                        raidId = pageState.raidId,
                    })
                end
            else
                apply = function()
                    return Codec.applyPersonal(root, { clientFamily = family, realmId = realmId, player = player, raidId = pageState.raidId }, preview, { mode = codecMode })
                end
            end

            local function commit()
                if apply() then
                    localMessage(L["导入成功。"] or "导入成功。")
                    panel:Hide()
                    refreshAll()
                else
                    localMessage(L["导入失败。"] or "导入失败。")
                end
            end

            if replace then
                local popupName = "BGNEXT_REPLACE_AUCTION_PRICES"
                StaticPopupDialogs[popupName] = StaticPopupDialogs[popupName] or {
                    button1 = YES or "是",
                    button2 = NO or "否",
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                }
                StaticPopupDialogs[popupName].text = L["替换将覆盖当前已保存的价格，确定继续？"] or "替换将覆盖当前已保存的价格，确定继续？"
                StaticPopupDialogs[popupName].OnAccept = commit
                StaticPopup_Show(popupName)
            else
                commit()
            end
        end

        function showImportPanel()
            if exportPanel then exportPanel:Hide() end
            if not importPanel then importPanel = createImportPanel() end
            importPanel:SetShown(not importPanel:IsShown())
            if not importPanel:IsShown() then return end
            importPanel.edit:SetText("")
            importPanel.mode = nil
            local keys = M.IMPORT_MODES[pageState.mode] or {}
            local labels
            if pageState.mode == "leader" then
                labels = { (L["新建方案"] or "新建方案"), (L["替换全部"] or "替换全部") }
            else
                labels = { (L["合并"] or "合并"), (L["替换"] or "替换") }
            end
            for i = 1, 2 do
                local button = importPanel.modeButtons[i]
                button.modeKey = keys[i]
                button:SetText(labels[i])
                fitButtonToText(button, 70, 86, 14)
            end
            refreshImportPreview(importPanel)
            importPanel.edit:SetFocus()
        end

        -- ---- Wire scripts now that every function is defined ----
        leaderButton:SetScript("OnClick", function()
            M.setMode(pageState, "leader")
            refreshAll()
        end)
        personalButton:SetScript("OnClick", function()
            M.setMode(pageState, "personal")
            refreshAll()
        end)
        presetButton:SetScript("OnClick", function() cyclePreset(1) end)
        newButton:SetScript("OnClick", newScheme)
        copyButton:SetScript("OnClick", copyScheme)
        renameButton:SetScript("OnClick", renameScheme)
        deleteButton:SetScript("OnClick", deleteScheme)
        clearPersonalButton:SetScript("OnClick", confirmClearPersonal)
        importButton:SetScript("OnClick", showImportPanel)
        exportButton:SetScript("OnClick", showExportPanel)
        importPersonalButton:SetScript("OnClick", showImportPanel)
        exportPersonalButton:SetScript("OnClick", showExportPanel)
        local function saveBasePrice(self)
            local money = tonumber(self:GetText())
            if not money or money % 1 ~= 0 or money < 0 or money > Store.MAX_MONEY then
                refreshToolbar()
                return false
            end
            local presetId = activePresetId(pageState.raidId)
            if not presetId then return false end
            local root, family = context(pageState.raidId)
            if not Store.setBasePrice(root, family, pageState.raidId, presetId, money) then return false end
            refreshToolbar()
            refreshRows()
            return true
        end
        basePriceEdit:SetScript("OnEnterPressed", function(self)
            if saveBasePrice(self) then self:ClearFocus() end
        end)
        basePriceEdit:SetScript("OnEditFocusLost", saveBasePrice)
        searchBox:SetScript("OnTextChanged", function(self)
            if self._refreshing then return end
            M.setFilter(pageState, "text", self:GetText())
            refreshRows()
            refreshBossBar()
        end)
        stateButton:SetScript("OnClick", function()
            local s = pageState.filters.state
            if s == nil or s == "all" then M.setFilter(pageState, "state", "set")
            elseif s == "set" then M.setFilter(pageState, "state", "unset")
            else M.setFilter(pageState, "state", nil) end
            refreshFilterBar()
            refreshRows()
        end)
        clearFiltersButton:SetScript("OnClick", function()
            M.clearFilters(pageState)
            refreshFilterBar()
            refreshBossBar()
            refreshRows()
        end)

        main.itemSlider:SetScript("OnValueChanged", function(self, value)
            if self._refreshing then return end
            pageState.itemOffset = math.floor((tonumber(value) or 0) + 0.5)
            refreshRows()
        end)
        main.itemScroll:SetScript("OnMouseWheel", function(_, delta)
            local offset = tonumber(pageState.itemOffset) or 0
            main.itemSlider:SetValue(offset - (tonumber(delta) or 0) * 3)
        end)

        for i = 1, pageCapacity do
            local row = main.rows[i]
            row.edit:SetScript("OnTextChanged", function(self)
                if self:GetParent().edit._refreshing then return end
                validateEdit(self:GetParent())
            end)
            row.edit:SetScript("OnEnterPressed", function(self)
                local r = self:GetParent()
                if validateEdit(r) and saveEdit(r) then
                    refreshToolbar()
                    local items = filteredItems()
                    local next = M.nextVisibleIndex(items, r.absoluteIndex)
                    if next then
                        local offset = tonumber(pageState.itemOffset) or 0
                        if next <= offset or next > offset + pageCapacity then
                            pageState.itemOffset = next - 1
                        end
                        refreshRows()
                        local visibleIndex = next - pageState.itemOffset
                        if main.rows[visibleIndex] then main.rows[visibleIndex].edit:SetFocus() end
                    else
                        self:ClearFocus()
                    end
                end
            end)
            row.edit:SetScript("OnEditFocusLost", function(self)
                if self._discardOnBlur then
                    self._discardOnBlur = nil
                    refreshRows()
                    return
                end
                local r = self:GetParent()
                if validateEdit(r) and saveEdit(r) then
                    refreshToolbar()
                    refreshRows()
                end
            end)
            row.edit:SetScript("OnEscapePressed", function(self)
                self._discardOnBlur = true
                self:ClearFocus()
            end)
            row.clear:SetScript("OnClick", function(self) clearRow(self:GetParent()) end)
        end

        BG.Create_TabButton(M.tabNumber, L["价格预设"], main)
        main:SetScript("OnShow", function()
            -- This page owns a compact raid selector because changing raids
            -- also resets its local boss/search state. Hide the global ledger
            -- selector while the page is visible so the two bars never overlap.
            if BG.TabButtonsFB then BG.TabButtonsFB:Hide() end
            relayout()
            refreshAll()
        end)
        main:SetScript("OnHide", function()
            if BG.TabButtonsFB then BG.TabButtonsFB:Show() end
        end)
        -- The main frame animates between table heights and responds to UI scale
        -- and locale-driven description height changes; re-derive the viewport
        -- from the actual content area instead of a one-time estimate.
        main:SetScript("OnSizeChanged", function()
            if main:IsShown() then relayout() end
        end)
        relayout()
        refreshAll()
    end)
end

BG.BGNext.AuctionPriceUI = M
return M
