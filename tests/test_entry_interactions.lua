return function(test)
    BG = { BGNext = {} }
    local Interactions = dofile("Core/BGNext/EntryInteractions.lua")

    -- Minimap maps each button to a single, testable intent.
    test.eq(Interactions.minimapAction("LeftButton"), "toggle-main", "minimap left toggles the main table")
    test.eq(Interactions.minimapAction("RightButton"), "menu", "minimap right opens the entry menu")
    test.eq(Interactions.minimapAction("MiddleButton"), "toggle-role", "minimap middle toggles the role overview")
    test.eq(Interactions.minimapAction("Button4"), nil, "an unknown minimap button does nothing")
    test.eq(Interactions.minimapAction(nil), nil, "a missing minimap button does nothing")

    -- The menu always shows main first and settings last; role sits between
    -- them only when the role overview is available on this client.
    local available = Interactions.menuModel({ mainShown = false, roleShown = true, roleAvailable = true })
    test.eq(#available, 3, "available clients show three entries")
    test.eq(available[1].id, "main", "main is first")
    test.eq(available[1].verb, "open", "hidden main receives open")
    test.eq(available[2].id, "role", "role is second")
    test.eq(available[2].verb, "close", "shown role receives close")
    test.eq(available[3].id, "settings", "settings is last")

    local unavailable = Interactions.menuModel({ mainShown = true, roleAvailable = false })
    test.eq(#unavailable, 2, "unavailable clients omit role")
    test.eq(unavailable[1].verb, "close", "shown main receives close")
    test.eq(unavailable[2].id, "settings", "settings remains")

    local roleOpen = Interactions.menuModel({ mainShown = true, roleShown = false, roleAvailable = true })
    test.eq(roleOpen[1].verb, "close", "shown main receives close")
    test.eq(roleOpen[2].id, "role", "role remains second")
    test.eq(roleOpen[2].verb, "open", "hidden role receives open")
    test.eq(roleOpen[3].id, "settings", "settings remains last")
end
