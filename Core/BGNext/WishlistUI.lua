local _, ns = ...

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = { tabNumber = 3 }

local function pairedHorizontal(difficultyIndex, difficultyCount)
    if difficultyCount <= 1 then return 1 end
    local target = difficultyIndex % 2 == 1 and difficultyIndex + 1 or difficultyIndex - 1
    return target <= difficultyCount and target or difficultyIndex
end

local function verticalEdge(difficultyIndex, difficultyCount, key)
    if difficultyCount > 2 then
        return difficultyIndex <= 2 and difficultyIndex + 2 or difficultyIndex - 2
    end
    if key == "DOWN" and difficultyIndex == 2 then return 1 end
    return difficultyIndex
end

local function tabDifficulty(difficultyIndex, difficultyCount)
    local target
    if difficultyIndex == 1 then
        target = difficultyCount > 2 and 3 or 2
    elseif difficultyIndex == 3 then
        target = 2
    elseif difficultyIndex == 2 then
        target = 4
    end
    return target and target <= difficultyCount and target or nil
end

function M.nextCell(difficultyIndex, bossIndex, slotIndex, key, difficultyCount, bossCount, slotCount, modified)
    if modified then
        local target
        if (key == "UP" or key == "DOWN") and difficultyCount > 2 then
            target = difficultyIndex <= 2 and difficultyIndex + 2 or difficultyIndex - 2
        elseif key == "LEFT" or key == "RIGHT" then
            target = pairedHorizontal(difficultyIndex, difficultyCount)
        end
        if target and target ~= difficultyIndex then
            return { difficultyIndex = target, bossIndex = bossIndex, slotIndex = slotIndex }
        end
        return nil
    end

    if key == "TAB" then
        if slotIndex < slotCount then
            return { difficultyIndex = difficultyIndex, bossIndex = bossIndex, slotIndex = slotIndex + 1 }
        end
        if bossIndex < bossCount then
            return { difficultyIndex = difficultyIndex, bossIndex = bossIndex + 1, slotIndex = 1 }
        end
        local target = tabDifficulty(difficultyIndex, difficultyCount)
        return target and { difficultyIndex = target, bossIndex = 1, slotIndex = 1 } or nil
    elseif key == "LEFT" then
        if slotIndex > 1 then
            return { difficultyIndex = difficultyIndex, bossIndex = bossIndex, slotIndex = slotIndex - 1 }
        end
        return {
            difficultyIndex = pairedHorizontal(difficultyIndex, difficultyCount),
            bossIndex = bossIndex,
            slotIndex = slotCount,
        }
    elseif key == "RIGHT" then
        if slotIndex < slotCount then
            return { difficultyIndex = difficultyIndex, bossIndex = bossIndex, slotIndex = slotIndex + 1 }
        end
        return {
            difficultyIndex = pairedHorizontal(difficultyIndex, difficultyCount),
            bossIndex = bossIndex,
            slotIndex = 1,
        }
    elseif key == "UP" then
        if bossIndex > 1 then
            return { difficultyIndex = difficultyIndex, bossIndex = bossIndex - 1, slotIndex = slotIndex }
        end
        return {
            difficultyIndex = verticalEdge(difficultyIndex, difficultyCount, key),
            bossIndex = bossCount,
            slotIndex = slotIndex,
        }
    elseif key == "DOWN" then
        if bossIndex < bossCount then
            return { difficultyIndex = difficultyIndex, bossIndex = bossIndex + 1, slotIndex = slotIndex }
        end
        return {
            difficultyIndex = verticalEdge(difficultyIndex, difficultyCount, key),
            bossIndex = 1,
            slotIndex = slotIndex,
        }
    end
    return nil
end

function M.shortcutAction(isMasterLooter, button, altDown)
    if not altDown then return nil end
    if button == "LeftButton" then return "wishlist" end
    if isMasterLooter and button == "RightButton" then return "auction" end
    return nil
end

local function runtimeReady()
    return ns and BG.Init and BG.MainFrame and BG.Create_TabButton and BG.BGNext.Wishlist and BG.BGNext.DB
end

if runtimeReady() then
    local wishlist = BG.BGNext.Wishlist
    local hopeMaxn = ns.HopeMaxn
    local hopeMaxb = ns.HopeMaxb
    local hopeMaxi = ns.HopeMaxi
    local L = ns.L or setmetatable({}, { __index = function(_, key) return key end })

    local function context(raidId)
        return BG.BGNext.DB, BG.realmID, BG.playerName, raidId or BG.FB1
    end

    local function limitsFor(raidId)
        return {
            difficulties = hopeMaxn[raidId] or 0,
            bosses = hopeMaxb[raidId] or 0,
            slots = hopeMaxi or 0,
        }
    end

    local function sameItem(left, right)
        if BG.IsSame then return BG.IsSame(left, right) end
        return tonumber(left) == tonumber(right)
    end

    local function resolveDrop(itemId, raidId)
        local difficulties = BG.difficultyTable and BG.difficultyTable[raidId]
        local raidLoot = BG.Loot and BG.Loot[raidId]
        if not difficulties or not raidLoot then return nil end
        for difficultyIndex, difficultyName in ipairs(difficulties) do
            local difficultyLoot = raidLoot[difficultyName]
            if difficultyLoot then
                for bossIndex = 1, hopeMaxb[raidId] or 0 do
                    for _, droppedItemId in ipairs(difficultyLoot["boss" .. bossIndex] or {}) do
                        if sameItem(itemId, droppedItemId) then
                            return { difficultyIndex = difficultyIndex, bossIndex = bossIndex }
                        end
                    end
                end
            end
        end
        return nil
    end

    local function localMessage(message)
        if BG.SendSystemMessage then BG.SendSystemMessage(message) else print("<BGNext> " .. message) end
    end

    local function difficultyLabel(raidId, difficultyIndex)
        if BG.IsWLKFB and BG.IsWLKFB(raidId) then
            return ({
                "< |cffFFFFFF10人|r|cff00BFFF普通|r >",
                "< |cffFFFFFF25人|r|cff00BFFF普通|r >",
                "< |cffFFFFFF10人|r|cffFF0000英雄|r >",
                "< |cffFFFFFF25人|r|cffFF0000英雄|r >",
            })[difficultyIndex]
        elseif BG.IsRetail then
            return ({ "< |cff00BFFF普通|r >", "< |cffFF0000英雄|r >", "< |cffa335ee史诗|r >" })[difficultyIndex]
        end
        return ({ "< |cff00BFFF普通|r >", "< |cffFF0000英雄|r >" })[difficultyIndex]
            or tostring(BG.difficultyTable[raidId][difficultyIndex])
    end

    local function setSlotText(slot, itemId)
        slot._refreshing = true
        if itemId then
            local _, link = GetItemInfo(itemId)
            slot:SetText(link or tostring(itemId))
            if BG.OnItemLoad then
                BG.OnItemLoad(itemId):ContinueOnItemLoad(function()
                    if slot.itemId ~= itemId then return end
                    local _, loadedLink = GetItemInfo(itemId)
                    if loadedLink then
                        slot._refreshing = true
                        slot:SetText(loadedLink)
                        slot:SetCursorPosition(0)
                        slot._refreshing = nil
                    end
                end)
            end
        else
            slot:SetText("")
        end
        slot:SetCursorPosition(0)
        slot._refreshing = nil
    end

    local function updateSlotAppearance(slot)
        local text = slot:GetText()
        local itemId = wishlist.itemIdFromValue(text)
        slot.itemId = itemId
        if itemId then
            local _, link, _, level, _, _, _, _, _, texture, _, typeId, _, bindType = GetItemInfo(itemId)
            slot.icon:SetTexture(texture)
            if BG.AddHText and link then BG.AddHText(slot.FB, link, itemId, slot) end
            if BG.BindOnEquip then BG.BindOnEquip(slot, bindType) end
            if BG.LevelText then BG.LevelText(slot, level, typeId) end
            if BG.IsHave then BG.IsHave(slot) end
        else
            slot.icon:SetTexture(nil)
            if BG.BindOnEquip then BG.BindOnEquip(slot) end
            if BG.LevelText then BG.LevelText(slot) end
            if BG.IsHave then BG.IsHave(slot) end
        end
        if BG.UpdateFilter then BG.UpdateFilter(slot) end
        if BG.Update_IsLooted then BG.Update_IsLooted(slot) end
    end

    local function persistSlot(slot)
        if slot._refreshing then return true end
        local itemId = wishlist.itemIdFromValue(slot:GetText())
        local root, realmId, player, raidId = context(slot.FB)
        if not itemId then
            if slot:GetText() == "" then
                wishlist.clearSlot(root, realmId, player, raidId, slot.hopenandu, slot.bossnum, slot.i)
                slot.itemId = nil
                updateSlotAppearance(slot)
                return true
            end
            return false
        end
        local location = resolveDrop(itemId, raidId)
        if not location or location.difficultyIndex ~= slot.hopenandu or location.bossIndex ~= slot.bossnum then
            return false
        end
        wishlist.setSlot(root, realmId, player, raidId, limitsFor(raidId), slot.hopenandu, slot.bossnum, slot.i, itemId)
        slot.itemId = itemId
        updateSlotAppearance(slot)
        return true
    end

    local function focusCell(raidId, cell)
        local target = cell and BG.HopeFrame[raidId]
            and BG.HopeFrame[raidId]["nandu" .. cell.difficultyIndex]
            and BG.HopeFrame[raidId]["nandu" .. cell.difficultyIndex]["boss" .. cell.bossIndex]
            and BG.HopeFrame[raidId]["nandu" .. cell.difficultyIndex]["boss" .. cell.bossIndex]["zhuangbei" .. cell.slotIndex]
        if target then target:SetFocus() end
    end

    local function createSlot(parent, raidId, difficultyIndex, bossIndex, slotIndex, anchor, xOffset)
        local slot = CreateFrame("EditBox", nil, parent, BG.editTemplate)
        slot:SetSize(115, 20)
        slot:SetFrameLevel(110)
        slot:SetPoint("TOPLEFT", anchor, slotIndex == 1 and "BOTTOMLEFT" or "TOPLEFT", xOffset or 0, slotIndex == 1 and -1 or 0)
        slot:SetAutoFocus(false)
        if BG.SetEditStickyFocus then BG.SetEditStickyFocus(slot) end
        slot.FB, slot.hopenandu, slot.bossnum, slot.i = raidId, difficultyIndex, bossIndex, slotIndex
        slot.icon = slot:CreateTexture(nil, "ARTWORK")
        slot.icon:SetPoint("LEFT", -22, 0)
        slot.icon:SetSize(16, 16)
        if BG.LootedText then BG.LootedText(slot) end

        slot.hover = slot:CreateTexture(nil, "BACKGROUND")
        slot.hover:SetPoint("TOPLEFT", -4, -2)
        slot.hover:SetPoint("BOTTOMRIGHT", -1, 0)
        slot.hover:SetColorTexture(1, 1, 1, 0.1)
        slot.hover:Hide()
        slot.focus = slot:CreateTexture(nil, "BACKGROUND")
        slot.focus:SetAllPoints(slot.hover)
        slot.focus:SetColorTexture(1, 1, 1, 0.1)
        slot.focus:Hide()

        slot:SetScript("OnTextChanged", function(self)
            if not self._refreshing then persistSlot(self) end
        end)
        slot:SetScript("OnMouseDown", function(self, button)
            if button == "RightButton" and not IsAltKeyDown() then
                self._refreshing = true
                self:SetText("")
                self._refreshing = nil
                local root, realmId, player = context(self.FB)
                wishlist.clearSlot(root, realmId, player, self.FB, self.hopenandu, self.bossnum, self.i)
                updateSlotAppearance(self)
                self:ClearFocus()
            elseif IsShiftKeyDown() and self:GetText() ~= "" and BG.InsertLink then
                BG.InsertLink(self:GetText())
                self:ClearFocus()
            elseif IsControlKeyDown() and self:GetText() ~= "" and BG.GoToItemLib then
                BG.GoToItemLib(self)
            end
        end)
        slot:SetScript("OnMouseUp", function(self)
            local infoType, _, itemLink = GetCursorInfo()
            if infoType == "item" and itemLink then
                local oldItemId = self.itemId
                self._refreshing = true
                self:SetText(itemLink)
                self._refreshing = nil
                if not persistSlot(self) then
                    self.itemId = oldItemId
                    setSlotText(self, oldItemId)
                    localMessage("只能设置该难度下对应首领正常掉落的装备为心愿。")
                end
                self:ClearFocus()
                ClearCursor()
            end
        end)
        slot:SetScript("OnEnter", function(self)
            self.hover:Show()
            if self.itemId then
                GameTooltip:SetOwner(self, BG.ButtonIsInRight and BG.ButtonIsInRight(self) and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(self.itemId)
                GameTooltip:AddLine("右键取消心愿装备", 0.5, 1, 0.5, true)
                GameTooltip:Show()
            end
        end)
        slot:SetScript("OnLeave", function(self)
            self.hover:Hide()
            GameTooltip:Hide()
            SetCursor(nil)
        end)
        slot:SetScript("OnEditFocusGained", function(self)
            self:HighlightText()
            self.focus:Show()
            BG.lastfocuszhuangbei = self
            BG.lastfocus = self
            if BG.SetListzhuangbei then BG.SetListzhuangbei(self) end
        end)
        slot:SetScript("OnEditFocusLost", function(self)
            self:ClearHighlightText()
            self.focus:Hide()
            if self:GetText() ~= "" and not persistSlot(self) then
                setSlotText(self, self.itemId)
                localMessage("该装备不属于此难度下的当前首领，心愿未改变。")
            end
        end)
        slot:SetScript("OnTabPressed", function(self)
            focusCell(self.FB, M.nextCell(self.hopenandu, self.bossnum, self.i, "TAB",
                hopeMaxn[self.FB], hopeMaxb[self.FB], hopeMaxi, false))
        end)
        slot:SetScript("OnKeyDown", function(self, key)
            if key == "UP" or key == "DOWN" or key == "LEFT" or key == "RIGHT" then
                focusCell(self.FB, M.nextCell(self.hopenandu, self.bossnum, self.i, key,
                    hopeMaxn[self.FB], hopeMaxb[self.FB], hopeMaxi, IsModifierKeyDown()))
            end
        end)
        slot:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            if BG.FrameZhuangbeiList then BG.FrameZhuangbeiList:Hide() end
        end)
        slot:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            if BG.FrameZhuangbeiList then BG.FrameZhuangbeiList:Hide() end
        end)
        return slot
    end

    local function createRaidGrid(raidId, parent)
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetAllPoints(parent)
        frame:Hide()
        BG.HopeFrame[raidId] = {}
        local previousBottomFirst, previousHeaderLast

        for difficultyIndex = 1, hopeMaxn[raidId] do
            local difficulty = frame:CreateFontString(nil, "OVERLAY")
            if difficultyIndex == 1 then
                difficulty:SetPoint("TOPLEFT", BG.MainFrame, "TOPLEFT", 10, -60)
            elseif difficultyIndex == 2 or difficultyIndex == 4 then
                difficulty:SetPoint("TOPRIGHT", previousBottomFirst, "TOPLEFT", -20, -30)
            else
                difficulty:SetPoint("TOPLEFT", previousHeaderLast, "TOPRIGHT", 20, 0)
            end
            difficulty:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
            difficulty:SetTextColor(1, 0.82, 0)
            difficulty:SetSize(100, 20)
            difficulty:SetJustifyH("RIGHT")
            difficulty:SetText(difficultyLabel(raidId, difficultyIndex))

            local headers, priorHeader = {}, difficulty
            for slotIndex = 1, hopeMaxi do
                local header = frame:CreateFontString(nil, "OVERLAY")
                header:SetPoint("TOPLEFT", priorHeader, "TOPRIGHT", slotIndex == 1 and 20 or 26, 0)
                header:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                header:SetTextColor(1, 0.82, 0)
                header:SetSize(115, 20)
                header:SetJustifyH("LEFT")
                header:SetText("心愿" .. slotIndex)
                headers[slotIndex], priorHeader = header, header
            end
            previousHeaderLast = headers[#headers]

            BG.HopeFrame[raidId]["nandu" .. difficultyIndex] = {}
            local priorFirstSlot
            for bossIndex = 1, hopeMaxb[raidId] do
                local boss = {}
                BG.HopeFrame[raidId]["nandu" .. difficultyIndex]["boss" .. bossIndex] = boss
                local rowAnchor = bossIndex == 1 and headers[1] or priorFirstSlot
                for slotIndex = 1, hopeMaxi do
                    local anchor = slotIndex == 1 and rowAnchor or boss["zhuangbei1"]
                    local xOffset = slotIndex == 1 and 0 or (115 + 26) * (slotIndex - 1)
                    local slot = createSlot(frame, raidId, difficultyIndex, bossIndex, slotIndex, anchor, xOffset)
                    boss["zhuangbei" .. slotIndex] = slot
                end
                priorFirstSlot = boss.zhuangbei1
                local bossLabel = frame:CreateFontString(nil, "OVERLAY")
                bossLabel:SetPoint("TOPRIGHT", boss.zhuangbei1, "TOPLEFT", -26, -3)
                bossLabel:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
                local bossInfo = BG.Boss[raidId] and BG.Boss[raidId]["boss" .. bossIndex]
                local color = bossInfo and bossInfo.color or "FFFFFF"
                if ns.RGB then bossLabel:SetTextColor(ns.RGB(color)) else bossLabel:SetTextColor(1, 1, 1) end
                bossLabel:SetSize(100, 20)
                bossLabel:SetJustifyH("RIGHT")
                bossLabel:SetText(bossInfo and bossInfo.name2 or ("Boss " .. bossIndex))
                boss.name = bossLabel
            end
            previousBottomFirst = priorFirstSlot
        end

        function frame:Refresh()
            local root, realmId, player = context(raidId)
            for difficultyIndex = 1, hopeMaxn[raidId] do
                for bossIndex = 1, hopeMaxb[raidId] do
                    local writeIndex = 1
                    for slotIndex = 1, hopeMaxi do
                        local itemId = wishlist.getSlot(root, realmId, player, raidId, difficultyIndex, bossIndex, slotIndex)
                        if itemId then
                            if writeIndex ~= slotIndex then
                                wishlist.setSlot(root, realmId, player, raidId, limitsFor(raidId),
                                    difficultyIndex, bossIndex, writeIndex, itemId)
                                wishlist.clearSlot(root, realmId, player, raidId, difficultyIndex, bossIndex, slotIndex)
                            end
                            writeIndex = writeIndex + 1
                        end
                    end
                    for slotIndex = 1, hopeMaxi do
                        local slot = BG.HopeFrame[raidId]["nandu" .. difficultyIndex]["boss" .. bossIndex]["zhuangbei" .. slotIndex]
                        local itemId = wishlist.getSlot(root, realmId, player, raidId, difficultyIndex, bossIndex, slotIndex)
                        slot.itemId = itemId
                        setSlotText(slot, itemId)
                        updateSlotAppearance(slot)
                    end
                end
            end
        end
        return frame
    end

    local importPanel, exportPanel

    local function limitsByRaid()
        local result = {}
        for _, raidId in ipairs(BG.FBtable or {}) do
            result[raidId] = limitsFor(raidId)
        end
        return result
    end

    local function createTextPanel(owner, title, importMode)
        local panel = CreateFrame("Frame", nil, owner, "BackdropTemplate")
        panel:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 10,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        panel:SetBackdropColor(0, 0, 0, 0.8)
        panel:SetPoint("TOPRIGHT", BG.MainFrame, "TOPRIGHT", -20, -20)
        panel:SetSize(250, 250)
        panel:SetFrameLevel(130)
        panel:EnableMouse(true)
        panel:Hide()

        local heading = panel:CreateFontString(nil, "OVERLAY")
        heading:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
        heading:SetPoint("TOP", 0, -8)
        heading:SetTextColor(1, 1, 1)
        heading:SetText(title)

        local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        box:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeSize = 1,
        })
        box:SetBackdropColor(0, 0, 0, 0.8)
        box:SetBackdropBorderColor(1, 1, 1, 0.5)
        box:SetPoint("TOPLEFT", 8, -28)
        box:SetSize(234, 180)

        local scroll = CreateFrame("ScrollFrame", nil, box, BG.scrollTemplate)
        scroll:SetPoint("TOPLEFT", 5, -4)
        scroll:SetPoint("BOTTOMRIGHT", -27, 4)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetWidth(200)
        edit:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:EnableMouse(true)
        edit:SetTextInsets(5, 5, 5, 10)
        scroll:SetScrollChild(edit)
        edit:SetScript("OnEscapePressed", function() panel:Hide() end)
        panel.edit, panel.scroll = edit, scroll

        local cancel = BG.CreateButton(panel)
        cancel:SetSize(110, 25)
        cancel:SetPoint("BOTTOMRIGHT", -8, 10)
        cancel:SetText(CANCEL or "取消")
        cancel:SetScript("OnClick", function() panel:Hide() end)

        if importMode then
            local function acceptImport()
                local parsed = wishlist.parseImport(edit:GetText(), limitsByRaid())
                if not parsed.ok then
                    localMessage("心愿导入失败：" .. tostring(parsed.reason))
                    return
                end
                local root, realmId, player = context()
                if not wishlist.applyImport(root, realmId, player, parsed) then
                    localMessage("心愿导入失败：当前角色信息不可用。")
                    return
                end
                for raidId in pairs(parsed.raids) do
                    local raidFrame = BG["HopeFrame" .. raidId]
                    if raidFrame and raidFrame:IsShown() then raidFrame:Refresh() end
                end
                localMessage(string.format("心愿清单导入成功，一共导入%d件装备。", parsed.itemCount))
                panel:Hide()
            end
            local okay = BG.CreateButton(panel)
            okay:SetSize(110, 25)
            okay:SetPoint("BOTTOMLEFT", 8, 10)
            okay:SetText(OKAY or "确定")
            okay:SetScript("OnClick", acceptImport)
            edit:SetScript("OnEnterPressed", acceptImport)
        end
        return panel
    end

    local function showImportPanel()
        if exportPanel then exportPanel:Hide() end
        if not importPanel then
            importPanel = createTextPanel(BG.ButtonImportHope, "导入心愿", true)
        end
        importPanel:SetShown(not importPanel:IsShown())
        if importPanel:IsShown() then
            importPanel.edit:SetText("")
            importPanel.edit:SetFocus()
        end
    end

    local function showExportPanel()
        if importPanel then importPanel:Hide() end
        if not exportPanel then
            exportPanel = createTextPanel(BG.ButtonExportHope, "导出心愿", false)
        end
        exportPanel:SetShown(not exportPanel:IsShown())
        if exportPanel:IsShown() then
            local root, realmId, player, raidId = context()
            local payload = wishlist.exportRaid(root, realmId, player, raidId, limitsFor(raidId))
            exportPanel.edit:SetText(payload or "心愿清单是空的")
            exportPanel.edit:HighlightText()
            exportPanel.edit:SetFocus()
        end
    end

    local function confirmClearRaid()
        local popupName = "BGNEXT_CLEAR_CURRENT_WISHLIST"
        StaticPopupDialogs[popupName] = StaticPopupDialogs[popupName] or {
            text = "确定清空心愿？",
            button1 = YES or "是",
            button2 = NO or "否",
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            showAlert = true,
        }
        StaticPopupDialogs[popupName].OnAccept = function()
            local root, realmId, player, raidId = context()
            if wishlist.clearRaid(root, realmId, player, raidId) then
                local frame = BG["HopeFrame" .. raidId]
                if frame then frame:Refresh() end
                local shortName = BG.GetFBinfo and BG.GetFBinfo(raidId, "shortName") or raidId
                localMessage(string.format("已清空心愿< %s >", tostring(shortName)))
                if BG.PlaySound then BG.PlaySound(2) end
            end
        end
        StaticPopup_Show(popupName)
    end

    BG.Init(function()
        BG.HopeMainFrame = CreateFrame("Frame", nil, BG.MainFrame)
        BG.HopeMainFrame:SetAllPoints(BG.MainFrame)
        BG.HopeMainFrame:Hide()
        BG.HopeFrame = {}
        local quarantined = 0
        for _, raidId in ipairs(BG.FBtable or {}) do
            local migration = wishlist.migrateFlatRaid(BG.BGNext.DB, BG.realmID, BG.playerName,
                raidId, limitsFor(raidId), resolveDrop)
            quarantined = quarantined + migration.quarantined
            BG["HopeFrame" .. raidId] = createRaidGrid(raidId, BG.HopeMainFrame)
        end
        if quarantined > 0 then
            localMessage(string.format("有%d件旧测试版心愿无法可靠匹配首领，已保留但未自动放入心愿格。", quarantined))
        end

        local function showCurrentRaid()
            for _, raidId in ipairs(BG.FBtable or {}) do
                local frame = BG["HopeFrame" .. raidId]
                if raidId == BG.FB1 then
                    frame:Show()
                    frame:Refresh()
                else
                    frame:Hide()
                end
            end
        end
        BG.HopeMainFrame:SetScript("OnShow", showCurrentRaid)
        BG.Create_TabButton(M.tabNumber, L["心愿清单"] or "心愿清单", BG.HopeMainFrame)

        BG.ButtonImportHope = CreateFrame("Button", nil, BG.HopeMainFrame)
        BG.ButtonImportHope:SetPoint("TOPRIGHT", BG.MainFrame, "TOPRIGHT", -35, 4)
        if BG.FontGreen15 then BG.ButtonImportHope:SetNormalFontObject(BG.FontGreen15) end
        if BG.FontDis15 then BG.ButtonImportHope:SetDisabledFontObject(BG.FontDis15) end
        if BG.FontWhite15 then BG.ButtonImportHope:SetHighlightFontObject(BG.FontWhite15) end
        BG.ButtonImportHope:SetText("导入心愿")
        BG.ButtonImportHope:SetSize(BG.ButtonImportHope:GetFontString():GetWidth(), 30)
        if BG.SetTextHighlightTexture then BG.SetTextHighlightTexture(BG.ButtonImportHope) end
        BG.ButtonImportHope:SetScript("OnClick", showImportPanel)

        BG.ButtonExportHope = CreateFrame("Button", nil, BG.HopeMainFrame)
        BG.ButtonExportHope:SetPoint("RIGHT", BG.ButtonImportHope, "LEFT", -7, 0)
        if BG.FontGreen15 then BG.ButtonExportHope:SetNormalFontObject(BG.FontGreen15) end
        if BG.FontDis15 then BG.ButtonExportHope:SetDisabledFontObject(BG.FontDis15) end
        if BG.FontWhite15 then BG.ButtonExportHope:SetHighlightFontObject(BG.FontWhite15) end
        BG.ButtonExportHope:SetText("导出心愿")
        BG.ButtonExportHope:SetSize(BG.ButtonExportHope:GetFontString():GetWidth(), 30)
        if BG.SetTextHighlightTexture then BG.SetTextHighlightTexture(BG.ButtonExportHope) end
        BG.ButtonExportHope:SetScript("OnClick", showExportPanel)

        BG.ButtonHopeQingKong = BG.CreateButton(BG.HopeMainFrame)
        BG.ButtonHopeQingKong:SetSize(120, 25)
        BG.ButtonHopeQingKong:SetPoint("BOTTOMLEFT", BG.MainFrame, "BOTTOMLEFT", 30, 38)
        BG.ButtonHopeQingKong:SetText("清空心愿")
        BG.ButtonHopeQingKong:SetScript("OnClick", confirmClearRaid)

        if hooksecurefunc and BG.ClickFBbutton then
            hooksecurefunc(BG, "ClickFBbutton", function()
                if BG.HopeMainFrame:IsShown() then showCurrentRaid() end
            end)
        end

        BG.IsHope = function(value, raidId)
            local itemId = wishlist.itemIdFromValue(value)
            if not itemId then return false end
            local root, realmId, player, currentRaidId = context(raidId)
            return wishlist.contains(root, realmId, player, currentRaidId, itemId)
        end

        BG.SetHope = function(value, raidId)
            local itemId = wishlist.itemIdFromValue(value)
            local root, realmId, player, currentRaidId = context(raidId)
            local result = wishlist.placeItem(root, realmId, player, currentRaidId, limitsFor(currentRaidId), itemId, resolveDrop)
            if result.ok then
                local frame = BG["HopeFrame" .. currentRaidId]
                if frame and frame:IsShown() then frame:Refresh() end
                return true
            end
            localMessage(result.reason == "boss-full" and "该首领的心愿格子已满。" or "只能设置团本首领正常掉落的装备为心愿。")
            return false
        end

        BG.DeleteHope = function(value, raidId)
            local itemId = wishlist.itemIdFromValue(value)
            if not itemId then return false end
            local root, realmId, player, currentRaidId = context(raidId)
            local matches = wishlist.findItem(root, realmId, player, currentRaidId, itemId)
            for _, match in ipairs(matches) do
                wishlist.clearSlot(root, realmId, player, currentRaidId,
                    match.difficultyIndex, match.bossIndex, match.slotIndex)
            end
            local frame = BG["HopeFrame" .. currentRaidId]
            if frame and frame:IsShown() then frame:Refresh() end
            return #matches > 0
        end

        BG.ToggleCurrentWish = function(value)
            return BG.SetHope(value, BG.FB1)
        end
    end)
end

BG.BGNext.WishlistUI = M
return M
