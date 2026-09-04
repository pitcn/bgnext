return function(test)
    -- Fresh environment for this suite.
    BG = { BGNext = {} }
    BGA = { Frames = {} }
    GameTooltip = {
        SetOwner = function() end,
        SetHyperlink = function() end,
        ClearLines = function() end,
        AddLine = function() end,
        Show = function() end,
        Hide = function() end,
    }
    UIParent = { GetHeight = function() return 768 end }

    -- Core queue must load first.
    local Queue = dofile("Core/BGNext/AuctionQueue.lua")
    BG.BGNext.AuctionQueue = Queue

    -- The runtime now delegates its shared environment checks and the pre-send
    -- gate to this module, so it must load before the runtime.
    dofile("Core/BGNext/AuctionPreSend.lua")

    -- --- Fake frame factory -------------------------------------------------

    local function fakeRegion()
        return {
            text = "",
            SetText = function(self, t) self.text = t end,
            GetText = function(self) return self.text end,
            SetPoint = function() end,
            SetFont = function() end,
            SetJustifyH = function() end,
            SetWordWrap = function() end,
            SetTextColor = function() end,
            SetWidth = function() end,
            GetStringWidth = function() return 10 end,
            Show = function() end,
            Hide = function() end,
        }
    end

    local function fakeFrame(name)
        local f = {
            name = name or "frame",
            scripts = {},
            hooks = {},
            shown = false,
            text = "",
            enabled = true,
            fontString = nil,
            parent = nil,
            width = 0,
            height = 0,
        }
        function f:GetScript(script) return self.scripts[script] end
        function f:SetScript(script, fn) self.scripts[script] = fn end
        function f:HookScript(script, fn)
            self.hooks[script] = self.hooks[script] or {}
            self.hooks[script][#self.hooks[script] + 1] = fn
        end
        function f:Show()
            self.shown = true
            if self.scripts.OnShow then self.scripts.OnShow(self) end
        end
        function f:Hide()
            self.shown = false
            if self.scripts.OnHide then self.scripts.OnHide(self) end
            local hooked = self.hooks.OnHide
            if hooked then for _, h in ipairs(hooked) do h(self) end end
        end
        function f:IsShown() return self.shown end
        function f:IsVisible() return self.shown end
        function f:SetShown(v) if v then self:Show() else self:Hide() end end
        function f:SetSize(w, h) self.width, self.height = w, h end
        function f:SetWidth(w) self.width = w end
        function f:SetHeight(h) self.height = h end
        function f:GetWidth() return self.width end
        function f:GetHeight() return self.height end
        function f:SetText(t) self.text = t; if self.fontString then self.fontString:SetText(t) end end
        function f:GetText() return self.text end
        function f:SetEnabled(v) self.enabled = v end
        function f:GetParent() return self.parent end
        function f:SetPoint(...) self.point = { ... } end
        function f:ClearAllPoints() self.point = nil end
        function f:SetBackdrop() end
        function f:SetBackdropColor() end
        function f:SetBackdropBorderColor() end
        function f:SetFrameStrata() end
        function f:SetFrameLevel() end
        function f:SetClampedToScreen() end
        function f:SetMovable() end
        function f:EnableMouse() end
        function f:EnableMouseWheel(v) self.mouseWheelEnabled = v end
        function f:SetToplevel() end
        function f:SetAutoFocus() end
        function f:SetNumeric() end
        function f:SetMaxLetters() end
        function f:SetTextColor() end
        function f:ClearFocus() end
        function f:StartMoving() end
        function f:StopMovingOrSizing() end
        function f:CreateFontString()
            self.fontString = fakeRegion()
            return self.fontString
        end
        return f
    end

    CreateFrame = function(frameType, name, parent, template)
        local f = fakeFrame(name or tostring(frameType))
        f.parent = parent
        return f
    end

    -- --- BG and WoW stubs ---------------------------------------------------

    local initCallbacks = {}
    local init2Callbacks = {}
    BG.Init = function(fn) initCallbacks[#initCallbacks + 1] = fn end
    BG.Init2 = function(fn) init2Callbacks[#init2Callbacks + 1] = fn end
    local events = {}
    BG.RegisterEvent = function(event, fn)
        events[event] = events[event] or {}
        events[event][#events[event] + 1] = fn
    end
    local messages = {}
    BG.SendSystemMessage = function(msg) messages[#messages + 1] = msg end
    local after = {}
    BG.After = function(delay, fn) after[#after + 1] = { delay = delay, fn = fn } end
    local sends = 0
    local sentRecords = {}
    local auctionIdSeq = 0
    local clearCalls = 0
    local defaultResolve = function(root, family, raidId, itemId)
        if itemId == 1001 then return { price = 900, source = "override" } end
        if itemId == 1002 then return { price = 500, source = "base" } end
        return nil
    end
    -- The approval resolver carries the producing preset id so the shared
    -- pre-send gate can re-validate scheme identity at the actual send.
    local defaultApproval = function(root, family, raidId, itemId)
        if itemId == 1001 then return { price = 900, source = "override", activePresetId = "p1" } end
        if itemId == 1002 then return { price = 500, source = "base", activePresetId = "p1" } end
        return nil
    end
    BiaoGe = { Auction = { money = 100, duration = 40, fastMoney = { 300, 500, 1000, 2000, 3000 } } }
    BG.SendStartAuctionMsg = function(itemID, money, duration, link)
        auctionIdSeq = auctionIdSeq + 1
        sends = sends + 1
        sentRecords[#sentRecords + 1] = { auctionID = auctionIdSeq, itemID = itemID, money = money }
        return auctionIdSeq
    end
    -- Production-faithful start handler: mirrors the real Core/Module/Auction.lua
    -- Start_OnClick contract -- a private Start_OnClick that (1) honours an optional
    -- per-button onPreSend veto before any side effect, (2) schedules the send with
    -- BG.After(0), and (3) hands the returned auctionID to the optional per-button
    -- onAuctionSent. Edit2 Enter and quick-money both call the private Start_OnClick
    -- directly, exactly like the legacy dialog.
    BG.StartAuction = function(link, bt, isNotAuctioned, notAlt, isRightButton, noSound, callback)
        local itemId = tonumber(tostring(link):match("item:(%d+)")) or 1001
        local frame = fakeFrame("StartAucitonFrame")
        frame.Edit3 = fakeFrame("Edit3")
        frame.Edit3.text = "5"
        frame.Edit3.parent = frame
        frame.Edit2 = fakeFrame("Edit2")
        frame.Edit2.text = tostring(BiaoGe.Auction.money)
        frame.Edit2.parent = frame
        frame.bt = fakeFrame("bt")
        frame.bt.parent = frame
        frame.bt.items = { { id = itemId, link = link } }

        local function Start_OnClick(self)
            if self.onPreSend and not self.onPreSend(self) then
                return
            end
            if not self.noSound then BG.PlaySound(1) end
            local money = self.money or tonumber(BiaoGe.Auction.money)
            local duration = tonumber(BiaoGe.Auction.duration) or 40
            if not (money and duration) then return end
            local count = tonumber(self:GetParent().Edit3:GetText()) or 1
            for _ = 1, count do
                local itemID = self.items[1].id
                local lnk = self.items[1].link
                BG.After(0, function()
                    local auctionID = BG.SendStartAuctionMsg(itemID, money, duration, lnk)
                    if self.onAuctionSent then
                        self.onAuctionSent(auctionID, itemID, money, lnk)
                    end
                end)
            end
            if self.callback then self.callback() end
            self:GetParent():Hide()
        end

        frame.bt:SetScript("OnClick", Start_OnClick)
        frame.Edit2.num = 2
        frame.Edit2:SetScript("OnEnterPressed", function(edit)
            if edit.num == 2 then Start_OnClick(edit:GetParent().bt) end
        end)
        frame.fastMoney = {}
        for i, m in ipairs(BiaoGe.Auction.fastMoney or {}) do
            local fbtn = fakeFrame("fastMoney" .. i)
            fbtn.money = m
            fbtn:SetScript("OnClick", function(self)
                frame.Edit2:SetText(tostring(self.money))
                BiaoGe.Auction.money = self.money
                Start_OnClick(frame.bt)
            end)
            frame.fastMoney[i] = fbtn
        end

        BG.StartAucitonFrame = frame
        return frame
    end
    BG.HookCreateAuction = function(frame) end
    BG.ClearBiaoGe = function(_type, FB) clearCalls = clearCalls + 1; return true end
    BG.CreateButton = function(parent) return fakeFrame("CreateButton") end
    BG.PlaySound = function() end
    BG.IsML = true
    BG.FB1 = "ULD"
    BG.raidRosterInfo = { { name = "Alice" }, { name = "Bob" } }
    BG.raidLeader = "Alice"
    BG.IsWLK = true
    BG.BGNext.DB = {}
    BG.BGNext.AuctionPriceStore = {
        resolveLeaderPriceDetail = defaultResolve,
        resolveLeaderApproval = defaultApproval,
    }
    InCombatLockdown = function() return false end
    IsInRaid = function() return true end
    SlashCmdList = {}

    local M = dofile("Core/BGNext/AuctionQueueRuntime.lua")

    -- Wire the runtime (wraps StartAuction / HookCreateAuction / ClearBiaoGe,
    -- registers events, installs the slash command and main-tab entry).
    for _, fn in ipairs(initCallbacks) do fn() end
    for _, fn in ipairs(init2Callbacks) do fn() end

    local function freshQueue()
        M.clear()
        M.onLeavingWorld()
        sends = 0
        sentRecords = {}
        auctionIdSeq = 0
        after = {}
        messages = {}
        BiaoGe.Auction.money = 100
    end

    local function flushZeroTimers()
        local zero, rest = {}, {}
        for _, t in ipairs(after) do
            if t.delay == 0 then zero[#zero + 1] = t else rest[#rest + 1] = t end
        end
        after = rest
        for _, t in ipairs(zero) do t.fn() end
    end

    local function clickStart()
        BG.StartAucitonFrame.bt.scripts.OnClick(BG.StartAucitonFrame.bt)
    end
    local function pressEnter()
        BG.StartAucitonFrame.Edit2.scripts.OnEnterPressed(BG.StartAucitonFrame.Edit2)
    end
    local function clickFast(index)
        BG.StartAucitonFrame.fastMoney[index].scripts.OnClick(BG.StartAucitonFrame.fastMoney[index])
    end

    local function lastAuctionID()
        return sentRecords[#sentRecords] and sentRecords[#sentRecords].auctionID
    end

    local function loopback(itemID, auctionID)
        BG.HookCreateAuction({ itemID = itemID, link = "item:" .. itemID, auctionID = auctionID })
    end

    -- --- Finding 1: opening the dialog never removes the row ----------------

    freshQueue()
    local id1 = M.add({ itemId = 1001, link = "item:1001" })
    test.eq(M.state().queueSize, 1, "one queued item before confirm")
    test.eq(M.confirm(id1), true, "confirm opens the dialog")
    test.eq(M.state().queueSize, 1, "opening the dialog keeps the row")
    test.eq(M.state().hasPending, true, "a pending confirm is armed")
    test.eq(sends, 0, "opening the dialog sends nothing")

    BG.StartAucitonFrame:Hide()
    test.eq(M.state().queueSize, 1, "cancelling keeps the row")
    test.eq(M.state().hasPending, false, "cancelling frees the pending slot")

    -- --- Finding 2: Edit3 is forced to 1 and locked, single send -------------

    freshQueue()
    local id2 = M.add({ itemId = 1001, link = "item:1001" })
    M.confirm(id2)
    test.eq(BG.StartAucitonFrame.Edit3.text, "1", "Edit3 is forced to one")
    test.eq(BG.StartAucitonFrame.Edit3.enabled, false, "Edit3 is locked")

    clickStart()
    flushZeroTimers()
    test.eq(sends, 1, "the start handler ran once")
    test.eq(M.state().queueSize, 1, "a send without a loopback keeps the row")
    test.eq(M.state().pendingFired, true, "the pending is marked fired")

    clickStart()
    test.eq(sends, 1, "a second click never re-sends")

    loopback(1001, lastAuctionID())
    test.eq(M.state().queueSize, 0, "the matching loopback removes the row")
    test.eq(M.state().hasPending, false, "the loopback clears the pending")

    -- --- Finding 1: quantity > 1 decrements by exactly one ------------------

    freshQueue()
    local qid = M.add({ itemId = 1001, link = "item:1001", quantity = 2 })
    test.eq(M.confirm(qid), true, "first confirm opens for a quantity-two row")
    clickStart()
    flushZeroTimers()
    loopback(1001, lastAuctionID())
    test.eq(M.state().queueSize, 1, "quantity two becomes one, not removed")
    test.eq(M.project()[1].quantity, 1, "remaining quantity is one")
    test.eq(M.state().hasPending, false, "pending cleared after the round-trip")

    test.eq(M.confirm(M.project()[1].id), true, "second confirm opens again")
    clickStart()
    flushZeroTimers()
    loopback(1001, lastAuctionID())
    test.eq(M.state().queueSize, 0, "the second confirm removes the last quantity")

    -- --- Finding 1: a timed-out send keeps the entry ------------------------

    freshQueue()
    local tid = M.add({ itemId = 1001, link = "item:1001" })
    M.confirm(tid)
    clickStart()
    local timeout
    for _, t in ipairs(after) do
        if t.delay == 10 then timeout = t end
    end
    test.eq(timeout ~= nil, true, "a timeout is armed after the send")
    timeout.fn()
    test.eq(M.state().queueSize, 1, "a timed-out send keeps the row")
    test.eq(M.state().hasPending, false, "the timeout frees the pending slot")

    -- --- Counterexample 1: all three start paths run the second gate ---------

    local paths = {
        { name = "button", run = clickStart },
        { name = "enter", run = pressEnter },
        { name = "fast", run = function() clickFast(1) end },
    }
    local conditions = {
        {
            name = "combat",
            setup = function() InCombatLockdown = function() return true end end,
            teardown = function() InCombatLockdown = function() return false end end,
        },
        {
            name = "permission",
            setup = function() BG.IsML = false end,
            teardown = function() BG.IsML = true end,
        },
        {
            name = "auction-busy",
            setup = function() BGA.Frames[1] = { IsEnd = false } end,
            teardown = function() BGA.Frames = {} end,
        },
        {
            name = "price-snapshot",
            setup = function() BG.BGNext.AuctionPriceStore.resolveLeaderApproval = function() return { price = 999, source = "override", activePresetId = "p1" } end end,
            teardown = function() BG.BGNext.AuctionPriceStore.resolveLeaderApproval = defaultApproval end,
        },
        {
            name = "scope",
            setup = function() BG.FB1 = "ICC" end,
            teardown = function() BG.FB1 = "ULD" end,
        },
    }
    for _, cond in ipairs(conditions) do
        for _, path in ipairs(paths) do
            freshQueue()
            M.add({ itemId = 1001, link = "item:1001" })
            test.eq(M.confirm(M.project()[1].id), true, cond.name .. "/" .. path.name .. ": confirm opens")
            cond.setup()
            path.run()
            flushZeroTimers()
            test.eq(sends, 0, cond.name .. "/" .. path.name .. ": second gate blocks the send")
            test.eq(M.state().pendingFired, false, cond.name .. "/" .. path.name .. ": veto never fires")
            cond.teardown()
            BG.StartAucitonFrame:Hide()
        end
    end

    -- --- Finding 3: one active card blocks, many ended cards do not ---------

    BGA.Frames = {}
    test.eq(M.auctionInProgress(), false, "no cards means not busy")
    BGA.Frames[1] = { IsEnd = true }
    BGA.Frames[2] = { IsEnd = true }
    BGA.Frames[3] = { IsEnd = true }
    test.eq(M.auctionInProgress(), false, "only ended linger cards are not busy")
    BGA.Frames[4] = { IsEnd = false }
    test.eq(M.auctionInProgress(), true, "one active card is busy")
    BGA.Frames = {}

    -- --- Finding 4: scope includes the raid session -------------------------

    freshQueue()
    M.add({ itemId = 1001, link = "item:1001" })
    test.eq(M.state().queueSize, 1, "queue populated under the current raid")
    BG.raidRosterInfo = { { name = "Alice" }, { name = "Bob" }, { name = "Carol" } }
    M.onRosterUpdate()
    test.eq(M.state().queueSize, 0, "switching raid (same table) clears the queue")

    M.add({ itemId = 1001, link = "item:1001" })
    IsInRaid = function() return false end
    M.onRosterUpdate()
    test.eq(M.state().queueSize, 0, "leaving the raid clears the queue")
    IsInRaid = function() return true end

    M.add({ itemId = 1001, link = "item:1001" })
    BG.FB1 = "ICC"
    M.ensureQueue()
    test.eq(M.state().queueSize, 0, "switching the table clears the queue")
    BG.FB1 = "ULD"

    freshQueue()
    M.add({ itemId = 1001, link = "item:1001" })
    BG.ClearBiaoGe(nil, "ULD")
    test.eq(M.state().queueSize, 0, "clearing the current table clears the queue")
    test.eq(clearCalls, 1, "the original clear still runs")

    M.add({ itemId = 1001, link = "item:1001" })
    for _, fn in ipairs(events["PLAYER_LEAVING_WORLD"] or {}) do fn() end
    test.eq(M.state().queueSize, 0, "leaving the world clears the queue")

    -- --- Finding 5: player-accessible UI ------------------------------------

    freshQueue()
    test.eq(type(M.parseItemText("item:1001")), "number", "hyperlink parses to an id")
    test.eq(M.parseItemText("|cff0070dd|Hitem:1001:0:0|h[Item]|h|r"), 1001, "full item link parses")
    test.eq(M.parseItemText("1002"), 1002, "a bare id parses")
    test.eq(M.parseItemText("garbage"), nil, "garbage does not parse")
    test.eq(M.parseItemText(""), nil, "empty text does not parse")

    test.eq(type(M.addFromText("item:1001")), "number", "drag/typed add accepts a hyperlink")
    test.eq(M.state().queueSize, 1, "typed add queues one item")
    test.eq(M.addFromText("not-an-item"), nil, "invalid typed text is rejected")

    local frame = M.openFrame()
    test.eq(frame.mouseWheelEnabled, true, "the scroll frame enables the mouse wheel")
    test.eq(type(frame.scripts.OnMouseWheel), "function", "the wheel handler is still wired")
    test.eq(type(frame.rows), "table", "frame exposes a row pool")
    test.eq(#frame.rows, 40, "row pool is fixed")
    test.eq(frame.rows[1].shown, true, "the first row is bound and shown")
    test.eq(frame.rows[2].shown, false, "the second pooled row stays hidden")
    test.eq(type(frame.closeButton), "table", "the queue window exposes an obvious close button")
    frame.closeButton.scripts.OnClick(frame.closeButton)
    test.eq(frame.shown, false, "the close button hides the queue window")
    M.openFrame()

    frame.rows[1].plus.scripts.OnClick(frame.rows[1].plus)
    test.eq(M.project()[1].quantity, 2, "the plus button increments quantity")
    frame.rows[1].minus.scripts.OnClick(frame.rows[1].minus)
    test.eq(M.project()[1].quantity, 1, "the minus button decrements quantity")

    M.addFromText("item:1002")
    test.eq(M.project()[1].itemId, 1001, "first added item stays first")
    frame.rows[2].up.scripts.OnClick(frame.rows[2].up)
    test.eq(M.project()[1].itemId, 1002, "move up reorders the queue")

    local removedId = M.project()[1].id
    frame.rows[1].remove.scripts.OnClick(frame.rows[1].remove)
    test.eq(M.state().queueSize, 1, "remove drops exactly one row")
    test.eq(M.project()[1].id ~= removedId, true, "the removed row is gone")

    local mrid = M.add({ itemId = 1003, link = "item:1003" })
    test.eq(M.project()[2].source, "manual", "unresolved item asks for manual input")
    test.eq(M.setPrice(mrid, 1200), true, "manual price is stored")
    test.eq(M.project()[2].price, 1200, "manual price resolves the row")
    test.eq(M.project()[2].source, "manual", "manual source is preserved")

    frame.clearButton.scripts.OnClick(frame.clearButton)
    test.eq(M.state().queueSize, 0, "the clear button empties the queue")

    test.eq(type(SlashCmdList["BGNQUEUE"]), "function", "slash command is registered")
    test.eq(_G.SLASH_BGNQUEUE1, "/bgnqueue", "slash trigger is installed")
    local mainFrame = fakeFrame("MainFrame")
    BG.ButtonCurrentTradeRecord = nil
    BG.ButtonRoleOverview = nil
    local entry = M.installEntry(mainFrame)
    test.eq(type(entry), "table", "the main-tab entry button is built")
    test.eq(entry.text, "待拍队列", "the entry is labelled with the queue title")
    local roleEntry = fakeFrame("RoleOverview")
    local tradeEntry = fakeFrame("TradeRecord")
    BG.ButtonRoleOverview = roleEntry
    BG.ButtonCurrentTradeRecord = tradeEntry
    test.eq(M.installEntry(mainFrame), entry, "reinstall reuses the queue entry")
    test.eq(entry.point[2], tradeEntry,
        "a late footer relayout moves the queue left of the record buttons and keeps role overview far right")

    local mainFile = assert(io.open("Core/BiaoGe.lua", "rb"))
    local mainSource = mainFile:read("*a")
    mainFile:close()
    test.eq(mainSource:find("AuctionQueueRuntime.installEntry", 1, true) ~= nil, true,
        "main footer asks the queue to relayout after role and settlement entries exist")

    -- --- Finding 7: exact loopback binding (auctionID, not itemID) ---------

    freshQueue()
    local b1 = M.add({ itemId = 1001, link = "item:1001", quantity = 2 })
    test.eq(M.confirm(b1), true, "confirm opens without starting")
    loopback(1001, 777)
    test.eq(M.project()[1].quantity, 2, "a same-item loopback before Start never consumes")
    test.eq(M.state().queueSize, 1, "the quantity-two row is still one row")

    clickStart()
    flushZeroTimers()
    test.eq(M.state().pendingFired, true, "Start marks the pending fired")
    loopback(1001, 999)
    test.eq(M.project()[1].quantity, 2, "a wrong auctionID loopback is ignored")
    loopback(1001, lastAuctionID())
    test.eq(M.project()[1].quantity, 1, "the exact auctionID decrements exactly once")
    test.eq(M.state().hasPending, false, "the round-trip clears the pending")
    loopback(1001, lastAuctionID())
    test.eq(M.project()[1].quantity, 1, "a repeated loopback never consumes again")

    -- --- Counterexample 3: causal binding in the BG.After(0) window ---------

    freshQueue()
    local cid = M.add({ itemId = 1001, link = "item:1001", quantity = 2 })
    test.eq(M.confirm(cid), true, "confirm opens")
    clickStart()
    test.eq(M.state().pendingFired, true, "Start marks the pending fired")
    -- A foreign same-item sender runs before the queue's own zero-delay send.
    local foreignID = BG.SendStartAuctionMsg(1001, 777, 40, "item:1001")
    flushZeroTimers()
    local ownID = lastAuctionID()
    test.eq(ownID ~= foreignID, true, "foreign and own sends have distinct ids")
    test.eq(M.state().pendingAuctionID, ownID, "the queue binds only its own auctionID")
    loopback(1001, foreignID)
    test.eq(M.project()[1].quantity, 2, "a foreign loopback never consumes the queue row")
    loopback(1001, ownID)
    test.eq(M.project()[1].quantity, 1, "the own loopback consumes exactly once")
    test.eq(M.state().hasPending, false, "the own round-trip clears the pending")

    -- --- Counterexample 2: quick-money success binds and consumes once -------

    freshQueue()
    local q2 = M.add({ itemId = 1002, link = "item:1002", quantity = 2 })
    test.eq(M.confirm(q2), true, "confirm opens the quantity-two row")
    test.eq(BG.StartAucitonFrame.bt.money, 500, "approved base price bound to the button")
    clickFast(2) -- the 500 fast-money button matches the approved amount
    test.eq(M.state().pendingFired, true, "the fast path marks the pending fired")
    flushZeroTimers()
    test.eq(sends, 1, "the fast path sends once")
    test.eq(sentRecords[1].money, 500, "the fast path sends the approved amount")
    local ownFastID = lastAuctionID()
    test.eq(M.state().pendingAuctionID, ownFastID, "the fast path records the exact own auctionID")
    loopback(1002, ownFastID)
    test.eq(M.project()[1].quantity, 1, "the correct loopback decrements 2 -> 1")
    test.eq(M.state().hasPending, false, "the round-trip clears the pending")
    loopback(1002, ownFastID)
    test.eq(M.project()[1].quantity, 1, "a repeated loopback never consumes again")

    -- --- Counterexample 4: approved 500 never replaced by 100 or 999 ---------

    -- Stale global 100 never wins (button + enter).
    for _, path in ipairs({ { name = "button", run = clickStart }, { name = "enter", run = pressEnter } }) do
        freshQueue()
        BiaoGe.Auction.money = 100
        local p = M.add({ itemId = 1003, link = "item:1003" })
        test.eq(M.setPrice(p, 500), true, path.name .. ": manual 500 stored")
        test.eq(M.confirm(p), true, path.name .. ": manual confirm opens")
        test.eq(BG.StartAucitonFrame.bt.money, 500, path.name .. ": approved bound")
        path.run()
        flushZeroTimers()
        test.eq(sends, 1, path.name .. ": sends once with a stale global")
        test.eq(sentRecords[1].money, 500, path.name .. ": never sends the stale global 100")
    end

    -- An edited 999 blocks button + enter (never 999).
    for _, path in ipairs({ { name = "button", run = clickStart }, { name = "enter", run = pressEnter } }) do
        freshQueue()
        BiaoGe.Auction.money = 100
        local p = M.add({ itemId = 1003, link = "item:1003" })
        test.eq(M.setPrice(p, 500), true, path.name .. ": manual 500 stored")
        test.eq(M.confirm(p), true, path.name .. ": manual confirm opens")
        BG.StartAucitonFrame.Edit2:SetText("999")
        path.run()
        flushZeroTimers()
        test.eq(sends, 0, path.name .. ": never silently sends the edited 999")
        test.eq(M.state().pendingFired, false, path.name .. ": edited 999 never fires")
        BG.StartAucitonFrame:Hide()
    end

    -- A non-matching fast amount is blocked, and the matching one succeeds.
    freshQueue()
    BiaoGe.Auction.money = 100
    local p3 = M.add({ itemId = 1003, link = "item:1003" })
    M.setPrice(p3, 500)
    M.confirm(p3)
    clickFast(1) -- 300
    flushZeroTimers()
    test.eq(sends, 0, "a fast 300 never replaces the approved 500")
    test.eq(M.state().pendingFired, false, "a fast 300 never fires")
    BG.StartAucitonFrame:Hide()

    freshQueue()
    BiaoGe.Auction.money = 100
    local p4 = M.add({ itemId = 1003, link = "item:1003" })
    M.setPrice(p4, 500)
    M.confirm(p4)
    clickFast(2) -- 500 == approved
    test.eq(M.state().pendingFired, true, "the matching fast 500 fires")
    flushZeroTimers()
    test.eq(sends, 1, "the matching fast 500 sends once")
    test.eq(sentRecords[1].money, 500, "the matching fast 500 sends the approved 500")

    -- --- Counterexample 5: integer zero and invalid amounts ------------------

    for _, path in ipairs({ { name = "button", run = clickStart }, { name = "enter", run = pressEnter } }) do
        freshQueue()
        local z = M.add({ itemId = 1003, link = "item:1003" })
        test.eq(M.setPrice(z, 0), true, path.name .. ": manual zero accepted")
        test.eq(M.confirm(z), true, path.name .. ": zero-price row confirmable")
        test.eq(BG.StartAucitonFrame.bt.money, 0, path.name .. ": zero bound to the button")
        path.run()
        flushZeroTimers()
        test.eq(sends, 1, path.name .. ": zero-price row sends once")
        test.eq(sentRecords[1].money, 0, path.name .. ": zero is sent as zero")
    end

    -- A fast amount would change the zero price, so it is blocked.
    freshQueue()
    local z2 = M.add({ itemId = 1003, link = "item:1003" })
    M.setPrice(z2, 0)
    M.confirm(z2)
    clickFast(1) -- 300
    flushZeroTimers()
    test.eq(sends, 0, "a fast amount never silently changes a zero-price row")

    -- Negative, fractional, NaN and over-ceiling amounts are all rejected.
    freshQueue()
    local bad = M.add({ itemId = 1003, link = "item:1003" })
    test.eq(M.setPrice(bad, -1), false, "negative price rejected")
    test.eq(M.setPrice(bad, 12.5), false, "fractional price rejected")
    test.eq(M.setPrice(bad, 0 / 0), false, "NaN price rejected")
    test.eq(M.setPrice(bad, 10000001), false, "over-ceiling price rejected")
    test.eq(M.project()[1].source, "manual", "the bad row stays unresolved")
    test.eq(M.confirm(bad), false, "an unresolved row cannot be confirmed")

    -- --- Counterexample 6: 40 rows stay on-screen with bounded scrolling -----

    freshQueue()
    for i = 1, 40 do
        M.add({ itemId = 5000 + i, link = "item:" .. (5000 + i) })
    end
    test.eq(M.state().queueSize, 40, "forty rows are accepted")

    -- The 41st row is rejected while the queue is full.
    local overflow = M.add({ itemId = 6000, link = "item:6000" })
    test.eq(overflow, nil, "the 41st row is rejected")
    M.addFromText("item:6000")
    test.eq(messages[#messages], "待拍队列已满（最多40项）", "a localized full-queue message is shown")
    test.eq(M.state().queueSize, 40, "a rejected typed add never grows the queue")

    local full = M.openFrame()
    test.eq(type(full.maxVisible), "number", "the viewport exposes a visible-row cap")
    test.eq(full:GetHeight() <= 768, true, "the frame height fits the 768 viewport")
    test.eq(type(M.scrollToBottom), "function", "a scroll API is exposed")
    M.scrollToBottom()
    local id40 = M.project()[40].id
    local lastSlot = full.rows[full.maxVisible]
    test.eq(lastSlot ~= nil, true, "the last visible slot exists")
    test.eq(lastSlot.id, id40, "the 40th row is reachable and bound after scrolling")
    lastSlot.remove.scripts.OnClick(lastSlot.remove)
    test.eq(M.state().queueSize, 39, "the 40th row is operable after scrolling")

    -- The up/down arrow buttons keep working alongside the wheel enable.
    M.scrollToTop()
    test.eq(full.scrollOffset, 0, "scrollToTop resets the offset")
    full.scrollDown.scripts.OnClick(full.scrollDown)
    test.eq(full.scrollOffset, 1, "the down arrow scrolls forward one")
    full.scrollUp.scripts.OnClick(full.scrollUp)
    test.eq(full.scrollOffset, 0, "the up arrow scrolls back to the top")

    -- --- Finding 6: the runtime never sends directly ------------------------

    local file = assert(io.open("Core/BGNext/AuctionQueueRuntime.lua", "rb"))
    local source = file:read("*a")
    file:close()
    for _, token in ipairs({
        "BG.SendStartAuctionMsg(",
        "SendAddonMessage",
        "C_ChatInfo.SendAddonMessage",
        "SendChatMessage",
    }) do
        test.eq(source:find(token, 1, true), nil, "no direct " .. token .. " call in the runtime")
    end
    test.eq(source:find("BG.StartAuction", 1, true) ~= nil, true, "the runtime reuses the existing start path")
    test.eq(source:find("onPreSend", 1, true) ~= nil, true, "the runtime installs the authoritative pre-send gate")
    test.eq(source:find("onAuctionSent", 1, true) ~= nil, true, "the runtime captures the causal auctionID")
end
