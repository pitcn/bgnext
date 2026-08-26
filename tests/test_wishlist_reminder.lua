return function(test)
    BG = { BGNext = {} }
    local reminder = dofile("Core/BGNext/WishlistReminder.lua")

    local event = reminder.matchEvent({ 8001, 8001, 8002 }, 8001, "ICC", "loot:42")
    test.eq(event.matched, true, "matching wish reminds")
    test.eq(event.key, "loot:42:8001", "event key is deterministic")
    test.eq(reminder.shouldNotify({}, event.key), true, "first event notifies")
    local seen = {}
    reminder.markNotified(seen, event.key)
    test.eq(reminder.shouldNotify(seen, event.key), false, "duplicate slot and event notifies once")
    test.eq(reminder.matchEvent({ 8001 }, 8999, "ICC", "auction:7").matched, false,
        "unmatched item stays silent")
    test.eq(reminder.matchEvent({}, 8001, "ICC", "loot:43").matched, false, "empty wishlist stays silent")

    local file = assert(io.open("Core/BGNext/WishlistReminder.lua", "rb"))
    local source = file:read("*a")
    file:close()
    for _, forbidden in ipairs({
        "SendChatMessage",
        "SendAddonMessage",
        "C_ChatInfo",
        "BiaoGe.BGNext",
        "C_Timer",
    }) do
        test.eq(source:find(forbidden, 1, true), nil, "reminder has no send or persistent path: " .. forbidden)
    end
end
