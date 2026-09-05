return function(test)
    BG = { BGNext = {} }
    BG.BGNext.FeatureCatalog = dofile("Core/BGNext/FeatureCatalog.lua")
    BG.BGNext.FeatureSettings = dofile("Core/BGNext/FeatureSettings.lua")
    local ui = dofile("Core/BGNext/FeatureManagementUI.lua")

    local root = { settings = {} }
    local model = ui.viewModel(root, "titan")
    test.eq(model.mode, "custom", "new opt-in tools keep an untouched install custom")
    test.eq(#model.groups, 4, "view keeps catalog group order")
    test.eq(model.groups[1].id, "personal", "personal group remains first")

    local rows = {}
    for _, group in ipairs(model.groups) do
        for _, row in ipairs(group.rows) do rows[row.id] = row end
    end
    test.eq(rows.auction_safety.required, true, "required row has no editable state")
    test.eq(rows.auction_safety.saved, nil, "required row has no saved toggle")
    test.eq(rows.wishlist.required, false, "optional row is toggleable")
    test.eq(rows.wishlist.enabled, true, "optional row reports effective state")
    test.eq(rows.local_history.enabled, false, "history is visibly opt-in")

    local ok, reason = ui.toggleFeature(root, "titan", "auction_safety", false)
    test.eq(ok, false, "UI refuses required toggle")
    test.eq(reason, "required", "UI returns required reason")
    test.eq(ui.toggleFeature(root, "titan", "wishlist", false), true, "UI delegates optional toggle")
    test.eq(ui.viewModel(root, "titan").mode, "custom", "toggle refreshes derived mode")
    test.eq(ui.applyMode(root, "titan", "basic"), true, "UI applies basic mode")
    test.eq(ui.viewModel(root, "titan").mode, "basic", "basic mode appears in view")

    local unknown, unknownReason = ui.toggleFeature(root, "titan", "missing", false)
    test.eq(unknown, false, "unknown feature is rejected")
    test.eq(unknownReason, "unknown", "unknown result is explicit")
    local unavailable, unavailableReason = ui.toggleFeature(root, "unknown", "wishlist", false)
    test.eq(unavailable, false, "unavailable feature is rejected")
    test.eq(unavailableReason, "unavailable", "unavailable result is explicit")
    test.eq(ui.buildPanel(), nil, "frame creation is harmless without WoW UI helpers")

    local file = assert(io.open("Core/BGNext/FeatureManagementUI.lua", "rb"))
    local source = file:read("*a")
    file:close()
    test.eq(source:find("GetStringWidth", 1, true) ~= nil, true, "localized buttons calculate their width")
end
