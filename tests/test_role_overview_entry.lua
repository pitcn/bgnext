return function(test)
    BG = { BGNext = {} }
    local Model = dofile("Core/BGNext/OwnCharacters.lua")
    dofile("Core/BGNext/OwnCharactersAdapters.lua")
    local Entry = dofile("Core/BGNext/RoleOverviewEntry.lua")

    -- Hover previews, leaving hides again, unless the window was pinned.
    test.eq(Entry.intent("hover", {}), "preview", "hover previews the overview")
    test.eq(Entry.intent("hover", { pinned = true }), "keep", "hover over a pinned window changes nothing")
    test.eq(Entry.intent("leave", { pinned = false }), "hide", "leaving hides the preview")
    test.eq(Entry.intent("leave", { pinned = true }), "keep", "leaving keeps a pinned window")

    -- Middle-click and Ctrl+left-click pin it.
    test.eq(Entry.intent("middle-click", {}), "pin", "middle click pins")
    test.eq(Entry.intent("left-click", { ctrl = true }), "pin", "ctrl+left click pins")
    test.eq(Entry.intent("middle-click", { pinned = true }), "unpin", "middle click again unpins")
    test.eq(Entry.intent("left-click", { ctrl = true, pinned = true }), "unpin", "ctrl+left click again unpins")

    -- A plain left click is not a pin gesture.
    test.eq(Entry.intent("left-click", {}) ~= "pin", true, "a plain left click does not pin")

    -- Slash commands toggle the pinned window.
    test.eq(Entry.intent("slash-role", {}), "toggle-pinned", "slash command toggles the pinned window")
    test.eq(Entry.intent("close", { pinned = true }), "unpin", "the close control unpins")
    test.eq(Entry.intent("refresh", {}), "refresh", "the refresh control refreshes")
    test.eq(Entry.intent("settings", {}), "settings", "the settings control opens settings")
    test.eq(Entry.intent("nonsense", {}), nil, "unknown actions do nothing")
    test.eq(Entry.intent(nil, {}), nil, "a missing action does nothing")
    test.eq(Entry.intent("hover", nil), "preview", "a missing state is safe")

    -- Both documented commands are recognised, with and without arguments.
    test.eq(Entry.parseCommand("role"), "role", "/bgn role is recognised")
    test.eq(Entry.parseCommand("  role  "), "role", "surrounding spaces are ignored")
    test.eq(Entry.parseCommand("ROLE"), "role", "the command is case-insensitive")
    test.eq(Entry.parseCommand("角色总览"), "role", "the localized command is recognised")
    test.eq(Entry.parseCommand(""), nil, "an empty command is not the role command")
    test.eq(Entry.parseCommand(nil), nil, "a missing command is safe")
    test.eq(Entry.parseCommand("something-else"), nil, "unrelated arguments are ignored")

    -- Default is the current realm; holding Shift widens to all local realms.
    test.eq(Entry.showAllRealms({}), false, "default shows the current realm only")
    test.eq(Entry.showAllRealms({ shift = true }), true, "shift shows every local realm")
    test.eq(Entry.showAllRealms(nil), false, "a missing state defaults to current realm")

    -- Deletion is keyed by family, realm and name together.
    local root = {}
    Model.upsert(root, "titan", {
        realmId = 123, realmName = "时光II", player = "Piti", class = "HUNTER", updatedAt = 1,
    })
    Model.upsert(root, "titan", {
        realmId = 456, realmName = "时光III", player = "Piti", class = "MAGE", updatedAt = 1,
    })

    local request = Entry.deleteRequest({ key = "titan:123:Piti", player = "Piti", realmId = 123 }, "titan")
    test.eq(request.family, "titan", "delete request carries the family")
    test.eq(request.realmId, 123, "delete request carries the realm")
    test.eq(request.player, "Piti", "delete request carries the character")

    -- Without confirmation nothing is removed.
    test.eq(Entry.applyDelete(root, request, false), false, "an unconfirmed delete does nothing")
    test.eq(Model.get(root, "titan", 123, "Piti") ~= nil, true, "the character survives an unconfirmed delete")
    test.eq(Entry.applyDelete(root, request), false, "a missing confirmation does nothing")
    test.eq(Model.get(root, "titan", 123, "Piti") ~= nil, true, "the character survives a missing confirmation")

    -- Confirmed, it removes exactly one character.
    test.eq(Entry.applyDelete(root, request, true), true, "a confirmed delete removes the character")
    test.eq(Model.get(root, "titan", 123, "Piti"), nil, "the requested character is gone")
    test.eq(Model.get(root, "titan", 456, "Piti") ~= nil, true, "the same-name character on another realm survives")

    -- A malformed request never deletes anything.
    test.eq(Entry.applyDelete(root, nil, true), false, "a missing request deletes nothing")
    test.eq(Entry.applyDelete(root, { family = "titan", player = "Piti" }, true), false, "a request without a realm deletes nothing")
    test.eq(Entry.applyDelete(root, { family = "titan", realmId = 456 }, true), false, "a request without a name deletes nothing")
    test.eq(Model.get(root, "titan", 456, "Piti") ~= nil, true, "malformed requests left the data alone")

    -- Refresh re-reads the current character only; it never scans others.
    test.eq(type(Entry.refreshPlan), "function", "a refresh plan is exposed")
    local plan = Entry.refreshPlan()
    test.eq(plan.rereadCurrentCharacter, true, "refresh re-reads the logged-in character")
    test.eq(plan.scanOtherPlayers, false, "refresh never scans other players")
    test.eq(plan.sendsMessage, false, "refresh never sends a message")

    -- Source-level invariants: the entry never communicates or inspects.
    local handle = io.open("Core/BGNext/RoleOverviewEntry.lua", "r")
    local source = handle:read("*a")
    handle:close()
    for _, forbidden in ipairs({
        "SendAddonMessage", "SendChatMessage", "C_ChatInfo", "NotifyInspect",
        "INSPECT_READY", "COMBAT_LOG_EVENT", "CHAT_MSG", "GROUP_ROSTER_UPDATE",
    }) do
        test.eq(string.find(source, forbidden, 1, true), nil, "entry never uses " .. forbidden)
    end
end
