return function(test)
    BG = { BGNext = {} }
    local Refresh = dofile("Core/BGNext/EventRefresh.lua")

    local scheduled = {}
    local runs = 0
    local trigger = Refresh.debounce(function(delay, callback)
        scheduled[#scheduled + 1] = { delay = delay, callback = callback }
    end, 0.1, function()
        runs = runs + 1
    end)

    for _ = 1, 100 do trigger() end
    test.eq(#scheduled, 1, "one hundred events schedule one table refresh")
    test.eq(scheduled[1].delay, 0.1, "table refresh keeps the short delay")
    scheduled[1].callback()
    test.eq(runs, 1, "the scheduled batch refreshes once")

    trigger()
    test.eq(#scheduled, 2, "a later event can schedule the next batch")
    scheduled[2].callback()
    test.eq(runs, 2, "the later batch refreshes once")
end
