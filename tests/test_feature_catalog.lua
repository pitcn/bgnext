return function(test)
    BG = { BGNext = {} }
    local catalog = dofile("Core/BGNext/FeatureCatalog.lua")

    local valid, errors = catalog.validate()
    test.eq(valid, true, errors and table.concat(errors, "; ") or "catalog validates")

    local groups = catalog.groups()
    test.eq(#groups, 4, "four feature groups")
    test.eq(groups[1].id, "personal", "personal group first")
    test.eq(groups[2].id, "auction", "auction group second")
    test.eq(groups[3].id, "settlement", "settlement group third")
    test.eq(groups[4].id, "interface", "interface group fourth")

    local entries = catalog.all()
    local seen = {}
    for _, entry in ipairs(entries) do
        test.eq(seen[entry.id], nil, "feature IDs are unique")
        seen[entry.id] = true
    end
    test.eq(catalog.get("auction_safety").policy, "required", "auction safety is required")
    test.eq(catalog.get("storage_privacy").policy, "required", "privacy controls are required")
    test.eq(catalog.get("auction_queue").policy, "optional", "auction queue is optional")
    test.eq(catalog.get("expense_templates").defaultEnabled, false, "new leader tools require explicit opt-in")
    test.eq(catalog.get("local_history").defaultEnabled, false, "history is private and disabled by default")
    test.eq(catalog.get("auction_center").defaultEnabled, false, "auction center is disabled by default")
    test.eq(catalog.get("settlement_summary").defaultEnabled, false, "settlement summary is disabled by default")
    test.eq(catalog.get("role_overview").basic, false, "role overview is outside basic mode")
    test.eq(catalog.available("role_overview", "mop"), true, "role overview supports mists")
    test.eq(catalog.available("role_overview", "unknown"), false, "unknown clients are unavailable")

    local actions = catalog.publicActions()
    local commands, interactions = {}, {}
    for _, command in ipairs(actions.commands) do commands[command] = true end
    for _, interaction in ipairs(actions.interactions) do interactions[interaction] = true end
    for _, command in ipairs({ "/bgn", "/bgnext", "/bgo", "/bgm", "/bgnqueue", "/bgnq" }) do
        test.eq(commands[command], true, command .. " is documented")
    end
    for _, interaction in ipairs({
        "table_right_click", "table_ctrl_right_click", "table_alt_right_click",
        "table_shift_right_click", "wishlist_mouse_wheel",
    }) do
        test.eq(interactions[interaction], true, interaction .. " is documented")
    end

    entries[1].id = "mutated"
    groups[1].id = "mutated"
    actions.commands[1] = "mutated"
    test.eq(catalog.all()[1].id == "mutated", false, "entries are defensively copied")
    test.eq(catalog.groups()[1].id, "personal", "groups are defensively copied")
    test.eq(catalog.publicActions().commands[1] == "mutated", false, "actions are defensively copied")
end
