return function(test)
    -- Real CHAT_MSG_LOOT registration and real bill writes; only client APIs/UI
    -- are fixtures. Keep globals isolated from the rest of the Lua suites.
    local function fixture(raidId)
        raidId = raidId or "ULDtitan"
        local e = setmetatable({}, { __index = _G })
        e._G = e
        local f = { events = {}, timers = {}, loads = {}, messages = {}, now = 100, ready = false }
        local function noop() end
        local function widget(name)
            return setmetatable({ text = "", GetName = function() return name or "fixture" end,
                AddMessage = function(_, message) table.insert(f.messages, message) end,
                SetText = function(self, text) self.text = text end,
                GetText = function(self) return self.text end,
                IsVisible = function() return false end,
                CreateFontString = function() return widget("font") end,
            }, { __index = function() return noop end })
        end
        e.tinsert, e.strmatch, e.format = table.insert, string.match, string.format
        e.GetTime = function() return f.now end
        e.GetServerTime = e.GetTime
        e.CreateFrame = function(_, name) return widget(name) end
        e.SetLootMethod, e.GetLootMethod = noop, noop
        e.IsInRaid = function() return true end
        e.IsInGroup = e.IsInRaid
        e.GetInstanceInfo = function() return "Ulduar", "raid", 4, nil, nil, nil, nil, 603 end
        e.GetRaidDifficultyID = function() return 4 end
        e.GetItemInfo = function(link)
            if not f.ready then return nil end
            if type(link) == "number" then link = "item:" .. link end
            return "item", link, f.quality or 4, 225, nil, nil, nil, f.stack or 1, nil, 123, nil, f.typeID or 4, f.subclassID or 1, f.bindType or 1
        end
        local function itemID(link) return type(link) == "string" and tonumber(link:match("item:(%d+)")) end
        e.GetItemInfoInstant = itemID
        e.UnitClass = function() return "Warrior", "WARRIOR" end
        local init = {}
        e.BiaoGe = { options = { autoLoot = 1 }, point = {}, [raidId] = {} }
        local bg = { IsTitan = true, playerName = "Fixture", options = {}, Movetable = {},
            Init = function(fn) init[#init + 1] = fn end, Init2 = noop,
            RegisterEvent = function(names, fn)
                if type(names) == "string" then names = { names } end
                for _, name in ipairs(names) do
                    f.events[name] = f.events[name] or {}
                    table.insert(f.events[name], fn)
                end
            end,
            IsSecret = function() return false end, FB1 = raidId, FB2 = raidId,
            Loot = { blacklist = {}, whitelist = {}, stackItems = {}, noStackItems = {},
                itemToBoss = {}, zaXiangItems = {} },
            lootQuality = { [raidId] = 4 }, Frame = { [raidId] = {} }, DuiZhangFrame = { [raidId] = {} },
            GetMaxi = function() return 2 end, GetItemCount = function() return 0 end,
            LootFilterClassItem = function() return "" end, Tooltip_SetItemByID = noop,
            ItemLibMainFrame = widget(), IsHope = function() return false end,
            GetLeiTingItem = function(id) return id end,
            GetBossIndexByBossID = function(id) return id end,
            After = function(delay, fn) table.insert(f.timers, { at = f.now + delay, run = fn }) end,
            OnItemLoad = function(link)
                return { ContinueOnItemLoad = function(_, fn) table.insert(f.loads, fn) end }
            end,
        }
        e.BG = bg
        for b = 1, 16 do
            e.BiaoGe[raidId]["boss" .. b] = {}
            bg.Frame[raidId]["boss" .. b] = {}
            bg.DuiZhangFrame[raidId]["boss" .. b] = {}
            for i = 1, 2 do
                bg.Frame[raidId]["boss" .. b]["zhuangbei" .. i] = widget()
                bg.DuiZhangFrame[raidId]["boss" .. b]["zhuangbei" .. i] = widget()
            end
        end
        for _, key in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
            "LOOT_ITEM_MULTIPLE", "LOOT_ITEM_PUSHED_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF",
            "LOOT_ITEM", "LOOT_ITEM_PUSHED", "LOOT_ITEM_BONUS_ROLL_SELF", "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE" }) do
            e[key] = key .. ":%s"
            if key:find("MULTIPLE") then e[key] = key .. ":%sx%d" end
        end
        local ns = { L = setmetatable({}, { __index = function(_, key) return key end }), RR = "",
            GetClassRGB = function() return 1, 1, 1 end, GetItemID = itemID,
            AddTexture = function() return "" end, Maxb = { [raidId] = 16 } }
        setfenv(assert(loadfile("Core/Module/Loot.lua")), e)("BGNext", ns)
        init[1]()
        function f.emit(name, ...)
            for _, fn in ipairs(f.events[name] or {}) do fn(nil, name, ...) end
        end
        function f.advance(seconds)
            f.now = f.now + seconds
            local timers = f.timers
            f.timers = {}
            for _, timer in ipairs(timers) do
                if timer.at <= f.now then timer.run() else table.insert(f.timers, timer) end
            end
        end
        function f.load()
            f.ready = true
            for _, fn in ipairs(f.loads) do fn() end
        end
        function f.item(b, i) return e.BiaoGe[raidId]["boss" .. b]["zhuangbei" .. (i or 1)] end
        f.env, f.bg = e, bg
        return f
    end

    local f = fixture()
    f.emit("ENCOUNTER_START", 1)
    f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:45132")
    test.eq(f.item(1), nil, "uncached item waits without writing")
    f.load()
    f.advance(0.2)
    test.eq(f.item(1), "item:45132", "loaded item reaches the real bill")

    f = fixture()
    f.ready = true
    f.emit("ENCOUNTER_START", 1)
    f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:45132")
    f.advance(0.2)
    test.eq(f.item(1), "item:45132", "cached item keeps the original path")
    test.eq(#f.loads, 0, "cached loot never starts a metadata request")

    f = fixture()
    f.emit("ENCOUNTER_START", 1)
    f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:45132")
    f.emit("ENCOUNTER_START", 2)
    f.load()
    f.advance(0.2)
    test.eq(f.item(1), "item:45132", "late metadata retains original boss")
    test.eq(f.item(2), nil, "late metadata never writes the next boss")

    f = fixture()
    f.emit("ENCOUNTER_START", 1)
    f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:45132")
    f.emit("PLAYER_LEAVING_WORLD")
    f.load()
    f.advance(0.2)
    test.eq(f.item(1), nil, "world leave cancels pending writes")

    -- A zone notification alone is not proof of a changed loot scope.
    for _, beforeLoad in ipairs({ true, false }) do
        f = fixture()
        f.emit("ENCOUNTER_START", 1)
        f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:45132")
        if not beforeLoad then f.load() end
        f.emit("ZONE_CHANGED_NEW_AREA")
        if beforeLoad then f.load() end
        f.advance(0.2)
        test.eq(f.item(1), "item:45132", "unchanged scope preserves pending and scheduled loot")
    end

    -- Metadata completion and the existing 0.1s bill timer are both guarded.
    for _, change in ipairs({
        function(f) f.bg.InvalidatePendingLoot("ULDtitan") end,
        function(f) f.emit("GROUP_LEFT") end,
        function(f)
            f.env.GetInstanceInfo = function() return "Other", "raid", 4, nil, nil, nil, nil, 533 end
            f.emit("ZONE_CHANGED_NEW_AREA")
        end,
        function(f) f.bg.FB2 = "NAXX" end,
        function(f) f.env.GetInstanceInfo = function() return "Other", "raid", 4, nil, nil, nil, nil, 533 end end,
        function(f) f.env.GetInstanceInfo = function() return "Ulduar", "raid", 3, nil, nil, nil, nil, 603 end end,
        function(f) f.env.BiaoGe.options.autoLoot = 0 end,
        function(f) f.env.BiaoGe.ULDtitan = {} end,
    }) do
        for _, beforeLoad in ipairs({ true, false }) do
            f = fixture()
            f.emit("ENCOUNTER_START", 1)
            f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:45132")
            if not beforeLoad then f.load() end
            change(f)
            if beforeLoad then f.load() end
            f.advance(0.2)
            test.eq(f.bg.Frame.ULDtitan.boss1.zhuangbei1:GetText(), "", "invalidated scope cannot write")
        end
    end

    f = fixture()
    f.emit("ENCOUNTER_START", 1)
    f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:45132")
    f.advance(15)
    test.eq(#f.messages, 1, "failed load gives a local manual-record warning")
    f.load()
    f.advance(0.2)
    test.eq(f.item(1), nil, "expired loader cannot resurrect a drop")

    f = fixture()
    f.emit("ENCOUNTER_START", 1)
    f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:45132")
    f.advance(14.95)
    f.load()
    f.advance(0.2)
    test.eq(f.item(1), "item:45132", "accepted load survives the short bill-write timer")

    f = fixture()
    f.emit("ENCOUNTER_START", 1)
    f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:45132")
    f.load()
    f.load()
    f.advance(0.2)
    test.eq(f.item(1), "item:45132", "first loader completion writes")
    test.eq(f.item(1, 2), nil, "duplicate completion never double records")

    -- Independent copies remain independent events, even for the same item.
    f = fixture()
    f.emit("ENCOUNTER_START", 1)
    f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:45132")
    f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:45132")
    f.load()
    f.advance(0.2)
    test.eq(f.item(1, 2), "item:45132", "two actual drops each get a row")

    for _, ready in ipairs({ true, false }) do
        for _, rule in ipairs({ "quality", "blacklist", "quest", "gem", "disenchant" }) do
            f = fixture()
            f.ready = ready
            if rule == "quality" then f.quality = 2 end
            if rule == "blacklist" then f.bg.Loot.blacklist[45132] = true end
            if rule == "quest" then f.bindType = 4 end
            if rule == "gem" then f.typeID = 3 end
            if rule == "disenchant" then f.typeID, f.subclassID = 7, 12 end
            f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:45132")
            if not ready then f.load() end
            f.advance(0.2)
            test.eq(f.item(15), nil, rule .. " remains filtered")
        end
        f = fixture()
        f.ready, f.quality = ready, 2
        f.bg.Loot.whitelist[45132] = true
        f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:45132")
        if not ready then f.load() end
        f.advance(0.2)
        test.eq(f.item(15), "item:45132", "whitelist still bypasses quality")

        f = fixture()
        f.ready = ready
        f.bg.Loot.itemToBoss.ULDtitan = { [45132] = 3 }
        f.emit("ENCOUNTER_START", 1)
        f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:45132")
        if not ready then f.load() end
        f.advance(0.2)
        test.eq(f.item(3), "item:45132", "special boss routing survives")

        f = fixture()
        f.ready = ready
        f.bg.Loot.stackItems[270187] = true
        f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF_MULTIPLE:item:270187x3")
        if not ready then f.load() end
        test.eq(f.item(15), "item:270187x3", "fragment chat quantity reaches misc")

        f = fixture()
        f.ready = ready
        f.bg.Loot.stackItems[270187] = true
        local fragment = "|cffa335ee|Hitem:270187::::::::|h[Fragment]|h|r"
        f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF_MULTIPLE:" .. fragment .. "x3")
        f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF_MULTIPLE:" .. fragment .. "x2")
        if not ready then f.load() end
        test.eq(f.item(15), fragment .. "x5", "two fragment drops accumulate actual quantities")

        f = fixture()
        f.ready, f.stack = ready, 200
        f.bg.Loot.noStackItems[45132] = true
        f.emit("ENCOUNTER_START", 1)
        f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:45132")
        if not ready then f.load() end
        f.advance(0.2)
        test.eq(f.item(1), "item:45132", "nonstack override preserves boss routing")

        f = fixture()
        f.ready = ready
        f.bg.Loot.zaXiangItems[270157] = true
        f.emit("ENCOUNTER_START", 1)
        f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:270157")
        if not ready then f.load() end
        f.advance(0.2)
        test.eq(f.item(15), "item:270157", "upgrade material keeps misc routing")
    end

    f = fixture("ICC")
    f.bg.IsTitan, f.bg.IsWLK = false, true
    f.emit("ENCOUNTER_START", 1)
    f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:50730")
    f.load()
    f.advance(0.2)
    test.eq(f.item(1), "item:50730", "legacy raid cache miss still records")

    f = fixture("TOC")
    f.bg.Loot.TOC = { N25 = { boss3 = { 45132 }, boss4 = {} }, H25 = { boss6 = { 45132 } } }
    f.emit("ENCOUNTER_START", 1)
    f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:45132")
    f.env.GetRaidDifficultyID = function() return 6 end
    f.load()
    f.advance(0.2)
    test.eq(f.item(3), "item:45132", "legacy TOC box uses event-time difficulty")

    for _, ready in ipairs({ true, false }) do
        for _, blocked in ipairs({ "trade", "merchant", "quest" }) do
            f = fixture()
            f.ready = ready
            f.env.C_Timer = { After = f.bg.After }
            f.env.GetTradeTargetItemInfo = function() return "item" end
            if blocked == "trade" then f.emit("TRADE_ACCEPT_UPDATE", 1) end
            if blocked == "merchant" then f.emit("MERCHANT_UPDATE") end
            if blocked == "quest" then f.emit("QUEST_TURNED_IN") end
            f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:45132")
            test.eq(#f.loads, 0, blocked .. " never queues excluded self loot")
            f.load()
            f.advance(0.2)
            test.eq(f.item(15), nil, blocked .. " never records excluded self loot")
        end
    end

    f = fixture()
    f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:not-an-item")
    test.eq(#f.loads, 0, "invalid link never requests metadata")

    -- Execute the real clearing entry, without constructing its unrelated UI.
    -- This is the same function body defined by BG.ClearBiaoGeUI at runtime.
    f = fixture()
    local sourceFile = assert(io.open("Core/Module/ClearBiaoGe.lua", "rb"))
    local source = sourceFile:read("*a")
    sourceFile:close()
    local first = assert(source:find("    function BG.ClearBiaoGeByIndex", 1, true))
    local last = assert(source:find("    -- Automatic new-lockout cleanup", first, true))
    f.env.Maxb = { ULDtitan = 16 }
    f.bg.Maxi, f.bg.playerClass = 0, {}
    for i = 1, 2 do
        local row = f.bg.Frame.ULDtitan.boss1
        row["maijia" .. i], row["jine" .. i] = row["zhuangbei" .. i], row["zhuangbei" .. i]
        row["qiankuan" .. i], row["guanzhu" .. i] = row["zhuangbei" .. i], row["zhuangbei" .. i]
        f.bg.DuiZhangFrame.ULDtitan.boss1["myjine" .. i] = row["zhuangbei" .. i]
    end
    setfenv(assert(loadstring(source:sub(first, last - 1))), f.env)()
    f.emit("ENCOUNTER_START", 1)
    f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:45132")
    f.bg.ClearBiaoGeByIndex("ULDtitan", 1)
    f.load()
    f.advance(0.2)
    test.eq(f.item(1), nil, "actual row clearing invalidates pending loot")

    f = fixture()
    for i = 1, 129 do f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:45132") end
    test.eq(#f.loads, 128, "pending load count is bounded")
    test.eq(#f.messages, 1, "overflow gives local manual fallback")
    f.bg.InvalidatePendingLoot("ULDtitan")
    f.advance(15)
    f.load()
    f.advance(0.2)
    test.eq(f.item(15), nil, "cancelled capacity batch cannot write")
    test.eq(#f.messages, 1, "cancelled pending loads do not emit stale warnings")

    f = fixture()
    f.emit("ENCOUNTER_START", 1)
    f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:45132")
    f.bg.InvalidatePendingLoot("ICC")
    f.load()
    f.advance(0.2)
    test.eq(f.item(1), "item:45132", "clearing a different table preserves pending loot")

    for _, cancel in ipairs({ false, true }) do
        f = fixture("TOCtitan")
        f.stack, f.typeID = 200, 7
        f.bg.Loot.itemPack = { [270187] = 270148 }
        f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:270187")
        f.ready = true
        f.loads[1]()
        test.eq(#f.loads, 2, "legacy packed material requests its display item")
        if cancel then f.bg.InvalidatePendingLoot("TOCtitan") end
        f.loads[2]()
        local expected
        if not cancel then expected = "item:270148" end
        test.eq(f.item(15), expected, "packed material follows scope")
    end
end
