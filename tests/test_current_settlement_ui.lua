local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

local function keys(columns)
    local list = {}
    for index, column in ipairs(columns) do
        list[index] = column.key
    end
    return table.concat(list, ",")
end

return function(test)
    BG = { BGNext = {} }
    local life = dofile("Core/BGNext/DataLifecycle.lua")
    local trade = dofile("Core/BGNext/CurrentTrade.lua")
    dofile("Core/BGNext/ReturnMarker.lua")
    local mail = dofile("Core/BGNext/CurrentMail.lua")
    dofile("Core/BGNext/CurrentSettlementView.lua")
    local ui = dofile("Core/BGNext/CurrentSettlementUI.lua")

    local function stubDate(_, t)
        return "t" .. tostring(t)
    end

    -- 1. the tables keep the familiar column order and are clearly scoped
    test.eq(keys(ui.columns("trade")), "item,player,amount,time,status", "trade column order")
    test.eq(keys(ui.columns("mail")), "item,player,amount,time,direction,status", "mail column order")
    test.eq(ui.title("trade"), "交易记录（当前团）", "trade window title names the current raid scope")
    test.eq(ui.title("mail"), "邮件记录（当前团）", "mail window title names the current raid scope")

    -- 2. empty state
    local saved = {
        tradeHistory = { { player = "历史买家" } },
        mailHistory = { { player = "历史收件人" } },
        History = { ["raid-old"] = true },
        ICC = { auctionLog = { { maijia = "我" } } },
        options = { autoTrade = 1 },
    }
    local root = life.ensureRoot(saved)
    local rows, isEmpty = ui.rows(root, "trade", { now = 1000, dateFn = stubDate })
    test.eq(#rows, 0, "no trade rows in a fresh settlement")
    test.eq(isEmpty, true, "trade table reports the empty state")
    test.eq(type(ui.emptyText("trade")), "string", "trade empty state has text")
    test.eq(ui.emptyText("trade") ~= ui.emptyText("mail"), true, "each table has its own empty state text")

    -- 3. rows come only from the current settlement
    life.beginSettlement(root, "raid-a", 1000)
    test.eq(trade.append(root, {
        raidId = "raid-a", player = "甲", completed = true, status = "complete",
        myGold = 0, theirGold = 100, myItems = { { itemId = 11, quantity = 1 } }, time = 1100,
    }), true, "trade stored")
    test.eq(mail.append(root, {
        raidId = "raid-a", player = "乙", amount = 200, time = 1200, status = "sent", direction = "outgoing",
    }), true, "mail stored")

    rows, isEmpty = ui.rows(root, "trade", { now = 1300, dateFn = stubDate })
    test.eq(isEmpty, false, "trade table is populated")
    test.eq(#rows, 1, "only the settlement trade is listed")
    test.eq(rows[1].player, "甲", "trade row shows the counterparty")
    test.eq(rows[1].theirGold, 100, "trade row carries the received gold")
    test.eq(ui.goldText(rows[1]), "收到 100 / 寄出 0", "gold shows both directions, an explicit 0 included")
    test.eq(rows[1].timeText, "t1100", "trade row shows the time")

    local mailRows = ui.rows(root, "mail", { now = 1300, dateFn = stubDate })
    test.eq(#mailRows, 1, "only the settlement mail is listed")
    test.eq(mailRows[1].player, "乙", "mail row shows the counterparty")
    test.eq(mailRows[1].subject, nil, "mail row exposes no subject")
    test.eq(mailRows[1].body, nil, "mail row exposes no body")

    -- 4. status and direction are presented with distinct labels and colours
    test.eq(ui.statusLabel("trade", "complete") ~= ui.statusLabel("trade", "pending"), true,
        "success and pending are distinguishable")
    test.eq(ui.statusLabel("trade", "cancelled") ~= ui.statusLabel("trade", "failed"), true,
        "cancelled and failed are distinguishable")
    test.eq(type(ui.statusLabel("mail", "sent")), "string", "mail sent status has a label")
    test.eq(ui.directionLabel("outgoing") ~= ui.directionLabel("incoming"), true,
        "mail directions are distinguishable")
    test.eq(ui.quantityText(2), "×2", "a delivered count renders as a compact suffix")
    test.eq(ui.quantityText(1), "×1", "a single delivered item still shows its count")
    test.eq(ui.quantityText(nil), "", "a legacy record without quantity shows no suffix")
    test.eq(ui.quantityText(0), "", "a zero quantity shows no suffix")
    test.eq(ui.quantityText(1.5), "", "a fractional quantity shows no suffix")
    local r, g, b = ui.statusColor("trade", "complete")
    test.eq(r == 0 and g == 1 and b == 0, true, "success is green in the table")
    r, g, b = ui.statusColor("trade", "pending")
    test.eq(r == 1 and b == 0, true, "pending is gold in the table")
    r, g, b = ui.statusColor("trade", "failed")
    test.eq(r == 1 and g == 0 and b == 0, true, "failure is red in the table")

    -- 5. the tooltip is driven by the stored item id, nothing else
    test.eq(ui.tooltipTarget({ itemId = 11 }), 11, "tooltip uses the stored item id")
    test.eq(ui.tooltipTarget({ itemId = "11" }), nil, "tooltip refuses a non-numeric item id")
    test.eq(ui.tooltipTarget({}), nil, "a row without an item has no tooltip")
    test.eq(ui.tooltipTarget({ myItems = { { itemId = 22 } } }), 22, "tooltip uses a grouped outgoing item")
    test.eq(ui.tooltipTarget({ theirItems = { { itemId = 33 } } }), 33, "tooltip uses a grouped incoming item")

    -- 5b. trade facts and reconciliation state are two independently visible
    --     dimensions. A grouped trade whose exchange actually completed is
    --     labelled with its trade fact in front of its reconciliation state, so
    --     "completed but still pending" reads as both instead of only 待核对.
    local grouped = {
        completedKey = true, statusKey = "pending",
        myGold = 0, theirGold = 0,
        myItems = { { itemId = 11, quantity = 2 }, { itemId = 22, quantity = 1 } },
        theirItems = { { itemId = 33, quantity = 1 } },
    }
    local dual = ui.statusText("trade", grouped.statusKey, grouped.completedKey)
    test.eq(dual:find("已交易", 1, true) ~= nil, true,
        "a completed trade is labelled with its trade fact")
    test.eq(dual:find("待核对", 1, true) ~= nil, true,
        "a completed-but-pending trade still shows its reconciliation state")
    test.eq(ui.statusText("trade", "complete", true):find("已交易", 1, true) ~= nil, true,
        "the trade fact stays explicit even after reconciliation completes")
    test.eq(ui.statusText("trade", "pending", nil), ui.statusLabel("trade", "pending"),
        "a legacy row without a trade fact shows only its reconciliation state")
    test.eq(ui.statusText("trade", "pending", false), ui.statusLabel("trade", "pending"),
        "an unconfirmed grouped row shows only its reconciliation state")
    test.eq(ui.statusText("mail", "sent", true), ui.statusLabel("mail", "sent"),
        "mail rows never gain a trade fact")
    test.eq(ui.returnActionAvailable(root, {
        index = 1, completedKey = true, myItems = { { itemId = 11 } }, theirItems = {},
    }), false, "an outgoing delivery never offers the return action")
    test.eq(ui.returnActionAvailable(root, {
        index = 1, completedKey = true, myItems = {}, theirItems = { { itemId = 11 } },
    }), true, "a completed incoming item offers the return action")

    -- narrow-column text: the two dimensions stay two short, distinct labels
    -- rather than one ambiguous word, so they survive a compact status column.
    test.eq(dual ~= ui.statusLabel("trade", "pending"), true,
        "the combined label is distinct from the bare reconciliation label")

    -- explicit 0 and two-way gold are never collapsed or netted
    test.eq(ui.goldText({ theirGold = 0, myGold = 0 }), "收到 0 / 寄出 0",
        "two-way gold renders both directions even when both sides are zero")
    test.eq(ui.goldText({ theirGold = 200, myGold = 50 }), "收到 200 / 寄出 50",
        "two-way gold keeps both amounts and is never netted")
    test.eq(ui.goldText({ theirGold = 100 }), "收到 100",
        "an unknown side is omitted instead of invented")

    -- every delivered item in a grouped row is reachable from the tooltip, not
    -- only the first.
    local entries = ui.itemEntries(grouped)
    test.eq(#entries, 3, "a grouped row exposes every delivered item")
    test.eq(entries[1].itemId, 11, "the first outgoing item is listed first")
    test.eq(entries[1].direction, "outgoing", "outgoing items keep their direction")
    test.eq(entries[3].itemId, 33, "incoming items follow outgoing items")
    test.eq(entries[3].direction, "incoming", "incoming items keep their direction")
    local legacyEntries = ui.itemEntries({ itemId = 44, quantity = 1 })
    test.eq(#legacyEntries, 1, "a legacy row contributes its single item")
    test.eq(legacyEntries[1].itemId, 44, "a legacy row names its item")
    test.eq(legacyEntries[1].direction, nil, "a legacy row has no direction")
    local lines = ui.itemTooltipLines(grouped)
    test.eq(#lines, 3, "the item tooltip has one line per delivered item")
    test.eq(lines[1]:find("寄出", 1, true) ~= nil, true, "outgoing lines are prefixed")
    test.eq(lines[1]:find("item:11", 1, true) ~= nil, true, "the first item id is named")
    test.eq(lines[3]:find("收到", 1, true) ~= nil, true, "incoming lines are prefixed")
    test.eq(lines[3]:find("item:33", 1, true) ~= nil, true, "the last item id is named")

    -- the status tooltip explains each dimension, then the toggle hint
    local statusLines = ui.statusTooltipLines("trade", "pending", true)
    test.eq(#statusLines, 3, "the trade status tooltip explains both dimensions")
    test.eq(statusLines[1].text:find("交易已完成", 1, true) ~= nil, true,
        "the trade fact is explained first")
    test.eq(statusLines[2].text:find("核对状态", 1, true) ~= nil, true,
        "the reconciliation dimension is labelled")
    test.eq(statusLines[2].text:find("待核对", 1, true) ~= nil, true,
        "the reconciliation state is named")
    test.eq(statusLines[3].text:find("左键切换待核对/已完成", 1, true) ~= nil, true,
        "the toggle hint remains")
    test.eq(#ui.statusTooltipLines("trade", "pending", nil), 2,
        "a legacy row drops the trade-fact tooltip line")

    -- 6. filtering and reconciliation are explicit, local and reversible.
    test.eq(#ui.filterRows(rows, "all"), 1, "all filter keeps every row")
    test.eq(#ui.filterRows(rows, "pending"), 0, "pending filter excludes completed rows")
    test.eq(#ui.filterRows(rows, "complete"), 1, "complete filter keeps completed rows")
    test.eq(ui.setTradeStatus(root, rows[1].index, "pending"), true,
        "a completed row can be returned to pending")
    rows = ui.rows(root, "trade", { now = 1300, dateFn = stubDate })
    test.eq(rows[1].statusKey, "pending", "reconciliation status change is visible")
    test.eq(ui.setTradeStatus(root, rows[1].index, "complete"), true,
        "a pending row can be marked complete")
    test.eq(ui.setTradeStatus(root, rows[1].index, "failed"), false,
        "the reconciliation action cannot invent failure states")
    test.eq(ui.scrollOuterWidth("trade") - ui.contentWidth("trade"), 31,
        "scroll frame reserves the helper's scrollbar inset without clipping rows")

    -- 7. clearing removes the settlement only
    test.eq(type(ui.clearConfirmText()), "string", "clearing asks for confirmation")
    test.eq(ui.clear(root), true, "clear reported success")
    test.eq(root.currentSettlement.raidId, nil, "settlement identity cleared")
    test.eq(#root.currentSettlement.trades, 0, "settlement trades cleared")
    test.eq(#root.currentSettlement.mails, 0, "settlement mails cleared")
    -- everything else survives
    test.eq(saved.ICC.auctionLog[1].maijia, "我", "the current bill and purchase log survive")
    test.eq(saved.options.autoTrade, 1, "BGLite options survive")
    test.eq(saved.tradeHistory ~= nil, true, "untouched legacy data is not deleted")
    test.eq(saved.mailHistory ~= nil, true, "untouched legacy mail data is not deleted")
    test.eq(saved.History ~= nil, true, "untouched legacy raid data is not deleted")
    test.eq(root.wishlist ~= nil, true, "wishlist survives")
    test.eq(root.equipmentFilters ~= nil, true, "equipment filters survive")
    test.eq(root.ownCharacters ~= nil, true, "own-character overview survives")
    test.eq(root.auctionPresets, nil, "no auto-bid presets are created")
    test.eq(root.settings ~= nil, true, "settings survive")

    -- 8. an expired settlement is purged before the table is shown
    life.beginSettlement(root, "raid-b", 2000)
    test.eq(trade.append(root, {
        raidId = "raid-b", player = "丙", completed = true, status = "complete",
        myGold = 0, theirGold = 300, myItems = { { itemId = 22, quantity = 1 } }, time = 2100,
    }), true, "second settlement trade stored")
    test.eq(ui.prepare(root, 2000 + 7 * 86400), true, "opening the page purges an expired settlement")
    test.eq(root.currentSettlement.raidId, nil, "expired settlement identity removed")
    rows, isEmpty = ui.rows(root, "trade", { now = 2000 + 7 * 86400, dateFn = stubDate })
    test.eq(#rows, 0, "no expired rows are displayed")
    test.eq(isEmpty, true, "expired settlement shows the empty state")

    -- 9. defence in depth on the source
    local source = readAll("Core/BGNext/CurrentSettlementUI.lua")
    for _, forbidden in ipairs({
        "SendAddonMessage", "SendChatMessage", "NotifyInspect",
        "COMBAT_LOG_EVENT_UNFILTERED", "tradeHistory", "mailHistory",
        "BiaoGe.History", "GetInboxText",
    }) do
        test.eq(source:find(forbidden, 1, true), nil, "settlement UI never references " .. forbidden)
    end
    test.eq(source:find("交易记录（当前团）", 1, true) ~= nil, true, "trade window is explicitly labelled")
    test.eq(source:find("邮件记录（当前团）", 1, true) ~= nil, true, "mail window is explicitly labelled")
    test.eq(source:find("StaticPopup_Show", 1, true) ~= nil, true, "clearing goes through a confirmation popup")
    test.eq(source:find("OnUpdate", 1, true), nil, "settlement UI adds no per-frame handler")
    test.eq(source:find("C_Timer.NewTicker", 1, true), nil, "settlement UI adds no repeating ticker")
    test.eq(source:find("C_Timer.NewTimer(remaining + 1", 1, true) ~= nil, true,
        "expiry uses a cancellable one-shot timer just past the deadline")
    test.eq(source:find(":Cancel()", 1, true) ~= nil, true, "the one-shot timer is cancelled on hide")
    test.eq(source:find("HookScript", 1, true) ~= nil, true, "bill edit frames are subscribed by hooking")

    -- 10. the settlement checklist window: refresh, locate and cleanup run on
    --     real frames (mocked), and every swapped global comes back
    local watchedGlobals = {
        "BG", "CreateFrame", "BIAOGE_TEXT_FONT", "GetServerTime", "BiaoGe",
        "GameTooltip", "C_Timer", "hooksecurefunc", "StaticPopupDialogs", "StaticPopup_Show",
    }
    local originalValues = {}
    for _, name in ipairs(watchedGlobals) do
        originalValues[name] = rawget(_G, name)
    end
    local function setGlobal(name, value)
        rawset(_G, name, value)
    end

    local checklistOk, checklistErr = pcall(function()
        BG = { BGNext = {} }
        local checklistLife = dofile("Core/BGNext/DataLifecycle.lua")
        local checklistTrade = dofile("Core/BGNext/CurrentTrade.lua")
        dofile("Core/BGNext/ReturnMarker.lua")
        dofile("Core/BGNext/CurrentMail.lua")
        dofile("Core/BGNext/CurrentSettlementView.lua")
        dofile("Core/BGNext/CurrentSettlementChecklist.lua")

        local function makeFrame()
            local frame = {
                points = {}, scripts = {}, children = {},
                text = "", shown = true, width = 0, height = 0,
            }
            function frame:SetPoint(point, relative, relativePoint)
                self.points[#self.points + 1] = { point = point, relative = relative, relativePoint = relativePoint }
            end
            function frame:SetSize(width, height) self.width, self.height = width, height end
            function frame:SetWidth(width) self.width = width end
            function frame:SetHeight(height) self.height = height end
            function frame:SetScript(name, handler) self.scripts[name] = handler end
            function frame:HookScript(name, handler)
                local previous = self.scripts[name]
                self.scripts[name] = function(...)
                    if previous then previous(...) end
                    handler(...)
                end
            end
            function frame:SetText(value) self.text = value end
            function frame:GetText() return self.text end
            function frame:SetTextColor() end
            function frame:SetFont() end
            function frame:SetJustifyH() end
            function frame:SetWordWrap() end
            function frame:SetAllPoints() end
            function frame:ClearAllPoints() self.points = {} end
            function frame:SetColorTexture() end
            function frame:SetTexture() end
            function frame:SetShown(value) self.shown = value and true or false end
            function frame:Show()
                if self.shown then return end
                self.shown = true
                if self.scripts.OnShow then self.scripts.OnShow(self) end
            end
            function frame:Hide()
                self.shown = false
                if self.scripts.OnHide then self.scripts.OnHide(self) end
            end
            function frame:IsShown() return self.shown end
            function frame:EnableMouse() end
            function frame:SetFrameLevel() end
            function frame:SetCursorPosition() end
            function frame:CreateFontString()
                local label = makeFrame()
                self.children[#self.children + 1] = label
                return label
            end
            function frame:CreateTexture()
                local texture = makeFrame()
                self.children[#self.children + 1] = texture
                return texture
            end
            return frame
        end

        setGlobal("CreateFrame", function(_, _, parent)
            local frame = makeFrame()
            if parent and parent.children then
                parent.children[#parent.children + 1] = frame
            end
            return frame
        end)
        setGlobal("BIAOGE_TEXT_FONT", "Fonts\\FRIZQT__.TTF")
        local nowValue = 1000000
        setGlobal("GetServerTime", function() return nowValue end)
        local tooltipLines = {}
        setGlobal("GameTooltip", {
            SetOwner = function() end,
            ClearLines = function()
                for key in pairs(tooltipLines) do tooltipLines[key] = nil end
            end,
            AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = text end,
            Show = function() end,
            Hide = function() end,
        })
        local tickers = {}
        local afters = {}
        setGlobal("C_Timer", {
            -- Burst coalescing uses After(0) and runs immediately in tests. The
            -- one-shot expiry invalidation uses NewTimer, which returns a real
            -- cancellable handle; those are recorded in `afters` for the
            -- lifecycle assertions below. Both take the client's dot-notation
            -- signature (no self argument), matching how production calls them.
            After = function(delay, callback)
                if delay == 0 then
                    callback()
                end
            end,
            NewTimer = function(delay, callback)
                local timer = { delay = delay, callback = callback, cancelled = false }
                function timer:Cancel() self.cancelled = true end
                function timer:IsCancelled() return self.cancelled end
                afters[#afters + 1] = timer
                return timer
            end,
            NewTicker = function(_, _, callback)
                local ticker = { callback = callback, cancelled = false }
                function ticker:Cancel() self.cancelled = true end
                tickers[#tickers + 1] = ticker
                return ticker
            end,
        })
        setGlobal("hooksecurefunc", function(object, name, hook)
            local original = object[name]
            object[name] = function(...)
                original(...)
                hook(...)
            end
        end)
        local shownPopup
        setGlobal("StaticPopupDialogs", {})
        setGlobal("StaticPopup_Show", function(which, _, _, data)
            shownPopup = { which = which, data = data }
            return shownPopup
        end)

        BG.CreateMainFrame = function()
            local frame = makeFrame()
            frame.titleText = makeFrame()
            return frame
        end
        BG.CreateScrollFrame = function()
            return makeFrame(), makeFrame()
        end
        BG.CreateButton = function() return makeFrame() end
        BG.GetMaxi = function() return 2 end
        local clickTargets = {}
        BG.ClickFBbutton = function(fb) clickTargets[#clickTargets + 1] = fb end
        BG.RegisterEvent = function() end
        BG.ClearBiaoGe = function() end
        BG.SetListjine = function()
            local edit = makeFrame()
            edit:SetScript("OnTextChanged", function(self)
                BiaoGe.ICC.boss1.qiankuan2 = tonumber(self:GetText())
            end)
            BG.FrameQianKuanEdit = edit
        end
        BG.Init = function(callback) callback() end
        setGlobal("BiaoGe", {
            options = {},
            ICC = {
                boss1 = {
                    zhuangbei1 = "[装备一]", maijia1 = "买家甲", jine1 = "100",
                    zhuangbei2 = "[装备二]", maijia2 = "买家乙", jine2 = "", qiankuan2 = 300,
                },
                boss4 = { jine3 = "500", jine4 = "40", jine5 = "12.50" },
            },
        })
        -- Real bill edit frames for the hook-based invalidation.
        local hookCounts = {}
        BG.Frame = { ICC = {} }
        for boss = 1, 4 do
            BG.Frame.ICC["boss" .. boss] = {}
        end
        BG.Frame.ICC.boss1.jine1 = makeFrame()
        BG.Frame.ICC.boss1.zhuangbei1 = makeFrame()
        BG.Frame.ICC.boss1.maijia1 = makeFrame()
        BG.Frame.ICC.boss1.qiankuan1 = makeFrame()
        for _, frame in ipairs({ BG.Frame.ICC.boss1.jine1, BG.Frame.ICC.boss1.zhuangbei1,
            BG.Frame.ICC.boss1.maijia1, BG.Frame.ICC.boss1.qiankuan1 }) do
            hookCounts[frame] = 0
            local rawHook = frame.HookScript
            frame.HookScript = function(self, name, handler)
                hookCounts[frame] = hookCounts[frame] + 1
                local previous = self.scripts[name]
                self.scripts[name] = function(...)
                    if previous then previous(...) end
                    handler(...)
                end
            end
        end

        -- The collector runtime wires the real clear-table notification and
        -- roots the SavedVariables on the mocked BiaoGe table.
        dofile("Core/BGNext/CurrentSettlementRuntime.lua")
        -- Mirror DataLifecycle's init: root the SavedVariables on the mocked
        -- BiaoGe table.
        BG.BGNext.DB = checklistLife.ensureRoot(BiaoGe)

        checklistLife.beginSettlement(BG.BGNext.DB, "ICC@123", nowValue, { fb = "ICC", realm = "realm" })
        checklistTrade.append(BG.BGNext.DB, {
            raidId = "ICC@123", player = "买家甲", completed = true, status = "pending",
            myGold = 0, theirGold = 100, myItems = { { itemId = 7001, quantity = 1 } }, time = nowValue,
        })
        local chunk = assert(loadfile("Core/BGNext/CurrentSettlementUI.lua"))
        local ui2 = chunk("BGNEXT", {
            Maxb = { ICC = 2 },
            GetItemID = function(text)
                return text == "[装备一]" and 7001 or 7002
            end,
        })

        test.eq(ui2.Show("checklist"), true, "checklist window opens")
        local state = ui2.checklistState()
        test.eq(state.shown, true, "checklist window is shown")
        test.eq(state.report ~= nil, true, "opening computes the report")
        test.eq(state.report.status, "issues", "collected anomalies surface as issues")
        test.eq(state.report.issueCount, 3, "unconfirmed trade, debt and missing amount are counted")
        test.eq(#state.rows, state.report.total + 4, "entries render grouped under four category headers")
        test.eq(state.rows[1].isHeader, true, "the first group starts with a category header")

        -- 10a. locate buttons perform real jumps only
        local clickedWindow, clickedTable = false, false
        for _, row in ipairs(state.rows) do
            local locate = row.entry and row.entry.locate
            if locate and locate.type == "table" then
                row.locateButton.scripts.OnClick(row.locateButton)
                clickedTable = true
            elseif locate and locate.type == "window" then
                row.locateButton.scripts.OnClick(row.locateButton)
                clickedWindow = true
            end
        end
        test.eq(clickedWindow and clickedTable, true, "both locate kinds are offered")
        test.eq(clickTargets[1], "ICC", "table locate switches to the raid table")
        test.eq(ui2.windowState("trade").filter, "pending", "window locate applies the pending filter")
        local refreshTradeCalls = 0
        local originalRefresh = ui2.Refresh
        ui2.Refresh = function(kind)
            if kind == "trade" then refreshTradeCalls = refreshTradeCalls + 1 end
            return originalRefresh(kind)
        end
        ui2.Show("trade", "all")
        test.eq(refreshTradeCalls, 1, "changing a visible window filter refreshes its rows once")
        ui2.Refresh = originalRefresh

        -- 10aa. the real return-action entry enforces permission, then routes
        --       one match through the confirmation popup.
        checklistTrade.append(BG.BGNext.DB, {
            raidId = "ICC@123", player = "买家甲", completed = true, status = "pending",
            myGold = 0, theirGold = 0, myItems = {},
            theirItems = { { itemId = 7001, quantity = 1 } }, time = nowValue + 1,
        })
        checklistTrade.append(BG.BGNext.DB, {
            raidId = "ICC@123", player = "买家甲", completed = true, status = "pending",
            myGold = 0, theirGold = 0, myItems = {},
            theirItems = { { itemId = 7001, quantity = 1 } }, time = nowValue + 2,
        })
        ui2.Refresh("trade")
        local actionRows = ui2.windowState("trade").rows
        actionRows[1].cells.status.scripts.OnEnter(actionRows[1].cells.status)
        test.eq(tooltipLines[#tooltipLines] == "右键：标记退货 / 清除退货提醒", false,
            "an outgoing delivery does not advertise the return action")
        actionRows[2].cells.status.scripts.OnEnter(actionRows[2].cells.status)
        test.eq(tooltipLines[#tooltipLines], "右键：标记退货 / 清除退货提醒",
            "an incoming item advertises the return action")
        BG.IsML = false
        test.eq(ui2.OpenReturnAction(2), false, "a non-leader cannot open the return action")
        test.eq(shownPopup, nil, "permission rejection shows no confirmation")
        BG.IsML = true
        test.eq(ui2.OpenReturnAction(2), true, "one matching bill row opens return confirmation")
        test.eq(shownPopup.which, "BGNextMarkReturn", "single match uses the explicit mark popup")
        test.eq(shownPopup.data.selection.boss, 1, "single match confirms the matching boss")
        test.eq(shownPopup.data.selection.slot, 1, "single match confirms the matching row")
        StaticPopupDialogs[shownPopup.which].OnAccept(nil, shownPopup.data)
        local tradeWindow = ui2.windowState("trade")
        test.eq(tradeWindow.rows[2].cells.status.text:GetText():find("退货待处理", 1, true) ~= nil, true,
            "confirmed return is visible in the trade status")
        test.eq(BG.Frame.ICC.boss1.zhuangbei1.bgnextReturnBadge:GetText(), "退",
            "confirmed return creates the red bill-row badge")
        test.eq(BG.Frame.ICC.boss1.zhuangbei1.bgnextReturnBadge:IsShown(), true,
            "the return badge is visible while pending")

        -- A second row with the same item and buyer turns a later incoming
        -- trade into an explicit selection step instead of auto-picking.
        BiaoGe.ICC.boss1.zhuangbei2 = "[装备一]"
        BiaoGe.ICC.boss1.maijia2 = "买家甲"
        BiaoGe.ICC.boss1.jine2 = "120"
        test.eq(ui2.OpenReturnAction(3), true, "duplicate bill rows open the selector")
        local returnState = ui2.returnActionState()
        test.eq(returnState.selectorShown, true, "duplicate match selector is visible")
        test.eq(#returnState.selectorButtons, 2, "duplicate match exposes both bill rows")
        BG.BGNext.DB.currentSettlement.trades[3] = nil
        BG.BGNext.DB.currentSettlement.trades[2] = nil
        BG.BGNext.DB.currentSettlement.returns = {}
        BiaoGe.ICC.boss1.zhuangbei2 = "[装备二]"
        BiaoGe.ICC.boss1.maijia2 = "买家乙"
        BiaoGe.ICC.boss1.jine2 = ""
        ui2.Refresh("trade")

        -- 10b. the full reason is available through the row tooltip
        local entryRow = state.rows[2]
        test.eq(entryRow.isHeader, false, "the second row is an entry")
        entryRow.scripts.OnEnter(entryRow)
        test.eq(tooltipLines[1], entryRow.fullReason, "the tooltip carries the untruncated reason")

        -- 10c. bill edits reach the checklist through the real hooked frames,
        --      with no repeating ticker and one one-shot expiry invalidation
        test.eq(#tickers, 0, "no repeating ticker is created")
        test.eq(#afters, 1, "one one-shot expiry invalidation is armed")
        test.eq(afters[1].delay, 604801, "the one-shot fires just after the deadline")
        test.eq(hookCounts[BG.Frame.ICC.boss1.jine1], 1, "the bill edit frame is subscribed once")
        BiaoGe.ICC.boss1.qiankuan1 = 999
        BG.Frame.ICC.boss1.jine1.scripts.OnTextChanged(BG.Frame.ICC.boss1.jine1)
        state = ui2.checklistState()
        test.eq(state.report.issueCount, 4, "the new debt appears through the hooked frame")
        for _, row in ipairs(state.rows) do
            test.eq(row:IsShown(), true, "refreshed checklist entries and headers remain visible")
        end

        -- 10d. idle time alone rebuilds nothing
        -- Opening a new popup after the checklist must subscribe immediately,
        -- even when the existing debt indicator never hides or shows again.
        for _, debt in ipairs({ 500, 300 }) do
            local previousReport = state.report
            BG.SetListjine()
            local edit = BG.FrameQianKuanEdit
            edit:SetText(tostring(debt))
            edit.scripts.OnTextChanged(edit)
            state = ui2.checklistState()
            test.eq(state.report ~= previousReport, true, "new debt popup invalidates the checklist")
            test.eq(BiaoGe.ICC.boss1.qiankuan2, debt, "original debt editor handler is preserved")
        end
        local idleReport = state.report
        nowValue = nowValue + 30
        test.eq(ui2.checklistState().report, idleReport, "idle time causes zero report builds")

        -- 10e. back to live data; the purged settlement is re-established and
        --      the findings return through the normal pipeline
        nowValue = 1000000
        BiaoGe.ICC.boss1.qiankuan1 = nil
        checklistLife.beginSettlement(BG.BGNext.DB, "ICC@123", nowValue, { fb = "ICC", realm = "realm" })
        checklistTrade.append(BG.BGNext.DB, {
            raidId = "ICC@123", player = "买家甲", completed = true, status = "pending",
            myGold = 0, theirGold = 100, myItems = { { itemId = 7001, quantity = 1 } }, time = nowValue,
        })
        ui2.Refresh("trade")
        state = ui2.checklistState()
        test.eq(state.report.issueCount, 3, "re-established findings return on refresh")

        -- 10f. closing releases the report, rows and locate closures
        ui2.Toggle("checklist")
        state = ui2.checklistState()
        test.eq(state.shown, false, "checklist window closes")
        test.eq(state.report, nil, "closing releases the derived report")
        test.eq(next(state.rows), nil, "closing releases the active row list")
        local retainedEntries = 0
        for _, row in ipairs(state.pooledRows) do
            if row.entry ~= nil or row.fullReason ~= nil or row.text:GetText() ~= "" then
                retainedEntries = retainedEntries + 1
            end
        end
        test.eq(retainedEntries, 0, "pooled rows retain no derived entries or text")
        test.eq(afters[1].cancelled, true, "the one-shot expiry timer is cancelled on hide")
        test.eq(#tickers, 0, "still no repeating ticker after a full cycle")

        -- 10g. reopening arms a fresh one-shot for the re-established scope
        --      and does not accumulate frame hooks
        ui2.Show("checklist")
        test.eq(ui2.checklistState().report.status, "issues", "report is recomputed on reopen")
        test.eq(#afters, 2, "reopening arms a fresh one-shot expiry timer")
        test.eq(afters[2].delay, 604801, "the fresh timer matches the new deadline")
        test.eq(hookCounts[BG.Frame.ICC.boss1.jine1], 1, "reopening does not accumulate frame hooks")

        -- 10h. expiry fires once and drops the purged scope to pending
        nowValue = 1000000 + 8 * 86400
        afters[2].callback()
        state = ui2.checklistState()
        test.eq(state.report.status, "pending", "an expired re-established scope drops to pending")
        test.eq(#afters, 2, "no re-arm without a live settlement")

        -- 10i. clearing the active raid table invalidates the scope at once
        checklistLife.beginSettlement(BG.BGNext.DB, "ICC@123", nowValue, { fb = "ICC", realm = "realm" })
        checklistTrade.append(BG.BGNext.DB, {
            raidId = "ICC@123", player = "买家甲", completed = true, status = "pending",
            myGold = 0, theirGold = 100, myItems = { { itemId = 7001, quantity = 1 } }, time = nowValue,
        })
        ui2.Refresh("checklist")
        test.eq(ui2.checklistState().report.status, "issues", "the re-established scope is checked")
        BG.ClearBiaoGe("biaoge", "ICC")
        test.eq(BG.BGNext.DB.currentSettlement.raidId, nil, "clearing the raid table clears the settlement")
        state = ui2.checklistState()
        test.eq(state.report.status, "pending", "the checklist follows the scope reset immediately")
        ui2.Toggle("checklist")
    end)

    for _, name in ipairs(watchedGlobals) do
        rawset(_G, name, originalValues[name])
    end
    for _, name in ipairs(watchedGlobals) do
        test.eq(rawget(_G, name), originalValues[name], "settlement UI suite restores global: " .. name)
    end
    if not checklistOk then
        error(checklistErr, 0)
    end
end
