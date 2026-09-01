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

    -- Every shipped locale carries the player-facing menu labels.
    local menuKeys = { "打开金团表格", "关闭金团表格", "打开角色总览", "关闭角色总览", "设置" }
    for _, locale in ipairs({ "zhCN", "zhTW", "enUS" }) do
        local handle = io.open("Locales/" .. locale .. ".lua", "r")
        local src = handle:read("*a")
        handle:close()
        for _, key in ipairs(menuKeys) do
            test.eq(string.find(src, '["' .. key .. '"]', 1, true) ~= nil, true,
                locale .. " ships the menu label " .. key)
        end
    end

    -- The minimap adapts user input through the pure mapper and a dropdown,
    -- never the legacy SetFBCD main-table toggle for the role overview.
    local handle = io.open("Core/Module/minimap.lua", "r")
    local minimapSource = handle:read("*a")
    handle:close()
    test.eq(string.find(minimapSource, "EntryInteractions.minimapAction", 1, true) ~= nil, true,
        "minimap dispatches through the shared action mapper")
    test.eq(string.find(minimapSource, 'CreateFrame("Frame", nil, UIParent)', 1, true) ~= nil, true,
        "minimap right click uses a private entry-menu frame")
    test.eq(string.find(minimapSource, "if entryMenu:IsShown()", 1, true) ~= nil, true,
        "a second right click detects the private entry menu")
    test.eq(string.find(minimapSource, "entryMenu:Hide()", 1, true) ~= nil, true,
        "a second right click closes only the private entry menu")
    test.eq(string.find(minimapSource, "BG.SetFBCD", 1, true), nil,
        "minimap no longer calls the legacy SetFBCD toggle")

    -- Hover previews on the minimap reuse the shared role-overview entry API;
    -- the minimap must not build its own preview, timer or window.
    test.eq(string.find(minimapSource, "RoleOverviewEntry.hoverEnter", 1, true) ~= nil, true,
        "minimap hover enters through the shared entry API")
    test.eq(string.find(minimapSource, "RoleOverviewEntry.hoverLeave", 1, true) ~= nil, true,
        "minimap hover leaves through the shared entry API")
    test.eq(string.find(minimapSource, "BGNextRoleOverviewFrame", 1, true), nil,
        "minimap never builds its own role overview window")
end
