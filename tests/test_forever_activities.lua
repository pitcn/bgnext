return function(T)
    BG = { BGNext = {} }
    local Catalog = dofile('Core/BGNext/OwnCharactersCatalog.lua')
    local Adapters = dofile('Core/BGNext/OwnCharactersAdapters.lua')
    local column = assert(Catalog.column('forever', 'resource', 'bootyBayWeekly'), 'Forever Booty Bay weekly')
    T.eq(Catalog.column('vanilla', 'resource', 'bootyBayWeekly'), nil)
    local completed = {}
    local api = { time = function() return 1000 end,
        C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 5000 end },
        C_QuestLog = { IsQuestFlaggedCompleted = function(id) return completed[id] == true end } }
    local function read() return Adapters.readActivityStates(api, 'forever', {column}).bootyBayWeekly end
    T.eq(Adapters.canReadColumn('forever', api, column), true)
    T.eq(read().status, 'incomplete')
    for _, id in ipairs({96075, 96076, 96087, 96088}) do
        completed = {[id] = true}
        T.eq(read().status, 'completed', 'rotation completion '..id)
        T.eq(read().resetsAt, 6000)
    end
    api.C_DateAndTime = nil
    T.eq(read().status, 'unknown', 'no guessed reset')
    api.C_DateAndTime = {GetSecondsUntilWeeklyReset = function() return 5000 end}
    api.C_QuestLog.IsQuestFlaggedCompleted = function() return nil end
    T.eq(read().status, 'unknown', 'unreliable quest flag')

    local Model = dofile('Core/BGNext/OwnCharacters.lua')
    local Collector = dofile('Core/BGNext/OwnCharactersCollector.lua')
    local Runtime = dofile('Core/BGNext/OwnCharactersRuntime.lua')
    local now, nextReset, visible, reads = 1000, 2000, true, 0
    completed = {[96076] = true}
    api.time = function() return now end
    api.C_DateAndTime = {GetSecondsUntilWeeklyReset = function() return nextReset - now end}
    api.C_QuestLog.IsQuestFlaggedCompleted = function(id) reads = reads + 1; return completed[id] == true end
    api.UnitName = function() return 'Player' end
    api.GetRealmID = function() return 1 end
    api.UnitLevel = function() return 60 end
    api.GetMoney = function() return 12345 end
    local root = {wishlist = {sentinel = true}}
    local deps = {family = 'forever', catalog = Catalog.forFamily('forever'), root = root,
        api = api, adapters = Adapters, collector = Collector, model = Model,
        now = function() return now end,
        ui = {IsVisible = function() return visible end, Refresh = function() end}}
    Runtime.collectAndStore(deps)
    T.eq(Model.get(root, 'forever', 1, 'Player').activityStates.bootyBayWeekly.status, 'completed')
    Model.upsert(root, 'forever', {realmId = 1, player = 'Offline', money = 6789,
        activityStates = {bootyBayWeekly = {status = 'completed', resetsAt = 2000}}})
    now, nextReset, completed = 2000, 3000, {}
    api.GetMoney = function() return 0 end
    Runtime.refreshVisible(deps)
    T.eq(Model.get(root, 'forever', 1, 'Player').activityStates.bootyBayWeekly.status, 'incomplete', 'visible weekly reset rereads current character')
    T.eq(Model.get(root, 'forever', 1, 'Player').money, 12345, 'activity refresh preserves gold')
    T.eq(Model.get(root, 'forever', 1, 'Offline').activityStates.bootyBayWeekly, nil, 'offline weekly only expires')
    T.eq(Model.get(root, 'forever', 1, 'Offline').money, 6789)
    local previous = reads
    Runtime.refreshVisible(deps)
    T.eq(reads, previous, 'no periodic polling')
    visible = false; now, nextReset = 3000, 4000
    Runtime.refreshVisible(deps)
    T.eq(reads, previous, 'hidden overview does not read quest flags')
    visible = true; Runtime.refreshVisible(deps)
    T.eq(reads > previous, true, 'reopening reads the expired current character')
    T.eq(root.wishlist.sentinel, true)
end
