return function(test)
    BG = { BGNext = {} }
    local guard = dofile("Core/BGNext/ConflictGuard.lua")
    local addons = {
        { name = "BGLite", project = "BGNext", enabled = true, loaded = true },
        { name = "BiaoGe", enabled = true, loaded = true },
        { name = "DisabledCopy", project = "BGLite", enabled = false, loaded = false },
        { name = "Unrelated", title = "Damage Meter", enabled = true, loaded = true },
    }

    local conflicts = guard.findConflicts("BGLite", addons)
    test.eq(#conflicts, 1, "only one confirmed local conflict")
    test.eq(conflicts[1].name, "BiaoGe", "BiaoGe is reported")
    test.eq(guard.isKnownFamily({ name = "BGNext" }), true, "BGNext folder is known")
    test.eq(guard.isKnownFamily({ name = "Renamed", project = "BGNext" }), true, "BGNext metadata is known")
    test.eq(guard.isKnownFamily({ name = "Renamed", upstream = "BGLite 2.4.0" }), true, "BGLite upstream metadata is known")
    test.eq(guard.isKnownFamily({ name = "Unrelated", title = "BGLite guide" }), false, "title text alone is not enough")

    local names = guard.conflictNames(conflicts)
    test.eq(names, "BiaoGe", "prompt lists exact conflict names")

    local disabled = {}
    local reloaded = false
    local success = guard.disableConfirmed(conflicts, function(name)
        disabled[#disabled + 1] = name
        return true
    end, function()
        reloaded = true
    end)
    test.eq(success, true, "confirmed disable succeeds")
    test.eq(#disabled, 1, "only confirmed conflicts disabled")
    test.eq(disabled[1], "BiaoGe", "self addon never disabled")
    test.eq(reloaded, true, "reload occurs after confirmed disable")

    local failedReload = false
    local failed = guard.disableConfirmed(conflicts, function()
        return false
    end, function()
        failedReload = true
    end)
    test.eq(failed, false, "disable failure is reported")
    test.eq(failedReload, false, "reload is skipped after disable failure")

    local runtimeInventory = guard.buildInventory({
        getNumAddOns = function() return 3 end,
        getAddOnInfo = function(index)
            if index == 1 then return "BGLite", "BGNext" end
            if index == 2 then return { name = "BiaoGe", title = "BiaoGe" } end
            return "DisabledCopy", "BGLite"
        end,
        getMetadata = function(name, field)
            if name == "BGLite" and field == "X-Project" then return "BGNext" end
            if name == "DisabledCopy" and field == "X-Upstream" then return "BGLite 2.4.0" end
        end,
        getEnableState = function(name)
            return name ~= "DisabledCopy" and 2 or 0
        end,
        isLoaded = function(name)
            return name == "BGLite" or name == "BiaoGe"
        end,
    })
    test.eq(#runtimeInventory, 3, "runtime inventory normalized")
    test.eq(runtimeInventory[2].name, "BiaoGe", "table add-on info normalized")
    test.eq(runtimeInventory[3].enabled, false, "disabled state normalized")

    local loginHandler
    local promptCount = 0
    local promptedNames
    local installed = guard.installRuntime("BGLite", {
        inventory = runtimeInventory,
        defineDialog = function() end,
        onLogin = function(callback) loginHandler = callback end,
        showPopup = function(namesArg)
            promptCount = promptCount + 1
            promptedNames = namesArg
        end,
    })
    test.eq(installed, true, "runtime guard installed")
    loginHandler()
    loginHandler()
    test.eq(promptCount, 1, "conflict prompt appears once per session")
    test.eq(promptedNames, "BiaoGe", "runtime prompt lists exact conflict")
end
