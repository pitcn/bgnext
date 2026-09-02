return function(test)
    BG = { BGNext = {} }
    local Collector = dofile("Core/BGNext/OwnCharactersCollector.lua")

    local function baseEnv(overrides)
        local env = {
            family = "titan",
            now = function() return 1000 end,
            playerName = function() return "Piti" end,
            realmId = function() return 123 end,
            realmName = function() return "时光II" end,
            faction = function() return "Alliance" end,
            class = function() return "HUNTER" end,
            level = function() return 80 end,
            itemLevel = function() return 230.75 end,
            money = function() return 50000 end,
            equipment = function() return {} end,
            raidStates = function() return {} end,
            resources = function() return {} end,
            professions = function() return {} end,
        }
        -- `false` means "this client does not expose the API at all"; nil
        -- cannot express that because pairs() skips it.
        for key, value in pairs(overrides or {}) do
            if value == false then env[key] = nil else env[key] = value end
        end
        return env
    end

    local snapshot = Collector.collect(baseEnv())
    test.eq(snapshot.player, "Piti", "collects logged-in player")
    test.eq(snapshot.realmId, 123, "collects own realm")
    test.eq(snapshot.realmName, "时光II", "collects own realm name")
    test.eq(snapshot.class, "HUNTER", "collects own class")
    test.eq(snapshot.level, 80, "collects own level")
    test.eq(snapshot.itemLevel, 230.75, "collects own item level")
    test.eq(snapshot.money, 50000, "collects own money")
    test.eq(snapshot.updatedAt, 1000, "stamps the observation time")

    -- The collector reads the current character only. There is no parameter
    -- through which another player's name or a unit token could be supplied.
    for _, reader in ipairs({ "playerName", "class", "level", "itemLevel", "money", "equipment" }) do
        local received = {}
        local env = baseEnv({
            [reader] = function(...)
                received = { ... }
                return nil
            end,
        })
        Collector.collect(env)
        test.eq(#received, 0, reader .. " is called with no unit or player argument")
    end

    -- Missing APIs yield a partial snapshot instead of an error or a fake value.
    local partial = Collector.collect(baseEnv({
        itemLevel = false, money = false, equipment = false,
        professions = false, resources = false, raidStates = false,
    }))
    test.eq(partial.player, "Piti", "partial snapshot keeps identity")
    test.eq(partial.itemLevel, nil, "missing item level API stays empty")
    test.eq(partial.money, nil, "missing money API stays empty")
    test.eq(partial.equipment, nil, "missing equipment API stays empty")

    -- Protected or throwing APIs are swallowed, not propagated.
    local guarded = Collector.collect(baseEnv({
        money = function() error("protected value") end,
        itemLevel = function() error("secret") end,
    }))
    test.eq(guarded.player, "Piti", "throwing API keeps the rest of the snapshot")
    test.eq(guarded.money, nil, "throwing money API yields no value")
    test.eq(guarded.itemLevel, nil, "throwing item level API yields no value")

    -- Values of the wrong type are discarded rather than stored opaquely.
    local wrongTypes = Collector.collect(baseEnv({
        level = function() return "eighty" end,
        money = function() return {} end,
        equipment = function() return 7 end,
    }))
    test.eq(wrongTypes.level, nil, "non-numeric level is discarded")
    test.eq(wrongTypes.money, nil, "non-numeric money is discarded")
    test.eq(wrongTypes.equipment, nil, "non-table equipment is discarded")

    -- Identity is mandatory: without a name or realm there is no snapshot.
    test.eq(Collector.collect(baseEnv({ playerName = function() return nil end })), nil, "no player name means no snapshot")
    test.eq(Collector.collect(baseEnv({ realmId = function() return nil end })), nil, "no realm id means no snapshot")
    test.eq(Collector.collect(baseEnv({ playerName = function() return "" end })), nil, "empty player name is rejected")
    test.eq(Collector.collect(nil), nil, "missing environment is safe")
    test.eq(Collector.collect({}), nil, "empty environment is safe")

    -- Nested readers are passed through for the model to whitelist.
    local rich = Collector.collect(baseEnv({
        equipment = function() return { [1] = { itemId = 1234, itemLevel = 226 } } end,
        raidStates = function() return { MCtitan = { completed = true, resetsAt = 9000 } } end,
        resources = function() return { currencies = { honor = 15 }, items = { bagFree = 4 } } end,
        professions = function() return { { name = "锻造", skill = 450 } } end,
    }))
    test.eq(rich.equipment[1].itemId, 1234, "equipment is collected")
    test.eq(rich.raidStates.MCtitan.completed, true, "own raid state is collected")
    test.eq(rich.currencies.honor, 15, "currencies are collected")
    test.eq(rich.items.bagFree, 4, "item counts are collected")
    test.eq(rich.professions[1].name, "锻造", "professions are collected")

    -- Profession cooldowns ride the same resources reader as currencies/items.
    local cdCollected = Collector.collect(baseEnv({
        resources = function()
            return { currencies = {}, items = {}, professionCooldowns = { transmute = { ready = true } } }
        end,
    }))
    test.eq(cdCollected.professionCooldowns.transmute.ready, true, "profession cooldowns are collected")
    test.eq(Collector.collect(baseEnv({
        resources = function() return { currencies = {}, items = {} } end,
    })).professionCooldowns, nil, "a resources reader without cooldowns stores none")

    local resourceSelection
    local currencyPatch = Collector.collect(baseEnv({
        resources = function(selection)
            resourceSelection = selection
            return { currencies = { honor = 25 }, items = { bagFree = 7 } }
        end,
    }), { currencies = true })
    test.eq(resourceSelection.currencies, true, "currency refresh scopes the shared resource reader")
    test.eq(resourceSelection.items, nil, "currency refresh does not request bag items")
    test.eq(currencyPatch.currencies.honor, 25, "currency refresh returns currency values")
    test.eq(currencyPatch.items, nil, "currency refresh omits unrequested item values")

    -- Event registration is restricted to a reviewed own-character allowlist.
    local registered = {}
    local frame = {
        RegisterEvent = function(_, event) registered[#registered + 1] = event end,
        SetScript = function() end,
    }
    Collector.installEvents({ frame = frame, family = "titan" }, function() end)
    test.eq(#registered > 0, true, "installEvents registers at least one event")

    local allowed = {}
    for _, event in ipairs(Collector.allowedEvents) do allowed[event] = true end
    local forbidden = {
        "CHAT_MSG_SAY", "CHAT_MSG_WHISPER", "CHAT_MSG_ADDON", "COMBAT_LOG_EVENT",
        "COMBAT_LOG_EVENT_UNFILTERED", "GROUP_ROSTER_UPDATE", "RAID_ROSTER_UPDATE",
        "INSPECT_READY", "TRADE_SHOW", "MAIL_SHOW", "PLAYER_TARGET_CHANGED",
        "UNIT_TARGET", "PARTY_MEMBERS_CHANGED",
    }
    for _, event in ipairs(forbidden) do
        test.eq(allowed[event], nil, event .. " is never in the allowlist")
    end
    for _, event in ipairs(registered) do
        test.eq(allowed[event], true, event .. " was registered from the allowlist")
    end

    -- Debounce collapses bursts into a single snapshot write while preserving
    -- the union of data sections made dirty by the contributing events.
    local writes = 0
    local dirty
    local scheduled = {}
    local burstFrame = { RegisterEvent = function() end, SetScript = function(_, _, fn) scheduled.handler = fn end }
    local ticks = {}
    Collector.installEvents({
        frame = burstFrame,
        family = "titan",
        after = function(delay, fn) ticks[#ticks + 1] = fn end,
    }, function(sections)
        writes = writes + 1
        dirty = sections
    end)
    if scheduled.handler then
        scheduled.handler(burstFrame, "PLAYER_EQUIPMENT_CHANGED")
        scheduled.handler(burstFrame, "PLAYER_EQUIPMENT_CHANGED")
        scheduled.handler(burstFrame, "PLAYER_MONEY")
        test.eq(#ticks, 1, "a burst schedules exactly one refresh")
        ticks[1]()
        test.eq(writes, 1, "a burst produces one snapshot write")
        test.eq(dirty.equipment, true, "equipment events dirty only the equipment section")
        test.eq(dirty.money, true, "money events join the pending dirty-section union")
        test.eq(dirty.raid, nil, "unrelated raid data is not dirtied by the burst")

        for _ = 1, 100 do scheduled.handler(burstFrame, "BAG_UPDATE_DELAYED") end
        test.eq(#ticks, 2, "one hundred bag events schedule one additional refresh")
        ticks[2]()
        test.eq(writes, 2, "one hundred bag events produce one additional snapshot write")
        test.eq(dirty.items, true, "bag bursts dirty only the bag-item section")
        test.eq(dirty.equipment, nil, "a later bag burst does not retain old dirty sections")
    end
end
