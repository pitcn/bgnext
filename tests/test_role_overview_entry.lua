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
    test.eq(Entry.intent("escape", { pinned = true }), "unpin", "escape unpins the fixed window")
    test.eq(Entry.intent("refresh", {}), "refresh", "the refresh control refreshes")
    test.eq(Entry.intent("settings", {}), "settings", "the settings control opens settings")
    test.eq(Entry.intent("nonsense", {}), nil, "unknown actions do nothing")
    test.eq(Entry.intent(nil, {}), nil, "a missing action does nothing")
    test.eq(Entry.intent("hover", nil), "preview", "a missing state is safe")

    -- Footer role-overview button maps ordinary clicks to toggle, right to settings.
    test.eq(Entry.buttonAction("LeftButton"), "toggle", "left click toggles the pinned window")
    test.eq(Entry.buttonAction("LeftButton", false), "toggle", "a plain left click still toggles")
    test.eq(Entry.buttonAction("LeftButton", true), "toggle", "ctrl+left click is a compat toggle alias")
    test.eq(Entry.buttonAction("MiddleButton"), "toggle", "middle click is a compat toggle alias")
    test.eq(Entry.buttonAction("RightButton"), "settings", "right click opens settings")
    test.eq(Entry.buttonAction("Button4"), nil, "an unknown button does nothing")
    test.eq(Entry.buttonAction(nil), nil, "a missing button does nothing")

    -- Hover preview waits a deliberate delay so a quick pass never flashes.
    test.eq(Entry.previewDelay(), 0.2, "hover preview waits a deliberate delay")

    -- A scheduled reveal fires only while its token is still current; a quick
    -- enter-then-leave advances the token before the timer, so it never flashes.
    test.eq(Entry.hoverTokenCurrent(3, 4), false, "a stale hover token never reveals the preview")
    test.eq(Entry.hoverTokenCurrent(4, 4), true, "a current hover token may reveal the preview")

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
    test.eq(Entry.canOpen({
        isEnabled = function() return true end,
        isAvailable = function() return false end,
    }), false, "an excluded client never exposes the role overview entry")
    test.eq(Entry.canOpen({
        isEnabled = function() return true end,
        isAvailable = function() return true end,
    }), true, "a pending validation client may expose the entry")
    test.eq(toggles, 3, "non-role commands never toggle")

    -- Default is the current realm; holding Shift widens to all local realms.
    test.eq(Entry.showAllRealms({}), false, "default shows the current realm only")
    test.eq(Entry.showAllRealms({ shift = true }), true, "shift shows every local realm")
    test.eq(Entry.showAllRealms(nil), false, "a missing state defaults to current realm")

    -- The main-frame entry follows the original bottom-right presentation.
    local presentation = Entry.entryPresentation("HUNTER")
    test.eq(presentation.point, "BOTTOMRIGHT", "entry anchors from the bottom-right")
    test.eq(presentation.relativePoint, "BOTTOMRIGHT", "entry uses the main frame bottom-right")
    test.eq(presentation.x, -20, "entry keeps the original right inset")
    test.eq(presentation.y, 1, "entry sits on the original bottom bar")
    test.eq(presentation.height, 25, "entry matches the bottom-bar height")
    test.eq(string.find(presentation.text, "GarrMission_ClassIcon-hunter", 1, true) ~= nil, true,
        "entry includes the current class icon")
    test.eq(string.find(presentation.text, "角色总览", 1, true) ~= nil, true,
        "entry includes the original label")

    -- Hover previews attach to the entry and must render above the main addon.
    local preview = Entry.windowPresentation("preview")
    test.eq(preview.strata, "FULLSCREEN_DIALOG", "hover preview renders above the main addon")
    test.eq(preview.point, "BOTTOMRIGHT", "hover preview uses its bottom-right corner")
    test.eq(preview.relativePoint, "TOPRIGHT", "hover preview opens above the entry")
    test.eq(preview.x, 0, "hover preview has no horizontal gap")
    test.eq(preview.y, 0, "hover preview has no vertical gap")

    local fixed = Entry.windowPresentation("pinned")
    test.eq(fixed.strata, "HIGH", "pinned window keeps the original high strata")
    test.eq(fixed.point, "CENTER", "an unsaved pinned window defaults to the screen center")

    local hidden = false
    local newWindow = { Hide = function() hidden = true end }
    test.eq(Entry.prepareNewWindow(newWindow), true, "a newly created role window is initialized")
    test.eq(hidden, true, "a newly created role window starts hidden until explicit interaction")
    test.eq(Entry.previewShouldRemain(false, true, true), true,
        "an intentional hover keeps an unpinned preview visible")
    test.eq(Entry.previewShouldRemain(false, false, true), false,
        "a hidden parent cannot leave a preview visible")
    test.eq(Entry.previewShouldRemain(false, true, false), false,
        "a preview closes when the cursor is no longer over the entry")
    test.eq(Entry.previewShouldRemain(true, false, false), true,
        "a deliberately pinned window is independent of hover state")

    -- The runtime owns the redraw that happens when a window becomes visible.
    -- Entry wiring must not redraw a second time after asking the runtime to
    -- start its visible-window lifecycle.
    local visibilityCalls, directRefreshes = 0, 0
    local handled = Entry.syncVisibility({
        setVisible = function(_, visible)
            visibilityCalls = visibilityCalls + 1
            test.eq(visible, true, "the requested visible state reaches the runtime")
        end,
    }, { Refresh = function() directRefreshes = directRefreshes + 1 end }, true)
    test.eq(handled, "runtime", "the runtime owns visible-window refresh when available")
    test.eq(visibilityCalls, 1, "visibility is forwarded exactly once")
    test.eq(directRefreshes, 0, "entry does not duplicate the runtime redraw")

    local fallbackRefreshes = 0
    handled = Entry.syncVisibility(nil, {
        Refresh = function() fallbackRefreshes = fallbackRefreshes + 1 end,
    }, true)
    test.eq(handled, "ui", "plain UI refresh remains a safe fallback without a runtime")
    test.eq(fallbackRefreshes, 1, "the fallback redraw happens exactly once")

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
    test.eq(string.find(source, 'HookScript("OnHide"', 1, true) ~= nil, true,
        "hiding the main addon closes any transient preview")
    test.eq(string.find(source, 'IsMouseOver', 1, true) ~= nil, true,
        "transient previews verify that the entry is still hovered")
    test.eq(string.find(source, 'BGNextRoleOverviewFrame', 1, true) ~= nil, true,
        "the role overview has a stable global frame name for UISpecialFrames")
    test.eq(string.find(source, 'UISpecialFrames', 1, true) ~= nil, true,
        "the fixed role overview participates in Blizzard escape handling")

    -- The footer uses one OnClick path, never a split mouse-down/mouse-up that
    -- could let a single physical click toggle twice.
    test.eq(string.find(source, "OnMouseDown", 1, true), nil,
        "footer clicks use a single OnClick path")
    test.eq(string.find(source, "buttonAction", 1, true) ~= nil, true,
        "footer clicks route through the shared buttonAction mapper")
    test.eq(string.find(source, 'RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")', 1, true) ~= nil,
        true, "footer registers every mouse button handled by OnClick")
    test.eq(string.find(source, 'Open("raid")', 1, true) ~= nil, true,
        "right click opens the role overview raid settings section")

    -- Hover preview waits with a one-shot timer, never a recurring ticker.
    test.eq(string.find(source, "C_Timer.After", 1, true) ~= nil, true,
        "hover preview waits with a one-shot timer")
    test.eq(string.find(source, "C_Timer.NewTicker", 1, true), nil,
        "hover preview never spins a recurring ticker")

    -- The role overview key binding is independent of the main-table binding.
    local bindings = io.open("Bindings.xml", "r")
    local bindingSource = bindings:read("*a")
    bindings:close()
    test.eq(string.find(bindingSource, 'name="BIAOGE"', 1, true) ~= nil, true,
        "the main-table binding is unchanged")
    test.eq(string.find(bindingSource, 'name="BGNEXT_ROLE_OVERVIEW"', 1, true) ~= nil, true,
        "a role overview binding distinct from BIAOGE is declared")
    local roleBinding = bindingSource:match('name="BGNEXT_ROLE_OVERVIEW"[^>]*>(.-)</Binding>')
    test.eq(type(roleBinding), "string", "the role binding has a body")
    test.eq(string.find(roleBinding or "", "togglePinned", 1, true) ~= nil, true,
        "the role binding calls the guarded role toggle")
    test.eq(string.find(roleBinding or "", "MainFrame", 1, true), nil,
        "the role binding never touches the main table")

    local init = io.open("Core/DB/Init2.lua", "r")
    local initSource = init:read("*a")
    init:close()
    test.eq(string.find(initSource, "BINDING_NAME_BGNEXT_ROLE_OVERVIEW", 1, true) ~= nil, true,
        "the role binding display name is registered")
end
