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
    UIParent = {}

    -- Core queue must load first.
    local Queue = dofile("Core/BGNext/AuctionQueue.lua")
    BG.BGNext.AuctionQueue = Queue

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
        function f:SetPoint() end
        function f:SetBackdrop() end
        function f:SetBackdropColor() end
        function f:SetBackdropBorderColor() end
        function f:SetFrameStrata() end
        function f:SetFrameLevel() end
        function f:SetClampedToScreen() end
        function f:SetMovable() end
        function f:EnableMouse() end
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
    BiaoGe = { Auction = { money = 100 } }
    BG.SendStartAuctionMsg = function(itemID, money, duration, link)
        auctionIdSeq = auctionIdSeq + 1
        sends = sends + 1
        sentRecords[#sentRecords + 1] = { auctionID = auctionIdSeq, itemID = itemID, money = money }
        return auctionIdSeq
    end
    BG.StartAuction = function(link, bt, isNotAuctioned, notAlt, isRightButton, noSound, callback)
        local itemId = tonumber(tostring(link):match("item:(%d+)")) or 1001
        local frame = fakeFrame("StartAucitonFrame")
        frame.Edit3 = fakeFrame("Edit3")
        frame.Edit3.text = "5"
        frame.Edit2 = fakeFrame("Edit2")
        frame.Edit2.text = tostring(BiaoGe.Auction.money)
        frame.bt = fakeFrame("bt")
        frame.bt.items = { { id = itemId, link = link } }
        frame.bt:SetScript("OnClick", function(self)
            local money = self.money or tonumber(BiaoGe.Auction.money)
            BG.SendStartAuctionMsg(self.items[1].id, money, 40, self.items[1].link)
            frame:Hide()
        end)
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
    BG.BGNext.AuctionPriceStore = { resolveLeaderPriceDetail = defaultResolve }
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
    end

    local function clickStart()
        BG.StartAucitonFrame.bt.scripts.OnClick(BG.StartAucitonFrame.bt)
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

    -- Cancelling (frame hide without a start click) keeps the row and frees the slot.
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
    test.eq(sends, 1, "the original start handler ran once")
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
    loopback(1001, lastAuctionID())
    test.eq(M.state().queueSize, 1, "quantity two becomes one, not removed")
    test.eq(M.project()[1].quantity, 1, "remaining quantity is one")
    test.eq(M.state().hasPending, false, "pending cleared after the round-trip")

    test.eq(M.confirm(M.project()[1].id), true, "second confirm opens again")
    clickStart()
    loopback(1001, lastAuctionID())
    test.eq(M.state().queueSize, 0, "the second confirm removes the last quantity")

    -- --- Finding 1: a timed-out send keeps the entry ------------------------

    freshQueue()
    local tid = M.add({ itemId = 1001, link = "item:1001" })
    M.confirm(tid)
    clickStart()
    test.eq(#after, 1, "a timeout is armed after the send")
    after[1].fn()
    test.eq(M.state().queueSize, 1, "a timed-out send keeps the row")
    test.eq(M.state().hasPending, false, "the timeout frees the pending slot")

    -- --- Finding 2: the second gate re-checks every condition ---------------

    -- Combat gained after opening blocks the send.
    freshQueue()
    local cid = M.add({ itemId = 1001, link = "item:1001" })
    M.confirm(cid)
    InCombatLockdown = function() return true end
    clickStart()
    test.eq(sends, 0, "combat blocks the original handler")
    InCombatLockdown = function() return false end
    BG.StartAucitonFrame:Hide()

    -- Permission lost after opening blocks the send.
    freshQueue()
    local pid = M.add({ itemId = 1001, link = "item:1001" })
    M.confirm(pid)
    BG.IsML = false
    clickStart()
    test.eq(sends, 0, "lost permission blocks the original handler")
    BG.IsML = true
    BG.StartAucitonFrame:Hide()

    -- An active auction card blocks the send.
    freshQueue()
    local aid = M.add({ itemId = 1001, link = "item:1001" })
    M.confirm(aid)
    BGA.Frames[1] = { IsEnd = false }
    clickStart()
    test.eq(sends, 0, "an active auction blocks the original handler")
    BGA.Frames = {}
    BG.StartAucitonFrame:Hide()

    -- A changed price/source snapshot blocks the send.
    freshQueue()
    local sid = M.add({ itemId = 1001, link = "item:1001" })
    M.confirm(sid)
    BG.BGNext.AuctionPriceStore.resolveLeaderPriceDetail = function()
        return { price = 999, source = "override" }
    end
    clickStart()
    test.eq(sends, 0, "a changed price snapshot blocks the original handler")
    BG.BGNext.AuctionPriceStore.resolveLeaderPriceDetail = defaultResolve
    BG.StartAucitonFrame:Hide()

    -- An existing pending start blocks opening a second confirm.
    freshQueue()
    local e1 = M.add({ itemId = 1001, link = "item:1001" })
    local e2 = M.add({ itemId = 1002, link = "item:1002" })
    M.confirm(e1)
    test.eq(M.confirm(e2), false, "a second confirm is blocked while one is pending")
    BG.StartAucitonFrame:Hide()

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

    -- Leaving the raid clears.
    M.add({ itemId = 1001, link = "item:1001" })
    IsInRaid = function() return false end
    M.onRosterUpdate()
    test.eq(M.state().queueSize, 0, "leaving the raid clears the queue")
    IsInRaid = function() return true end

    -- Switching the selected table clears.
    M.add({ itemId = 1001, link = "item:1001" })
    BG.FB1 = "ICC"
    M.ensureQueue()
    test.eq(M.state().queueSize, 0, "switching the table clears the queue")
    BG.FB1 = "ULD"

    -- Clearing the current table clears.
    freshQueue()
    M.add({ itemId = 1001, link = "item:1001" })
    BG.ClearBiaoGe(nil, "ULD")
    test.eq(M.state().queueSize, 0, "clearing the current table clears the queue")
    test.eq(clearCalls, 1, "the original clear still runs")

    -- Leaving the world clears.
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

    -- Open the frame and drive the row controls through the fixed pool.
    local frame = M.openFrame()
    test.eq(type(frame.rows), "table", "frame exposes a row pool")
    test.eq(#frame.rows, 40, "row pool is fixed")
    test.eq(frame.rows[1].shown, true, "the first row is bound and shown")
    test.eq(frame.rows[2].shown, false, "the second pooled row stays hidden")

    -- Quantity +/-.
    frame.rows[1].plus.scripts.OnClick(frame.rows[1].plus)
    test.eq(M.project()[1].quantity, 2, "the plus button increments quantity")
    frame.rows[1].minus.scripts.OnClick(frame.rows[1].minus)
    test.eq(M.project()[1].quantity, 1, "the minus button decrements quantity")

    -- Add a second row, then move it up.
    M.addFromText("item:1002")
    test.eq(M.project()[1].itemId, 1001, "first added item stays first")
    frame.rows[2].up.scripts.OnClick(frame.rows[2].up)
    test.eq(M.project()[1].itemId, 1002, "move up reorders the queue")

    -- Remove the front row.
    local removedId = M.project()[1].id
    frame.rows[1].remove.scripts.OnClick(frame.rows[1].remove)
    test.eq(M.state().queueSize, 1, "remove drops exactly one row")
    test.eq(M.project()[1].id ~= removedId, true, "the removed row is gone")

    -- Manual price for an unresolved item resolves it memory-only.
    local mrid = M.add({ itemId = 1003, link = "item:1003" })
    test.eq(M.project()[2].source, "manual", "unresolved item asks for manual input")
    test.eq(M.setPrice(mrid, 1200), true, "manual price is stored")
    test.eq(M.project()[2].price, 1200, "manual price resolves the row")
    test.eq(M.project()[2].source, "manual", "manual source is preserved")

    -- Clear via the frame button.
    frame.clearButton.scripts.OnClick(frame.clearButton)
    test.eq(M.state().queueSize, 0, "the clear button empties the queue")

    -- Entry reachability: slash command and a main-tab button exist.
    test.eq(type(SlashCmdList["BGNQUEUE"]), "function", "slash command is registered")
    test.eq(_G.SLASH_BGNQUEUE1, "/bgnqueue", "slash trigger is installed")
    local entry = M.installEntry(fakeFrame("MainFrame"))
    test.eq(type(entry), "table", "the main-tab entry button is built")
    test.eq(entry.text, "待拍队列", "the entry is labelled with the queue title")

    -- --- Finding 7: exact loopback binding (auctionID, not itemID) ---------

    -- quantity=2, open confirm but do NOT click Start, then inject a same-item
    -- other-auction frame: the row is untouched.
    freshQueue()
    local b1 = M.add({ itemId = 1001, link = "item:1001", quantity = 2 })
    test.eq(M.confirm(b1), true, "confirm opens without starting")
    loopback(1001, 777)
    test.eq(M.project()[1].quantity, 2, "a same-item loopback before Start never consumes")
    test.eq(M.state().queueSize, 1, "the quantity-two row is still one row")

    -- Click Start, then only the exact auctionID consumes, exactly once.
    clickStart()
    test.eq(M.state().pendingFired, true, "Start marks the pending fired")
    loopback(1001, 999)
    test.eq(M.project()[1].quantity, 2, "a wrong auctionID loopback is ignored")
    loopback(1001, lastAuctionID())
    test.eq(M.project()[1].quantity, 1, "the exact auctionID decrements exactly once")
    test.eq(M.state().hasPending, false, "the round-trip clears the pending")
    loopback(1001, lastAuctionID())
    test.eq(M.project()[1].quantity, 1, "a repeated loopback never consumes again")

    -- --- Finding 8: approved price is bound to the real send amount ---------

    -- manual=500, stale global=100, no edit -> sends 500, never 100.
    freshQueue()
    BiaoGe.Auction.money = 100
    local p1 = M.add({ itemId = 1003, link = "item:1003" })
    test.eq(M.setPrice(p1, 500), true, "manual price 500 stored")
    test.eq(M.confirm(p1), true, "manual price confirm opens")
    test.eq(BG.StartAucitonFrame.bt.money, 500, "button money bound to the approved amount")
    test.eq(BG.StartAucitonFrame.Edit2.text, "500", "dialog displays the approved amount")
    test.eq(BiaoGe.Auction.money, 100, "the saved preset is not mutated")
    clickStart()
    test.eq(sends, 1, "start sends once")
    test.eq(sentRecords[1].money, 500, "the stale global never swaps the approved amount")

    -- manual=500, stale global=100, Edit2 edited to 999 -> blocked, never 999.
    freshQueue()
    BiaoGe.Auction.money = 100
    local p2 = M.add({ itemId = 1003, link = "item:1003" })
    test.eq(M.setPrice(p2, 500), true, "second manual price 500 stored")
    test.eq(M.confirm(p2), true, "second manual confirm opens")
    BG.StartAucitonFrame.Edit2.text = "999"
    clickStart()
    test.eq(sends, 0, "editing the dialog input after confirm blocks the send")
    test.eq(M.state().queueSize, 1, "the row is kept for a fresh confirm")
    test.eq(M.state().pendingFired, false, "the blocked send is not marked fired")
    BG.StartAucitonFrame:Hide()

    -- --- Finding 9: integer zero starting price is sent as zero -------------

    freshQueue()
    local z1 = M.add({ itemId = 1003, link = "item:1003" })
    test.eq(M.setPrice(z1, 0), true, "manual zero price accepted")
    test.eq(M.confirm(z1), true, "zero-price row is confirmable")
    test.eq(BG.StartAucitonFrame.bt.money, 0, "zero bound to the button")
    test.eq(BG.StartAucitonFrame.Edit2.text, "0", "dialog displays zero")
    clickStart()
    test.eq(sends, 1, "zero price sends once")
    test.eq(sentRecords[1].money, 0, "zero is sent as zero through the send path")
    loopback(1003, lastAuctionID())
    test.eq(M.state().queueSize, 0, "the zero-price round-trip consumes the row")

    -- --- Finding 10: the 41st row is rejected with a localized reason -------

    freshQueue()
    for i = 1, 40 do
        M.add({ itemId = 5000 + i, link = "item:" .. (5000 + i) })
    end
    test.eq(M.state().queueSize, 40, "forty rows are accepted")
    local overflow, overflowReason = M.add({ itemId = 6000, link = "item:6000" })
    test.eq(overflow, nil, "the 41st row is rejected")
    test.eq(overflowReason, "queue-full", "the rejection reason is queue-full")
    test.eq(M.state().queueSize, 40, "the queue stays at 40")
    M.addFromText("item:6000")
    test.eq(messages[#messages], "待拍队列已满（最多40项）", "a localized full-queue message is shown")
    test.eq(M.state().queueSize, 40, "a rejected typed add never grows the queue")

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
end
