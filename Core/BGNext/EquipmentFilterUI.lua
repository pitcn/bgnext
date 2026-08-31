local AddonName, ns = ...
local L = ns.L
local LibBG = ns.LibBG

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}
local shortcutButtons = {}
local chooserButtons = {}
local ruleButtons = {}
local sectionTitles = {}
local openProfileMenu
local updateRuleButtons

local sectionOrder = {
    { key = "weapon", title = "武器类型过滤" },
    { key = "armor", title = "护甲类型过滤" },
    { key = "affix", title = "装备词缀过滤" },
    { key = "classRestriction", title = "职业限定过滤", boolean = true },
    { key = "ignoreBattleNetBound", title = "忽略战网绑定", boolean = true },
    { key = "tankOnly", title = "坦克专属过滤", boolean = true },
    { key = "primaryStat", title = "主属性" },
}

local function state()
    local root = BG.BGNext.DB
    local realmId = BG.realmID or GetRealmID()
    local player = BG.playerName
    local byRealm = root and root.equipmentFilters and root.equipmentFilters[realmId]
    return byRealm and byRealm[player]
end

local function activeProfile()
    local current = state()
    return current and current.selectedId and current.profiles[current.selectedId], current
end

local function play()
    if BG.PlaySound then BG.PlaySound(1) end
end

local function refreshItems()
    if BG.UpdateAllFilter then BG.UpdateAllFilter() end
end

local function hideButtons(buttons)
    for _, button in ipairs(buttons) do button:Hide() end
end

local function setProfileButton(button, profile, selected)
    button.profileId = profile.id
    button.icon:SetTexture(profile.icon or 134400)
    button.icon:SetDesaturated(not selected)
    button.selected:SetShown(selected)
    button:Show()
end

-- Resolves the current character's specialization to its built-in key plus a
-- player-visible name and icon, or nil when the family/class is unknown or the
-- specialization is unrecorded. Reads only the current character.
local function resolveFollowTarget()
    local adapter = BG.BGNext.SpecializationAdapter
    local catalog = BG.BGNext.EquipmentFilterSpecializations
    if not (adapter and catalog) then return nil end
    local family = adapter.detect()
    if not family then return nil end
    local _, classToken = UnitClass("player")
    if not classToken then return nil end
    local resolved = adapter.resolve(family, _G, classToken)
    if not resolved or not resolved.specKey then return nil end
    local profile = catalog.getDefault(family, classToken, resolved.specKey)
    if not profile then return nil end
    return {
        builtInId = profile.builtInKey,
        name = resolved.name or profile.name,
        icon = resolved.icon or profile.icon,
    }
end

-- Rebuilds the specialization defaults for the current character and returns them
-- with the resolved built-in id (or the class fallback when the specialization is
-- unknown). Mirrors the runtime's initial setup for the reset button.
local function buildDefaults()
    local adapter = BG.BGNext.SpecializationAdapter
    local catalog = BG.BGNext.EquipmentFilterSpecializations
    local profiles = BG.BGNext.EquipmentFilterProfiles
    local runtime = BG.BGNext.EquipmentFilterRuntime
    local family = adapter and adapter.detect()
    local _, classToken = UnitClass("player")
    if runtime and runtime.buildDefaults then
        return runtime.buildDefaults(adapter, catalog, profiles, family, classToken, _G)
    end
    return {}, nil
end

local function createProfileButton(parent, index, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(25, 25)
    if index == 1 then
        if parent.followButton then
            button:SetPoint("LEFT", parent.followButton, "RIGHT", 10, 0)
        else
            button:SetPoint("LEFT", 0, 0)
        end
    else
        button:SetPoint("LEFT", parent.buttons[index - 1], "RIGHT", 10, 0)
    end
    local selected = button:CreateTexture(nil, "BACKGROUND")
    selected:SetSize(40, 40)
    selected:SetPoint("CENTER")
    selected:SetTexture("Interface/ChatFrame/UI-ChatIcon-BlinkHilight")
    button.selected = selected
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    button.icon = icon
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(23, 23)
    highlight:SetPoint("CENTER")
    highlight:SetColorTexture(1, 1, 1, .2)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self)
        local current = state()
        local profile = current and current.profiles[self.profileId]
        if not profile then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine(L["使用装备过滤方案："] .. profile.name, 1, .82, 0)
        GameTooltip:AddLine(L["右键修改方案"], 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    parent.buttons[index] = button
    return button
end

local function updateProfileRows()
    local current = state()
    if not current then return end
    hideButtons(shortcutButtons)
    hideButtons(chooserButtons)
    local target = resolveFollowTarget()
    local following = current.selectionMode == "follow-spec"
    local followTexture = (target and target.icon) or "Interface/Icons/INV_Misc_QuestionMark"
    for _, rowFrame in ipairs({ BG.EquipmentFilterShortcutFrame, BG.FilterClassItemMainFrame.ProfileRow }) do
        local followButton = rowFrame.followButton
        if not followButton then
            followButton = CreateFrame("Button", nil, rowFrame)
            followButton:SetSize(25, 25)
            followButton:SetPoint("LEFT", 0, 0)
            followButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            local icon = followButton:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            followButton.icon = icon
            followButton:SetScript("OnClick", function()
                local target = resolveFollowTarget()
                if target then
                    local defaults = buildDefaults()
                    BG.BGNext.EquipmentFilter.followSpecialization(state(), target.builtInId, defaults)
                else
                    BG.BGNext.EquipmentFilter.followSpecialization(state(), nil)
                end
                updateProfileRows(); updateRuleButtons(); refreshItems(); play()
            end)
            followButton:SetScript("OnEnter", function(self)
                local resolved = resolveFollowTarget()
                GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
                if resolved and resolved.name then
                    GameTooltip:AddLine(L["跟随当前专精"] .. "：" .. resolved.name, 1, .82, 0)
                else
                    GameTooltip:AddLine(L["未识别当前专精，沿用当前方案"], 1, .82, 0)
                end
                GameTooltip:Show()
            end)
            followButton:SetScript("OnLeave", GameTooltip_Hide)
            rowFrame.followButton = followButton
        end
        followButton.icon:SetTexture(followTexture)
        followButton.icon:SetDesaturated(not following)
        followButton:Show()
    end
    for index, id in ipairs(current.order) do
        local profile = current.profiles[id]
        if profile then
            local shortcut = shortcutButtons[index]
            if not shortcut then
                shortcut = createProfileButton(BG.EquipmentFilterShortcutFrame, index, function(self, mouseButton)
                    if mouseButton == "RightButton" then
                        openProfileMenu(self)
                    else
                        BG.BGNext.EquipmentFilter.selectProfile(state(), self.profileId)
                        updateProfileRows()
                        refreshItems()
                    end
                    play()
                end)
                shortcutButtons[index] = shortcut
            end
            local chooser = chooserButtons[index]
            if not chooser then
                chooser = createProfileButton(BG.FilterClassItemMainFrame.ProfileRow, index, function(self, mouseButton)
                    if mouseButton == "RightButton" then
                        openProfileMenu(self)
                    else
                        BG.BGNext.EquipmentFilter.selectProfile(state(), self.profileId)
                        updateProfileRows()
                        refreshItems()
                    end
                    play()
                end)
                chooserButtons[index] = chooser
            end
            setProfileButton(shortcut, profile, current.selectedId == id)
            setProfileButton(chooser, profile, current.selectedId == id)
        end
    end
    local width = math.max(1, (#current.order + 1) * 35)
    BG.EquipmentFilterShortcutFrame:SetWidth(width)
    BG.FilterClassItemMainFrame.ProfileRow:SetWidth(width)
end

local function sortedRules(values)
    local result = {}
    for id, label in pairs(values or {}) do result[#result + 1] = { id = id, label = label } end
    table.sort(result, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return result
end

updateRuleButtons = function()
    local profile = activeProfile()
    for _, button in ipairs(ruleButtons) do button:Hide() end
    if not profile then return end
    local adapter = BG.BGNext.SpecializationAdapter
    local family = adapter and adapter.detect()
    local catalog = BG.BGNext.EquipmentFilterProfiles.getRuleCatalog({ family = family })
    local parent = BG.FilterClassItemMainFrame.RuleFrame
    local y = -5
    local used = 0
    for sectionIndex, section in ipairs(sectionOrder) do
        local title = sectionTitles[sectionIndex]
        if not title then
            title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            sectionTitles[sectionIndex] = title
        end
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", 10, y)
        title:SetText(L[section.title] or section.title)
        title:SetTextColor(section.key == "tankOnly" and .2 or 0, section.key == "tankOnly" and .65 or 1, 1)
        y = y - 22
        local values
        if section.boolean then
            values = { { id = section.key, label = L[section.title] or section.title } }
        else
            values = sortedRules(catalog[section.key])
        end
        for index, rule in ipairs(values) do
            used = used + 1
            local button = ruleButtons[used]
            if not button then
                button = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
                button:SetSize(24, 24)
                button.Text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                button.Text:SetPoint("LEFT", button, "RIGHT", 1, 0)
                button:SetScript("OnClick", function(self)
                    local selected = activeProfile()
                    if not selected then return end
                    if self.boolean then
                        selected[self.sectionKey] = self:GetChecked() and true or false
                    else
                        selected[self.sectionKey][self.ruleId] = self:GetChecked() and true or nil
                    end
                    refreshItems()
                    play()
                end)
                ruleButtons[used] = button
            end
            local column = (index - 1) % 5
            local row = math.floor((index - 1) / 5)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", 10 + column * 105, y - row * 24)
            button.sectionKey = section.key
            button.ruleId = rule.id
            button.boolean = section.boolean
            button.Text:SetText(rule.label)
            button:SetChecked(BG.BGNext.EquipmentFilter.isRuleSelected(profile, section.key, rule.id, section.boolean))
            button:Show()
        end
        y = y - (math.ceil(#values / 5) * 24) - 8
    end
end

local function showEdit(profileId)
    local frame = BG.FilterClassItemMainFrame.EditFrame
    local current = state()
    local profile = current and current.profiles[profileId]
    frame.profileId = profileId
    frame.Title:SetText(profile and (L["正在修改方案："] .. profile.name) or L["新建过滤方案"])
    frame.NameEdit:SetText(profile and profile.name or "")
    frame.selectedIcon = profile and profile.icon or 134400
    frame.Icon:SetTexture(frame.selectedIcon)
    for _, button in ipairs(frame.IconButtons or {}) do
        button.Selected:SetShown(button.iconPath == frame.selectedIcon)
    end
    frame:Show()
end

function BG.EquipmentFilterEditProfile(profileId)
    showEdit(profileId)
end

openProfileMenu = function(button)
    local current = state()
    local profile = current and current.profiles[button.profileId]
    if not profile then return end
    local orderMenu = { { isTitle = true, text = L["更改至第几位"], notCheckable = true } }
    local currentIndex
    for index, id in ipairs(current.order) do
        if id == button.profileId then currentIndex = index end
    end
    for target = 1, #current.order do
        orderMenu[#orderMenu + 1] = {
            text = tostring(target), notCheckable = true,
            func = function()
                if currentIndex then BG.BGNext.EquipmentFilter.moveProfile(current, button.profileId, target - currentIndex) end
                updateProfileRows(); refreshItems()
            end,
        }
    end
    local menu = {
        { isTitle = true, text = profile.name, notCheckable = true },
        { text = L["修改名称/图标"], notCheckable = true, func = function() showEdit(button.profileId) end },
        { text = L["更改顺序"], notCheckable = true, hasArrow = true, menuList = orderMenu },
        { isTitle = true, text = "   ", notCheckable = true },
        { text = L["删除方案"], notCheckable = true, func = function()
            BG.BGNext.EquipmentFilter.deleteProfile(current, button.profileId)
            updateProfileRows(); updateRuleButtons(); refreshItems()
        end },
        { isTitle = true, text = "   ", notCheckable = true },
        { text = CANCEL, notCheckable = true, func = function() LibBG:CloseDropDownMenus() end },
    }
    LibBG:EasyMenu(menu, BG.dropDown, button, 0, 0, "MENU", 3)
end

local function createUI()
    local main = CreateFrame("Frame", nil, BG.MainFrame, "BackdropTemplate")
    main:SetBackdrop({ bgFile = "Interface/ChatFrame/ChatFrameBackground", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 16, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    main:SetBackdropColor(0, 0, 0, 1)
    main:SetSize(560, 700)
    main:SetPoint("CENTER", BG.MainFrame, "CENTER", 100, 0)
    main:SetFrameLevel(290)
    main:EnableMouse(true)
    main:SetMovable(true)
    main:SetToplevel(true)
    main:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    main:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)
    main:SetScript("OnShow", function() updateProfileRows(); updateRuleButtons() end)
    main:Hide()
    BG.FilterClassItemMainFrame = main

    local title = main:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -7)
    title:SetText(L["< 装备过滤 >"])

    local profileRow = CreateFrame("Frame", nil, main)
    profileRow:SetPoint("TOP", 30, -40)
    profileRow:SetSize(1, 30)
    profileRow.buttons = chooserButtons
    main.ProfileRow = profileRow
    local chooseText = profileRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chooseText:SetPoint("RIGHT", profileRow, "LEFT", -10, 0)
    chooseText:SetText(L["选择方案："])

    local add = BG.CreateButton(main)
    add:SetSize(25, 25)
    add:SetPoint("LEFT", profileRow, "RIGHT", 0, 0)
    add:SetText("+")
    add:SetScript("OnClick", function() showEdit(nil); play() end)

    local reset = BG.CreateButton(main)
    reset:SetSize(60, 30)
    reset:SetPoint("TOPLEFT", 5, -40)
    reset:SetText(RESET)
    reset:SetScript("OnClick", function()
        local defaults, builtInId = buildDefaults()
        BG.BGNext.EquipmentFilter.resetDefaults(state(), defaults, builtInId)
        updateProfileRows(); updateRuleButtons(); refreshItems(); play()
    end)

    local close = BG.CreateButton(main)
    close:SetSize(130, 25)
    close:SetPoint("BOTTOMRIGHT", -10, 15)
    close:SetText(CLOSE)
    close:SetScript("OnClick", function() main:Hide(); play() end)

    local rules = CreateFrame("Frame", nil, main)
    rules:SetPoint("TOPLEFT", 5, -65)
    rules:SetPoint("BOTTOMRIGHT", -5, 45)
    main.RuleFrame = rules

    local edit = CreateFrame("Frame", nil, main, "BackdropTemplate")
    edit:SetBackdrop({ bgFile = "Interface/ChatFrame/ChatFrameBackground", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 16 })
    edit:SetBackdropColor(0, 0, 0, .98)
    edit:SetPoint("TOPLEFT", 10, -80)
    edit:SetPoint("BOTTOMRIGHT", -10, 45)
    edit:SetFrameLevel(300)
    edit:Hide()
    main.EditFrame = edit
    edit.Title = edit:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    edit.Title:SetPoint("TOP", 0, -15)
    local nameLabel = edit:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", 25, -45)
    nameLabel:SetText(L["名称："])
    edit.NameEdit = CreateFrame("EditBox", nil, edit, "InputBoxTemplate")
    edit.NameEdit:SetSize(150, 20)
    edit.NameEdit:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -5)
    edit.NameEdit:SetAutoFocus(false)
    edit.Icon = edit:CreateTexture(nil, "ARTWORK")
    edit.Icon:SetSize(40, 40)
    edit.Icon:SetPoint("LEFT", edit.NameEdit, "RIGHT", 25, 0)
    edit.IconButtons = {}
    local iconChoices = {
        134400, 132089, 132272, 132333, 132349,
        132355, 132485, 133733, 134153, 135846,
        "Interface/Icons/classicon_warrior", "Interface/Icons/classicon_paladin",
        "Interface/Icons/classicon_hunter", "Interface/Icons/classicon_rogue",
        "Interface/Icons/classicon_priest", "Interface/Icons/classicon_shaman",
        "Interface/Icons/classicon_mage", "Interface/Icons/classicon_warlock",
        "Interface/Icons/classicon_druid", "Interface/Icons/classicon_monk",
    }
    local iconLabel = edit:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    iconLabel:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -45)
    iconLabel:SetText(L["图标："])
    for index, iconPath in ipairs(iconChoices) do
        local button = CreateFrame("Button", nil, edit)
        button:SetSize(30, 30)
        local column = (index - 1) % 10
        local row = math.floor((index - 1) / 10)
        button:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", column * 45, -8 - row * 40)
        button.iconPath = iconPath
        local texture = button:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints()
        texture:SetTexture(iconPath)
        button:SetHighlightTexture("Interface/Buttons/ButtonHilight-Square", "ADD")
        local selected = button:CreateTexture(nil, "OVERLAY")
        selected:SetTexture("Interface/Buttons/CheckButtonHilight")
        selected:SetBlendMode("ADD")
        selected:SetAllPoints()
        selected:Hide()
        button.Selected = selected
        button:SetScript("OnClick", function(self)
            edit.selectedIcon = self.iconPath
            edit.Icon:SetTexture(self.iconPath)
            for _, other in ipairs(edit.IconButtons) do other.Selected:SetShown(other == self) end
            play()
        end)
        edit.IconButtons[index] = button
    end
    local confirm = BG.CreateButton(edit)
    confirm:SetSize(120, 25)
    confirm:SetPoint("BOTTOMLEFT", 25, 20)
    confirm:SetText(L["确定"])
    confirm:SetScript("OnClick", function()
        local current = state()
        if edit.profileId then
            BG.BGNext.EquipmentFilter.updateProfile(current, edit.profileId, { name = edit.NameEdit:GetText(), icon = edit.selectedIcon })
        else
            local active = activeProfile()
            local _, id = BG.BGNext.EquipmentFilter.createProfile(current, {
                name = edit.NameEdit:GetText(),
                icon = edit.selectedIcon or 134400,
                weapon = (active and active.weapon) or {},
                armor = (active and active.armor) or {},
                affix = (active and active.affix) or {},
                classRestriction = (not active) or active.classRestriction ~= false,
                ignoreBattleNetBound = active and active.ignoreBattleNetBound == true,
                tankOnly = active and active.tankOnly == true,
                primaryStat = (active and active.primaryStat) or {},
            })
            if id then BG.BGNext.EquipmentFilter.selectProfile(current, id) end
        end
        edit:Hide(); updateProfileRows(); updateRuleButtons(); refreshItems(); play()
    end)
    local back = BG.CreateButton(edit)
    back:SetSize(120, 25)
    back:SetPoint("LEFT", confirm, "RIGHT", 15, 0)
    back:SetText(L["返回"])
    back:SetScript("OnClick", function() edit:Hide(); play() end)

    local shortcuts = CreateFrame("Frame", nil, BG.FBMainFrame)
    shortcuts:SetPoint("BOTTOMLEFT", BG.MainFrame, "BOTTOMLEFT", BG.onlyOneHard and 250 or 410, 35)
    shortcuts:SetSize(1, 30)
    shortcuts.buttons = shortcutButtons
    BG.EquipmentFilterShortcutFrame = shortcuts
    local settings = CreateFrame("Button", nil, shortcuts)
    settings:SetPoint("LEFT", shortcuts, "RIGHT", 0, 0)
    settings:SetSize(25, 25)
    settings:SetNormalTexture("Interface/Buttons/UI-OptionsButton")
    settings:SetHighlightTexture("Interface/Buttons/UI-OptionsButton")
    settings:SetScript("OnClick", function() main:SetShown(not main:IsShown()); play() end)
    settings:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine(L["自定义装备过滤方案"], 1, 1, 1)
        GameTooltip:Show()
    end)
    settings:SetScript("OnLeave", GameTooltip_Hide)
    main.SettingsButton = settings
    updateProfileRows()
    refreshItems()
end

BG.FilterClassItemUI = function()
    if BG.FilterClassItemMainFrame and BG.FilterClassItemMainFrame.GetObjectType then return end
    createUI()
end

BG.BGNext.EquipmentFilterUI = M
return M
