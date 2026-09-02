return function(test)
    -- Frame-mock harness: drives the real wishlist UI init callback with mock
    -- frames and asserts the runtime-applied anchors, insets and control
    -- bounds — including the upstream owned/dropped indicators — instead of
    -- estimating glyph widths.
    -- Every global this suite swaps out is listed explicitly and snapshotted
    -- before any swap, so the original value — including nil — is restored
    -- afterwards and verified, keeping later suites in tests/run.lua
    -- unpolluted.
    local watchedGlobals = {
        "BG",
        "CreateFrame",
        "BIAOGE_TEXT_FONT",
        "GetItemInfo",
        "GetCursorInfo",
        "SetCursor",
        "GameTooltip",
    }
    local originalValues = {}
    for _, name in ipairs(watchedGlobals) do
        originalValues[name] = rawget(_G, name)
    end
    local function setGlobal(name, value)
        rawset(_G, name, value)
    end
    local function restoreGlobals()
        for _, name in ipairs(watchedGlobals) do
            rawset(_G, name, originalValues[name])
        end
    end

    local function makeFrame(kind)
        local frame = {
            kind = kind,
            points = {},
            scripts = {},
            children = {},
            text = "",
            width = 0,
            height = 0,
            shown = true,
        }
        function frame:SetPoint(point, relative, relativePoint, x, y)
            self.points[#self.points + 1] = {
                point = point, relative = relative, relativePoint = relativePoint, x = x, y = y,
            }
        end
        function frame:ClearAllPoints() self.points = {} end
        function frame:SetAllPoints(target)
            self.points[#self.points + 1] = { point = "ALL", relative = target, relativePoint = "ALL" }
        end
        function frame:SetSize(width, height) self.width, self.height = width, height end
        function frame:SetWidth(width) self.width = width end
        function frame:SetHeight(height) self.height = height end
        function frame:SetScript(name, handler) self.scripts[name] = handler end
        function frame:SetText(value) self.text = value end
        function frame:GetText() return self.text end
        function frame:SetCursorPosition() end
        function frame:HighlightText() end
        function frame:ClearHighlightText() end
        function frame:SetAutoFocus() end
        function frame:SetMultiLine() end
        function frame:SetTextInsets(left, right, top, bottom)
            self.insets = { left = left, right = right, top = top, bottom = bottom }
        end
        function frame:SetFont() end
        function frame:SetTextColor() end
        function frame:SetJustifyH() end
        function frame:SetColorTexture(r, g, b) self.color = { r, g, b } end
        function frame:SetTexture(value) self.texture = value end
        function frame:Show() self.shown = true end
        function frame:Hide() self.shown = false end
        function frame:SetShown(value) self.shown = value and true or false end
        function frame:IsShown() return self.shown end
        function frame:SetFrameLevel() end
        function frame:SetFocus() end
        function frame:ClearFocus() end
        function frame:HasFocus() return false end
        function frame:EnableMouse() end
        function frame:SetBackdrop() end
        function frame:SetBackdropColor() end
        function frame:SetBackdropBorderColor() end
        function frame:GetFontString()
            local label = makeFrame("FontString")
            label.width = 60
            return label
        end
        function frame:GetWidth() return self.width end
        function frame:GetHeight() return self.height end
        function frame:CreateTexture()
            local texture = makeFrame("Texture")
            self.children[#self.children + 1] = texture
            return texture
        end
        function frame:CreateFontString()
            local label = makeFrame("FontString")
            self.children[#self.children + 1] = label
            return label
        end
        return frame
    end

    local ok, err = pcall(function()
        setGlobal("BG", { BGNext = {} })
        local wish = dofile("Core/BGNext/Wishlist.lua")

        -- Upstream geometry mirrors: the dropped label anchors RIGHT, is
        -- vertically centered and 15px high (Core/function2.lua BG.LootedText).
        local lootedWidth, lootedHeight = 45, 15
        local isHaveCalls = 0
        local tooltipOwned = false
        local tooltipLines = {}

        setGlobal("CreateFrame", function(_, _, parent)
            local frame = makeFrame("Frame")
            if parent and parent.children then
                parent.children[#parent.children + 1] = frame
            end
            return frame
        end)
        setGlobal("BIAOGE_TEXT_FONT", "Fonts\\FRIZQT__.TTF")
        setGlobal("GetItemInfo", function() return nil end)
        setGlobal("GetCursorInfo", function() return nil end)
        setGlobal("SetCursor", function() end)
        setGlobal("GameTooltip", {
            SetOwner = function() end,
            SetItemByID = function() end,
            AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = text end,
            Show = function() end,
            Hide = function() end,
            IsOwned = function() return tooltipOwned end,
        })

        BG.editTemplate = "MockEditBoxTemplate"
        BG.scrollTemplate = "MockScrollTemplate"
        BG.MainFrame = makeFrame("Frame")
        BG.Create_TabButton = function() end
        BG.CreateButton = function() return makeFrame("Button") end
        BG.FBtable = { "ICC" }
        BG.FB1 = "ICC"
        BG.Boss = { ICC = {} }
        BG.realmID = "realm"
        BG.playerName = "A"
        BG.BGNext.DB = { wishlist = {}, wishlistUnplaced = {} }
        BG.BGNext.Wishlist = wish
        BG.Init = function(callback) callback() end
        BG.SendSystemMessage = function() end
        BG.LootedText = function(slot)
            local looted = makeFrame("Frame")
            looted:SetPoint("RIGHT", 0, 0)
            looted:SetSize(lootedWidth, lootedHeight)
            slot.looted = looted
        end
        BG.IsHave = function() isHaveCalls = isHaveCalls + 1 end

        local limits = { difficulties = 2, bosses = 2, slots = 2 }
        local ns = {
            HopeMaxn = { ICC = 2 },
            HopeMaxb = { ICC = 2 },
            HopeMaxi = 2,
            Maxb = { ICC = 2 },
        }

        local chunk = assert(loadfile("Core/BGNext/WishlistUI.lua"))
        chunk("BGNEXT", ns)

        local cells = BG.HopeFrame and BG.HopeFrame.ICC
        test.eq(cells ~= nil, true, "wishlist cell table was created")
        local slot = cells["nandu1"]["boss1"]["zhuangbei1"]
        local grid = BG.HopeFrameICC
        test.eq(type(grid.Refresh), "function", "grid exposes its refresh entry point")
        test.eq(slot ~= nil, true, "wishlist slot was created")
        test.eq(slot.width, 115, "slot keeps its upstream width")
        test.eq(slot.height, 20, "slot keeps its upstream height")

        -- 1. the item name region is untouched: no inset reservation at all
        test.eq(slot.insets, nil, "item text keeps the template insets (no reserved strip)")

        -- 2. runtime priority mark anchors and bounds
        local mark = slot.priorityMark
        test.eq(mark ~= nil, true, "compact priority mark exists")
        local bottomLeft, bottomRight
        for _, point in ipairs(mark.points) do
            if point.point == "BOTTOMLEFT" then bottomLeft = point end
            if point.point == "BOTTOMRIGHT" then bottomRight = point end
        end
        test.eq(bottomLeft ~= nil and bottomRight ~= nil, true, "mark spans the slot bottom edge")
        test.eq(bottomLeft.relative, slot, "mark is anchored to its own slot")
        test.eq(bottomLeft.x, 0, "mark starts at the slot edge")
        test.eq(bottomLeft.y, 0, "mark sits on the bottom edge")
        test.eq(bottomRight.y, 0, "mark bottom edge is level")
        test.eq(mark.height, 2, "mark stays a thin underline")
        local markBottom = slot.height - mark.height - bottomLeft.y
        local markTop = slot.height - bottomLeft.y

        -- 3. dropped label keeps its upstream anchor and never overlaps the mark
        local looted = slot.looted
        test.eq(looted ~= nil, true, "dropped indicator still created")
        test.eq(looted.points[1].point, "RIGHT", "dropped label keeps its upstream anchor")
        test.eq(looted.height, lootedHeight, "dropped label keeps its upstream height")
        local lootedTop = (slot.height + looted.height) / 2
        test.eq(markBottom >= lootedTop, true,
            "priority mark stays clear of the dropped label: mark bottom " ..
            markBottom .. " vs label top " .. lootedTop)
        test.eq(markTop > lootedTop, true, "mark occupies only the band above the label")
        grid:Refresh()
        test.eq(isHaveCalls > 0, true, "owned indicator still runs on refresh")

        -- 4. the default priority shows no mark
        wish.setSlot(BG.BGNext.DB, "realm", "A", "ICC", limits, 1, 1, 1, 7001)
        grid:Refresh()
        test.eq(slot.itemId, 7001, "refresh populates the slot item")
        test.eq(mark.shown, false, "default priority shows no mark")

        -- 5. core shows the mark; the wheel keeps switching and updates it
        --    (cycle order: backup -> normal -> core)
        wish.setSlotPriority(BG.BGNext.DB, "realm", "A", "ICC", 1, 1, 1, "core")
        grid:Refresh()
        test.eq(mark.shown, true, "core priority shows the mark")
        test.eq(mark.color[1] > 0.9 and mark.color[2] > 0.7, true, "core mark uses the warm emphasis color")
        slot.scripts["OnMouseWheel"](slot, -1)
        test.eq(wish.getSlotPriority(BG.BGNext.DB, "realm", "A", "ICC", 1, 1, 1), "normal",
            "wheel down moves core back to the default")
        test.eq(mark.shown, false, "default priority hides the mark again")
        slot.scripts["OnMouseWheel"](slot, -1)
        test.eq(wish.getSlotPriority(BG.BGNext.DB, "realm", "A", "ICC", 1, 1, 1), "backup",
            "wheel down reaches backup")
        test.eq(mark.color[3] > mark.color[1], true, "backup mark switches to the cool color")
        slot.scripts["OnMouseWheel"](slot, 1)
        test.eq(wish.getSlotPriority(BG.BGNext.DB, "realm", "A", "ICC", 1, 1, 1), "normal",
            "wheel up steps backup up to normal")
        slot.scripts["OnMouseWheel"](slot, 1)
        test.eq(wish.getSlotPriority(BG.BGNext.DB, "realm", "A", "ICC", 1, 1, 1), "core",
            "wheel up returns to core")

        -- 6. the tooltip carries the full name and explanation at runtime
        grid:Refresh()
        tooltipLines = {}
        slot.scripts["OnEnter"](slot)
        test.eq(tooltipLines[1], "右键取消心愿装备", "remove hint stays first")
        test.eq(tooltipLines[2], "心愿优先级：BIS（核心提升）", "tooltip names the full priority")
        test.eq(tooltipLines[3], "BIS：核心提升，最高优先级的毕业装备。", "tooltip explains the priority")
        test.eq(tooltipLines[4], "滚轮切换心愿优先级", "tooltip reminds the wheel shortcut")

        -- 7. the wheel refreshes a visible tooltip in place
        tooltipOwned = true
        tooltipLines = {}
        slot.scripts["OnMouseWheel"](slot, -1)
        test.eq(tooltipLines[2], "心愿优先级：次BIS（普通需求）", "visible tooltip re-renders after a wheel change")
        tooltipOwned = false
    end)

    restoreGlobals()
    -- The harness itself must clean up: every swapped global — including ones
    -- that were nil before this suite — is back to its original value.
    for _, name in ipairs(watchedGlobals) do
        test.eq(rawget(_G, name), originalValues[name], "runtime suite restores global: " .. name)
    end
    if not ok then
        error(err, 0)
    end
end
