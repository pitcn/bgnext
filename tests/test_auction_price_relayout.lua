return function(test)
    -- Build the real price-page frame tree under a minimal WoW mock and drive
    -- its OnSizeChanged / mode-switch / OnHide wiring with a deterministic,
    -- advancable fake clock. The catalog re-filter is counted through a spied
    -- Catalog.filter, so the assertions can prove:
    --   * a resize animation performs ZERO catalog scans (geometry only),
    --   * at most one debounce timer is pending at any time,
    --   * after every size event the shown rows stay inside the current
    --     content area and never intrude into the fixed bottom click region,
    --   * a mode switch rebuilds the cache exactly once and commits layout
    --     using the real wrapped-text height.
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
        -- ---- Deterministic fake clock ----
        local now = 0
        local timers = {}
        local timerCounter = 0
        local maxPending = 0
        -- `timers` is a map keyed by a monotonic timer id, so a fired timer's
        -- deleted slot never hides later live timers behind a nil hole the way
        -- an ipairs walk over a dense array would.
        local function pendingTimers()
            local n = 0
            for _ in pairs(timers) do
                n = n + 1
            end
            return n
        end
        local function advance(dt)
            now = now + dt
            while true do
                local id, best = nil, math.huge
                for tid, t in pairs(timers) do
                    if t.due <= now and t.due < best then
                        best = t.due
                        id = tid
                    end
                end
                if not id then break end
                local t = timers[id]
                timers[id] = nil
                t.cb()
            end
        end

        local filterCount = 0

        local function makeFrame()
            local frame = {
                points = {}, scripts = {}, children = {},
                text = "", shown = true, width = 0, height = 0, stringWidth = 0,
            }
            -- Unknown methods (SetBackdrop, SetOrientation, SetValueStep, ...)
            -- are cheap no-ops so the page shell can build without a full WoW API.
            -- Only uppercase method-like keys get a no-op; lowercase flag fields
            -- (e.g. `_refreshing`, `itemId`) must read back as nil so guards like
            -- `if self._refreshing then return end` behave like a real frame.
            setmetatable(frame, { __index = function(_, key)
                if type(key) == "string" and key:match("^%u") then
                    return function() end
                end
                return nil
            end })
            function frame:SetPoint(point, relTo, relPoint, x, y)
                self.points[#self.points + 1] = true
                if point == "TOPLEFT" and type(x) == "number" and type(y) == "number" then
                    self.posX, self.posY = x, y
                end
            end
            function frame:SetSize(w, h) self.width, self.height = w, h end
            function frame:SetWidth(w) self.width = w end
            function frame:SetHeight(h) self.height = h end
            function frame:GetWidth() return self.width end
            function frame:GetHeight() return self.height end
            function frame:SetText(value) self.text = value end
            function frame:GetText() return self.text end
            function frame:SetShown(value) self.shown = value and true or false end
            function frame:SetMinMaxValues(min, max) self.min, self.max = min, max end
            function frame:SetValue(value) self.value = value end
            function frame:GetValue() return self.value end
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
            -- The page uses a one-shot After for its debounce. The fake clock
            -- records the due time so tests can advance deterministically and
            -- interleave size events with callbacks at any frame rate.
            After = function(delay, callback)
                timerCounter = timerCounter + 1
                timers[timerCounter] = { due = now + delay, cb = callback }
                local n = pendingTimers()
                if n > maxPending then maxPending = n end
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

        local locales = {}
        local chunk = assert(loadfile("Core/BGNext/AuctionPriceUI.lua"))
        local ui = chunk("BGNEXT", { L = locales })

        test.eq(type(ui), "table", "price page module loads")
        test.eq(type(initCallback), "function", "the page registers its frame builder")

        initCallback()
        local main = BG.PricePresetMainFrame
        test.eq(main ~= nil, true, "the page frame is built")

        -- Assert every shown row stays inside the current content area and that
        -- rows beyond the derived capacity are hidden immediately.
        local function assertContained(contentHeight)
            local layout = ui.viewportLayout(BG.MainFrame:GetWidth(), contentHeight)
            local capacity = layout.capacity
            for i = 1, 60 do
                local row = main.rows[i]
                if row then
                    if i <= capacity then
                        test.eq(row.shown, true, "row " .. i .. " visible within capacity " .. capacity)
                        if row.posY ~= nil then
                            local bottom = -row.posY + 22
                            test.eq(bottom <= contentHeight, true,
                                "row " .. i .. " stays inside the " .. contentHeight .. "px content area")
                        end
                    else
                        test.eq(row.shown, false, "row " .. i .. " hidden beyond capacity " .. capacity)
                    end
                end
            end
        end

        local function resetClock()
            now = 0
            timers = {}
            timerCounter = 0
            maxPending = 0
            filterCount = 0
        end

        -- Bring the page to a shown, tall (980 logical height -> 60 rows) state.
        main.itemScroll.height = 756
        main:Show()
        test.eq(#main.rows, 60, "the tall content area grows the pool to 60 rows")

        -- 1. Low-FPS shrink (980 -> 810): one size event every 100 ms, so each
        --    50 ms debounce callback fires before the next event. The whole
        --    animation must perform ZERO catalog refreshes, keep at most one
        --    timer pending, and never leave out-of-bounds rows interactive.
        resetClock()
        for i = 1, 30 do
            local h = 756 - math.floor((170 * i) / 30)
            main.itemScroll.height = h
            main.scripts.OnSizeChanged(main)
            assertContained(h)
            test.eq(filterCount, 0, "no catalog re-filter during the shrink animation")
            advance(100)
        end
        test.eq(filterCount, 0, "the whole shrink animation performs zero catalog refreshes")
        test.eq(maxPending <= 1, true, "at most one timer is pending at any time")

        -- Reachability: all 60 items stay reachable by scrolling at the end.
        local shortLayout = ui.viewportLayout(BG.MainFrame:GetWidth(), 586)
        test.eq(shortLayout.capacity, 48, "the 810 content area yields 48 rows")
        test.eq(main.itemSlider.max, 60 - 48, "the slider reaches the last item")
        main.itemSlider.scripts.OnValueChanged(main.itemSlider, main.itemSlider.max)
        test.eq(main.rows[48].itemId, 1060, "scrolling to the end shows the last item")

        -- 2. Expand back (810 -> 980): grows the pool again without re-filtering
        --    and leaves every item reachable.
        resetClock()
        for i = 1, 30 do
            local h = 586 + math.floor((170 * i) / 30)
            main.itemScroll.height = h
            main.scripts.OnSizeChanged(main)
            assertContained(h)
            test.eq(filterCount, 0, "no catalog re-filter during the expand animation")
            advance(100)
        end
        test.eq(filterCount, 0, "the expand animation performs zero catalog refreshes")
        test.eq(main.rows[60].shown, true, "all 60 rows are visible after expanding")
        test.eq(main.rows[60].itemId, 1060, "the 60th item is populated after expanding")

        -- 3. High-FPS burst: a full shrink emitted back-to-back arms exactly one
        --    debounce timer and still keeps the geometry contained at every step.
        resetClock()
        for i = 1, 30 do
            local h = 756 - math.floor((170 * i) / 30)
            main.itemScroll.height = h
            main.scripts.OnSizeChanged(main)
            assertContained(h)
            test.eq(filterCount, 0, "no catalog re-filter during the burst")
        end
        test.eq(timerCounter, 1, "the whole burst schedules exactly one timer")
        test.eq(maxPending, 1, "at most one timer is pending")
        advance(50)
        test.eq(filterCount, 0, "the burst settle consumes the cache without re-filtering")
        test.eq(main.rows[49].shown, false, "the final shrink hides rows beyond capacity")

        -- 4. Hide/reopen: a pending settle is invalidated on hide (no re-filter),
        --    and reopening re-lays out once from the cached list.
        resetClock()
        main.itemScroll.height = 400
        main.scripts.OnSizeChanged(main)
        test.eq(pendingTimers(), 1, "a size change arms a pending settle")
        main:Hide()
        advance(100)
        test.eq(filterCount, 0, "a hidden page never re-filters the catalog")
        main.itemScroll.height = 300
        main:Show()
        test.eq(filterCount, 1, "reopening refreshes once")
        local reopened = ui.viewportLayout(BG.MainFrame:GetWidth(), 300)
        test.eq(main.rows[reopened.capacity].shown, true, "reopen lays out within capacity")
        test.eq(main.rows[reopened.capacity + 1].shown, false, "reopen hides rows beyond capacity")

        -- 5. Timer ownership (round-4 race): schedule the pre-hide settle, hide
        --    + reopen, schedule a new settle, then fire the OLD callback first.
        --    A stale callback must not clear the new generation's pending flag,
        --    so the following resize schedules no second current-generation
        --    timer and the final commit runs exactly once.
        resetClock()
        local itemInfoReads = 0
        setGlobal("GetItemInfo", function()
            itemInfoReads = itemInfoReads + 1
            return nil
        end)
        main.itemScroll.height = 400
        main.scripts.OnSizeChanged(main)
        test.eq(pendingTimers(), 1, "old settle armed")
        main:Hide()
        test.eq(pendingTimers(), 1, "old timer stays queued after hide")
        advance(0.02)
        main.itemScroll.height = 300
        main:Show()
        test.eq(filterCount, 1, "reopen refreshes once")
        main.scripts.OnSizeChanged(main)
        test.eq(pendingTimers(), 2, "old and new settle timers both queued")
        test.eq(timerCounter, 2, "exactly two settle timers scheduled before firing")
        local readsBeforeCommit = itemInfoReads
        advance(0.04) -- fires the OLD callback first (due 0.05 < new due 0.07)
        test.eq(pendingTimers(), 1, "old callback drained, new still pending")
        main.scripts.OnSizeChanged(main)
        test.eq(timerCounter, 2, "stale callback cleared no pending: no second timer")
        test.eq(pendingTimers(), 1, "still exactly one current-generation timer")
        advance(0.06)
        test.eq(pendingTimers(), 0, "all settle timers drained")
        test.eq(itemInfoReads - readsBeforeCommit, 24, "exactly one final relayout commit")

        -- 6. Mode switch with a long localized description that wraps and
        --    shortens the content area: the description is updated, the cache is
        --    rebuilt exactly once, and the settle commits with the real height.
        resetClock()
        local personalButton = main.modeBar.children[2]
        test.eq(personalButton ~= nil, true, "the personal mode button exists")
        locales[ui.DESCRIPTIONS.personal] = "我的心理价：用于参团时自动填入已保存的心理价，不会自动启用或发送。My psychological price is used to prefill saved expectations while raiding."
        personalButton.scripts.OnClick(personalButton)
        test.eq(main.description.text, locales[ui.DESCRIPTIONS.personal], "mode switch updates the description")
        test.eq(filterCount, 1, "mode switch rebuilds the cache exactly once")
        test.eq(pendingTimers(), 1, "mode switch arms exactly one settle")
        main.itemScroll.height = 288
        advance(100)
        test.eq(filterCount, 1, "the settle commits layout without re-filtering")
        local wrapped = ui.viewportLayout(BG.MainFrame:GetWidth(), 288)
        test.eq(wrapped.capacity, 24, "the wrapped height yields 24 rows")
        test.eq(main.rows[24].shown, true, "rows within the wrapped capacity stay visible")
        test.eq(main.rows[25].shown, false, "rows beyond the wrapped capacity are hidden")
    end)

    for _, name in ipairs(watchedGlobals) do
        rawset(_G, name, originals[name])
    end
    for _, name in ipairs(watchedGlobals) do
        test.eq(rawget(_G, name), originals[name], "relayout suite restores global: " .. name)
    end
    if not ok then error(err, 0) end
end
