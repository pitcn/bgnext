return function(T)
    BG = {BGNext = {}}
    local Catalog = dofile('Core/BGNext/OwnCharactersCatalog.lua')
    local Adapters = dofile('Core/BGNext/OwnCharactersAdapters.lua')
    local columns = Catalog.forFamily('forever').resourceColumns
    local transmute = assert(Catalog.column('forever', 'resource', 'transmute'), 'Forever shared transmute cooldown')
    local mooncloth = assert(Catalog.column('forever', 'resource', 'mooncloth'))
    local salt = assert(Catalog.column('forever', 'resource', 'saltShaker'))
    local known, counts = {}, {}
    local calls = {}
    local api = {time = function() return 10000 end, GetTime = function() return 1000 end,
        IsSpellKnown = function(id) return known[id] == true end,
        C_Spell = {
            GetSpellInfo = function(id) return {name = 'spell'..id} end,
            GetSpellCooldown = function(id) calls[#calls+1] = id; return {startTime = 900, duration = 1000} end,
        },
        C_Item = {
            GetItemCount = function(id) return counts[id] or 0 end,
            GetItemCooldown = function(id) T.eq(id, 15846); return 800, 2000, true end,
        },
    }
    T.eq(Adapters.readResources(api, 'forever', columns), nil, 'globally resolvable recipes do not prove ownership')
    T.eq(Adapters.canReadColumn('forever', api, transmute), false)
    for _, id in ipairs({17187, 1317279, 17559, 17560, 17561, 17562, 17563, 17564, 17565, 17566, 25146}) do
        known = {[id] = true}; calls = {}
        local result = Adapters.readResources(api, 'forever', columns)
        T.eq(result.professionCooldowns.transmute.endsAt, 10900, 'shared cooldown via learned recipe '..id)
        T.eq(Adapters.canReadColumn('forever', api, transmute), true)
        T.eq(calls[1], id, 'query only learned recipe')
    end
    known = {[18560] = true}
    T.eq(Adapters.readResources(api, 'forever', columns).professionCooldowns.mooncloth.endsAt, 10900)
    T.eq(Adapters.canReadColumn('forever', api, mooncloth), true)
    known = {[2108] = true}; counts = {[15846] = 1}
    T.eq(Adapters.canReadColumn('forever', api, salt), true, 'owned salt shaker and learned leatherworking')
    T.eq(Adapters.readResources(api, 'forever', columns).professionCooldowns.saltShaker.endsAt, 11800)
    counts = {}
    T.eq(Adapters.canReadColumn('forever', api, salt), false, 'no salt shaker is not ready')
    counts = {[15846] = 1}; known = {}
    T.eq(Adapters.canReadColumn('forever', api, salt), false, 'item ownership alone is insufficient')
    known = {[18560] = true}
    api.C_Spell.GetSpellCooldown = function() return {startTime = 0, duration = 0} end
    T.eq(Adapters.readResources(api, 'forever', columns).professionCooldowns.mooncloth.ready, true)
    for key, id in pairs({ironToGold = 11479, mithrilToTruesilver = 11480}) do
        local column = assert(Catalog.column('forever', 'resource', key), 'independent one-hour transmute '..key)
        known = {[id] = true}
        T.eq(Adapters.canReadColumn('forever', api, column), true)
        T.eq(Adapters.readResources(api, 'forever', columns).professionCooldowns[key].ready, true)
    end

    -- The new Forever item timers use the existing debounced scoped writer.
    local Collector = dofile('Core/BGNext/OwnCharactersCollector.lua')
    local handler, queued, captured
    local frame = {RegisterEvent = function() end,
        SetScript = function(_, _, callback) handler = callback end}
    Collector.installEvents({frame = frame, family = 'forever',
        after = function(_, callback) queued = callback end},
        function(sections) captured = sections end)
    handler(frame, 'BAG_UPDATE_DELAYED')
    T.eq(type(queued), 'function', 'craft reagent change schedules cooldown refresh')
    queued()
    T.eq(captured.professionCooldowns, true)
    T.eq(captured.money, nil, 'cooldown event cannot overwrite gold')
    queued = nil; captured = nil
    handler(frame, 'BAG_UPDATE_COOLDOWN')
    T.eq(type(queued), 'function', 'salt shaker cooldown schedules refresh')
    queued()
    T.eq(captured.professionCooldowns, true)
end
