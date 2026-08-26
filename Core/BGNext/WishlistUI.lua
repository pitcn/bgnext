BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

function M.isWish(root, realmId, player, raidId, value)
    local wishlist = BG.BGNext.Wishlist
    if not wishlist then
        return false
    end
    local itemId = wishlist.itemIdFromValue(value)
    return itemId ~= nil and wishlist.contains(root, realmId, player, raidId, itemId)
end

function M.toggleWish(root, realmId, player, raidId, value)
    local wishlist = BG.BGNext.Wishlist
    if not wishlist then
        return nil
    end
    local itemId = wishlist.itemIdFromValue(value)
    if not itemId then
        return nil
    end
    return wishlist.toggle(root, realmId, player, raidId, itemId), itemId
end

function M.shortcutAction(isMasterLooter, button)
    if button == "LeftButton" then
        return "wishlist"
    end
    if isMasterLooter and button == "RightButton" then
        return "auction"
    end
    return nil
end

local function currentContext()
    return BG.BGNext.DB, BG.realmID, BG.playerName, BG.FB1
end

local function sendLocalMessage(message)
    if BG.SendSystemMessage then
        BG.SendSystemMessage(message)
    else
        print((BG.BG or "<BGNext> ") .. message)
    end
end

local function createWishlistFrame()
    local frame = CreateFrame("Frame", nil, BG.MainFrame)
    frame:SetAllPoints(BG.MainFrame)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -58)
    title:SetFont(BIAOGE_TEXT_FONT, 18, "OUTLINE")
    title:SetTextColor(1, 0.82, 0)
    title:SetText("个人心愿清单")

    local privacy = frame:CreateFontString(nil, "OVERLAY")
    privacy:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    privacy:SetFont(BIAOGE_TEXT_FONT, 13, "")
    privacy:SetTextColor(0.55, 0.85, 1)
    privacy:SetText("仅保存在本地，仅当前角色可见，不会发送给团队或其他玩家。")

    local raidText = frame:CreateFontString(nil, "OVERLAY")
    raidText:SetPoint("TOPLEFT", privacy, "BOTTOMLEFT", 0, -14)
    raidText:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    raidText:SetTextColor(0.92, 0.92, 0.92)

    local input = CreateFrame("EditBox", nil, frame, BG.editTemplate or "InputBoxTemplate")
    input:SetPoint("TOPLEFT", raidText, "BOTTOMLEFT", 0, -10)
    input:SetSize(285, 24)
    input:SetAutoFocus(false)
    input:SetTextInsets(8, 8, 0, 0)
    input:SetMaxLetters(255)

    local placeholder = input:CreateFontString(nil, "ARTWORK")
    placeholder:SetPoint("LEFT", input, "LEFT", 8, 0)
    placeholder:SetFont(BIAOGE_TEXT_FONT, 13, "")
    placeholder:SetTextColor(0.5, 0.5, 0.5)
    placeholder:SetText("输入物品 ID，或 Shift+点击物品链接")
    input:SetScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
    end)

    local addButton = BG.CreateButton(frame)
    addButton:SetPoint("LEFT", input, "RIGHT", 8, 0)
    addButton:SetSize(72, 24)
    addButton:SetText("添加")

    local clearButton = BG.CreateButton(frame)
    clearButton:SetPoint("LEFT", addButton, "RIGHT", 8, 0)
    clearButton:SetSize(100, 24)
    clearButton:SetText("清空本副本")

    local countText = frame:CreateFontString(nil, "OVERLAY")
    countText:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -14)
    countText:SetFont(BIAOGE_TEXT_FONT, 13, "")
    countText:SetTextColor(0.75, 0.75, 0.75)

    local scroll = CreateFrame("ScrollFrame", nil, frame, BG.scrollTemplate or "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", countText, "BOTTOMLEFT", 0, -8)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -48, 42)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(470, 1)
    scroll:SetScrollChild(content)

    local rows = {}
    local function removeItem(itemId)
        local root, realmId, player, raidId = currentContext()
        if BG.BGNext.Wishlist.remove(root, realmId, player, raidId, itemId) then
            sendLocalMessage("已从当前副本的个人心愿清单移除。")
            frame:Refresh()
        end
    end

    local function createRow(index)
        local row = CreateFrame("Button", nil, content)
        row:SetSize(470, 24)
        if index == 1 then
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", rows[index - 1], "BOTTOMLEFT", 0, -3)
        end
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        local background = row:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0.08, 0.08, 0.08, index % 2 == 0 and 0.7 or 0.45)

        local label = row:CreateFontString(nil, "OVERLAY")
        label:SetPoint("LEFT", row, "LEFT", 8, 0)
        label:SetPoint("RIGHT", row, "RIGHT", -90, 0)
        label:SetJustifyH("LEFT")
        label:SetFont(BIAOGE_TEXT_FONT, 14, "")

        local hint = row:CreateFontString(nil, "OVERLAY")
        hint:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        hint:SetFont(BIAOGE_TEXT_FONT, 12, "")
        hint:SetTextColor(0.65, 0.65, 0.65)
        hint:SetText("右键移除")

        row:SetScript("OnClick", function(self, button)
            if button == "RightButton" and self.itemId then
                removeItem(self.itemId)
            elseif self.itemLink and IsShiftKeyDown() and BG.InsertLink then
                BG.InsertLink(self.itemLink)
            end
        end)
        row:SetScript("OnEnter", function(self)
            if not self.itemId then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemId)
            GameTooltip:AddLine("右键：从个人心愿清单移除", 0.5, 1, 0.5, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        row.label = label
        row.hint = hint
        row:Hide()
        rows[index] = row
        return row
    end

    function frame:Refresh()
        local root, realmId, player, raidId = currentContext()
        local items = BG.BGNext.Wishlist.list(root, realmId, player, raidId)
        raidText:SetText("当前副本：" .. tostring(raidId or "未识别"))
        countText:SetText(string.format("已记录 %d 件装备", #items))

        for index, itemId in ipairs(items) do
            local row = rows[index] or createRow(index)
            row.itemId = itemId
            row.itemLink = nil
            local itemName, itemLink = GetItemInfo(itemId)
            row.itemLink = itemLink
            row.label:SetText(itemLink or itemName or ("物品 ID：" .. itemId))
            row:Show()
            if BG.OnItemLoad then
                BG.OnItemLoad(itemId):ContinueOnItemLoad(function()
                    if row.itemId ~= itemId then return end
                    local loadedName, loadedLink = GetItemInfo(itemId)
                    row.itemLink = loadedLink
                    row.label:SetText(loadedLink or loadedName or ("物品 ID：" .. itemId))
                end)
            end
        end
        for index = #items + 1, #rows do
            rows[index].itemId = nil
            rows[index].itemLink = nil
            rows[index]:Hide()
        end
        content:SetHeight(math.max(1, #items * 27))
    end

    local function addInput()
        local itemId = BG.BGNext.Wishlist.itemIdFromValue(input:GetText())
        if not itemId then
            sendLocalMessage("无法识别该物品，请输入物品 ID 或粘贴物品链接。")
            return
        end
        local root, realmId, player, raidId = currentContext()
        if BG.BGNext.Wishlist.add(root, realmId, player, raidId, itemId) then
            input:SetText("")
            input:ClearFocus()
            sendLocalMessage("已加入当前副本的个人心愿清单。")
            frame:Refresh()
        else
            sendLocalMessage("该物品已在清单中，或当前角色/副本信息不可用。")
        end
    end

    addButton:SetScript("OnClick", addInput)
    input:SetScript("OnEnterPressed", addInput)
    input:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    local popupName = "BGNEXT_CLEAR_CURRENT_WISHLIST"
    StaticPopupDialogs[popupName] = StaticPopupDialogs[popupName] or {
        text = "确认清空当前角色在当前副本的全部心愿装备？",
        button1 = YES,
        button2 = NO,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    clearButton:SetScript("OnClick", function()
        StaticPopupDialogs[popupName].OnAccept = function()
            local root, realmId, player, raidId = currentContext()
            if BG.BGNext.Wishlist.clear(root, realmId, player, raidId) then
                sendLocalMessage("已清空当前副本的个人心愿清单。")
                frame:Refresh()
            end
        end
        StaticPopup_Show(popupName)
    end)

    frame:SetScript("OnShow", function(self)
        self:Refresh()
    end)
    return frame
end

BG.IsHope = function(itemId, raidId)
    local root, realmId, player, currentRaidId = currentContext()
    return M.isWish(root, realmId, player, raidId or currentRaidId, itemId)
end

BG.ToggleCurrentWish = function(value)
    local root, realmId, player, raidId = currentContext()
    local enabled = M.toggleWish(root, realmId, player, raidId, value)
    if enabled == nil then
        sendLocalMessage("无法识别该物品，心愿清单未改变。")
        return nil
    end
    sendLocalMessage(enabled and "已加入当前副本的个人心愿清单。" or "已从当前副本的个人心愿清单移除。")
    if BG.WishlistMainFrame and BG.WishlistMainFrame:IsShown() then
        BG.WishlistMainFrame:Refresh()
    end
    return enabled
end

if BG.Init then
    BG.Init(function()
        if not BG.MainFrame or not BG.Create_TabButton or not BG.BGNext.Wishlist or not BG.BGNext.DB then
            return
        end
        BG.WishlistMainFrameTabNum = 2
        BG.WishlistMainFrame = createWishlistFrame()
        BG.Create_TabButton(BG.WishlistMainFrameTabNum, "心愿清单", BG.WishlistMainFrame, 105)
        if hooksecurefunc and BG.ClickFBbutton then
            hooksecurefunc(BG, "ClickFBbutton", function()
                if BG.WishlistMainFrame:IsShown() then
                    BG.WishlistMainFrame:Refresh()
                end
            end)
        end
    end)
end

BG.BGNext.WishlistUI = M
return M
