return function(test)
    BG = { BGNext = {} }
    local TooltipDebtCache = dofile("Core/BGNext/TooltipDebtCache.lua")
    local buildCount = 0
    local cache = TooltipDebtCache.new(function(raidId)
        buildCount = buildCount + 1
        return { Alice = raidId .. "-fine" }, { Alice = raidId .. "-debt" }
    end)

    local disabledFines, disabledDebts
    for _ = 1, 100 do
        local fines, debts = cache:get({ enabled = false, inRaid = true, raidId = "ULD" })
        disabledFines = disabledFines or fines
        disabledDebts = disabledDebts or debts
        test.eq(fines, disabledFines, "disabled requests reuse the empty fine table")
        test.eq(debts, disabledDebts, "disabled requests reuse the empty debt table")
    end
    test.eq(buildCount, 0, "disabled tooltip debt info never rebuilds the table cache")

    local fines, debts = cache:get({ enabled = true, inRaid = true, raidId = "ULD" })
    test.eq(buildCount, 1, "the first enabled tooltip request builds the cache once")
    test.eq(fines.Alice, "ULD-fine", "the cache returns the current raid's fine data")
    test.eq(debts.Alice, "ULD-debt", "the cache returns the current raid's debt data")

    cache:get({ enabled = true, inRaid = true, raidId = "ULD" })
    test.eq(buildCount, 1, "unchanged tooltip requests reuse the cache")

    cache:invalidate()
    cache:get({ enabled = true, inRaid = true, raidId = "ULD" })
    test.eq(buildCount, 2, "a dirty table rebuilds on the next tooltip request")

    cache:get({ enabled = true, inRaid = true, raidId = "ICC" })
    test.eq(buildCount, 3, "switching the current raid rebuilds the cache")

    cache:get({ enabled = true, inRaid = false, raidId = "ICC" })
    cache:get({ enabled = true, inRaid = true, raidId = "ICC" })
    test.eq(buildCount, 4, "leaving the raid clears cached values before a later rejoin")

    local hooksHandle = assert(io.open("Core/Module/hooks.lua", "r"))
    local hooksSource = hooksHandle:read("*a")
    hooksHandle:close()
    test.eq(hooksSource:find("C_Timer.NewTicker", 1, true), nil,
        "tooltip debt data no longer performs a permanent two-second table scan")
    test.eq(hooksSource:find("TooltipDebtRuntime.new", 1, true) ~= nil, true,
        "the tooltip runtime delegates rebuild decisions to the lazy cache")

    local tocHandle = assert(io.open("BGLite.toc", "r"))
    local toc = tocHandle:read("*a")
    tocHandle:close()
    local cachePos = toc:find("Core\\BGNext\\TooltipDebtCache.lua", 1, true)
    local runtimePos = toc:find("Core\\BGNext\\TooltipDebtRuntime.lua", 1, true)
    local hooksPos = toc:find("Core\\Module\\hooks.lua", 1, true)
    test.eq(cachePos ~= nil and runtimePos ~= nil and hooksPos ~= nil
        and cachePos < runtimePos and runtimePos < hooksPos, true,
        "the tooltip debt modules load before the tooltip runtime")
end
