return function(test)
    BG = { BGNext = {} }
    dofile("Core/BGNext/OwnCharactersAdapters.lua")
    dofile("Core/BGNext/OwnCharactersCatalog.lua")
    dofile("Core/BGNext/OwnCharactersCollector.lua")
    local Model = dofile("Core/BGNext/OwnCharacters.lua")
    local Settings = dofile("Core/BGNext/RoleOverviewSettings.lua")
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
            mergeSections = function(r, f, s, sections)
                spy.upsert = spy.upsert + 1
                return Model.mergeSections(r, f, s, sections)
            end,
            get = Model.get,
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
            settings = Settings,
            now = function() return 5000 end,
            ui = { Refresh = function() uiCalls.refresh = uiCalls.refresh + 1 end },
        }
        return deps, root, spy, uiCalls, apiCalls
    end

    test.eq(Runtime.isAvailable({ family = "titan", catalog = Catalog.forFamily("titan") }), true,
        "tested-in-game clients expose the overview")
    test.eq(Runtime.isAvailable({ family = "mop", catalog = Catalog.forFamily("mop") }), true,
        "pending clients expose the overview for real-client validation")
    test.eq(Runtime.isAvailable({ family = nil, catalog = nil }), false,
        "excluded clients such as Season of Discovery expose no overview")
    test.eq(Runtime.isAvailable({ family = "wrath", catalog = Catalog.forFamily("wrath") }), false,
        "unverified empty families expose no overview")

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

    -- A MoP farm harvest is observed from the current player's localized
    -- self-loot line, then stored only as a daily completion fact. A later
    -- full collection preserves it until Blizzard's daily reset boundary.
    local mopRoot = { settings = {} }
    local mopNow = 5000
    local mopApi = {
        time = function() return mopNow end,
        UnitName = function() return "Piti" end,
        GetRealmID = function() return 123 end,
        GetRealmName = function() return "时光II" end,
        UnitFactionGroup = function() return "Alliance" end,
        UnitClass = function() return "猎人", "HUNTER" end,
        UnitLevel = function() return 90 end,
        GetAverageItemLevel = function() return 540 end,
        GetMoney = function() return 50000 end,
        GetSubZoneText = function() return "日歌农场" end,
        GetQuestResetTime = function() return 3600 end,
        GetNumRandomDungeons = function() return 0 end,
        GetLFGRandomDungeonInfo = function() end,
        GetLFGDungeonRewards = function() end,
        C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 7200 end },
        C_QuestLog = { IsQuestFlaggedCompleted = function() return false end },
        LOOT_ITEM_SELF = "你获得了物品：%s。",
        LOOT_ITEM_SELF_MULTIPLE = "你获得了物品：%sx%d。",
        LOOT_ITEM_PUSHED_SELF = "你获得了物品：%s。",
        LOOT_ITEM_PUSHED_SELF_MULTIPLE = "你获得了物品：%sx%d。",
    }
    local mopDeps = {
        globals = { IsMOP = true }, family = "mop", catalog = Catalog.forFamily("mop"),
        root = mopRoot, api = mopApi, adapters = Adapters, collector = Collector, model = Model,
        now = function() return mopNow end,
        ui = { IsVisible = function() return false end, Refresh = function() end },
    }
    Runtime.collectAndStore(mopDeps)
    local cabbage = "|cff1eff00|Hitem:74840::::::::90:::::|h[绿色卷心菜]|h|r"
    test.eq(Runtime.observeEvent(mopDeps, "CHAT_MSG_LOOT", "你获得了物品：" .. cabbage .. "x5。"), nil,
        "the default-hidden farm column does not inspect loot messages")
    Settings.setVisible(mopRoot, "mop", "resource", "farmHarvest", true)
    local farmSections = Runtime.observeEvent(mopDeps, "CHAT_MSG_LOOT", "你获得了物品：" .. cabbage .. "x5。")
    test.eq(farmSections.activities, true, "a verified self harvest requests an activity refresh")
    Runtime.collectAndStore(mopDeps, farmSections)
    local farmState = Model.get(mopRoot, "mop", 123, "Piti").activityStates.farmHarvest
    test.eq(farmState.status, "completed", "the current character is marked as harvested today")
    test.eq(farmState.observedAt, 5000, "only the harvest observation time is retained")
    test.eq(farmState.resetsAt, 8600, "the harvest completion expires at the daily reset")
    Runtime.collectAndStore(mopDeps)
    test.eq(Model.get(mopRoot, "mop", 123, "Piti").activityStates.farmHarvest.status, "completed",
        "a later full collection preserves today's verified harvest")
    mopNow = 8600
    Runtime.collectAndStore(mopDeps)
    test.eq(Model.get(mopRoot, "mop", 123, "Piti").activityStates.farmHarvest.status, "unknown",
        "the prior day's harvest is not carried across the reset")

    -- Disabling the overview must discard any not-yet-stored harvest signal.
    -- Otherwise an observation from before a daily reset could be replayed as
    -- a false completion when the feature is enabled on a later day.
    mopNow = 9000
    test.eq(Runtime.observeEvent(mopDeps, "CHAT_MSG_LOOT", "你获得了物品：" .. cabbage .. "x5。").activities,
        true, "an enabled overview may stage a verified harvest")
    Runtime.setEnabled(mopDeps, false)
    test.eq(mopDeps._farmHarvestObservedAt, nil, "disabling discards a staged harvest observation")
    test.eq(Runtime.observeEvent(mopDeps, "CHAT_MSG_LOOT", "你获得了物品：" .. cabbage .. "x5。"), nil,
        "a disabled overview ignores later harvest messages")
    Runtime.setEnabled(mopDeps, true)
    test.eq(Model.get(mopRoot, "mop", 123, "Piti").activityStates.farmHarvest.status, "unknown",
        "re-enabling cannot replay a harvest observed while disabled")

    local hiddenDeps, hiddenRoot, _, hiddenUi = build()
    hiddenDeps.ui.IsVisible = function() return false end
    Runtime.collectAndStore(hiddenDeps)
    test.eq(Model.get(hiddenRoot, "titan", 123, "Piti") ~= nil, true,
        "hidden overview still stores the latest snapshot")
    test.eq(hiddenUi.refresh, 0, "hidden overview skips renderer work")

    local visibleDeps, _, _, visibleUi = build()
    visibleDeps.ui.IsVisible = function() return true end
    Runtime.collectAndStore(visibleDeps)
    test.eq(visibleUi.refresh, 1, "visible overview redraws after collection")

    -- A scoped event refresh reads identity plus only the section made dirty.
    local scopedDeps = build()
    local readerCalls = {}
    local function counted(key, value)
        return function()
            readerCalls[key] = (readerCalls[key] or 0) + 1
            return value
        end
    end
    scopedDeps.adapters = {
        readers = function()
            return {
                playerName = counted("playerName", "Piti"),
                realmId = counted("realmId", 123),
                realmName = counted("realmName", "时光II"),
                faction = counted("faction", "Alliance"),
                class = counted("class", "HUNTER"),
                level = counted("level", 80),
                itemLevel = counted("itemLevel", 230),
                money = counted("money", 60000),
                equipment = counted("equipment", {}),
                raidStates = counted("raidStates", {}),
                professions = counted("professions", {}),
                resources = counted("resources", {}),
            }
        end,
    }
    Model.upsert(scopedDeps.root, "titan", {
        player = "Piti", realmId = 123, money = 50000, updatedAt = 4000,
        equipment = { [1] = { itemId = 1234 } },
        raidStates = { toc = { completed = true, resetsAt = 9000 } },
    })
    local moneySnapshot = Runtime.collectAndStore(scopedDeps, { money = true })
    test.eq(moneySnapshot.money, 60000, "money refresh reads the new money value")
    test.eq(readerCalls.playerName, 1, "scoped refresh still identifies the current character")
    test.eq(readerCalls.realmId, 1, "scoped refresh still identifies the current realm")
    test.eq(readerCalls.money, 1, "money refresh calls the money reader once")
    for _, key in ipairs({ "realmName", "faction", "class", "level", "itemLevel", "equipment",
        "raidStates", "professions", "resources" }) do
        test.eq(readerCalls[key], nil, "money refresh skips unrelated reader " .. key)
    end
    Runtime.collectAndStore(scopedDeps, { money = true })
    local merged = Model.get(scopedDeps.root, "titan", 123, "Piti")
    test.eq(merged.money, 60000, "scoped refresh replaces the dirty field")
    test.eq(merged.equipment[1].itemId, 1234, "scoped refresh preserves stored equipment")
    test.eq(merged.raidStates.toc.completed, true, "scoped refresh preserves stored raid state")

    local firstScopedDeps = build()
    firstScopedDeps.adapters = scopedDeps.adapters
    readerCalls = {}
    Runtime.collectAndStore(firstScopedDeps, { money = true })
    local firstStored = Model.get(firstScopedDeps.root, "titan", 123, "Piti")
    test.eq(firstStored.realmName, "时光II", "first scoped event falls back to a complete identity snapshot")
    test.eq(firstStored.class, "HUNTER", "first scoped event fills non-dirty character fields")
    test.eq(type(firstStored.equipment), "table", "first scoped event fills equipment instead of persisting a partial record")
    test.eq(readerCalls.equipment, 1, "first scoped event performs one full fallback collection")

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

    local hiddenMutationDeps, _, _, hiddenMutationUi = build()
    hiddenMutationDeps.ui.IsVisible = function() return false end
    Runtime.setColumnVisible(hiddenMutationDeps, "resource", "titanShard", false)
    Runtime.clearFamily(hiddenMutationDeps)
    Runtime.clearAll(hiddenMutationDeps)
    test.eq(hiddenMutationUi.refresh, 0, "settings and clears do not redraw a hidden overview")

    -- install registers only the reviewed events and collects once immediately.
    local d4, root4, spy4, ui4, api4 = build()
    d4.family = "retail"
    d4.catalog = Catalog.forFamily("retail")
    d4.globals = { IsRetail = true }
    local registered = {}
    local rejectedRetailEvent = false
    local eventHandler, scheduledRefresh
    local installedReaderCalls = {}
    d4.adapters = {
        readers = function(...)
            local readers = Adapters.readers(...)
            for key, reader in pairs(readers) do
                readers[key] = function()
                    installedReaderCalls[key] = (installedReaderCalls[key] or 0) + 1
                    return reader()
                end
            end
            return readers
        end,
        validatedIdentity = Adapters.validatedIdentity,
    }
    local frame = {
        RegisterEvent = function(_, event)
            if event == "TRADE_SKILL_UPDATE" then
                rejectedRetailEvent = true
                error('Attempt to register unknown event "TRADE_SKILL_UPDATE"')
            end
            registered[#registered + 1] = event
        end,
        SetScript = function(_, _, fn) eventHandler = fn end,
    }
    d4.frame = frame
    d4.after = function(_, fn) scheduledRefresh = fn end
    Runtime.install(d4)
    test.eq(rejectedRetailEvent, true, "install encounters the unsupported retail profession event")
    test.eq(#registered > 0, true, "install registers events")
    test.eq(spy4.upsert >= 1, true, "install performs an immediate collection")
    test.eq(api4.raidInfo, 1, "install requests saved-instance data once")
    local allowed = {}
    for _, event in ipairs(Collector.allowedEvents) do allowed[event] = true end
    for _, event in ipairs(registered) do
        test.eq(allowed[event], true, "install registered only allowlisted event " .. tostring(event))
    end
    installedReaderCalls = {}
    eventHandler(frame, "PLAYER_MONEY")
    scheduledRefresh()
    test.eq(installedReaderCalls.money, 1, "installed money event reads money once")
    for _, key in ipairs({ "realmName", "faction", "class", "level", "itemLevel", "equipment",
        "raidStates", "professions", "resources" }) do
        test.eq(installedReaderCalls[key], nil, "installed money event skips unrelated reader " .. key)
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

    -- Header controls alter only this client's visibility preferences; the
    -- collected own-character snapshot remains the same stored value.
    local d6, root6 = build()
    Runtime.collectAndStore(d6)
    local storedCharacter = Model.get(root6, "titan", 123, "Piti")
    Runtime.setColumnVisible(d6, "resource", "titanShard", false)
    test.eq(Settings.isVisible(root6, "titan", "resource", "titanShard", d6.catalog), false,
        "header hide persists the current-family preference")
    test.eq(Model.get(root6, "titan", 123, "Piti"), storedCharacter,
        "hiding a column does not replace the character snapshot")

    -- Problem 3: on Retail the live UnitName/GetRealmID may be secret-protected
    -- even though Core/DB/Init.lua already captured the logged-in character. The
    -- runtime must prefer the validated init identity over the live re-read.
    local function buildRetailIdentity()
        local root = { settings = {} }
        local spy = { upsert = 0 }
        local model = {
            upsert = function(r, f, s) spy.upsert = spy.upsert + 1 return Model.upsert(r, f, s) end,
            expireRaidStates = function() end,
            clearFamily = function() end,
            clearAll = function() end,
        }
        local api = {
            time = function() return 5000 end,
            UnitName = function() error("secret value") end,
            GetRealmID = function() error("secret value") end,
            GetRealmName = function() error("secret value") end,
        }
        local deps = {
            globals = {
                IsRetail = true,
                playerName = "Piti",
                realmID = 123,
                realmName = "时光II",
                IsSecret = function() return false end,
            },
            family = "retail",
            catalog = Catalog.forFamily("retail"),
            root = root,
            api = api,
            adapters = Adapters,
            collector = Collector,
            model = model,
            settings = Settings,
            now = function() return 5000 end,
            ui = { Refresh = function() end },
        }
        return deps, spy
    end

    local retailDeps, retailSpy = buildRetailIdentity()
    local retailSnapshot = Runtime.collectAndStore(retailDeps)
    test.eq(retailSnapshot ~= nil, true, "retail collects despite secret live identity APIs")
    test.eq(retailSnapshot.player, "Piti", "retail uses the init-time player name")
    test.eq(retailSnapshot.realmId, 123, "retail uses the init-time realm id")
    test.eq(retailSpy.upsert, 1, "retail upserts the init-identity snapshot")

    -- First-enter-world without identity and with secret live APIs fails safely;
    -- once the init identity appears, a later collect recovers (no lockout).
    local lockoutDeps = buildRetailIdentity()
    lockoutDeps.globals = { IsRetail = true, IsSecret = function() return false end }
    test.eq(Runtime.collectAndStore(lockoutDeps), nil, "no identity means no snapshot")
    lockoutDeps.globals.playerName = "Piti"
    lockoutDeps.globals.realmID = 123
    lockoutDeps.globals.realmName = "时光II"
    local recovered = Runtime.collectAndStore(lockoutDeps)
    test.eq(recovered ~= nil, true, "a later collect recovers once identity is available")
    test.eq(recovered.player, "Piti", "recovered snapshot uses the current identity")

    -- Init identity must override the live read only on retail. Non-retail
    -- families (vanilla/tbc/wrath/titan/cata/mop) keep the original live
    -- identity read, even when a stray init identity is present.
    local nonRetailDeps = build()
    nonRetailDeps.globals.playerName = "WrongName"
    nonRetailDeps.globals.realmID = 999
    nonRetailDeps.globals.realmName = "错误服"
    local nonRetailSnapshot = Runtime.collectAndStore(nonRetailDeps)
    test.eq(nonRetailSnapshot.player, "Piti",
        "non-retail keeps the live player name, ignoring init identity")
    test.eq(nonRetailSnapshot.realmId, 123,
        "non-retail keeps the live realm id, ignoring init identity")
    test.eq(nonRetailSnapshot.realmName, "时光II",
        "non-retail keeps the live realm name, ignoring init identity")
end
