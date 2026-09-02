return function(test)
    BG = { BGNext = {} }
    local wish = dofile("Core/BGNext/Wishlist.lua")
    local limits = { difficulties = 2, bosses = 2, slots = 2 }

    -- 1) normalizePriority accepts only the stable core/normal/backup enum
    test.eq(wish.normalizePriority("core"), "core", "core is a valid priority")
    test.eq(wish.normalizePriority("normal"), "normal", "normal is a valid priority")
    test.eq(wish.normalizePriority("backup"), "backup", "backup is a valid priority")
    test.eq(wish.normalizePriority(nil), "normal", "missing priority falls back to normal")
    test.eq(wish.normalizePriority(""), "normal", "empty priority falls back to normal")
    test.eq(wish.normalizePriority("CORE"), "normal", "unknown casing falls back to normal")
    test.eq(wish.normalizePriority("weird"), "normal", "unknown text falls back to normal")
    test.eq(wish.normalizePriority(123), "normal", "illegal type falls back to normal")
    test.eq(wish.normalizePriority({}), "normal", "table priority falls back to normal")

    -- 2) priorities ride on the slot record; the default keeps the plain-number shape
    local root = { wishlist = {}, wishlistUnplaced = {} }
    test.eq(wish.setSlot(root, "realm", "A", "ICC", limits, 1, 1, 1, 7001), true, "slot stored")
    test.eq(type(root.wishlist.realm.A.ICC[1][1][1]), "number", "default priority keeps the plain-number record")
    local record = wish.getSlotRecord(root, "realm", "A", "ICC", 1, 1, 1)
    test.eq(record.itemId, 7001, "record exposes the item")
    test.eq(record.priority, "normal", "record exposes the default priority")
    test.eq(wish.setSlot(root, "realm", "A", "ICC", limits, 1, 1, 2, 7002, "core"), true, "priority stored")
    test.eq(wish.getSlot(root, "realm", "A", "ICC", 1, 1, 2), 7002, "table record unwraps the item id")
    record = wish.getSlotRecord(root, "realm", "A", "ICC", 1, 1, 2)
    test.eq(record.itemId, 7002, "priority record keeps the item")
    test.eq(record.priority, "core", "priority record keeps the enum")
    test.eq(wish.setSlot(root, "realm", "A", "ICC", limits, 2, 1, 1, 7003, "backup"), true, "backup stored")
    test.eq(wish.getSlotPriority(root, "realm", "A", "ICC", 2, 1, 1), "backup", "priority readable")
    test.eq(wish.getSlotPriority(root, "realm", "A", "ICC", 2, 2, 2), nil, "empty slot has no priority")
    test.eq(wish.setSlot(root, "realm", "A", "ICC", limits, 2, 2, 1, 7004, "nonsense"), true,
        "invalid priority is accepted at write time")
    test.eq(wish.getSlotPriority(root, "realm", "A", "ICC", 2, 2, 1), "normal", "invalid priority stored as normal")
    test.eq(type(root.wishlist.realm.A.ICC[2][2][1]), "number", "normalized default stores the plain-number record")

    -- 3) legacy SavedVariables without any priority keep working
    local legacyRoot = { wishlist = { realm = { A = { ICC = { [1] = { [2] = { [1] = 7100, [2] = 7101 } } } } } } }
    test.eq(wish.getSlot(legacyRoot, "realm", "A", "ICC", 1, 2, 1), 7100, "legacy numeric record reads")
    test.eq(wish.getSlotPriority(legacyRoot, "realm", "A", "ICC", 1, 2, 1), "normal", "legacy record shows normal")
    test.eq(wish.getSlotRecord(legacyRoot, "realm", "A", "ICC", 1, 2, 2).priority, "normal", "second legacy slot normal")

    -- 4) setSlotPriority edits in place; normal collapses back to the plain record
    test.eq(wish.setSlotPriority(root, "realm", "A", "ICC", 1, 1, 1, "core"), true, "priority edited")
    test.eq(wish.getSlotPriority(root, "realm", "A", "ICC", 1, 1, 1), "core", "edited priority stored")
    test.eq(wish.getSlot(root, "realm", "A", "ICC", 1, 1, 1), 7001, "priority edit keeps the item")
    test.eq(wish.setSlotPriority(root, "realm", "A", "ICC", 1, 1, 1, "unknown"), true, "downgrade accepted")
    test.eq(wish.getSlotPriority(root, "realm", "A", "ICC", 1, 1, 1), "normal", "downgrade stored")
    test.eq(type(root.wishlist.realm.A.ICC[1][1][1]), "number", "downgrade collapses the record")
    test.eq(wish.setSlotPriority(root, "realm", "A", "ICC", 2, 2, 2, "core"), false, "empty slot gains no priority")

    -- 5) deletion removes item and priority together
    wish.setSlotPriority(root, "realm", "A", "ICC", 1, 1, 2, "backup")
    test.eq(wish.getSlotPriority(root, "realm", "A", "ICC", 1, 1, 2), "backup", "pre-delete priority")
    test.eq(wish.clearSlot(root, "realm", "A", "ICC", 1, 1, 2), true, "slot cleared")
    test.eq(wish.getSlotRecord(root, "realm", "A", "ICC", 1, 1, 2), nil, "record removed")
    test.eq(root.wishlist.realm.A.ICC[1][1][2], nil, "cleared slot leaves no orphan priority data")
    test.eq(wish.findItem(root, "realm", "A", "ICC", 7003)[1].slotIndex, 1, "findItem still matches record slots")
    test.eq(wish.findItem(root, "realm", "A", "ICC", 7002)[1], nil, "cleared item no longer found")

    -- 6) wheel cycling over the three levels
    test.eq(wish.cyclePriority("normal", 1), "core", "wheel up from normal")
    test.eq(wish.cyclePriority("normal", -1), "backup", "wheel down from normal")
    test.eq(wish.cyclePriority("core", 1), "backup", "wheel up wraps from core")
    test.eq(wish.cyclePriority("backup", -1), "core", "wheel down wraps from backup")
    test.eq(wish.cyclePriority(nil, 1), "core", "missing priority cycles from the default")
    test.eq(wish.cyclePriority("garbage", -1), "backup", "unknown priority normalizes before cycling")

    -- 7) highest priority across several matches
    wish.setSlot(root, "realm", "A", "ICC", limits, 2, 2, 2, 7001, "core")
    test.eq(wish.highestPriority(root, "realm", "A", "ICC", 7001), "core", "highest matching slot wins")
    test.eq(wish.highestPriority(root, "realm", "A", "ICC", 7004), "normal", "plain record reports normal")
    test.eq(wish.highestPriority(root, "realm", "A", "ICC", 5999), nil, "missing item has no priority")

    -- 8) display keys stay stable behind the locale layer
    test.eq(wish.priorityTagKey("core"), "BIS", "core tag key")
    test.eq(wish.priorityTagKey("normal"), "次BIS", "normal tag key")
    test.eq(wish.priorityTagKey("backup"), "备选", "backup tag key")
    test.eq(wish.priorityTagKey("bogus"), "次BIS", "unknown priority renders the default tag")
    test.eq(wish.priorityNameKey("core"), "核心提升", "core name key")
    test.eq(wish.priorityNameKey("normal"), "普通需求", "normal name key")
    test.eq(wish.priorityNameKey("backup"), "备选", "backup name key")

    -- 9) export keeps the historical text and appends priorities only when set
    local exportRoot = { wishlist = {}, wishlistUnplaced = {} }
    wish.setSlot(exportRoot, "realm", "A", "ICC", limits, 1, 1, 1, 7001)
    wish.setSlot(exportRoot, "realm", "A", "ICC", limits, 1, 1, 2, 7002, "core")
    wish.setSlot(exportRoot, "realm", "A", "ICC", limits, 2, 1, 1, 7003, "backup")
    test.eq(wish.exportRaid(exportRoot, "realm", "A", "ICC", limits),
        "ICC:n1b1-7001-7002@core,n2b1-7003@backup", "prioritized export")
    wish.setSlot(exportRoot, "realm", "A", "ICC", limits, 1, 2, 1, 7004)
    test.eq(wish.exportRaid(exportRoot, "realm", "A", "ICC", limits),
        "ICC:n1b1-7001-7002@core,n1b2-7004,n2b1-7003@backup", "normal items keep the historical token shape")

    -- 10) historical strings import unchanged
    local parsed = wish.parseImport("ICC:n1b1-7001-7002,n2b1-7003", { ICC = limits })
    test.eq(parsed.ok, true, "historical string imports")
    test.eq(parsed.itemCount, 3, "historical string counts items")
    test.eq(parsed.raids.ICC[1][1][1], 7001, "historical slot 1")
    test.eq(parsed.raids.ICC[1][1][2], 7002, "historical slot 2")
    test.eq(parsed.raids.ICC[2][1][1], 7003, "historical second difficulty")
    test.eq(parsed.priorities, nil, "historical string carries no priorities")

    local legacyApplied = { wishlist = {}, wishlistUnplaced = {} }
    test.eq(wish.applyImport(legacyApplied, "realm", "A", parsed), true, "historical import applied")
    test.eq(wish.getSlotPriority(legacyApplied, "realm", "A", "ICC", 1, 1, 1), "normal",
        "historical import defaults to normal")
    test.eq(type(legacyApplied.wishlist.realm.A.ICC[1][1][1]), "number", "historical import keeps plain records")

    -- 11) prioritized text round-trips
    local text = wish.exportRaid(exportRoot, "realm", "A", "ICC", limits)
    local prioritized = wish.parseImport(text, { ICC = limits })
    test.eq(prioritized.ok, true, "prioritized string imports")
    test.eq(prioritized.raids.ICC[1][1][1], 7001, "prioritized parse keeps the item")
    test.eq(prioritized.priorities.ICC[1][1][2], "core", "core survives parse")
    test.eq(prioritized.priorities.ICC[2][1][1], "backup", "backup survives parse")
    local restored = { wishlist = {}, wishlistUnplaced = {} }
    test.eq(wish.applyImport(restored, "realm", "A", prioritized), true, "prioritized import applied")
    test.eq(wish.getSlotPriority(restored, "realm", "A", "ICC", 1, 1, 2), "core", "core survives apply")
    test.eq(wish.getSlotPriority(restored, "realm", "A", "ICC", 2, 1, 1), "backup", "backup survives apply")
    test.eq(wish.getSlot(restored, "realm", "A", "ICC", 1, 1, 1), 7001, "normal item survives apply")
    test.eq(wish.exportRaid(restored, "realm", "A", "ICC", limits), text, "export after import is byte-stable")

    -- 12) broken priority values fall back instead of rejecting valid data
    local forgiving = wish.parseImport("ICC:n1b1-7001@weird-7002@,n1b2-7003@core@x", { ICC = limits })
    test.eq(forgiving.ok, true, "corrupt priority does not reject the import")
    test.eq(forgiving.raids.ICC[1][1][1], 7001, "item before corrupt priority kept")
    test.eq(forgiving.raids.ICC[1][1][2], 7002, "item before empty priority kept")
    test.eq(forgiving.raids.ICC[1][2][1], 7003, "item before padded priority kept")
    test.eq(forgiving.priorities and forgiving.priorities.ICC and forgiving.priorities.ICC[1][2]
        and forgiving.priorities.ICC[1][2][1], nil, "corrupt priority is not stored")
    local forgivingApplied = { wishlist = {}, wishlistUnplaced = {} }
    wish.applyImport(forgivingApplied, "realm", "A", forgiving)
    test.eq(wish.getSlotPriority(forgivingApplied, "realm", "A", "ICC", 1, 1, 1), "normal",
        "corrupt priority applies as normal")

    -- 13) a failing import stays atomic
    local atomicRoot = { wishlist = { realm = { A = { ICC = { [1] = { [1] = { [1] = 7200 } } } } } } }
    local failed = wish.parseImport("ICC:n1b1-7001@core,n1b2-bad()", { ICC = limits })
    test.eq(failed.ok, false, "mixed invalid payload rejected")
    test.eq(wish.applyImport(atomicRoot, "realm", "A", failed), false, "failed import not applied")
    test.eq(wish.getSlot(atomicRoot, "realm", "A", "ICC", 1, 1, 1), 7200, "failed import preserves existing data")
    test.eq(wish.getSlotRecord(atomicRoot, "realm", "A", "ICC", 1, 1, 1).priority, "normal", "no half-written priority")

    -- 14) strict isolation of priority across every context key
    local isoRoot = { wishlist = {}, wishlistUnplaced = {} }
    wish.setSlot(isoRoot, "realm", "A", "ICC", limits, 1, 1, 1, 7300, "core")
    test.eq(wish.getSlotPriority(isoRoot, "realm", "B", "ICC", 1, 1, 1), nil, "other character isolated")
    test.eq(wish.getSlotPriority(isoRoot, "realm", "A", "TOC", 1, 1, 1), nil, "other raid isolated")
    test.eq(wish.getSlotPriority(isoRoot, "other-realm", "A", "ICC", 1, 1, 1), nil, "other realm isolated")
    test.eq(wish.getSlotPriority(isoRoot, "realm", "A", "ICC", 2, 1, 1), nil, "other difficulty isolated")
    test.eq(wish.getSlotPriority(isoRoot, "realm", "A", "ICC", 1, 2, 1), nil, "other boss isolated")
    test.eq(wish.getSlotPriority(isoRoot, "realm", "A", "ICC", 1, 1, 2), nil, "other slot isolated")

    -- 15) reminders include the hit priority
    BG.BGNext.Wishlist = wish
    BG.BGNext.DB = { wishlist = {}, wishlistUnplaced = {} }
    BG.realmID, BG.playerName = "realm", "A"
    local messages = {}
    BG.FrameLootMsg = { AddMessage = function(_, message) messages[#messages + 1] = message end }
    BG.PlaySound = function() end
    local reminder = dofile("Core/BGNext/WishlistReminder.lua")
    wish.setSlot(BG.BGNext.DB, "realm", "A", "ICC", limits, 1, 1, 1, 8001, "core")
    wish.setSlot(BG.BGNext.DB, "realm", "A", "ICC", limits, 1, 1, 2, 8002)
    test.eq(reminder.notify("loot", 8001, "ICC", "loot:1", "[CoreItem]", 251), true, "wish loot reminds")
    test.eq(messages[1]:find("心愿：核心提升", 1, true) ~= nil, true, "loot reminder names the core priority")
    test.eq(reminder.notify("auction", 8002, "ICC", "auction:1", "[NormalItem]"), true, "wish auction reminds")
    test.eq(messages[2]:find("心愿：普通需求", 1, true) ~= nil, true, "auction reminder names the default priority")
    test.eq(reminder.notify("loot", 8999, "ICC", "loot:2", "[Missing]"), false, "non-wish stays silent")
    test.eq(#messages, 2, "no extra reminder messages")

    -- 16) priorities never reach any send path
    local function readSource(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end
    for _, path in ipairs({
        "Core/BGNext/Wishlist.lua",
        "Core/BGNext/WishlistUI.lua",
        "Core/BGNext/WishlistReminder.lua",
    }) do
        local source = readSource(path)
        for _, forbidden in ipairs({ "SendChatMessage", "SendAddonMessage", "C_ChatInfo" }) do
            test.eq(source:find(forbidden, 1, true), nil, path .. " has no " .. forbidden)
        end
    end
    for _, path in ipairs({ "Core/BGNext/AuctionSender.lua", "Core/BGNext/BillBuyer.lua" }) do
        local source = readSource(path)
        test.eq(source:find("Wishlist", 1, true), nil, path .. " never reads the wishlist")
        test.eq(source:lower():find("priority", 1, true), nil, path .. " carries no priority field")
    end

    -- 17) manual add works without any loot database
    local dbless = { wishlist = {}, wishlistUnplaced = {} }
    test.eq(wish.setSlot(dbless, "realm", "A", "ICC", limits, 1, 1, 1, 7300), true,
        "manual slot stored without a catalog")
    test.eq(wish.getSlotPriority(dbless, "realm", "A", "ICC", 1, 1, 1), "normal", "manual slot defaults to normal")
    test.eq(wish.placeItem(dbless, "realm", "A", "ICC", limits, 7301, function() return nil end).reason, "unknown-drop",
        "no resolver still refuses to fabricate a source")
    test.eq(wish.getSlot(dbless, "realm", "A", "ICC", 1, 1, 1), 7300, "existing manual slot untouched")

    -- 18) the wishlist UI keeps priority interactions local and cheap
    local uiSource = readSource("Core/BGNext/WishlistUI.lua")
    for _, required in ipairs({
        "wishlist.cyclePriority",
        "wishlist.setSlotPriority",
        "wishlist.priorityTagKey",
        "wishlist.priorityTipKey",
        'SetScript("OnMouseWheel"',
    }) do
        test.eq(uiSource:find(required, 1, true) ~= nil, true, "wishlist UI keeps priority contract: " .. required)
    end
    for _, forbidden in ipairs({ "C_Timer", "OnUpdate" }) do
        test.eq(uiSource:find(forbidden, 1, true), nil, "wishlist UI stays event-free: " .. forbidden)
    end
    for _, required in ipairs({
        "M.slotTagLayout",
        "SetTextInsets",
        'SetPoint("LEFT", slot, "LEFT", 2, 0)',
    }) do
        test.eq(uiSource:find(required, 1, true) ~= nil, true, "wishlist UI keeps tag layout contract: " .. required)
    end
    test.eq(uiSource:find('priorityTag:SetPoint("BOTTOMRIGHT"', 1, true), nil,
        "priority tag no longer overlays the status-marker corner")

    -- 19) hot wish lookups must not allocate per scanned slot (GC paused, no
    --     wall-time assertions)
    local perfRoot = { wishlist = { realm = { A = { ICC = {} } } } }
    for difficultyIndex = 1, 3 do
        perfRoot.wishlist.realm.A.ICC[difficultyIndex] = {}
        for bossIndex = 1, 5 do
            perfRoot.wishlist.realm.A.ICC[difficultyIndex][bossIndex] = {}
            for slotIndex = 1, 7 do
                perfRoot.wishlist.realm.A.ICC[difficultyIndex][bossIndex][slotIndex] = 9000 + slotIndex
            end
        end
    end
    collectgarbage("stop")
    local beforeKiB = collectgarbage("count")
    for _ = 1, 5000 do
        if wish.contains(perfRoot, "realm", "A", "ICC", 424242) then
            collectgarbage("restart")
            error("miss probe unexpectedly matched")
        end
    end
    local containsGrownKiB = collectgarbage("count") - beforeKiB
    for _ = 1, 5000 do
        if wish.highestPriority(perfRoot, "realm", "A", "ICC", 424242) then
            collectgarbage("restart")
            error("miss probe unexpectedly matched")
        end
    end
    local priorityGrownKiB = collectgarbage("count") - beforeKiB
    collectgarbage("restart")
    test.eq(containsGrownKiB < 2048, true,
        "5000 miss contains scans allocate under 2 MiB, got " .. string.format("%.0f KiB", containsGrownKiB))
    test.eq(priorityGrownKiB < 2048, true,
        "5000 miss highestPriority scans allocate under 2 MiB, got " .. string.format("%.0f KiB", priorityGrownKiB))
    test.eq(wish.contains(perfRoot, "realm", "A", "ICC", 9001), true, "hit lookup still works after the GC pause")
    test.eq(wish.highestPriority(perfRoot, "realm", "A", "ICC", 9001), "normal", "hit priority still works")

    -- 20) the priority tag owns a reserved left strip; item text and the
    --     upstream owned/dropped/level markers keep disjoint regions
    local ui = dofile("Core/BGNext/WishlistUI.lua")
    local layout = ui.slotTagLayout(115)
    test.eq(layout.textLeftInset, layout.tagStrip + 2, "item text starts after the tag strip")
    test.eq(layout.textLeftInset + layout.textWidth + layout.textRightInset, layout.slotWidth,
        "text and tag regions tile the slot width")
    test.eq(layout.textWidth >= 65, true, "item text keeps a readable region")
    test.eq(layout.tagStrip <= layout.textLeftInset, true, "tag strip never reaches the text region")
    -- Glyph-width model for outline UI fonts: CJK/fullwidth glyphs render at
    -- the font height, Latin letters/digits/space at roughly 0.55x.
    local function estimatedTextWidth(text, fontHeight)
        local width = 0
        for index = 1, #text do
            local byte = string.byte(text, index)
            if byte >= 0xC0 then
                width = width + fontHeight
            elseif byte < 0x80 then
                width = width + fontHeight * 0.55
            end
        end
        return width
    end
    for _, label in ipairs({ "BIS", "次BIS", "备选", "備選", "BiS", "2nd BiS", "Backup" }) do
        test.eq(estimatedTextWidth(label, layout.tagFontHeight) <= layout.tagMaxTextWidth, true,
            "priority tag fits its reserved strip: " .. label)
    end
end
