return function(test)
    BG = { BGNext = {} }
    local catalog = dofile("Core/BGNext/FeatureCatalog.lua")
    local settings = dofile("Core/BGNext/FeatureSettings.lua")

    local root = { settings = {} }
    test.eq(settings.isEnabled(root, "wishlist", "titan"), true, "missing optional value defaults enabled")
    test.eq(settings.isEnabled(root, "local_history", "titan"), false, "privacy-sensitive history defaults disabled")
    test.eq(settings.mode(root, "titan"), "custom", "new tools do not silently change an existing install to full mode")

    local changed, reason = settings.setEnabled(root, "auction_safety", false)
    test.eq(changed, false, "required features cannot be disabled")
    test.eq(reason, "required", "required rejection is explained")
    test.eq(settings.isEnabled(root, "auction_safety", "titan"), true, "required feature stays enabled")

    test.eq(settings.applyMode(root, "basic", "titan"), true, "basic mode applies")
    for _, entry in ipairs(catalog.all()) do
        if entry.policy == "optional" and catalog.available(entry, "titan") then
            test.eq(settings.savedValue(root, entry.id), entry.basic, entry.id .. " follows basic mode")
        end
    end
    test.eq(settings.mode(root, "titan"), "basic", "basic mode is detected")
    test.eq(settings.applyMode(root, "full", "titan"), true, "full mode applies")
    test.eq(settings.savedValue(root, "local_history"), true, "full mode explicitly enables local history")
    test.eq(settings.mode(root, "titan"), "full", "full mode is detected")
    settings.setEnabled(root, "wishlist", false)
    test.eq(settings.mode(root, "titan"), "custom", "one individual change yields custom mode")

    local legacy = { settings = { roleOverviewEnabled = false } }
    test.eq(settings.isEnabled(legacy, "role_overview", "titan"), false,
        "legacy role overview preference is preserved")
    settings.setEnabled(legacy, "role_overview", true)
    test.eq(legacy.settings.roleOverviewEnabled, true, "new role setting mirrors legacy field")

    local dirty = {
        settings = {
            unrelated = "keep",
            features = { wishlist = false, auction_queue = "no", unknown = true, auction_safety = false },
        },
        wishlist = { keep = true },
    }
    settings.sanitize(dirty)
    test.eq(dirty.settings.features.wishlist, false, "known boolean survives sanitize")
    test.eq(dirty.settings.features.auction_queue, nil, "non-boolean is discarded")
    test.eq(dirty.settings.features.unknown, nil, "unknown feature is discarded")
    test.eq(dirty.settings.features.auction_safety, nil, "required feature is not persisted")
    test.eq(dirty.settings.unrelated, "keep", "unrelated setting is preserved")
    test.eq(dirty.wishlist.keep, true, "feature data is preserved")

    test.eq(settings.setEnabled(root, "missing", false), false, "unknown feature is rejected")
    test.eq(settings.applyMode(root, "missing", "titan"), false, "unknown mode is rejected")
    test.eq(settings.currentFamily({ IsWLK = true, IsTitan = true }), "titan",
        "specific overlapping client family wins")
    test.eq(settings.isCurrentEnabled("wishlist", { IsTitan = true }, root), false,
        "current-client helper uses the same feature state")
end
