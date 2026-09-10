-- BGNext role-overview column settings.
--
-- Stores which columns the user hid, scoped per client family, so hiding
-- "熔火之心" on the anniversary client leaves the retail or MoP layout alone.
--
-- Only booleans are stored, and only for columns the catalog declares. Hiding
-- a column changes the projection and the window size; it never deletes a
-- stored character snapshot.

local AddonName, ns = ...
local L = ns and ns.L or setmetatable({}, { __index = function(_, key) return tostring(key) end })

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

local SECTIONS = { raid = "raidColumns", resource = "resourceColumns" }

local function isFamily(family)
    return type(family) == "string" and family ~= ""
end

local function store(root, create)
    if type(root) ~= "table" then return nil end
    local existing = root.roleOverviewColumns
    if type(existing) ~= "table" then
        if not create then return nil end
        existing = {}
        root.roleOverviewColumns = existing
    end
    return existing
end

local function familyStore(root, family, create)
    if not isFamily(family) then return nil end
    local columns = store(root, create)
    if not columns then return nil end
    local entry = columns[family]
    if type(entry) ~= "table" then
        if not create then return nil end
        entry = { raid = {}, resource = {} }
        columns[family] = entry
    end
    entry.raid = type(entry.raid) == "table" and entry.raid or {}
    entry.resource = type(entry.resource) == "table" and entry.resource or {}
    return entry
end

-- Creates the per-family override table. Defaults are not written out: an
-- absent override means "use the catalog default", so a later catalog change
-- is picked up instead of being frozen into the save.
function M.ensure(root, family, catalog)
    if type(catalog) ~= "table" then return nil end
    return familyStore(root, family, true)
end

function M.isVisible(root, family, section, columnId, catalog)
    local sectionKey = SECTIONS[section]
    if not sectionKey or type(catalog) ~= "table" then return false end

    local declared
    for _, column in ipairs(catalog[sectionKey] or {}) do
        if column.id == columnId then declared = column break end
    end
    if not declared then return false end

    -- Read the override with explicit branches: `a and b or nil` would turn a
    -- stored `false` back into nil and silently re-show a hidden column.
    local entry = familyStore(root, family, false)
    if entry then
        local overrides = entry[section]
        if type(overrides) == "table" then
            local override = overrides[columnId]
            if type(override) == "boolean" then return override end
        end
    end
    return declared.defaultVisible == true
end

function M.setVisible(root, family, section, columnId, visible)
    if not SECTIONS[section] or type(columnId) ~= "string" then return end
    if type(visible) ~= "boolean" then return end
    local entry = familyStore(root, family, true)
    if not entry then return end
    entry[section][columnId] = visible
end

-- Clears this family's overrides only, restoring catalog defaults without
-- touching another client's layout or any character snapshot.
function M.resetFamily(root, family)
    local columns = store(root, false)
    if not columns or not isFamily(family) then return end
    columns[family] = nil
end

-- Returns the override table in the shape the projection expects.
function M.visibilityFor(root, family)
    local entry = familyStore(root, family, false)
    local visibility = { raid = {}, resource = {} }
    if not entry then return visibility end
    for section in pairs(SECTIONS) do
        for columnId, value in pairs(entry[section] or {}) do
            if type(value) == "boolean" and type(columnId) == "string" then
                visibility[section][columnId] = value
            end
        end
    end
    return visibility
end

-- Returns a predicate saying whether this client can actually read a column.
-- Both the settings page and the projection use it, so a field with no
-- verified reader is neither offered as a checkbox nor rendered with a guess.
function M.availableColumns(family, catalog, api)
    local adapters = BG.BGNext.OwnCharactersAdapters
    api = api or _G

    local index = {}
    for section, sectionKey in pairs(SECTIONS) do
        index[section] = {}
        if type(catalog) == "table" then
            for _, column in ipairs(catalog[sectionKey] or {}) do
                index[section][column.id] = column
            end
        end
    end

    return function(section, columnId)
        local column = index[section] and index[section][columnId] or nil
        if not column then return false end

        return adapters ~= nil and adapters.canReadColumn(family, api, column) == true
    end
end

-- Resolves the label shown for a column. Raid columns prefer Blizzard's own
-- localized zone name so BGNext does not ship a hand-written raid name where
-- the client can supply the real one.
function M.columnLabel(column)
    if type(column) ~= "table" then return "" end
    if column.zoneId and type(GetRealZoneText) == "function" then
        local zoneName = GetRealZoneText(column.zoneId)
        if type(zoneName) == "string" and zoneName ~= "" then return zoneName end
    end
    return L[column.title or ""]
end

local PANEL_SECTIONS = {
    { section = "raid", key = "raidColumns", title = "团本完成列" },
    { section = "resource", key = "resourceColumns", title = "货币与资源列" },
}

-- The confirmation text for a destructive clear, naming the exact scope so a
-- user never wipes another client's records by surprise.
function M.clearDialogText(kind)
    if kind == "family" then
        return L["确认清空当前版本的角色数据？此操作不可撤销。"]
    end
    return L["确认清空全部版本的角色数据？此操作不可撤销。"]
end

function M.characterOrderRows(root, family, model)
    local snapshots = type(model) == "table" and type(model.listOrdered) == "function"
        and model.listOrdered(root, family) or {}
    local counts, rows = {}, {}
    for _, snapshot in ipairs(snapshots) do
        if type(snapshot) == "table" and type(snapshot.realmId) == "number"
            and type(snapshot.player) == "string" and snapshot.player ~= "" then
            counts[snapshot.player] = (counts[snapshot.player] or 0) + 1
        end
    end
    for index, snapshot in ipairs(snapshots) do
        if type(snapshot) == "table" and type(snapshot.realmId) == "number"
            and type(snapshot.player) == "string" and snapshot.player ~= "" then
            local realm = type(snapshot.realmName) == "string" and snapshot.realmName ~= ""
                and snapshot.realmName or tostring(snapshot.realmId)
            rows[#rows + 1] = {
                realmId = snapshot.realmId, player = snapshot.player,
                label = counts[snapshot.player] > 1 and (realm .. "-" .. snapshot.player) or snapshot.player,
                canMoveUp = index > 1, canMoveDown = index < #snapshots,
            }
        end
    end
    return rows
end

function M.characterOrderLayout(rowCount, orderTop)
    local count = math.max(tonumber(rowCount) or 0, 1)
    local top = tonumber(orderTop) or 0
    local restoreY = top - count * 26 - 4
    local lowerY = restoreY - 41
    return { restoreY = restoreY, lowerY = lowerY, height = math.abs(lowerY) + 160 }
end

-- Shows the confirmation dialog and, on accept, runs the matching clear on the
-- runtime. The runtime's clear functions are already tested; this is only the
-- in-game confirmation wrapper.
function M.confirmClear(kind, family)
    if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then return end
    local dialogName = kind == "family" and "BGNextRoleOverviewClearFamily" or "BGNextRoleOverviewClearAll"
    StaticPopupDialogs[dialogName] = {
        text = M.clearDialogText(kind),
        button1 = L["清空"],
        button2 = L["取消"],
        OnAccept = function()
            local runtime = BG.BGNext and BG.BGNext.OwnCharactersRuntime
            if not runtime then return end
            if kind == "family" then
                if type(runtime.clearFamily) == "function" then runtime.clearFamily(nil, family) end
            else
                if type(runtime.clearAll) == "function" then runtime.clearAll(nil) end
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show(dialogName)
end

function M.Open(section)
    M.requestedSection = section == "resource" and "resource" or "raid"
    if type(BG.OpenOption) == "function" then BG.OpenOption() end
    if BG.ButtonOptions_roleOverview and type(BG.ButtonOptions_roleOverview.Click) == "function" then
        BG.ButtonOptions_roleOverview:Click()
        return true
    end
    return false
end

-- Builds the "角色总览" settings page. The available columns differ per client
-- family, so the page is generated from the catalog rather than hard-coded.
-- Runs only inside the game; the pure helpers above stay testable without it.
function M.BuildPanel(parent)
    if type(parent) ~= "table" then return end
    if type(CreateFrame) ~= "function" or type(BG.Init2) ~= "function" then return end

    BG.Init2(function()
        local adapters = BG.BGNext.OwnCharactersAdapters
        local catalogs = BG.BGNext.OwnCharactersCatalog
        if not adapters or not catalogs then return end

        local family = adapters.detect(BG)
        local catalog = family and catalogs.forFamily(family) or nil
        if not catalog then return end

        local root = BG.BGNext.DB
        local Model = BG.BGNext.OwnCharacters
        local isAvailable = M.availableColumns(family, catalog)
        local y = -10

        local function refresh()
            if BG.BGNext.OwnCharactersUI and BG.BGNext.OwnCharactersUI.Refresh then
                BG.BGNext.OwnCharactersUI.Refresh()
            end
        end

        for _, group in ipairs(PANEL_SECTIONS) do
            local heading = parent:CreateFontString(nil, "ARTWORK")
            heading:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
            heading:SetPoint("TOPLEFT", parent, 15, y)
            heading:SetText(BG.STC_g1(L[group.title]))
            y = y - 25

            for _, column in ipairs(catalog[group.key] or {}) do
                if isAvailable(group.section, column.id) then
                    local check = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
                    check:SetSize(30, 30)
                    check:SetPoint("TOPLEFT", parent, 20, y)
                    check.Text:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                    check.Text:SetText(M.columnLabel(column))
                    check.Text:SetWordWrap(false)
                    check.Text:SetWidth(min(check.Text:GetStringWidth() + 20, 220))
                    check:SetHitRectInsets(0, -check.Text:GetWidth(), 0, 0)
                    check:SetChecked(M.isVisible(root, family, group.section, column.id, catalog))
                    check:SetScript("OnClick", function(self)
                        M.setVisible(root, family, group.section, column.id, self:GetChecked() and true or false)
                        refresh()
                        if BG.PlaySound then BG.PlaySound(1) end
                    end)
                    check:SetScript("OnShow", function(self)
                        self:SetChecked(M.isVisible(root, family, group.section, column.id, catalog))
                    end)
                    y = y - 26
                end
            end
            y = y - 12
        end

        -- Restores catalog defaults for this client only. It clears display
        -- preferences; no character snapshot is touched.
        local reset = BG.CreateButton(parent)
        reset:SetSize(190, 25)
        reset:SetPoint("TOPLEFT", parent, 20, y)
        reset:SetText(L["恢复当前版本默认列"])
        reset:SetScript("OnClick", function()
            M.resetFamily(root, family)
            refresh()
            if BG.PlaySound then BG.PlaySound(1) end
            if parent.Hide and parent.Show then
                parent:Hide()
                parent:Show()
            end
        end)

        y = y - 40

        local orderHeading = parent:CreateFontString(nil, "ARTWORK")
        orderHeading:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
        orderHeading:SetPoint("TOPLEFT", parent, 15, y)
        orderHeading:SetText(BG.STC_g1(L["角色顺序"]))
        y = y - 25
        local orderTop, orderControls = y, {}
        local layoutLowerControls
        local emptyOrder = parent:CreateFontString(nil, "ARTWORK")
        emptyOrder:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
        emptyOrder:SetPoint("TOPLEFT", parent, 20, orderTop)
        emptyOrder:SetText(L["暂无角色数据"])
        local restoreOrder = BG.CreateButton(parent)
        restoreOrder:SetSize(190, 25)
        local function rebuildOrderRows()
            local rows = M.characterOrderRows(root, family, Model)
            for _, control in ipairs(orderControls) do control.label:Hide(); control.up:Hide(); control.down:Hide() end
            emptyOrder:SetShown(#rows == 0)
            for index, row in ipairs(rows) do
                local control = orderControls[index]
                if not control then
                    control = { label = parent:CreateFontString(nil, "ARTWORK"), up = BG.CreateButton(parent), down = BG.CreateButton(parent) }
                    control.label:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
                    control.up:SetSize(70, 22); control.down:SetSize(70, 22)
                    orderControls[index] = control
                end
                local rowY = orderTop - (index - 1) * 26
                control.label:ClearAllPoints(); control.label:SetPoint("TOPLEFT", parent, 20, rowY); control.label:SetText(row.label)
                control.up:ClearAllPoints(); control.up:SetPoint("TOPLEFT", parent, 180, rowY + 3)
                control.down:ClearAllPoints(); control.down:SetPoint("LEFT", control.up, "RIGHT", 5, 0)
                control.up:SetText(L["上移"]); control.down:SetText(L["下移"])
                control.up:SetEnabled(row.canMoveUp); control.down:SetEnabled(row.canMoveDown)
                control.up:SetScript("OnClick", function()
                    if Model and Model.moveCharacter(root, family, row.realmId, row.player, -1) then rebuildOrderRows(); refresh(); if BG.PlaySound then BG.PlaySound(1) end end
                end)
                control.down:SetScript("OnClick", function()
                    if Model and Model.moveCharacter(root, family, row.realmId, row.player, 1) then rebuildOrderRows(); refresh(); if BG.PlaySound then BG.PlaySound(1) end end
                end)
                control.label:Show(); control.up:Show(); control.down:Show()
            end
            local layout = M.characterOrderLayout(#rows, orderTop)
            restoreOrder:ClearAllPoints(); restoreOrder:SetPoint("TOPLEFT", parent, 20, layout.restoreY)
            restoreOrder:SetShown(#rows > 0)
            if layoutLowerControls then layoutLowerControls(layout) end
        end
        restoreOrder:SetText(L["恢复默认排序"])
        restoreOrder:SetScript("OnClick", function()
            if Model and Model.resetCharacterOrder(root, family) then rebuildOrderRows(); refresh(); if BG.PlaySound then BG.PlaySound(1) end end
        end)
        rebuildOrderRows()
        if type(parent.HookScript) == "function" then parent:HookScript("OnShow", rebuildOrderRows) end
        y = M.characterOrderLayout(#M.characterOrderRows(root, family, Model), orderTop).lowerY

        -- Disabling the module stops collection and refresh; no data is
        -- deleted, and re-checking restores collection.
        local runtime = BG.BGNext and BG.BGNext.OwnCharactersRuntime
        local enabledCheck = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
        enabledCheck:SetSize(30, 30)
        enabledCheck:SetPoint("TOPLEFT", parent, 20, y)
        enabledCheck.Text:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
        enabledCheck.Text:SetText(L["启用角色总览"])
        enabledCheck.Text:SetWordWrap(false)
        enabledCheck.Text:SetWidth(160)
        enabledCheck:SetHitRectInsets(0, -enabledCheck.Text:GetWidth(), 0, 0)
        local function updateEnabled()
            if runtime and type(runtime.isEnabled) == "function" then
                enabledCheck:SetChecked(runtime.isEnabled())
            end
        end
        updateEnabled()
        enabledCheck:SetScript("OnClick", function(self)
            if runtime and type(runtime.setEnabled) == "function" then
                runtime.setEnabled(nil, self:GetChecked() and true or false)
                refresh()
            end
        end)
        enabledCheck:SetScript("OnShow", updateEnabled)
        y = y - 40

        -- Clear this client's character data only, then every client's, each
        -- behind its own confirmation dialog.
        local clearFamily = BG.CreateButton(parent)
        clearFamily:SetSize(200, 25)
        clearFamily:SetPoint("TOPLEFT", parent, 20, y)
        clearFamily:SetText(L["清空当前版本角色数据"])
        clearFamily:SetScript("OnClick", function() M.confirmClear("family", family) end)
        y = y - 30

        local clearAll = BG.CreateButton(parent)
        clearAll:SetSize(200, 25)
        clearAll:SetPoint("TOPLEFT", parent, 20, y)
        clearAll:SetText(L["清空全部角色数据"])
        clearAll:SetScript("OnClick", function() M.confirmClear("all", nil) end)
        y = y - 30

        layoutLowerControls = function(layout)
            enabledCheck:ClearAllPoints(); enabledCheck:SetPoint("TOPLEFT", parent, 20, layout.lowerY)
            clearFamily:ClearAllPoints(); clearFamily:SetPoint("TOPLEFT", parent, 20, layout.lowerY - 40)
            clearAll:ClearAllPoints(); clearAll:SetPoint("TOPLEFT", parent, 20, layout.lowerY - 70)
            parent:SetSize(400, layout.height)
        end
        layoutLowerControls(M.characterOrderLayout(#M.characterOrderRows(root, family, Model), orderTop))

    end)
end

BG.BGNext.RoleOverviewSettings = M
return M
