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
        function frame:HookScript(name, handler) self.scripts[name] = handler end
        function frame:SetScrollChild(child) self.scrollChild = child end
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
        function frame:SetTextColor(r, g, b) self.color = { r, g, b } end
        -- Mock measurement only; actual translated glyph rendering is a game check.
        function frame:GetStringWidth() return #self.text * 6 end
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
        BG.MainFrame:SetSize(1275, 750)
        BG.Create_TabButton = function() end
        BG.CreateButton = function() return makeFrame("Button") end
        BG.FBtable = { "ICC", "TRIPLE", "QUAD", "SINGLE" }
        BG.FB1 = "ICC"
        BG.Boss = { ICC = {} }
        BG.difficultyTable = { TRIPLE = { "N", "H", "M" }, QUAD = { "10N", "25N", "10H", "25H" } }
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
            L = setmetatable({}, { __index = function(_, key) return key end }),
            HopeMaxn = { ICC = 2, TRIPLE = 3, QUAD = 4, SINGLE = 1 },
            HopeMaxb = { ICC = 2, TRIPLE = 15, QUAD = 15, SINGLE = 15 },
            HopeMaxi = 2,
            Maxb = { ICC = 2, TRIPLE = 15, QUAD = 15, SINGLE = 15 },
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

        -- 2. priority is readable without hovering or distinguishing colors.
        local mark = slot.priorityMark
        test.eq(mark ~= nil, true, "compact priority mark exists")
        test.eq(mark.label ~= nil, true, "priority has a separate text badge")
        local anchor = mark.points[1]
        test.eq(anchor.point, "TOPLEFT", "badge begins below the item field")
        test.eq(anchor.relative, slot, "badge belongs to its own item")
        test.eq(anchor.relativePoint, "BOTTOMLEFT", "badge has its own row")
        test.eq(anchor.x, 0, "badge aligns with the item field")
        test.eq(anchor.y, -1, "badge does not cover the field border")
        test.eq(mark.height, 14, "badge has room for readable text")
        local nextSlot = cells.nandu1.boss2.zhuangbei1
        test.eq(-nextSlot.points[1].y > mark.height - anchor.y, true,
            "next row reserves room for the entire badge")
        test.eq(grid.scroll.scrollChild, grid.content, "all rows belong to the scrollable content")
        test.eq(grid.content.height >= 2 * (20 + 2 * 36), true,
            "scroll content includes both difficulty blocks and badges")

        -- Resolve the actual applied vertical anchors, independently of the
        -- production height formula. Last badges must remain scroll-reachable.
        local function top(object, content)
            if object == content then return 0 end
            local point = assert(object.points[1], "anchored grid region")
            local y = top(point.relative, content) - (point.y or 0)
            if point.relativePoint:find("BOTTOM", 1, true) then
                y = y + point.relative.height
            end
            return y
        end
        for _, raidId in ipairs(BG.FBtable) do
            local raidGrid = BG["HopeFrame" .. raidId]
            for difficulty = 1, ns.HopeMaxn[raidId] do
                local previousBottom
                for boss = 1, ns.HopeMaxb[raidId] do
                    local cell = BG.HopeFrame[raidId]["nandu" .. difficulty]["boss" .. boss].zhuangbei1
                    local cellTop = top(cell, raidGrid.content)
                    local badgeBottom = top(cell.priorityMark, raidGrid.content) + cell.priorityMark.height
                    test.eq(not previousBottom or cellTop > previousBottom, true, "rows do not overlap badges")
                    test.eq(badgeBottom <= raidGrid.content.height, true, "last badge remains scroll-reachable")
                    previousBottom = badgeBottom
                end
            end
        end
        local quad = BG.HopeFrame.QUAD
        test.eq(top(quad.nandu1.boss1.zhuangbei1, BG.HopeFrameQUAD.content),
            top(quad.nandu3.boss1.zhuangbei1, BG.HopeFrameQUAD.content), "four difficulties align as two columns")
        test.eq(BG.HopeFrameTRIPLE.content.height > BG.MainFrame.height, true,
            "long lists retain all content rather than squeezing it into the viewport")
        grid.scroll.scripts.OnSizeChanged(grid.scroll, 1000)
        test.eq(grid.content.width, 1000, "scroll child width follows resized viewport")

        -- 3. dropped label keeps its upstream anchor and never overlaps the mark
        local looted = slot.looted
        test.eq(looted ~= nil, true, "dropped indicator still created")
        test.eq(looted.points[1].point, "RIGHT", "dropped label keeps its upstream anchor")
        test.eq(looted.height, lootedHeight, "dropped label keeps its upstream height")
        local lootedBottom = (slot.height + looted.height) / 2
        test.eq(slot.height - anchor.y > lootedBottom, true,
            "badge begins below the dropped label")
        grid:Refresh()
        test.eq(isHaveCalls > 0, true, "owned indicator still runs on refresh")

        -- 4. every occupied priority tier has a visible, distinct color
        wish.setSlot(BG.BGNext.DB, "realm", "A", "ICC", limits, 1, 1, 1, 7001)
        grid:Refresh()
        test.eq(slot.itemId, 7001, "refresh populates the slot item")
        test.eq(mark.shown, true, "second BiS has a visible mark too")
        test.eq(mark.label.text, "次BIS", "default priority is readable on the badge")
        local colorMark = mark.background
        test.eq(colorMark.color[3] > colorMark.color[1] and colorMark.color[1] > colorMark.color[2], true,
            "second BiS uses lavender")
        local normalColor = table.concat(colorMark.color, ",")

        -- 5. core shows the mark; the wheel keeps switching and updates it
        --    (cycle order: backup -> normal -> core)
        wish.setSlotPriority(BG.BGNext.DB, "realm", "A", "ICC", 1, 1, 1, "core")
        grid:Refresh()
        test.eq(mark.shown, true, "core priority shows the mark")
        test.eq(mark.label.text, "BIS", "core badge shows BIS")
        test.eq(colorMark.color[1] > 0.9 and colorMark.color[2] > 0.7, true, "core mark uses the warm emphasis color")
        slot.scripts["OnMouseWheel"](slot, -1)
        test.eq(wish.getSlotPriority(BG.BGNext.DB, "realm", "A", "ICC", 1, 1, 1), "normal",
            "wheel down moves core back to the default")
        test.eq(mark.shown, true, "second BiS stays visible after wheel change")
        test.eq(mark.label.text, "次BIS", "wheel updates the badge text immediately")
        test.eq(table.concat(colorMark.color, ","), normalColor, "wheel restores second BiS color")
        slot.scripts["OnMouseWheel"](slot, -1)
        test.eq(wish.getSlotPriority(BG.BGNext.DB, "realm", "A", "ICC", 1, 1, 1), "backup",
            "wheel down reaches backup")
        test.eq(mark.label.text, "备选", "backup badge shows its own label")
        test.eq(colorMark.color[3] > colorMark.color[1], true, "backup mark switches to the cool color")
        test.eq(mark.shown, true, "backup also shows its mark")
        test.eq(table.concat(colorMark.color, ",") ~= normalColor, true, "backup and second BiS are distinct")
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
        ns.L["次BIS"] = "2nd BiS"
        grid:Refresh()
        test.eq(mark.label.text, "2nd BiS", "badge uses the locale table")
        test.eq(mark.width >= mark.label:GetStringWidth() + 12, true,
            "translated badge text has measured horizontal padding")
        test.eq(mark.width <= slot.width, true, "English badge fits within its own column")
        ns.L["次BIS"] = nil
        BG.difficultyTable.ICC = { "N", "H" }
        BG.Loot = { ICC = { N = { boss1 = { 7001, 7002 } } } }
        slot:SetText("7002")
        slot.scripts.OnTextChanged(slot)
        test.eq(mark.label.text, "备选", "replacing an item starts at backup")
        slot.scripts.OnMouseWheel(slot, 1)
        test.eq(mark.label.text, "次BIS", "first step promotes backup to second BiS")
        slot.scripts.OnMouseWheel(slot, 1)
        slot.scripts.OnTextChanged(slot)
        test.eq(mark.label.text, "BIS", "confirming the same item preserves chosen priority")
        wish.clearSlot(BG.BGNext.DB, "realm", "A", "ICC", 1, 1, 1)
        grid:Refresh()
        test.eq(mark.shown, false, "empty slot has no priority color")
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
