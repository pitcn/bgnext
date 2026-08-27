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

    -- Controls read settings, refresh, close left-to-right (close far right).
    local order = Entry.controlOrder()
    test.eq(order[1], "settings", "settings control comes first")
    test.eq(order[2], "refresh", "refresh control comes second")
    test.eq(order[3], "close", "close control comes last")

    -- Both documented commands are recognised, with and without arguments.
    test.eq(Entry.parseCommand("role"), "role", "/bgn role is recognised")
    test.eq(Entry.parseCommand("  role  "), "role", "surrounding spaces are ignored")
    test.eq(Entry.parseCommand("ROLE"), "role", "the command is case-insensitive")
    test.eq(Entry.parseCommand("角色总览"), "role", "the localized command is recognised")
    test.eq(Entry.parseCommand(""), nil, "an empty command is not the role command")
    test.eq(Entry.parseCommand(nil), nil, "a missing command is safe")
    test.eq(Entry.parseCommand("something-else"), nil, "unrelated arguments are ignored")

    -- dispatchSlash decides whether the command was the role overview and, when
    -- it was, hands off to the entry's own toggle instead of the main frame.
    local toggles = 0
    local mockEntry = { togglePinned = function() toggles = toggles + 1 end }
    test.eq(Entry.dispatchSlash("role", mockEntry), true, "/bgn role is dispatched")
    test.eq(toggles, 1, "dispatchSlash toggles the pinned window")
    test.eq(Entry.dispatchSlash("  role  ", mockEntry), true, "surrounding spaces are ignored")
    test.eq(Entry.dispatchSlash("角色总览", mockEntry), true, "the localized command is dispatched")
    test.eq(toggles, 3, "three role commands toggle three times")
    test.eq(Entry.dispatchSlash("something", mockEntry), false, "an unrelated argument is not dispatched")
    test.eq(Entry.dispatchSlash("", mockEntry), false, "an empty command is not dispatched")
    test.eq(Entry.dispatchSlash(nil, mockEntry), false, "a missing command is not dispatched")

    test.eq(Entry.canOpen({ isEnabled = function() return true end }), true,
        "an enabled runtime allows the overview to open")
    test.eq(Entry.canOpen({ isEnabled = function() return false end }), false,
        "a disabled runtime blocks entry hover and slash opening")
    test.eq(toggles, 3, "non-role commands never toggle")

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

    -- The delete confirmation names the exact character and realm.
    local dialog = Entry.deleteDialogText({ player = "Piti", realmId = 123 }, { realmName = "时光II" })
    test.eq(type(dialog), "string", "delete confirmation produces text")
    test.eq(string.find(dialog, "Piti", 1, true) ~= nil, true, "delete confirmation names the character")
    test.eq(string.find(dialog, "时光II", 1, true) ~= nil, true, "delete confirmation names the realm")
    test.eq(string.find(dialog, "%", 1, true), nil, "delete confirmation has no format placeholder")

    -- Without a realm name it falls back to the realm id, still naming the row.
    local dialog2 = Entry.deleteDialogText({ player = "Piti", realmId = 123 }, nil)
    test.eq(string.find(dialog2, "123", 1, true) ~= nil, true, "delete confirmation falls back to the realm id")
    test.eq(Entry.deleteDialogText(nil, nil), "", "a missing request produces empty text")

    -- Window anchors save only serializable values, never the relative frame.
    local anchor = Entry.sanitizePoint("TOPLEFT", { name = "not-serializable" }, "BOTTOMRIGHT", 12.5, -7)
    test.eq(type(anchor), "table", "sanitizePoint keeps a valid anchor")
    test.eq(anchor.point, "TOPLEFT", "sanitizePoint keeps the point")
    test.eq(anchor.relativePoint, "BOTTOMRIGHT", "sanitizePoint keeps the relative point")
    test.eq(anchor.x, 12.5, "sanitizePoint keeps x")
    test.eq(anchor.y, -7, "sanitizePoint keeps y")
    test.eq(anchor.relativeTo, nil, "sanitizePoint drops the frame reference")
    test.eq(Entry.sanitizePoint(nil, nil, "CENTER", 0, 0), nil, "a missing point is rejected")
    test.eq(Entry.sanitizePoint("CENTER", nil, nil, 0, 0), nil, "a missing relative point is rejected")
    test.eq(Entry.sanitizePoint("CENTER", nil, "CENTER", "0", 0), nil, "a non-numeric x is rejected")
    test.eq(Entry.sanitizePoint("NOT_ANCHOR", nil, "CENTER", 0, 0), nil, "an invalid point is rejected")
    test.eq(Entry.sanitizePoint("CENTER", nil, "NOT_ANCHOR", 0, 0), nil, "an invalid relative point is rejected")

    -- Restore accepts only a valid, visible position.
    local restored = Entry.restorePoint({ point = "TOPLEFT", relativePoint = "BOTTOMRIGHT", x = 5, y = 5 })
    test.eq(type(restored), "table", "restorePoint accepts a valid anchor")
    test.eq(restored.x, 5, "restorePoint keeps x")
    test.eq(Entry.restorePoint(nil), nil, "restorePoint rejects a missing anchor")
    test.eq(Entry.restorePoint({ point = "TOPLEFT", relativePoint = "CENTER" }), nil, "restorePoint rejects missing coordinates")
    test.eq(Entry.restorePoint({ point = "TOPLEFT", relativePoint = "CENTER", x = "5", y = 5 }), nil,
        "restorePoint rejects non-numeric coordinates")
    test.eq(Entry.restorePoint({ point = "TOPLEFT", relativePoint = "CENTER", x = 999999999, y = 5 }), nil,
        "restorePoint rejects off-screen coordinates")
    local viewport = { width = 1920, height = 1080, windowWidth = 600, windowHeight = 300 }
    test.eq(Entry.restorePoint({ point = "CENTER", relativePoint = "CENTER", x = 600, y = 300 }, viewport) ~= nil,
        true, "restorePoint accepts a visible centered window")
    test.eq(Entry.restorePoint({ point = "CENTER", relativePoint = "CENTER", x = 800, y = 300 }, viewport), nil,
        "restorePoint rejects a moderately off-screen x coordinate")
    test.eq(Entry.restorePoint({ point = "CENTER", relativePoint = "CENTER", x = 600, y = 500 }, viewport), nil,
        "restorePoint rejects a moderately off-screen y coordinate")

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

    -- The settings control jumps straight to the 角色总览 settings page.
    test.eq(string.find(source, "ButtonOptions_roleOverview", 1, true) ~= nil, true,
        "settings control opens the role overview page")
end
