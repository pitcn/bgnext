return function(test)
    BG = { IsForever = true, IsVanilla = true, BGNext = { DB = { settings = {} } } }
    local catalog = dofile("Core/BGNext/FeatureCatalog.lua")
    local adapters = dofile("Core/BGNext/OwnCharactersAdapters.lua")
    dofile("Core/BGNext/OwnCharactersCatalog.lua")
    local settings = dofile("Core/BGNext/FeatureSettings.lua")
    local wishlist = dofile("Core/BGNext/WishlistUI.lua")
    local roles = dofile("Core/BGNext/OwnCharactersRuntime.lua")
    local management = dofile("Core/BGNext/FeatureManagementUI.lua")
    local root = BG.BGNext.DB
    test.eq(settings.currentFamily(BG), "forever", "real feature gate detects Forever")
    test.eq(wishlist.isFeatureEnabled(), true, "wishlist entry is available on Forever")
    local deps = roles.buildDeps(BG)
    local available
    deps.entry = { setAvailable = function(value) available = value end }
    test.eq(roles.refreshFeatureState(deps), true, "role overview's runtime accepts Forever")
    test.eq(available, true, "role entry is shown")
    local visible = {}
    for _, group in ipairs(management.viewModel(root, "forever").groups) do
        for _, row in ipairs(group.rows) do visible[row.id] = true end
    end
    for _, entry in ipairs(catalog.all()) do
        test.eq(catalog.available(entry, "forever"), catalog.available(entry, "vanilla"),
            entry.id .. " keeps the shared addon's feature availability")
        test.eq(visible[entry.id], true, entry.id .. " appears in feature settings")
    end
    test.eq(settings.isCurrentEnabled("local_history", BG, root), false, "opt-in features stay disabled")
    settings.setEnabled(root, "wishlist", false)
    test.eq(wishlist.isFeatureEnabled(), false, "user's disabled wishlist stays disabled")
    settings.setEnabled(root, "role_overview", false)
    test.eq(roles.refreshFeatureState(deps), false, "user's disabled role overview stays disabled")
    test.eq(available, false, "role entry hides only when explicitly disabled")
    settings.setEnabled(root, "role_overview", true)
    test.eq(roles.refreshFeatureState(deps), true, "role entry can be re-enabled")
    BG.BGNext.OwnCharactersAdapters = nil
    test.eq(settings.currentFamily(BG), "forever", "fallback keeps Forever identity too")
end
