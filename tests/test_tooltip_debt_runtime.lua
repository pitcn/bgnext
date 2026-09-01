return function(test)
    BG = { BGNext = {} }
    dofile("Core/BGNext/TooltipDebtCache.lua")
    local TooltipDebtRuntime = dofile("Core/BGNext/TooltipDebtRuntime.lua")

    local buyer = { text = "Alice-MyRealm", scripts = {} }
    local money = { text = "10", scripts = {} }
    function buyer:GetText() return self.text end
    function money:GetText() return self.text end

    local debtButton = { methodHooks = {} }
    function debtButton:Show()
        for _, callback in ipairs(self.methodHooks.Show or {}) do callback() end
    end
    function debtButton:Hide()
        for _, callback in ipairs(self.methodHooks.Hide or {}) do callback() end
    end

    local pairCount = 0
    local editHookCount = 0
    local methodHookCount = 0
    local debt = 5
    local runtime = TooltipDebtRuntime.new({
        isReady = function(raidId) return raidId == "ULD" end,
        pairItems = function(_, callback)
            pairCount = pairCount + 1
            callback(nil, buyer, money, 3, 1)
        end,
        maxBoss = function() return 3 end,
        getDebt = function() return debt end,
        getDebtButton = function() return debtButton end,
        hookEdit = function(edit, callback)
            editHookCount = editHookCount + 1
            edit.scripts.OnTextChanged = callback
        end,
        hookMethod = function(frame, method, callback)
            methodHookCount = methodHookCount + 1
            frame.methodHooks[method] = frame.methodHooks[method] or {}
            frame.methodHooks[method][#frame.methodHooks[method] + 1] = callback
        end,
        normalizeName = function(name)
            return name:gsub("%-MyRealm$", "")
        end,
    })

    for _ = 1, 100 do
        runtime:get({ enabled = false, inRaid = true, raidId = "ULD" })
    end
    test.eq(pairCount, 0, "disabled runtime requests never scan table rows")

    local fines, debts = runtime:get({ enabled = true, inRaid = true, raidId = "ULD" })
    test.eq(pairCount, 1, "the first enabled runtime request scans once")
    test.eq(fines.Alice, 10, "the runtime aggregates the fine column")
    test.eq(debts.Alice, 5, "the runtime aggregates debt values")
    runtime:get({ enabled = true, inRaid = true, raidId = "ULD" })
    test.eq(pairCount, 1, "an unchanged runtime request reuses cached values")

    buyer.text = "Bob-MyRealm"
    buyer.scripts.OnTextChanged()
    fines = runtime:get({ enabled = true, inRaid = true, raidId = "ULD" })
    test.eq(pairCount, 2, "changing the buyer rebuilds on the next request")
    test.eq(fines.Bob, 10, "the rebuilt cache exposes the changed buyer")

    money.text = "25"
    money.scripts.OnTextChanged()
    fines = runtime:get({ enabled = true, inRaid = true, raidId = "ULD" })
    test.eq(pairCount, 3, "changing the amount rebuilds on the next request")
    test.eq(fines.Bob, 25, "the rebuilt cache exposes the changed amount")

    debt = 7
    debtButton:Show()
    debts = select(2, runtime:get({ enabled = true, inRaid = true, raidId = "ULD" }))
    test.eq(pairCount, 4, "showing an updated debt marks the cache dirty")
    test.eq(debts.Bob, 7, "the rebuilt cache exposes the changed debt")

    debtButton:Hide()
    debtButton:Show()
    runtime:get({ enabled = true, inRaid = true, raidId = "ULD" })
    test.eq(pairCount, 5, "multiple changes before one request cause only one rebuild")
    test.eq(editHookCount, 2, "buyer and amount change hooks are installed once")
    test.eq(methodHookCount, 2, "debt Show and Hide hooks are installed once")

    runtime:get({ enabled = true, inRaid = false, raidId = "ULD" })
    test.eq(pairCount, 5, "leaving the raid never performs a scan")
end
