return function(T)
    BG = {BGNext = {}}
    local Catalog = dofile('Core/BGNext/OwnCharactersCatalog.lua')
    local Adapters = dofile('Core/BGNext/OwnCharactersAdapters.lua')
    local Settings = dofile('Core/BGNext/RoleOverviewSettings.lua')
    local View = dofile('Core/BGNext/OwnCharactersView.lua')
    local catalog = Catalog.forFamily('forever')
    T.eq(Adapters.capabilities('forever').hasCurrencyApi, true, 'Forever declares its currency API')
    local root = {}
    local expected = {undermineReal = {3469, true, 107}, honorPoints = {1792, false, 122}, merchantsFavor = {3402, false, 850}}
    local quantities = {[3469] = 107, [1792] = 122, [3402] = 850}
    local api = {C_CurrencyInfo = {GetCurrencyInfo = function(id)
        T.eq(quantities[id] ~= nil, true, 'only declared currency IDs are queried')
        return {quantity = quantities[id]}
    end}}
    for key, spec in pairs(expected) do
        local column = assert(Catalog.column('forever', 'resource', key), 'Forever currency '..key)
        T.eq(Adapters.currencyId('forever', key), spec[1])
        T.eq(column.source.currencyId, spec[1], 'header and count use same ID')
        T.eq(Adapters.canReadColumn('forever', api, column), true)
        T.eq(Settings.isVisible(root, 'forever', 'resource', key, catalog), spec[2])
        T.eq(Catalog.column('vanilla', 'resource', key), nil, 'Forever currency does not leak into Era')
    end
    local result = Adapters.readResources(api, 'forever', catalog.resourceColumns)
    for key, spec in pairs(expected) do T.eq(result.currencies[key], spec[3]) end
    local function project()
        local visibility = {resource = {}}
        for key in pairs(expected) do visibility.resource[key] = Settings.isVisible(root, 'forever', 'resource', key, catalog) end
        return View.project({family = 'forever', catalog = catalog, currentRealmId = 1, now = 1000,
            visibility = visibility, available = function(section, id)
                return Adapters.canReadColumn('forever', api, Catalog.column('forever', section, id))
            end,
            snapshots = {{realmId = 1, player = 'Player', level = 60, currencies = result.currencies}}})
    end
    local view = project()
    T.eq(#view.resource.columns, 1, 'only reals default visible with currency-only API')
    T.eq(view.resource.columns[1].id, 'undermineReal')
    T.eq(view.resource.rows[1].cells[1].value, 107)
    Settings.setVisible(root, 'forever', 'resource', 'honorPoints', true)
    Settings.setVisible(root, 'forever', 'resource', 'merchantsFavor', true)
    view = project()
    T.eq(#view.resource.columns, 3, 'optional currencies can be enabled')
    Settings.setVisible(root, 'forever', 'resource', 'undermineReal', false)
    T.eq(#project().resource.columns, 2, 'explicit hide overrides reals default')
    quantities[3469] = 0
    T.eq(Adapters.readResources(api, 'forever', catalog.resourceColumns).currencies.undermineReal, 0, 'zero balance is valid')
    api.C_CurrencyInfo.GetCurrencyInfo = function() return nil end
    T.eq(Adapters.readResources(api, 'forever', catalog.resourceColumns), nil, 'missing balance never invents zero')
end
