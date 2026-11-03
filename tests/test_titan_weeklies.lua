return function(T)
    BG = {BGNext = {}}
    local Catalog = dofile('Core/BGNext/OwnCharactersCatalog.lua')
    local Adapters = dofile('Core/BGNext/OwnCharactersAdapters.lua')
    local catalog = Catalog.forFamily('titan')
    local weekly = assert(Catalog.column('titan', 'resource', 'raidWeekly'), 'Titan raid weekly column')
    local zg = assert(Catalog.column('titan', 'resource', 'zgWeekly'), 'Titan ZG weekly column')
    T.eq(Catalog.column('wrath', 'resource', 'raidWeekly'), nil)
    local completed = {}
    local api = {time=function() return 1000 end,
        C_DateAndTime={GetSecondsUntilWeeklyReset=function() return 50000 end},
        IsQuestFlaggedCompleted=function(id) return completed[id] == true end}
    local function states() return Adapters.readActivityStates(api,'titan',{weekly,zg}) end
    T.eq(states().raidWeekly.status,'incomplete')
    for _, id in ipairs({93975,94577,94579,95037,96312,96315,96318}) do
        completed={[id]=true}
        T.eq(states().raidWeekly.status,'completed','known Titan rotation '..id)
        T.eq(states().raidWeekly.resetsAt,51000)
        T.eq(states().zgWeekly.status,'incomplete')
    end
    completed={[98183]=true}
    T.eq(states().zgWeekly.status,'completed')
    T.eq(states().raidWeekly.status,'incomplete')
    api.IsQuestFlaggedCompleted=function() return nil end
    T.eq(states().raidWeekly.status,'unknown','unreliable completion is not incomplete')
    api.IsQuestFlaggedCompleted=function() return true end
    for _, invalid in ipairs({0,-1,math.huge,0/0,'50000'}) do
        api.C_DateAndTime.GetSecondsUntilWeeklyReset=function() return invalid end
        T.eq(states().raidWeekly.status,'unknown','invalid weekly deadline fails closed')
    end
    api.C_DateAndTime=nil
    T.eq(states().raidWeekly.status,'unknown','no guessed calendar reset')
    T.eq(Adapters.canReadColumn('titan',api,weekly),true,'missing reset remains an explicit unknown cell')
    T.eq(Adapters.canReadColumn('mop',api,weekly),false)

    local Model=dofile('Core/BGNext/OwnCharacters.lua')
    local Collector=dofile('Core/BGNext/OwnCharactersCollector.lua')
    local Runtime=dofile('Core/BGNext/OwnCharactersRuntime.lua')
    local now,nextReset,visible,reads=1000,2000,true,0
    completed={[96318]=true}
    api.time=function() return now end
    api.C_DateAndTime={GetSecondsUntilWeeklyReset=function() return nextReset-now end}
    api.IsQuestFlaggedCompleted=function(id) reads=reads+1;return completed[id]==true end
    api.UnitName=function(unit) T.eq(unit,'player');return 'Player' end
    api.GetRealmID=function() return 1 end
    api.UnitLevel=function() return 80 end
    api.GetMoney=function() return 123456 end
    local root={wishlist={sentinel=true},settings={raidWelcome={enabled=true,text='Welcome'}}}
    local deps={family='titan',catalog=catalog,root=root,api=api,adapters=Adapters,
        collector=Collector,model=Model,now=function() return now end,
        ui={IsVisible=function() return visible end,Refresh=function() end}}
    Runtime.collectAndStore(deps)
    local current=Model.get(root,'titan',1,'Player')
    T.eq(current.activityStates.raidWeekly.status,'completed','weekly completion reaches the actual snapshot model')
    T.eq(current.activityStates.zgWeekly.status,'incomplete')
    for field in pairs(current.activityStates.raidWeekly) do
        T.eq(field=='status' or field=='observedAt' or field=='resetsAt',true,'no quest IDs or log persist')
    end
    Model.upsert(root,'titan',{realmId=1,player='Offline',money=654321,
        activityStates={raidWeekly={status='completed',resetsAt=2000}}})
    local handler,queued,queueCount=nil,nil,0
    deps.frame={RegisterEvent=function() end,SetScript=function(_,_,callback) handler=callback end}
    deps.after=function(_,callback) queued=callback;queueCount=queueCount+1 end
    Runtime.install(deps)
    completed={[98183]=true};api.GetMoney=function() return 0 end
    handler(deps.frame,'QUEST_TURNED_IN',98183);handler(deps.frame,'QUEST_LOG_UPDATE')
    T.eq(queueCount,1,'weekly turn-in uses the existing debounce')
    queued()
    current=Model.get(root,'titan',1,'Player')
    T.eq(current.activityStates.zgWeekly.status,'completed')
    T.eq(current.money,123456,'quest-only writes preserve recorded gold')
    T.eq(root.wishlist.sentinel,true);T.eq(root.settings.raidWelcome.text,'Welcome')
    now,nextReset,completed=2000,3000,{}
    Runtime.refreshVisible(deps)
    T.eq(Model.get(root,'titan',1,'Player').activityStates.zgWeekly.status,'incomplete','visible weekly reset reads the current character once')
    T.eq(Model.get(root,'titan',1,'Offline').activityStates.raidWeekly,nil,'offline completion only expires')
    T.eq(Model.get(root,'titan',1,'Offline').money,654321)
    local afterReset=reads;Runtime.refreshVisible(deps);T.eq(reads,afterReset,'no periodic quest polling')
    visible=false;now,nextReset=3000,4000;Runtime.refreshVisible(deps)
    T.eq(reads,afterReset,'hidden weekly window never queries quest flags')
    visible=true;Runtime.refreshVisible(deps);T.eq(reads>afterReset,true,'reopen after reset refreshes only the current character')
    Runtime.setEnabled(deps,false);afterReset=reads;now=4000;Runtime.refreshVisible(deps)
    T.eq(reads,afterReset,'disabled overview does not read weekly quests')
end
