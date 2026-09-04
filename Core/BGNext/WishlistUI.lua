local _, ns = ...

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = { tabNumber = 3 }

-- The wishlist equipment picker is the single shared frame BG.FrameZhuangbeiList,
-- created by BG.SetListzhuangbei (which the normal bill slots also use). Its
-- lifecycle lives here: at most one picker is open at a time, it is owned by the
-- slot that opened it, and clicking that same slot again collapses it.
local openPickerSlot = nil

function M.hidePicker()
    if BG.FrameZhuangbeiList and BG.FrameZhuangbeiList:IsShown() then
        BG.FrameZhuangbeiList:Hide()
    end
end

function M.closePicker()
    M.hidePicker()
    if openPickerSlot and openPickerSlot.ClearFocus then
        openPickerSlot:ClearFocus()
    end
    openPickerSlot = nil
end

function M.openPicker(slot)
    M.hidePicker()
    if BG.SetListzhuangbei then BG.SetListzhuangbei(slot) end
    openPickerSlot = slot
end

function M.togglePicker(slot)
    if openPickerSlot == slot and BG.FrameZhuangbeiList and BG.FrameZhuangbeiList:IsShown() then
        M.closePicker()
    else
        M.openPicker(slot)
    end
end

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

function M.shortcutAction(isMasterLooter, button, altDown, controlDown, shiftDown)
    if altDown then
        if button == "LeftButton" then return "wishlist" end
        -- Always consume Alt+right-click through the guarded auction path.
        -- BG.StartAuction performs the authoritative permission check; falling
        -- through here would let the legacy plain-right-click branch delete the
        -- bill item for solo players or while leadership state is refreshing.
        if button == "RightButton" then return "auction" end
        return nil
    end
    -- Editing a local preset is safe outside a group. Consume the shortcut
    -- before the legacy delete branch regardless of current loot authority.
    if controlDown and not shiftDown and button == "RightButton" then
        return "leader-price"
    end
    return nil
end

function M.isLooted(wishItemId, recordedItemIds)
    if type(wishItemId) ~= "number" then return false end
    for _, itemId in ipairs(recordedItemIds or {}) do
        if itemId == wishItemId then return true end
    end
    return false
end

-- A dedicated second line preserves the item name, icon and level bounds.
-- Rows reserve badge space even when empty, so changing priority never reflows.
local PRIORITY_MARK_HEIGHT = 14
local SLOT_ROW_PITCH = 36
local PRIORITY_LINE_KEY = "心愿优先级：%s（%s）"
local PRIORITY_LINE_PLAIN_KEY = "心愿优先级：%s"
local WHEEL_HINT_KEY = "滚轮切换心愿优先级"

function M.priorityTooltipLines(priority, L)
    local wishlist = BG.BGNext and BG.BGNext.Wishlist
    if not wishlist or not wishlist.priorityTagKey then
        return nil
    end
    local function translate(key)
        return L and L[key] or key
    end
    local tag = translate(wishlist.priorityTagKey(priority))
    local name = translate(wishlist.priorityNameKey(priority))
    local label
    if tag == name then
        label = string.format(translate(PRIORITY_LINE_PLAIN_KEY), name)
    else
        label = string.format(translate(PRIORITY_LINE_KEY), tag, name)
    end
    return { label, translate(wishlist.priorityTipKey(priority)), translate(WHEEL_HINT_KEY) }
end

-- Computes where one difficulty header block sits in the wishlist grid. Pure
-- data (no frames, no WoW calls) so the layout is testable in plain Lua.
--
-- Returns a descriptor with:
--   .point         point on this difficulty's own header frame
--   .relative      "main" for the first block, or { index, anchor } referencing
--                  the previous block's bottomFirst boss slot or its headerLast
--   .relativePoint point on the referenced frame
--   .x, .y         offset
--
-- Layout contract:
--   1 difficulty   -> single block top-left
--   2 difficulties -> stacked vertically
--   3 difficulties -> stacked vertically (retail N/H/M; never a second column)
--   4 difficulties -> 2x2 grid (WLK 10/25 N/H; rightward only on index 3)
function M.difficultyAnchor(difficultyIndex, difficultyCount)
    if difficultyIndex == 1 then
        return { point = "TOPLEFT", relative = "main", relativePoint = "TOPLEFT", x = 10, y = -60 }
    end
    if difficultyIndex == 2 or (difficultyCount == 4 and difficultyIndex == 4) then
        return {
            point = "TOPRIGHT",
            relative = { index = difficultyIndex - 1, anchor = "bottomFirst" },
            relativePoint = "TOPLEFT", x = -20, y = -46,
        }
    end
    if difficultyIndex == 3 then
        if difficultyCount == 3 then
            return {
                point = "TOPRIGHT",
                relative = { index = difficultyIndex - 1, anchor = "bottomFirst" },
                relativePoint = "TOPLEFT", x = -20, y = -46,
            }
        end
        return {
            point = "TOPLEFT",
            relative = { index = 1, anchor = "headerLast" },
            relativePoint = "TOPRIGHT", x = 20, y = 0,
        }
    end
    return nil
end

function M.gridContentHeight(difficultyCount, bossCount)
    local rows = difficultyCount == 4 and 2 or difficultyCount
    return (rows - 1) * (bossCount * SLOT_ROW_PITCH + 31)
        + bossCount * SLOT_ROW_PITCH + 24
end

local function runtimeReady()
    return ns and BG.Init and BG.BGNext.Wishlist
end

if runtimeReady() then
    local wishlist = BG.BGNext.Wishlist
    local hopeMaxn = ns.HopeMaxn
    local hopeMaxb = ns.HopeMaxb
    local hopeMaxi = ns.HopeMaxi
    local maxb = ns.Maxb
    local L = ns.L or setmetatable({}, { __index = function(_, key) return key end })

    -- Three distinct tiers without changing the item's own quality color:
    -- backup (slate blue) < normal/second BiS (lavender) < core/BiS (gold).
    local priorityMarkColors = {
        core = { 1, 0.82, 0.35 },
        normal = { 0.76, 0.62, 0.94 },
        backup = { 0.48, 0.60, 0.70 },
    }

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

    local function resolveDrop(itemId, raidId, preferredDifficultyIndex, preferredBossIndex)
        local difficulties = BG.difficultyTable and BG.difficultyTable[raidId]
        local raidLoot = BG.Loot and BG.Loot[raidId]
        if not difficulties or not raidLoot then return nil end
        return wishlist.resolveDrop(itemId, difficulties, raidLoot, hopeMaxb[raidId] or 0, sameItem,
            preferredDifficultyIndex, preferredBossIndex)
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

    local function recordedRaidItems(raidId)
        local result = {}
        local raidFrame = BG.Frame and BG.Frame[raidId]
        if not raidFrame then return result end
        for bossIndex = 1, maxb[raidId] or 0 do
            local boss = raidFrame["boss" .. bossIndex]
            local slotCount = BG.GetMaxi and BG.GetMaxi(raidId, bossIndex) or 0
            for slotIndex = 1, slotCount do
                local cell = boss and boss["zhuangbei" .. slotIndex]
                local itemId = cell and wishlist.itemIdFromValue(cell:GetText())
                if itemId then
                    result[#result + 1] = BG.GetLeiTingItem and BG.GetLeiTingItem(itemId, raidId) or itemId
                end
            end
        end
        return result
    end

    local function slotPriority(slot)
        local root, realmId, player, raidId = context(slot.FB)
        local record = wishlist.getSlotRecord(root, realmId, player, raidId, slot.hopenandu, slot.bossnum, slot.i)
        return record and record.priority or nil
    end

    local function updateSlotPriorityMark(slot)
        local priority = slot.itemId and slotPriority(slot) or nil
        if priority then
            local color = priorityMarkColors[priority]
            local mark = slot.priorityMark
            mark.label:SetText(L[wishlist.priorityTagKey(priority)])
            mark.label:SetTextColor(color[1], color[2], color[3])
            mark.background:SetColorTexture(color[1], color[2], color[3], 0.18)
            mark:SetWidth(math.max(36, mark.label:GetStringWidth() + 12))
            slot.priorityMark:Show()
        else
            slot.priorityMark:Hide()
        end
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
        updateSlotPriorityMark(slot)
        if BG.UpdateFilter then BG.UpdateFilter(slot) end
        if slot.looted then
            local canonicalItemId = itemId
            if canonicalItemId and BG.GetLeiTingItem then
                canonicalItemId = BG.GetLeiTingItem(canonicalItemId, slot.FB)
            end
            slot.looted:SetShown(M.isLooted(canonicalItemId, recordedRaidItems(slot.FB)))
        end
    end

    local function showSlotTooltip(slot)
        GameTooltip:SetOwner(slot, BG.ButtonIsInRight and BG.ButtonIsInRight(slot) and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(slot.itemId)
        GameTooltip:AddLine("右键取消心愿装备", 0.5, 1, 0.5, true)
        local priority = slotPriority(slot)
        local lines = priority and M.priorityTooltipLines(priority, L) or nil
        if lines then
            GameTooltip:AddLine(lines[1], 0.95, 0.85, 0.55, true)
            GameTooltip:AddLine(lines[2], 0.7, 0.7, 0.7, true)
            GameTooltip:AddLine(lines[3], 0.5, 0.8, 1, true)
        end
        GameTooltip:Show()
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
        local location = resolveDrop(itemId, raidId, slot.hopenandu, slot.bossnum)
        if not location or location.difficultyIndex ~= slot.hopenandu or location.bossIndex ~= slot.bossnum then
            return false
        end
        -- Re-confirming the same item keeps its priority; a genuinely new item
        -- starts at backup. Legacy decoding still treats plain IDs as normal.
        local existing = wishlist.getSlotRecord(root, realmId, player, raidId, slot.hopenandu, slot.bossnum, slot.i)
        local priority = existing and existing.itemId == itemId and existing.priority or "backup"
        wishlist.setSlot(root, realmId, player, raidId, limitsFor(raidId), slot.hopenandu, slot.bossnum, slot.i,
            itemId, priority)
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
        local rowGap = bossIndex == 1 and 1 or SLOT_ROW_PITCH - 20
        slot:SetPoint("TOPLEFT", anchor, slotIndex == 1 and "BOTTOMLEFT" or "TOPLEFT", xOffset or 0, slotIndex == 1 and -rowGap or 0)
        slot:SetAutoFocus(false)
        if BG.SetEditStickyFocus then BG.SetEditStickyFocus(slot) end
        slot.FB, slot.hopenandu, slot.bossnum, slot.i = raidId, difficultyIndex, bossIndex, slotIndex
        slot.icon = slot:CreateTexture(nil, "ARTWORK")
        slot.icon:SetPoint("LEFT", -22, 0)
        slot.icon:SetSize(16, 16)
        local mark = CreateFrame("Frame", nil, slot)
        mark:SetPoint("TOPLEFT", slot, "BOTTOMLEFT", 0, -1)
        mark:SetSize(36, PRIORITY_MARK_HEIGHT)
        mark:EnableMouse(false)
        mark.background = mark:CreateTexture(nil, "BACKGROUND")
        mark.background:SetAllPoints(mark)
        mark.label = mark:CreateFontString(nil, "OVERLAY")
        mark.label:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        mark.label:SetPoint("CENTER", mark, "CENTER", 0, 0)
        mark:Hide()
        slot.priorityMark = mark
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
            elseif button == "LeftButton" and not IsShiftKeyDown() and not IsControlKeyDown() then
                if self:HasFocus() then M.togglePicker(self) end
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
        slot:SetScript("OnMouseWheel", function(self, delta)
            if not self.itemId then return end
            local root, realmId, player, raidId = context(self.FB)
            if wishlist.setSlotPriority(root, realmId, player, raidId, self.hopenandu, self.bossnum, self.i,
                wishlist.cyclePriority(slotPriority(self), delta)) then
                updateSlotPriorityMark(self)
                if GameTooltip:IsOwned(self) then showSlotTooltip(self) end
            end
        end)
        slot:SetScript("OnEnter", function(self)
            self.hover:Show()
            if self.itemId then
                showSlotTooltip(self)
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
            M.openPicker(self)
            local boss = BG.HopeFrame[self.FB]
                and BG.HopeFrame[self.FB]["nandu" .. self.hopenandu]
                and BG.HopeFrame[self.FB]["nandu" .. self.hopenandu]["boss" .. self.bossnum]
            local nextSlot = boss and boss["zhuangbei" .. (self.i + 1)] or nil
            BG.lastfocuszhuangbei2 = nextSlot
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
            M.closePicker()
        end)
        slot:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            M.closePicker()
        end)
        return slot
    end

    local function createRaidGrid(raidId, parent)
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetAllPoints(parent)
        frame:Hide()
        -- Extra badge rows can exceed the viewport on multi-difficulty raids.
        -- Use the existing native scrollbar; no recurring work is added.
        local scroll = CreateFrame("ScrollFrame", nil, frame, BG.scrollTemplate)
        scroll:SetPoint("TOPLEFT", BG.MainFrame, "TOPLEFT", 0, -60)
        scroll:SetPoint("BOTTOMRIGHT", BG.MainFrame, "BOTTOMRIGHT", -28, 65)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(math.max(1, BG.MainFrame:GetWidth() - 28),
            M.gridContentHeight(hopeMaxn[raidId], hopeMaxb[raidId]))
        scroll:SetScrollChild(content)
        scroll:HookScript("OnSizeChanged", function(self, width)
            content:SetWidth(math.max(1, width))
        end)
        frame.scroll, frame.content = scroll, content
        BG.HopeFrame[raidId] = {}
        local bottomFirstByDifficulty, headerLastByDifficulty = {}, {}

        for difficultyIndex = 1, hopeMaxn[raidId] do
            local difficulty = content:CreateFontString(nil, "OVERLAY")
            local anchor = M.difficultyAnchor(difficultyIndex, hopeMaxn[raidId])
            local relative = content
            if anchor and type(anchor.relative) == "table" then
                relative = anchor.relative.anchor == "bottomFirst"
                    and bottomFirstByDifficulty[anchor.relative.index]
                    or headerLastByDifficulty[anchor.relative.index]
            end
            if anchor and relative then
                difficulty:SetPoint(anchor.point, relative, anchor.relativePoint, anchor.x,
                    anchor.relative == "main" and 0 or anchor.y)
            end
            difficulty:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
            difficulty:SetTextColor(1, 0.82, 0)
            difficulty:SetSize(100, 20)
            difficulty:SetJustifyH("RIGHT")
            difficulty:SetText(difficultyLabel(raidId, difficultyIndex))

            local headers, priorHeader = {}, difficulty
            for slotIndex = 1, hopeMaxi do
                local header = content:CreateFontString(nil, "OVERLAY")
                header:SetPoint("TOPLEFT", priorHeader, "TOPRIGHT", slotIndex == 1 and 20 or 26, 0)
                header:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                header:SetTextColor(1, 0.82, 0)
                header:SetSize(115, 20)
                header:SetJustifyH("LEFT")
                header:SetText("心愿" .. slotIndex)
                headers[slotIndex], priorHeader = header, header
            end
            headerLastByDifficulty[difficultyIndex] = headers[#headers]

            BG.HopeFrame[raidId]["nandu" .. difficultyIndex] = {}
            local priorFirstSlot
            for bossIndex = 1, hopeMaxb[raidId] do
                local boss = {}
                BG.HopeFrame[raidId]["nandu" .. difficultyIndex]["boss" .. bossIndex] = boss
                local rowAnchor = bossIndex == 1 and headers[1] or priorFirstSlot
                for slotIndex = 1, hopeMaxi do
                    local anchor = slotIndex == 1 and rowAnchor or boss["zhuangbei1"]
                    local xOffset = slotIndex == 1 and 0 or (115 + 26) * (slotIndex - 1)
                    local slot = createSlot(content, raidId, difficultyIndex, bossIndex, slotIndex, anchor, xOffset)
                    boss["zhuangbei" .. slotIndex] = slot
                end
                priorFirstSlot = boss.zhuangbei1
                local bossLabel = content:CreateFontString(nil, "OVERLAY")
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
            bottomFirstByDifficulty[difficultyIndex] = priorFirstSlot
        end

        function frame:Refresh()
            local root, realmId, player = context(raidId)
            for difficultyIndex = 1, hopeMaxn[raidId] do
                for bossIndex = 1, hopeMaxb[raidId] do
                    local writeIndex = 1
                    for slotIndex = 1, hopeMaxi do
                        local record = wishlist.getSlotRecord(root, realmId, player, raidId,
                            difficultyIndex, bossIndex, slotIndex)
                        local itemId = record and record.itemId or nil
                        if itemId then
                            if writeIndex ~= slotIndex then
                                wishlist.setSlot(root, realmId, player, raidId, limitsFor(raidId),
                                    difficultyIndex, bossIndex, writeIndex, itemId, record.priority)
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
        if not BG.MainFrame or not BG.Create_TabButton or not BG.BGNext.DB then return end
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
            M.closePicker()
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
        BG.HopeMainFrame:SetScript("OnHide", M.closePicker)
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
