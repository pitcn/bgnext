return function(test)
    BG = { BGNext = {} }
    dofile("Core/BGNext/OwnCharactersAdapters.lua")
    dofile("Core/BGNext/OwnCharactersCatalog.lua")
    dofile("Core/BGNext/OwnCharactersCollector.lua")
    local Model = dofile("Core/BGNext/OwnCharacters.lua")
    local Runtime = dofile("Core/BGNext/OwnCharactersRuntime.lua")

    local Adapters = BG.BGNext.OwnCharactersAdapters
    local Collector = BG.BGNext.OwnCharactersCollector
    local Catalog = BG.BGNext.OwnCharactersCatalog

    local function build()
        local root = { settings = {} }
        local uiCalls = { refresh = 0 }
        local apiCalls = { raidInfo = 0 }
        local spy = { upsert = 0, expire = 0, clearFamily = 0, clearAll = 0 }
        local model = {
            upsert = function(r, f, s) spy.upsert = spy.upsert + 1 return Model.upsert(r, f, s) end,
            expireRaidStates = function(r, n) spy.expire = spy.expire + 1 return Model.expireRaidStates(r, n) end,
            clearFamily = function(r, f) spy.clearFamily = spy.clearFamily + 1 return Model.clearFamily(r, f) end,
            clearAll = function(r) spy.clearAll = spy.clearAll + 1 return Model.clearAll(r) end,
        }
        local api = {
            time = function() return 5000 end,
            UnitName = function() return "Piti" end,
            GetRealmID = function() return 123 end,
            GetRealmName = function() return "时光II" end,
            UnitFactionGroup = function() return "Alliance" end,
            UnitClass = function() return "猎人", "HUNTER" end,
            UnitLevel = function() return 80 end,
            GetAverageItemLevel = function() return 230 end,
            GetMoney = function() return 50000 end,
            RequestRaidInfo = function() apiCalls.raidInfo = apiCalls.raidInfo + 1 end,
        }
        local deps = {
            globals = { IsTitan = true },
            family = "titan",
            catalog = Catalog.forFamily("titan"),
            root = root,
            api = api,
            adapters = Adapters,
            collector = Collector,
            model = model,
            now = function() return 5000 end,
            ui = { Refresh = function() uiCalls.refresh = uiCalls.refresh + 1 end },
        }
        return deps, root, spy, uiCalls, apiCalls
    end

    -- The full chain runs on collectAndStore and writes a snapshot.
    local deps, root, spy, uiCalls, apiCalls = build()
    local snapshot = Runtime.collectAndStore(deps)
    test.eq(type(snapshot), "table", "collection produces a snapshot")
    test.eq(snapshot.player, "Piti", "the snapshot is the logged-in character")
    test.eq(spy.upsert, 1, "collectAndStore upserts once")
    test.eq(spy.expire, 1, "collectAndStore expires raid states once")
    test.eq(uiCalls.refresh, 1, "collectAndStore refreshes the renderer once")
    test.eq(Model.get(root, "titan", 123, "Piti") ~= nil, true, "the snapshot reached storage")
    test.eq(apiCalls.raidInfo, 0, "ordinary event collection never requests raid data")

    -- Refresh reuses the same safe collection path: it re-reads, not redraw-stale.
    Runtime.refresh(deps)
    test.eq(spy.upsert, 2, "refresh re-collects the current character")
    test.eq(uiCalls.refresh, 2, "refresh re-renders")
    test.eq(apiCalls.raidInfo, 1, "an explicit refresh requests fresh saved-instance data once")

    -- A disabled module collects nothing and touches nothing.
    local d2, root2, spy2, ui2 = build()
    local availability = {}
    d2.entry = { setAvailable = function(value) availability[#availability + 1] = value end }
    Runtime.setEnabled(d2, false)
    test.eq(Runtime.isEnabled(d2), false, "the disable switch reads back")
    test.eq(availability[1], false, "disabling hides and closes the overview entry")
    test.eq(Runtime.collectAndStore(d2), nil, "a disabled module collects nothing")
    test.eq(spy2.upsert, 0, "a disabled module never upserts")
    test.eq(ui2.refresh, 0, "a disabled module never refreshes")

    Runtime.setEnabled(d2, true)
    test.eq(Runtime.isEnabled(d2), true, "re-enabling flips the switch back")
    test.eq(availability[2], true, "re-enabling restores the overview entry")
    test.eq(spy2.upsert, 1, "re-enabling immediately collects the current character")

    -- Clears are forwarded to the model and then re-rendered.
    local d3, root3, spy3, ui3 = build()
    Runtime.collectAndStore(d3)
    Runtime.clearFamily(d3)
    test.eq(spy3.clearFamily, 1, "clearFamily forwards to the model")
    Runtime.clearAll(d3)
    test.eq(spy3.clearAll, 1, "clearAll forwards to the model")

    -- install registers only the reviewed events and collects once immediately.
    local d4, root4, spy4, ui4, api4 = build()
    local registered = {}
    local frame = {
        RegisterEvent = function(_, event) registered[#registered + 1] = event end,
        SetScript = function() end,
    }
    d4.frame = frame
    d4.after = function(delay, fn) end
    Runtime.install(d4)
    test.eq(#registered > 0, true, "install registers events")
    test.eq(spy4.upsert >= 1, true, "install performs an immediate collection")
    test.eq(api4.raidInfo, 1, "install requests saved-instance data once")
    local allowed = {}
    for _, event in ipairs(Collector.allowedEvents) do allowed[event] = true end
    for _, event in ipairs(registered) do
        test.eq(allowed[event], true, "install registered only allowlisted event " .. tostring(event))
    end

    -- Countdown maintenance exists only while the overview is visible.
    local d5, root5, spy5, ui5 = build()
    local tick, interval, cancelled
    d5.newTicker = function(seconds, callback)
        interval = seconds
        tick = callback
        return { Cancel = function() cancelled = true end }
    end
    Runtime.setVisible(d5, true)
    test.eq(interval, 60, "a visible overview uses a low-frequency one-minute ticker")
    test.eq(type(tick), "function", "the visible ticker has a maintenance callback")
    local expireBefore, refreshBefore = spy5.expire, ui5.refresh
    tick()
    test.eq(spy5.expire, expireBefore + 1, "a visible tick expires stale raid state")
    test.eq(ui5.refresh, refreshBefore + 1, "a visible tick redraws the countdown")
    Runtime.setVisible(d5, false)
    test.eq(cancelled, true, "hiding the overview cancels the ticker")
    test.eq(d5._visibleTicker, nil, "no ticker remains after hiding")
end
