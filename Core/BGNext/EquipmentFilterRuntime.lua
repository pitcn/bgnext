-- BGNext equipment-filter runtime.
--
-- A pure, dependency-injected controller plus a thin live binding. The controller
-- coalesces specialization events and applies a freshly resolved specialization to
-- the model only when the stable built-in key changes. It reads only the current
-- character's class and specialization APIs, never inspects another player, never
-- sends messages, and never reads the legacy filter profile database.

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

-- Resolves the current specialization to a stable built-in key, or nil when the
-- family/class is unknown or the specialization is unrecorded. Purely functional.
function M.resolveBuiltIn(adapter, catalog, family, classToken, api)
    if not family or not classToken or not adapter then return nil end
    local resolved = adapter.resolve(family, api, classToken)
    if resolved and resolved.specKey then
        local profile = catalog and catalog.getDefault(family, classToken, resolved.specKey)
        if profile then return profile.builtInKey end
    end
    return nil
end

-- Constructs a controller. deps.adapter, deps.catalog, deps.model,
-- deps.getClassToken, deps.getState and deps.refresh are injected for testing;
-- the live binding wires the real modules below.
function M.new(deps)
    deps = deps or {}
    local c = { deps = deps, pending = false, lastBuiltInId = false }

    local function resolveNow()
        local family = deps.adapter and deps.adapter.detect(deps.globals or BG)
        local classToken = deps.getClassToken and deps.getClassToken()
        return M.resolveBuiltIn(deps.adapter, deps.catalog, family, classToken, deps.api)
    end

    function c:onEvent(event)
        if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN"
            or event == "PLAYER_TALENT_UPDATE" or event == "PLAYER_SPECIALIZATION_CHANGED" then
            self.pending = true
        end
    end

    function c:flush()
        if not self.pending then return end
        self.pending = false
        local builtInId = resolveNow()
        if builtInId ~= self.lastBuiltInId then
            local model = self.deps.model
            if model and model.applyResolvedSpecialization then
                model.applyResolvedSpecialization(self.deps.getState and self.deps.getState(), builtInId)
            end
            if self.deps.refresh then self.deps.refresh() end
            self.lastBuiltInId = builtInId
        end
    end

    return c
end

-- Live binding: initial setup plus event registration with one-second coalescing.
if BG.Init then
    BG.Init(function()
        local adapter = BG.BGNext.SpecializationAdapter
        local catalog = BG.BGNext.EquipmentFilterSpecializations
        local model = BG.BGNext.EquipmentFilter
        local profiles = BG.BGNext.EquipmentFilterProfiles
        if not (adapter and catalog and model and BG.BGNext.DB) then return end

        local function currentClassToken()
            local _, token = UnitClass("player")
            return token
        end

        local classToken = currentClassToken()
        if classToken then
            local family = adapter.detect()
            local defaults
            local builtInId
            if family then
                defaults = catalog.list(family, classToken)
                local fallback = catalog.getFallback(family, classToken)
                if fallback then defaults[#defaults + 1] = fallback end
                builtInId = M.resolveBuiltIn(adapter, catalog, family, classToken, _G)
                if not builtInId and fallback then builtInId = fallback.builtInKey end
            else
                defaults = profiles and profiles.getDefaults({ project = WOW_PROJECT_ID }, classToken) or {}
                builtInId = nil
            end
            model.ensureCharacter(BG.BGNext.DB, BG.realmID or GetRealmID(), BG.playerName, defaults,
                { builtInId = builtInId })

            local controller = M.new({
                adapter = adapter,
                catalog = catalog,
                model = model,
                getClassToken = currentClassToken,
                getState = function()
                    local byRealm = BG.BGNext.DB and BG.BGNext.DB.equipmentFilters
                        and BG.BGNext.DB.equipmentFilters[BG.realmID or GetRealmID()]
                    return byRealm and byRealm[BG.playerName]
                end,
                refresh = function()
                    if BG.UpdateAllFilter then BG.UpdateAllFilter() end
                end,
                api = _G,
            })

            local frame = CreateFrame("Frame")
            frame:RegisterEvent("PLAYER_ENTERING_WORLD")
            frame:RegisterEvent("PLAYER_TALENT_UPDATE")
            if BG.IsRetail or BG.IsMOP then
                frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
            end
            frame:SetScript("OnEvent", function(_, event) controller:onEvent(event) end)
            local accumulator = 0
            frame:SetScript("OnUpdate", function(_, elapsed)
                if not controller.pending then
                    accumulator = 0
                    return
                end
                accumulator = accumulator + elapsed
                if accumulator >= 1 then
                    accumulator = 0
                    controller:flush()
                end
            end)
        end
    end)
end

BG.BGNext.EquipmentFilterRuntime = M
return M
