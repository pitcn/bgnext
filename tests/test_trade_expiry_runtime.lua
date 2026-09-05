return function(test)
    local Expiry = dofile("Core/BGNext/TradeExpiryRuntime.lua")

    test.eq(Expiry.parseRemainingSeconds("1小时25分钟"), 5100,
        "Chinese trade time is parsed")
    test.eq(Expiry.parseRemainingSeconds("1 hour 25 minutes"), 5100,
        "English trade time is parsed")
    test.eq(Expiry.parseRemainingSeconds("58 sec"), 58,
        "short English units are parsed")
    test.eq(Expiry.shouldScan(true, true), true,
        "enabled loot leaders scan")
    test.eq(Expiry.shouldScan(false, true), false,
        "disabled reminders do not scan")
    test.eq(Expiry.shouldScan(true, false), false,
        "ordinary group members do not scan")

    local scanned = Expiry.scanBags({
        maxBag = 0,
        tradeTemplate = "Trade for %s",
        numSlots = function() return 2 end,
        itemLink = function(_, slot)
            return slot == 1 and "|Hitem:12345::::::::|h[Loot]|h" or nil
        end,
        tooltipLines = function()
            return { "Soulbound", "Trade for 20 minutes" }
        end,
    })
    test.eq(#scanned, 1, "bag scan keeps only slots with a trade deadline")
    test.eq(scanned[1].itemID, 12345, "bag scan extracts the local item id")
    test.eq(scanned[1].time, 20, "bag scan projects remaining minutes for the view")

    test.eq(Expiry.extractRemainingSeconds({
        "Soulbound",
        "You may trade this item for the next 1 hour 25 minutes",
    }, "You may trade this item for the next %s"), 5100,
        "only the localized trade-time tooltip line is accepted")
    test.eq(Expiry.extractRemainingSeconds({ "Cooldown remaining: 10 minutes" },
        "You may trade this item for the next %s"), nil,
        "unrelated tooltip durations are ignored")

    local scans, notices, updates, lastUpdateCount, scheduled, cancelled = 0, 0, 0, nil, {}, 0
    local enabled, leader, currentNow = true, true, 1000
    local scanEntries = { { key = "bag0:1", link = "[Loot]", remainingSeconds = 1200 } }
    local controller = Expiry.newController({
        enabled = function() return enabled end,
        isLootLeader = function() return leader end,
        now = function() return currentNow end,
        thresholdSeconds = function() return 1800 end,
        mutedUntil = function() return 0 end,
        scan = function()
            scans = scans + 1
            return scanEntries
        end,
        notify = function(entries)
            notices = notices + 1
            test.eq(#entries, 1, "notification receives expiring entries")
        end,
        updateView = function(entries)
            updates = updates + 1
            lastUpdateCount = #entries
        end,
        schedule = function(delay, callback)
            local timer = { delay = delay, callback = callback, cancelled = false }
            scheduled[#scheduled + 1] = timer
            return timer
        end,
        cancel = function(timer)
            timer.cancelled = true
            cancelled = cancelled + 1
        end,
    })

    controller:refresh()
    test.eq(scans, 1, "enabled loot leader scans once")
    test.eq(notices, 1, "an item below the threshold notifies once")
    test.eq(updates, 1, "the visible model is refreshed")
    test.eq(lastUpdateCount, 1, "view receives the current local entries")
    test.eq(#scheduled, 1, "one bounded follow-up is scheduled")

    controller:refresh()
    test.eq(notices, 1, "the same expiring bag slot is throttled")
    test.eq(cancelled, 1, "refresh replaces the previous one-shot timer")

    scanEntries = { { key = "bag0:2", link = "[New Loot]", remainingSeconds = 900 } }
    currentNow = 1100
    controller:refresh()
    test.eq(notices, 1, "different loot is still held by the five-minute global interval")

    currentNow = 1300
    controller:refresh()
    test.eq(notices, 2, "new loot notifies after the global interval")

    enabled = false
    controller:refresh()
    test.eq(scans, 4, "disabled refresh does not scan")
    test.eq(cancelled, 4, "disabling cancels the remaining timer")
    test.eq(#controller.entries, 0, "disabling drops the in-memory list")
    test.eq(lastUpdateCount, 0, "disabling clears the view")
end
