return function(test)
    -- Build the real price-page frame tree under a minimal WoW mock and drive
    -- its OnSizeChanged / mode-switch / OnHide wiring. The catalog re-filter is
    -- counted through a spied Catalog.filter so the assertions can prove the
    -- viewport is laid out once per animation burst, not once per frame.
    local watchedGlobals = {
        "BG", "CreateFrame", "BIAOGE_TEXT_FONT", "GetItemInfo", "GetItemQualityColor",
        "BiaoGe", "C_Timer", "GameTooltip", "CANCEL", "YES", "NO",
        "StaticPopupDialogs", "StaticPopup_Show",
    }
    local originals = {}
    for _, name in ipairs(watchedGlobals) do
        originals[name] = rawget(_G, name)
    end
    local function setGlobal(name, value) rawset(_G, name, value) end

    local ok, err = pcall(function()
        local filterCount = 0
        local scheduled = {}
        local function flush()
            for _, entry in ipairs(scheduled) do entry.callback() end
        end

        local function makeFrame()
            local frame = {
                points = {}, scripts = {}, children = {},
                text = "", shown = true, width = 0, height = 0, stringWidth = 0,
            }
            -- Unknown methods (SetBackdrop, SetOrientation, SetMinMaxValues, ...)
            -- are cheap no-ops so the page shell can build without a full WoW API.
            setmetatable(frame, { __index = function() return function() end end })
            function frame:SetPoint() self.points[#self.points + 1] = true end
            function frame:SetSize(w, h) self.width, self.height = w, h end
            function frame:SetWidth(w) self.width = w end
            function frame:SetHeight(h) self.height = h end
            function frame:GetWidth() return self.width end
            function frame:GetHeight() return self.height end
            function frame:SetText(value) self.text = value end
            function frame:GetText() return self.text end
            function frame:SetShown(value) self.shown = value and true or false end
            function frame:Show()
                self.shown = true
                if self.scripts.OnShow then self.scripts.OnShow(self) end
            end
            function frame:Hide()
                local wasShown = self.shown
                self.shown = false
                if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
            end
            function frame:IsShown() return self.shown end
            function frame:SetScript(name, handler) self.scripts[name] = handler end
            function frame:GetScript(name) return self.scripts[name] end
            function frame:GetFontString() return makeFrame() end
            function frame:GetThumbTexture() return makeFrame() end
            function frame:GetStringWidth() return self.stringWidth end
            function frame:CreateFontString()
                local child = makeFrame()
                self.children[#self.children + 1] = child
                return child
            end
            function frame:CreateTexture()
                local child = makeFrame()
                self.children[#self.children + 1] = child
                return child
            end
            function frame:ClearAllPoints() self.points = {} end
            function frame:Disable() self.disabled = true end
            function frame:Enable() self.disabled = false end
            return frame
        end

        setGlobal("CreateFrame", function(_, _, parent)
            local frame = makeFrame()
            if parent and parent.children then parent.children[#parent.children + 1] = frame end
            return frame
        end)
        setGlobal("BIAOGE_TEXT_FONT", "Fonts\\FRIZQT__.TTF")
        setGlobal("GetItemInfo", function() return nil end)
        setGlobal("GetItemQualityColor", function() return 1, 1, 1 end)
        setGlobal("C_Timer", {
            -- Debounce uses a one-shot After; tests queue callbacks and flush
            -- them manually so bursts can be exercised without real frames.
            After = function(delay, callback)
                scheduled[#scheduled + 1] = { delay = delay, callback = callback }
            end,
        })
        setGlobal("CANCEL", "取消")
        setGlobal("YES", "是")
        setGlobal("NO", "否")
        setGlobal("StaticPopupDialogs", {})
        setGlobal("StaticPopup_Show", function() end)
        setGlobal("GameTooltip", {
            SetOwner = function() end, SetHyperlink = function() end, SetItemByID = function() end,
        })

        BG = { BGNext = {} }
        local allItems = {}
        for i = 1, 60 do allItems[i] = { itemId = 1000 + i, name = "item" .. i, groupId = "boss1" } end
        BG.BGNext.AuctionPriceCatalog = {
            build = function()
                return { byItem = {}, groups = { { id = "boss1", name = "首领", items = {} } } }
            end,
            filter = function()
                filterCount = filterCount + 1
                return allItems
            end,
        }
        BG.BGNext.AuctionPriceStore = {
            MAX_MONEY = 99999999,
            ensureLeaderRaid = function() return { activePresetId = "p1", presets = { p1 = { basePrice = 100, itemPrices = {} } } } end,
            getPersonalPrice = function() return nil end,
            countPersonalPrices = function() return 0 end,
            clearLeaderItemPrice = function() end,
            clearPersonalPrice = function() end,
        }
        BG.BGNext.AuctionPriceCodec = {}
        BG.BGNext.DB = {}
        BG.BGNext.UIStyle = {
            applySurface = function() end,
            isPreviewEnabled = function() return false end,
            setButtonState = function() end,
            applyText = function() end,
        }

        BG.MainFrame = makeFrame()
        BG.MainFrame:SetSize(1280, 800)
        BG.Create_TabButton = function() end
        BG.CreateButton = function(parent)
            local button = makeFrame()
            if parent and parent.children then parent.children[#parent.children + 1] = button end
            return button
        end
        BG.scrollTemplate = "UIPanelScrollFrameTemplate"
        BG.editTemplate = nil
        BG.FBtable = { "ICC" }
        BG.FB1 = "ICC"
        BG.Boss = {}
        BG.Loot = {}
        BG.difficultyTable = nil
        BG.realmID = 123
        BG.playerName = "Piti"
        BG.GetFBinfo = function() return "ICC" end
        BG.SendSystemMessage = function() end
        BiaoGe = { options = { alpha = 1 }, Auction = {} }

        local initCallback
        BG.Init2 = function(callback) initCallback = callback end

        local chunk = assert(loadfile("Core/BGNext/AuctionPriceUI.lua"))
        local ui = chunk("BGNEXT", { L = {} })

        test.eq(type(ui), "table", "price page module loads")
        test.eq(type(initCallback), "function", "the page registers its frame builder")

        initCallback()
        local main = BG.PricePresetMainFrame
        test.eq(main ~= nil, true, "the page frame is built")

        -- Bring the page to a shown state at a known content height, then start
        -- from a clean spy for each scenario.
        main.itemScroll.height = 576
        main:Show()

        local function reset()
            filterCount = 0
            scheduled = {}
        end

        -- 1. Coalescing: thirty animation-frame size changes arm cheap one-shot
        --    debounce callbacks but trigger exactly one catalog re-filter, and
        --    that merged layout reads the final window size.
        reset()
        for i = 1, 30 do
            main.itemScroll.height = 500 - i
            BG.MainFrame:SetWidth(1200 + i)
            main.scripts.OnSizeChanged(main)
        end
        test.eq(#scheduled, 30, "every size change schedules a cheap debounce callback")
        test.eq(scheduled[1].delay > 0, true, "the layout callback is debounced, not immediate")
        flush()
        test.eq(filterCount, 1, "thirty size changes coalesce into one catalog refresh")
        local finalWidth = BG.MainFrame:GetWidth()
        local finalHeight = main.itemScroll.height
        local expectedWidth = ui.viewportLayout(finalWidth, finalHeight).columnWidth * 2 + 12
        test.eq(main.itemScroll.width, expectedWidth, "the merged relayout reads the final window size")

        -- 2. Mode switch recomputes capacity: a wrapped localized description
        --    shortens the content area, and switching modes re-derives the
        --    capacity so rows beyond it are hidden instead of entering the
        --    bottom reserve.
        reset()
        local personalButton = main.modeBar.children[2]
        test.eq(personalButton ~= nil, true, "the personal mode button exists")
        main.itemScroll.height = 288
        personalButton.scripts.OnClick(personalButton)
        test.eq(#scheduled, 1, "mode switch arms exactly one relayout")
        flush()
        test.eq(filterCount, 2, "mode switch refreshes rows once and relayouts once")
        local shortLayout = ui.viewportLayout(BG.MainFrame:GetWidth(), main.itemScroll.height)
        test.eq(main.rows[shortLayout.capacity].shown, true, "rows within the recomputed capacity stay visible")
        test.eq(main.rows[shortLayout.capacity + 1].shown, false, "rows beyond the recomputed capacity are hidden")

        -- 3. No stale callback after hide: a pending debounced relayout is
        --    invalidated when the page hides, so nothing re-filters the catalog
        --    while the page is closed.
        reset()
        main.itemScroll.height = 400
        main.scripts.OnSizeChanged(main)
        test.eq(#scheduled, 1, "a size change arms a pending relayout")
        main:Hide()
        flush()
        test.eq(filterCount, 0, "a hidden page never re-filters the catalog")
    end)

    for _, name in ipairs(watchedGlobals) do
        rawset(_G, name, originals[name])
    end
    for _, name in ipairs(watchedGlobals) do
        test.eq(rawget(_G, name), originals[name], "relayout suite restores global: " .. name)
    end
    if not ok then error(err, 0) end
end
