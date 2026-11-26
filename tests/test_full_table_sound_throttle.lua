return function(test)
    -- Unit behavior of the reusable throttle.
    BG = {}
    local throttle = assert(loadfile("Core/BGNext/AlertThrottle.lua"))("BGNext", {})
    test.eq(type(throttle), "table", "throttle module loads")
    local gate = throttle.new(30)
    test.eq(gate.allow(100), true, "first alert is allowed")
    test.eq(gate.allow(100.5), false, "repeat inside the window is suppressed")
    test.eq(gate.allow(129.9), false, "still suppressed just before the window ends")
    test.eq(gate.allow(130), true, "allowed again after the window")
    test.eq(gate.allow(131), false, "a new window starts after each alert")
    test.eq(gate.allow(nil), true, "unknown time never silences a real alert")
    gate.reset()
    test.eq(gate.allow(132), true, "reset re-arms the alert")
    test.eq(gate.allow(10), true, "a clock that went backwards re-arms the alert")

    -- Real Loot.lua full-table path: text every time, sound at most once per 30 seconds.
    local function fixture()
        local raidId = "ULDtitan"
        local e = setmetatable({}, { __index = _G })
        e._G = e
        local f = { events = {}, timers = {}, messages = {}, sounds = {}, now = 100 }
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
            if type(link) == "number" then link = "item:" .. link end
            return "item", link, 4, 225, nil, nil, nil, 1, nil, 123, nil, 4, 1, 1
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
            Boss = { [raidId] = { boss15 = { color = "ffffff", name2 = "miscellaneous" } } },
            GetMaxi = function() return 2 end, GetItemCount = function() return 0 end,
            LootFilterClassItem = function() return "" end, Tooltip_SetItemByID = noop,
            ItemLibMainFrame = widget(), IsHope = function() return false end,
            GetLeiTingItem = function(id) return id end,
            GetBossIndexByBossID = function(id) return id end,
            FrameLootMsg = widget("loot"),
            PlaySound = function(id) table.insert(f.sounds, id) end,
            After = function(delay, fn) table.insert(f.timers, { at = f.now + delay, run = fn }) end,
            OnItemLoad = function() return { ContinueOnItemLoad = noop } end,
        }
        bg.BGNext = { AlertThrottle = throttle }
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
        -- Fill the miscellaneous row (no boss selected => Maxb - 1) so every drop fails.
        for i = 1, 2 do
            bg.Frame[raidId]["boss15"]["zhuangbei" .. i]:SetText("filled")
        end
        function f.loot(id)
            f.emit("CHAT_MSG_LOOT", "LOOT_ITEM_SELF:item:" .. id)
            f.advance(0.2)
        end
        function f.fullSounds()
            local n = 0
            for _, id in ipairs(f.sounds) do if id == "biaogefull" then n = n + 1 end end
            return n
        end
        function f.fullMessages()
            local n = 0
            for _, m in ipairs(f.messages) do if tostring(m):find("格子满了", 1, true) then n = n + 1 end end
            return n
        end
        return f
    end

    local f = fixture()
    f.loot(1001)
    test.eq(f.fullSounds(), 1, "first unrecordable drop plays the full-table sound")
    test.eq(f.fullMessages(), 1, "first unrecordable drop shows the text")
    f.advance(2); f.loot(1002)
    f.advance(2); f.loot(1003)
    test.eq(f.fullSounds(), 1, "repeated drops do not repeat the sound")
    test.eq(f.fullMessages(), 3, "the text message is shown for every failed drop")
    f.advance(25); f.loot(1004)
    test.eq(f.fullSounds(), 1, "still suppressed before 30 seconds have passed")
    f.advance(2); f.loot(1005)
    test.eq(f.fullSounds(), 2, "sound plays again after the 30 second window")
    test.eq(f.fullMessages(), 5, "text is still shown every time")
end
