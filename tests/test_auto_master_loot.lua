return function(test)
    -- Loads the real Core/Module/Loot.lua; only client APIs are fixtures.
    local function fixture(opts)
        opts = opts or {}
        local e = setmetatable({}, { __index = _G })
        e._G = e
        local f = { events = {}, timers = {}, messages = {}, sets = {}, now = 100,
            method = opts.method or "group", leader = opts.leader ~= false,
            combat = false, instanceType = "raid", mapID = 603, inRaid = true }
        local function noop() end
        local function widget(name)
            return setmetatable({ text = "", GetName = function() return name or "fixture" end,
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
        e.IsInRaid = function() return f.inRaid end
        e.IsInGroup = function() return f.inRaid end
        e.UnitIsGroupLeader = function() return f.leader end
        e.InCombatLockdown = function() return f.combat end
        e.GetInstanceInfo = function() return "Ulduar", f.instanceType, 4, nil, nil, nil, nil, f.mapID end
        e.GetRaidDifficultyID = function() return 4 end
        e.GetLootMethod = function() return f.method end
        e.SetLootMethod = function(method, name)
            table.insert(f.sets, { method, name })
            f.method = method
        end
        e.GetItemInfo = function() return nil end
        e.GetItemInfoInstant = function() return nil end
        e.UnitClass = function() return "Warrior", "WARRIOR" end
        e.BiaoGe = { options = { autoMasterLoot = opts.enabled and 1 or 0 }, point = {} }
        local init = {}
        local bg = { IsTitan = false, playerName = "Fixture", options = {}, Movetable = {},
            Init = function(fn) init[#init + 1] = fn end, Init2 = noop,
            RegisterEvent = function(names, fn)
                if type(names) == "string" then names = { names } end
                for _, name in ipairs(names) do
                    f.events[name] = f.events[name] or {}
                    table.insert(f.events[name], fn)
                end
            end,
            IsSecret = function() return false end, FB1 = "ULDtitan", FB2 = "ULDtitan",
            Loot = { blacklist = {}, whitelist = {}, stackItems = {}, noStackItems = {},
                itemToBoss = {}, zaXiangItems = {} },
            lootQuality = {}, Frame = {}, DuiZhangFrame = {},
            GetMaxi = function() return 2 end, GetItemCount = function() return 0 end,
            LootFilterClassItem = function() return "" end, Tooltip_SetItemByID = noop,
            ItemLibMainFrame = widget(), IsHope = function() return false end,
            GN = function() return opts.name or "Fixture" end,
            SendSystemMessage = function(msg) table.insert(f.messages, msg) end,
            After = function(delay, fn) table.insert(f.timers, { at = f.now + delay, run = fn }) end,
            OnItemLoad = function() return { ContinueOnItemLoad = noop } end,
        }
        e.BG = bg
        for _, key in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
            "LOOT_ITEM_MULTIPLE", "LOOT_ITEM_PUSHED_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF",
            "LOOT_ITEM", "LOOT_ITEM_PUSHED", "LOOT_ITEM_BONUS_ROLL_SELF", "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE" }) do
            e[key] = key .. ":%s"
        end
        local ns = { L = setmetatable({}, { __index = function(_, key) return key end }), RR = "",
            GetClassRGB = function() return 1, 1, 1 end, GetItemID = function() end,
            AddTexture = function() return "" end, Maxb = {} }
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
        f.env, f.bg = e, bg
        return f
    end

    local f = fixture({ enabled = false })
    f.emit("PLAYER_ENTERING_WORLD")
    test.eq(#f.sets, 0, "default off never changes loot method")

    f = fixture({ enabled = true, leader = false })
    f.emit("PLAYER_ENTERING_WORLD")
    test.eq(#f.sets, 0, "non-leader never changes loot method")

    f = fixture({ enabled = true })
    f.inRaid = false
    f.emit("PLAYER_ENTERING_WORLD")
    test.eq(#f.sets, 0, "not in a raid group never changes loot method")

    f = fixture({ enabled = true })
    f.instanceType = "party"
    f.emit("PLAYER_ENTERING_WORLD")
    test.eq(#f.sets, 0, "non-raid instance never changes loot method")
    f.instanceType = "none"
    f.emit("ZONE_CHANGED_NEW_AREA")
    test.eq(#f.sets, 0, "open world never changes loot method")

    f = fixture({ enabled = true, method = "master" })
    f.emit("PLAYER_ENTERING_WORLD")
    test.eq(#f.sets, 0, "already master loot is left alone")
    f.method = 2
    f.emit("ZONE_CHANGED_NEW_AREA")
    test.eq(#f.sets, 0, "numeric master loot (retail enum) is also recognised")

    f = fixture({ enabled = true })
    f.emit("PLAYER_ENTERING_WORLD")
    test.eq(#f.sets, 1, "leader entering a raid switches once")
    test.eq(f.sets[1][1], "master", "uses master loot")
    test.eq(f.sets[1][2], "Fixture", "passes own name")
    f.advance(1.5)
    test.eq(#f.messages, 1, "one chat line after confirmed change")

    -- Same instance is never touched again, even after a manual change.
    f.method = "group"
    f.emit("ZONE_CHANGED_NEW_AREA")
    f.emit("PLAYER_ENTERING_WORLD")
    test.eq(#f.sets, 1, "same instance never changed twice")

    -- Leaving and entering a new instance allows one more change.
    f.instanceType = "none"
    f.emit("ZONE_CHANGED_NEW_AREA")
    f.instanceType, f.mapID = "raid", 533
    f.emit("PLAYER_ENTERING_WORLD")
    test.eq(#f.sets, 2, "new raid instance switches once more")

    -- Forever two-part names are passed through unchanged.
    f = fixture({ enabled = true, name = "Given Surname" })
    f.emit("PLAYER_ENTERING_WORLD")
    test.eq(f.sets[1][2], "Given Surname", "two-part name is preserved")

    -- Combat defers until PLAYER_REGEN_ENABLED, then acts once.
    f = fixture({ enabled = true })
    f.combat = true
    f.emit("PLAYER_ENTERING_WORLD")
    test.eq(#f.sets, 0, "combat defers the change")
    f.combat = false
    f.emit("PLAYER_REGEN_ENABLED")
    test.eq(#f.sets, 1, "leaving combat applies the change")
    f.emit("PLAYER_REGEN_ENABLED")
    test.eq(#f.sets, 1, "later combat exits do not repeat it")

    -- A deferred change is dropped when the player left the raid meanwhile.
    f = fixture({ enabled = true })
    f.combat = true
    f.emit("PLAYER_ENTERING_WORLD")
    f.combat, f.instanceType = false, "none"
    f.emit("PLAYER_REGEN_ENABLED")
    test.eq(#f.sets, 0, "deferred change is discarded outside a raid")

    -- No confirmation line when the client did not accept the change.
    f = fixture({ enabled = true })
    f.env.SetLootMethod = function(method, name) table.insert(f.sets, { method, name }) end
    f.emit("PLAYER_ENTERING_WORLD")
    f.advance(1.5)
    test.eq(#f.messages, 0, "unconfirmed change prints nothing")

    -- Retail namespace fallback.
    f = fixture({ enabled = true })
    f.env.SetLootMethod, f.env.GetLootMethod = nil, nil
    f.env.Enum = { LootMethod = { Masterlooter = 2 } }
    f.env.C_PartyInfo = {
        GetLootMethod = function() return f.method end,
        SetLootMethod = function(method, name) table.insert(f.sets, { method, name }); f.method = method end,
    }
    f.method = 0
    f.emit("PLAYER_ENTERING_WORLD")
    test.eq(#f.sets, 1, "C_PartyInfo fallback is used")
    test.eq(f.sets[1][1], 2, "retail enum value is passed")
end
