return function(test)
    BG = { BGNext = {} }
    local Runtime = dofile("Core/BGNext/EquipmentFilterRuntime.lua")
    local adapter = dofile("Core/BGNext/SpecializationAdapter.lua")
    local model = dofile("Core/BGNext/EquipmentFilter.lua")

    local function build(currentSpecId)
        local resolveCount = 0
        local refreshCount = 0
        local applied = {}
        local state = {
            selectionMode = "follow-spec",
            selectedId = "retail:MAGE:spec:63",
            order = { "retail:MAGE:spec:63", "retail:MAGE:spec:64" },
            profiles = {
                ["retail:MAGE:spec:63"] = { id = "retail:MAGE:spec:63" },
                ["retail:MAGE:spec:64"] = { id = "retail:MAGE:spec:64" },
            },
        }
        local catalog = {
            getDefault = function(family, classToken, specKey)
                if specKey == "spec:63" then return { builtInKey = "retail:MAGE:spec:63" } end
                if specKey == "spec:64" then return { builtInKey = "retail:MAGE:spec:64" } end
                return nil
            end,
        }
        local api = {
            GetSpecialization = function() return 1 end,
            GetSpecializationInfo = function() return currentSpecId() end,
        }
        local wrappedAdapter = {
            detect = adapter.detect,
            resolve = function(family, a, classToken)
                resolveCount = resolveCount + 1
                return adapter.resolve(family, a, classToken)
            end,
        }
        local deps = {
            adapter = wrappedAdapter,
            catalog = catalog,
            model = {
                applyResolvedSpecialization = function(st, builtInId)
                    applied[#applied + 1] = builtInId
                    return model.applyResolvedSpecialization(st, builtInId)
                end,
            },
            getClassToken = function() return "MAGE" end,
            getState = function() return state end,
            refresh = function() refreshCount = refreshCount + 1 end,
            globals = { IsRetail = true },
            api = api,
        }
        return Runtime.new(deps), state, function() return resolveCount, refreshCount, applied end
    end

    local current = 63
    local controller, state, counts = build(function() return current end)

    -- Initial login resolves once and refreshes once.
    controller:onEvent("PLAYER_ENTERING_WORLD")
    controller:flush()
    local rc, fc = counts()
    test.eq(rc, 1, "initial login resolves once")
    test.eq(fc, 1, "initial login refreshes once")
    test.eq(state.selectedId, "retail:MAGE:spec:63", "initial resolution selects the resolved built-in")

    -- Duplicate events coalesce and an unchanged specialization does not refresh.
    controller:onEvent("PLAYER_TALENT_UPDATE")
    controller:onEvent("PLAYER_SPECIALIZATION_CHANGED")
    controller:flush()
    rc, fc = counts()
    test.eq(rc, 2, "duplicate events coalesce into one resolve")
    test.eq(fc, 1, "unchanged specialization does not refresh")

    -- A changed specialization resolves and refreshes once.
    current = 64
    controller:onEvent("PLAYER_TALENT_UPDATE")
    controller:flush()
    rc, fc = counts()
    test.eq(rc, 3, "changed specialization resolves")
    test.eq(fc, 2, "changed specialization refreshes once")
    test.eq(state.selectedId, "retail:MAGE:spec:64", "follow mode switches to the new built-in")

    -- An unrecorded specialization preserves the active selection.
    current = 999999
    controller:onEvent("PLAYER_TALENT_UPDATE")
    controller:flush()
    test.eq(state.selectedId, "retail:MAGE:spec:64", "unknown specialization preserves selection")

    -- A manual selection is never switched by resolution.
    state.selectionMode = "manual"
    state.selectedId = "retail:MAGE:spec:64"
    current = 63
    controller:onEvent("PLAYER_TALENT_UPDATE")
    controller:flush()
    test.eq(state.selectedId, "retail:MAGE:spec:64", "manual selection is never switched by resolution")

    -- The resolver helper is deterministic and never guesses an unrecorded spec.
    test.eq(Runtime.resolveBuiltIn(adapter, {
        getDefault = function() return { builtInKey = "retail:MAGE:spec:63" } end,
    }, "retail", "MAGE", {
        GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function() return 63 end,
    }), "retail:MAGE:spec:63", "resolveBuiltIn maps spec to built-in")
    test.eq(Runtime.resolveBuiltIn(adapter, {
        getDefault = function() return nil end,
    }, "retail", "MAGE", {
        GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function() return 63 end,
    }), nil, "resolveBuiltIn returns nil for unrecorded spec")
    test.eq(Runtime.resolveBuiltIn(adapter, {}, nil, "MAGE", {}), nil, "resolveBuiltIn is nil for unknown family")

    -- Source safety: current-character-only, no communication, no legacy DB.
    local file = assert(io.open("Core/BGNext/EquipmentFilterRuntime.lua", "rb"))
    local source = file:read("*a")
    file:close()
    test.eq(source:find("NotifyInspect", 1, true), nil, "runtime never inspects another player")
    test.eq(source:find("SendChatMessage", 1, true), nil, "runtime sends no chat")
    test.eq(source:find("SendAddonMessage", 1, true), nil, "runtime sends no addon messages")
    test.eq(source:find("BiaoGe.FilterClassItemDB", 1, true), nil, "runtime never reads the legacy filter DB")
    test.eq(source:find("UnitClass", 1, true) ~= nil, true, "runtime reads only the current character class")
end
