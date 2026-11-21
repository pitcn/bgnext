return function(test)
    -- Two-client end-to-end auction simulation. Each client loads the REAL
    -- PlayerIdentity, AuctionSender, RaidAuthority, LedgerCapture-free auction
    -- modules (AuctionWA.lua + AuctionWAEvent.lua), the real roster-refresh block
    -- from BiaoGe.lua and the real BG.SendStartAuctionMsg from Auction.lua into
    -- its own sandbox. Clients are wired through a fake SendAddonMessage bus that
    -- delivers every RAID message to every client (sender included) with the
    -- sender name each client would see. Run once for Forever (empty realm,
    -- "名 姓" names, sender == playerName) and once for a normal client with a
    -- cross-realm member.
    local function read(path)
        local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
    end
    local rosterBlock = assert(read("Core/BiaoGe.lua"):match("(%-%-%-%-%-%-%-%-%-%-刷新团队成员信息.-)\n%-%- 插件命令"))
    local sendBlock = assert(read("Core/Module/Auction.lua"):match("(        function BG%.SendStartAuctionMsg%(.-\n        end)\n"))
    local fallbackL = setmetatable({}, { __index = function(_, key) return tostring(key) end })

    local METHOD = { "^Set", "^Get", "^Enable", "^Disable", "^Register", "^Unregister", "^Clear",
        "^Highlight", "^Start", "^Stop", "^Lock", "^Unlock", "^Hook", "^Add", "^Play", "^Raise", "^Lower" }
    local function makeFrame(parent)
        local frame = { scripts = {}, children = {}, text = "", shown = true, enabled = true,
            width = 0, height = 0, min = 0, max = 1000, value = 0, alpha = 1, parent = parent }
        function frame:SetScript(name, handler) self.scripts[name] = handler end
        function frame:GetScript(name) return self.scripts[name] end
        function frame:HookScript(name, handler) self.scripts[name] = handler end
        function frame:SetText(value) self.text = value end
        function frame:GetText() return self.text end
        function frame:SetShown(value) self.shown = value and true or false end
        function frame:Show() self.shown = true end
        function frame:Hide() self.shown = false end
        function frame:IsShown() return self.shown end
        function frame:IsVisible() return self.shown end
        function frame:Enable() self.enabled = true end
        function frame:Disable() self.enabled = false end
        function frame:SetEnabled(v) self.enabled = v and true or false end
        function frame:IsEnabled() return self.enabled end
        function frame:SetSize(w, h) self.width, self.height = w, h end
        function frame:SetWidth(w) self.width = w end
        function frame:SetHeight(h) self.height = h end
        function frame:GetWidth() return self.width end
        function frame:GetHeight() return self.height end
        function frame:GetStringWidth() return 10 end
        function frame:GetWrappedWidth() return self.width end
        function frame:GetParent() return self.parent end
        function frame:GetFrameLevel() return 1 end
        function frame:GetCenter() return 0, 0 end
        function frame:GetTop() return 0 end
        function frame:GetBottom() return 0 end
        function frame:GetLeft() return 0 end
        function frame:GetRight() return 0 end
        function frame:GetPoint() return "TOP" end
        function frame:GetAlpha() return self.alpha end
        function frame:SetAlpha(v) self.alpha = v end
        function frame:SetValue(v) self.value = v end
        function frame:GetValue() return self.value end
        function frame:GetMinMaxValues() return self.min, self.max end
        function frame:SetMinMaxValues(a, b) self.min, self.max = a, b end
        function frame:IsMouseOver() return false end
        function frame:HasFocus() return false end
        function frame:GetNumPoints() return 0 end
        function frame:GetFontString()
            if not self.fontString then self.fontString = makeFrame(self) end
            return self.fontString
        end
        function frame:CreateFontString() local c = makeFrame(self); self.children[#self.children + 1] = c; return c end
        function frame:CreateTexture() local c = makeFrame(self); self.children[#self.children + 1] = c; return c end
        function frame:CreateAnimationGroup() return makeFrame(self) end
        function frame:CreateAnimation() return makeFrame(self) end
        return setmetatable(frame, { __index = function(_, key)
            if type(key) ~= "string" then return nil end
            for _, p in ipairs(METHOD) do
                if key:match(p) then return function() end end
            end
            return nil
        end })
    end

    local function strsplit(delim, subject, maxPieces)
        maxPieces = maxPieces or 0
        subject = subject or ""
        local parts, startIdx, idx = {}, 1, 1
        while true do
            if maxPieces > 0 and idx >= maxPieces then break end
            local pos = string.find(subject, delim, startIdx, true)
            if not pos then break end
            parts[idx] = string.sub(subject, startIdx, pos - 1)
            idx = idx + 1
            startIdx = pos + #delim
        end
        parts[idx] = string.sub(subject, startIdx)
        return unpack(parts, 1, maxPieces > 0 and maxPieces or idx)
    end

    local LINK = "|cffa335ee|Hitem:10001::::::::60:::::|h[测试装备]|h|r"
    local ITEM2 = "|cffa335ee|Hitem:10002::::::::60:::::|h[测试装备二]|h|r"

    -- Builds a world: players = { {name, realm, rank, isML} }. forever => every
    -- realm is "" and names are shown/sent bare; otherwise the sender carries
    -- "-Realm" and the roster shows "-Realm" only for other realms.
    local function makeWorld(forever, everyone)
        local players = {}
        for _, p in ipairs(everyone) do if not p.outsider then players[#players + 1] = p end end
        local world = { now = 1000, queue = {}, clients = {}, afters = {} }
        local function viewName(viewer, p)
            if forever or p.realm == viewer.realm then return p.name end
            return p.name .. "-" .. p.realm
        end
        local function senderName(p)
            if forever then return p.name end
            return p.name .. "-" .. p.realm
        end

        local function makeClient(index)
            local me = players[index]
            local env = setmetatable({}, { __index = _G })
            env._G = env
            local client = { env = env, me = me, index = index, ended = {}, chat = {} }
            local function rosterRow(i)
                local p = players[i]
                if not p then return nil end
                return viewName(me, p), p.rank or 0, 1, 60, "战士", "WARRIOR", "Zone", true, false, nil, p.isML == true, nil
            end
            local items = {}
            local BG = {
                BGNext = {}, IsForever = forever or nil, IsVanilla = true, verLess2 = true,
                playerName = forever and me.name or me.name,
                realmName = forever and "" or me.realm,
                Init = function(cb) cb() end, Init2 = function() end,
                RegisterEvent = function() end,
                GN = function(unit)
                    unit = unit or "player"
                    if unit == "player" then return me.name end
                    if unit == "NPC" then return client.tradeTarget end
                    local i = tonumber(tostring(unit):match("^raid(%d+)$"))
                    return i and (rosterRow(i)) or nil
                end,
                playerClass = { class = { func = function() return "战士", "WARRIOR" end, select = 2 } },
                OnItemLoad = function() return { ContinueOnItemLoad = function(_, fn) fn() end } end,
                AuctionWAEnd = function(...) client.ended[#client.ended + 1] = { ... } end,
                IsSecret = function() return false end,
            }
            env.BG = BG
            env.BiaoGe = { options = {}, Auction = {} }
            env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
            env.C_Timer = { After = function(delay, fn) world.afters[#world.afters + 1] = { delay = delay, fn = fn } end,
                NewTimer = function() return { Cancel = function() end } end,
                NewTicker = function() return { Cancel = function() end } end }
            env.C_ChatInfo = { RegisterAddonMessagePrefix = function() end,
                SendAddonMessage = function(prefix, message, distribution)
                    world.queue[#world.queue + 1] = { prefix = prefix, message = message,
                        distribution = distribution, from = me }
                end }
            env.SOUNDKIT = setmetatable({}, { __index = function() return 1 end })
            env.PlaySound = function() end
            env.CreateFont = function() return makeFrame() end
            env.CreateFrame = function(_, _, parent) return makeFrame(parent) end
            env.UIParent = makeFrame()
            env.GameTooltip = makeFrame()
            env.GameTooltip_Hide = function() end
            env.BIAOGE_TEXT_FONT = "font"
            env.GetRealmName = function() return forever and "" or me.realm end
            env.GetNormalizedRealmName = function() return (not forever) and me.realm or nil end
            env.GetTime = function() return world.now end
            env.GetTimePreciseSec = nil
            env.GetUnitName = function(unit)
                -- Forever's UnitName/GetUnitName has only the given name; BG.GN
                -- adds the surname ("名 姓"), which is what addon senders carry.
                if unit == "player" then return forever and me.name:match("^(%S+)") or me.name end
                return nil
            end
            env.IsInRaid = function() return true end
            env.IsInGroup = function() return true end
            env.GetNumGroupMembers = function() return #players end
            env.GetRaidRosterInfo = rosterRow
            env.UnitIsUnit = function(unit, other)
                return other == "player" and unit == "raid" .. index
            end
            env.UnitIsGroupLeader = function(unit) return unit == "player" and (me.rank == 2) end
            env.IsMasterLooter = function() return me.isML == true end
            env.UnitGUID = function() return nil end
            env.UnitClass = function() return "战士", "WARRIOR" end
            env.Locale = "zhCN"
            env.strlen, env.format, env.strsplit = string.len, string.format, strsplit
            env.tinsert, env.tremove = table.insert, table.remove
            env.securecall = function(fn, ...) return fn(...) end
            env.SendChatMessage = function(msg, channel) client.chat[#client.chat + 1] = { msg = msg, channel = channel } end
            env.GetItemInfo = function(item)
                local link = (tostring(item):find("10002") and ITEM2) or LINK
                return "测试装备", link, 4, 60, 60, "护甲", "板甲", 1, "INVTYPE_CHEST", "icon", 0, 4, 4
            end
            env.GetItemQualityColor = function() return 1, 1, 1 end
            env.GetItemCount = function() return 0 end
            env.GetItemIcon = function() return "icon" end
            env.issecretvalue = nil
            local function load(path, ...)
                local chunk = assert(loadfile(path)); setfenv(chunk, env); return chunk(...)
            end
            load("Core/BGNext/PlayerIdentity.lua")
            load("Core/BGNext/AuctionSender.lua")
            load("Core/BGNext/RaidAuthority.lua")
            load("Core/Module/AuctionWA.lua", "BGNEXT", { LibBG = {}, L = fallbackL })
            load("Core/Module/AuctionWAEvent.lua", "BGNEXT", { LibBG = {}, L = fallbackL })
            local roster = assert(loadstring(rosterBlock)); setfenv(roster, env); roster()
            BG.UpdateRaidRosterInfo()
            local send = assert(loadstring(sendBlock)); setfenv(send, env); send()
            client.wa = env.BGA.aura_env
            client.handler = env.BGA.Event:GetScript("OnEvent")
            client.wa.SetClassCFF = function(player) return player end
            -- The entry points (bag / bill table / loot window) all gate on
            -- BG.CanStartAuction -> BG.IsAuctionController before BG.StartAuction.
            client.canStart = function() return BG.IsAuctionController() == true end
            client.start = function(entry, itemID, link, money)
                if not client.canStart() then client.refused = entry; return nil end
                return BG.SendStartAuctionMsg(itemID, money or 10, 20, link)
            end
            client.frames = function()
                local list = {}
                for _, f in pairs(env.BGA.Frames) do list[#list + 1] = f end
                return list
            end
            client.frameFor = function(itemID)
                for _, f in pairs(env.BGA.Frames) do
                    if f.itemID == itemID and not f.IsEnd then return f end
                end
            end
            client.frameById = function(id)
                for _, f in pairs(env.BGA.Frames) do if f.auctionID == id then return f end end
            end
            return client
        end

        for i = 1, #players do world.clients[i] = makeClient(i) end
        function world.flush()
            local guard = 0
            while #world.queue > 0 do
                guard = guard + 1; assert(guard < 200, "bus loop")
                local m = table.remove(world.queue, 1)
                for _, c in ipairs(world.clients) do
                    c.handler(c.env.BGA.Event, "CHAT_MSG_ADDON", m.prefix, m.message, m.distribution, senderName(m.from))
                end
            end
        end
        function world.injectFrom(p, prefix, message)
            world.queue[#world.queue + 1] = { prefix = prefix, message = message, distribution = "RAID", from = p }
            world.flush()
        end
        function world.advance(seconds)
            world.now = world.now + seconds
            for _, c in ipairs(world.clients) do
                for _, f in pairs(c.env.BGA.Frames) do
                    if f.bar and f.bar.scripts.OnUpdate then f.bar.scripts.OnUpdate(f.bar, seconds) end
                end
            end
        end
        world.senderName = senderName
        world.viewName = viewName
        return world
    end

    local function scenario(label, forever, players)
        local world = makeWorld(forever, players)
        local leader, member, assistant, outsiderP = world.clients[1], world.clients[2], world.clients[3], players[5]
        test.eq(#world.clients, 4, label .. ": four raid clients, outsider not in the raid")
        local ml = world.clients[4]
        local L = function(s) return label .. ": " .. s end

        test.eq(leader.env.BG.IsML, true, L("leader's cached permission set by roster refresh"))
        test.eq(member.env.BG.IsML, nil, L("member has no cached permission"))
        test.eq(assistant.env.BG.IsML, nil, L("assistant has no cached permission"))
        test.eq(ml.env.BG.IsML, true, L("master looter has cached permission"))

        -- Leader starts from each entry (bag / bill / loot) -> every client shows it.
        local entries = { "bag", "bill", "loot" }
        for n, entry in ipairs(entries) do
            world.now = world.now + 1
            local id = leader.start(entry, 10001, LINK, 10 * n)
            test.eq(id ~= nil, true, L(entry .. " entry sends a start"))
            world.flush()
            for _, c in ipairs(world.clients) do
                local f = c.frameById(id)
                test.eq(f ~= nil, true, L(entry .. " start creates the auction frame on client " .. c.index))
                if f then test.eq(f.money, 10 * n, L("start price arrives on client " .. c.index)) end
            end
            -- cancel the extra ones so only the last stays open
            if n < #entries then
                leader.wa.Cancel_OnClick({ owner = leader.frameById(id) })
                world.flush()
                for _, c in ipairs(world.clients) do
                    test.eq(c.frameById(id).IsEnd, true, L("leader cancel ends the auction on client " .. c.index))
                end
                local last = leader.ended[#leader.ended]
                test.eq(last and last[1], 3, L("cancel reports a cancel result to the leader ledger"))
            end
        end
        local liveId
        for _, f in ipairs(leader.frames()) do if not f.IsEnd then liveId = f.auctionID end end
        test.eq(liveId ~= nil, true, L("one auction is live"))

        -- Member bids -> leader (and everyone) accepts; own-bid recognition.
        world.now = world.now + 1
        member.wa.SendMyMoneyMsg(member.frameById(liveId), 50)
        world.flush()
        for _, c in ipairs(world.clients) do
            local f = c.frameById(liveId)
            test.eq(f.money, 50, L("member bid accepted on client " .. c.index))
            test.eq(c.env.BG.BGNext.PlayerIdentity.same(f.player, world.viewName(c.me, member.me), c.env.BG.realmName), true,
                L("bidder identity resolves to the member on client " .. c.index))
        end
        test.eq(member.wa.IsMe(member.frameById(liveId)), true, L("member recognises own top bid"))
        test.eq(leader.wa.IsMe(leader.frameById(liveId)), false, L("leader does not mistake the bid as own"))
        -- An outsider's bid is dropped everywhere.
        world.now = world.now + 2
        world.injectFrom(outsiderP, "BiaoGeAuction", "SendMyMoney," .. liveId .. ",999")
        for _, c in ipairs(world.clients) do
            test.eq(c.frameById(liveId).money, 50, L("outsider bid ignored on client " .. c.index))
        end
        -- Leader outbids, then member again.
        world.now = world.now + 2
        leader.wa.SendMyMoneyMsg(leader.frameById(liveId), 60)
        world.flush()
        test.eq(leader.wa.IsMe(leader.frameById(liveId)), true, L("leader recognises own bid"))
        test.eq(member.frameById(liveId).money, 60, L("member sees leader bid"))
        world.now = world.now + 2
        member.wa.SendMyMoneyMsg(member.frameById(liveId), 70)
        world.flush()
        test.eq(leader.frameById(liveId).money, 70, L("leader sees member's second bid"))

        -- Non-leader / assistant start: refused locally, and a forged message is dropped.
        test.eq(member.start("bag", 10002, ITEM2), nil, L("member start refused at the entry"))
        test.eq(assistant.start("bag", 10002, ITEM2), nil, L("assistant start refused at the entry"))
        world.now = world.now + 1
        local forged = string.format("StartAuction,%s,%s,%s,%s,,%s,%s", world.now, 10002, 10, 20, "normal", ITEM2)
        world.injectFrom(member.me, "BiaoGeAuction", forged)
        world.injectFrom(assistant.me, "BiaoGeAuction", forged)
        for _, c in ipairs(world.clients) do
            test.eq(c.frameFor(10002), nil, L("non-controller start ignored on client " .. c.index))
        end
        -- Forged cancel from member is ignored.
        world.injectFrom(member.me, "BiaoGeAuction", "CancelAuction," .. liveId)
        test.eq(leader.frameById(liveId).IsEnd and true or false, false, L("member cancel ignored"))
        -- Master looter (not leader) may start.
        world.now = world.now + 1
        local mlId = ml.start("loot", 10002, ITEM2, 10)
        test.eq(mlId ~= nil, true, L("master looter start allowed"))
        world.flush()
        for _, c in ipairs(world.clients) do
            test.eq(c.frameById(mlId) ~= nil, true, L("master looter's auction shown on client " .. c.index))
        end
        ml.wa.Cancel_OnClick({ owner = ml.frameById(mlId) })
        world.flush()
        test.eq(member.frameById(mlId).IsEnd, true, L("master looter cancel syncs"))

        -- Pause / resume sync (generation-2 channel carries pause).
        world.now = world.now + 1
        local g2 = world.now
        world.injectFrom(leader.me, "BiaoGeAuction1",
            string.format("StartAuction^%s^%s^%s^%s^^normal^%s^%s", g2, 10002, 10, 30, ITEM2, 3))
        local lf = leader.frameById(g2)
        test.eq(lf ~= nil and member.frameById(g2) ~= nil, true, L("gen2 start shown on both"))
        leader.wa.Pause_OnClick({ owner = lf })
        world.flush()
        test.eq(member.frameById(g2).isPaused, true, L("pause syncs to member"))
        test.eq(lf.isPaused, true, L("pause applies on leader"))
        leader.wa.Pause_OnClick({ owner = lf })
        world.flush()
        test.eq(member.frameById(g2).isPaused and true or false, false, L("resume syncs to member"))
        world.injectFrom(member.me, "BiaoGeAuction1", "PauseAuction^10002")
        test.eq(lf.isPaused and true or false, false, L("member pause ignored"))
        leader.wa.Cancel_OnClick({ owner = lf })
        world.flush()
        test.eq(member.frameById(g2).IsEnd, true, L("gen2 cancel syncs"))

        -- End: countdown runs out, winner reported to the leader ledger.
        world.advance(25)
        local result
        for _, call in ipairs(leader.ended) do if call[1] == 1 then result = call end end
        test.eq(result ~= nil, true, L("auction end reports a sale to the leader"))
        if not result then return end
        test.eq(result[4], 70, L("sale price is the last bid"))
        local buyer = result[3]
        local Identity = leader.env.BG.BGNext.PlayerIdentity
        local realm = leader.env.BG.realmName
        test.eq(Identity.same(buyer, world.viewName(leader.me, member.me), realm), true, L("sale buyer is the member"))

        -- Bill buyer cell (real BillBuyer) and trade matching (real TradeAuctionState).
        local chunk = assert(loadfile("Core/BGNext/BillBuyer.lua")); setfenv(chunk, leader.env); chunk()
        -- Like FBUIfunction's buyer cell: OnTextChanged (fired synchronously by
        -- SetText) stores BillBuyer.canonical(self) as the bill's maijia.
        local edit = makeFrame()
        local stored
        function edit:SetText(value)
            self.text = value
            stored = leader.env.BG.BGNext.BillBuyer.canonical(self)
        end
        leader.env.BG.BGNext.BillBuyer.set(edit, buyer)
        test.eq(type(stored) == "string" and stored ~= "", true, L("bill buyer stored"))
        test.eq(Identity.same(stored, world.viewName(leader.me, member.me), realm), true, L("stored bill buyer is the member"))
        chunk = assert(loadfile("Core/BGNext/TradeAuctionState.lua")); setfenv(chunk, leader.env); chunk()
        local Trade = leader.env.BG.BGNext.TradeAuctionState
        local records = { { type = 1, maijia = stored, zhuangbei = LINK } }
        leader.tradeTarget = world.viewName(leader.me, member.me)
        local marked = Trade.markDelivered(records, leader.env.BG.GN("NPC"), realm,
            { { count = 1, link = LINK } }, function(l) return tonumber(tostring(l):match("item:(%d+)")) end)
        test.eq(marked, 1, L("trading the item to the buyer marks the sale delivered"))
        records[1].trade = nil
        marked = Trade.markDelivered(records, world.viewName(leader.me, assistant.me), realm,
            { { count = 1, link = LINK } }, function(l) return tonumber(tostring(l):match("item:(%d+)")) end)
        test.eq(marked, 0, L("trading to someone else does not mark it"))
    end

    local saved = {}
    for _, k in ipairs({ "BG", "BGA", "BiaoGe" }) do saved[k] = rawget(_G, k) end
    local ok, err = pcall(function()
        scenario("Forever", true, {
            { name = "团 长", realm = "", rank = 2 },
            { name = "成 员", realm = "", rank = 0 },
            { name = "助 理", realm = "", rank = 1 },
            { name = "分 配", realm = "", rank = 0, isML = true },
            { name = "路 人", realm = "", outsider = true },
        })
        scenario("Normal", false, {
            { name = "Lead", realm = "MyRealm", rank = 2 },
            { name = "Bob", realm = "OtherRealm", rank = 0 },
            { name = "Asst", realm = "MyRealm", rank = 1 },
            { name = "Loot", realm = "MyRealm", rank = 0, isML = true },
            { name = "Stray", realm = "FarRealm", outsider = true },
        })
    end)
    for k, v in pairs(saved) do rawset(_G, k, v) end
    for _, k in ipairs({ "BG", "BGA", "BiaoGe" }) do if saved[k] == nil then rawset(_G, k, nil) end end
    if not ok then error(err, 0) end
end