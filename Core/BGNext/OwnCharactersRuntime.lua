-- BGNext own-character runtime bootstrap.
--
-- This is the single place that connects the live Blizzard current-character
-- APIs to the collector, the model and the renderer:
--
--     readers -> Collector.collect -> OwnCharacters.upsert
--              -> OwnCharacters.expireRaidStates -> OwnCharactersUI.Refresh
--
-- It also owns refresh, the per-family and global clears and the module-disable
-- switch. It never reads another player, combat or inspect data and never sends
-- a message. On MoP it may reduce one verified current-player Sunsong Ranch
-- self-loot line to a daily completed flag; no raw loot text is retained.

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

local function defaultNow()
    if type(time) == "function" then return time() end
    return 0
end

-- Builds the live dependency bundle once for the current client. Kept as a
-- function so the plain-Lua test suite can build its own bundle and never
-- touches frames or SavedVariables.
local liveDeps = nil
function M.buildDeps(globals)
    local adapters = BG.BGNext.OwnCharactersAdapters
    local catalog = BG.BGNext.OwnCharactersCatalog
    local family = adapters and adapters.detect(globals or BG) or nil
    return {
        globals = globals or BG,
        family = family,
        catalog = family and catalog and catalog.forFamily(family) or nil,
        root = BG.BGNext.DB,
        api = _G,
        adapters = adapters,
        collector = BG.BGNext.OwnCharactersCollector,
        model = BG.BGNext.OwnCharacters,
        ui = BG.BGNext.OwnCharactersUI,
        entry = BG.BGNext.RoleOverviewEntry,
        after = (type(C_Timer) == "table" and type(C_Timer.After) == "function" and C_Timer.After) or nil,
        newTicker = (type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" and C_Timer.NewTicker) or nil,
    }
end

function M.deps()
    if not liveDeps then liveDeps = M.buildDeps() end
    return liveDeps
end

-- Availability is separate from the user's enable switch. A client is
-- available only when it has an explicit testable catalog; excluded clients
-- (notably Season of Discovery) and empty unverified families never expose an
-- entry or collect a placeholder snapshot.
function M.isAvailable(deps)
    deps = deps or M.deps()
    if type(deps) ~= "table" or type(deps.family) ~= "string" then return false end
    local catalog = deps.catalog
    if type(catalog) ~= "table" then return false end
    local status = catalog.status
    if status ~= "tested-in-game" and status ~= "pending-in-game-verification" then return false end
    return #(catalog.raidColumns or {}) > 0 or #(catalog.resourceColumns or {}) > 0
end

-- The module-disable switch lives under root.settings.roleOverviewEnabled. A
-- missing value means enabled (backward-compatible default).
function M.isEnabled(deps)
    deps = deps or M.deps()
    local featureSettings = BG.BGNext.FeatureSettings
    if featureSettings and type(featureSettings.isCurrentEnabled) == "function" then
        return featureSettings.isCurrentEnabled("role_overview", deps and deps.globals or BG, deps and deps.root)
    end
    local settings = deps and deps.root and type(deps.root.settings) == "table" and deps.root.settings or nil
    if not settings or type(settings.roleOverviewEnabled) ~= "boolean" then return true end
    return settings.roleOverviewEnabled
end

local function refreshUIIfVisible(deps)
    local ui = deps and deps.ui
    if not ui or type(ui.Refresh) ~= "function" then return false end
    if type(ui.IsVisible) == "function" then
        local ok, visible = pcall(ui.IsVisible)
        if not ok or visible ~= true then return false end
    end
    ui.Refresh()
    return true
end

function M.setEnabled(deps, value)
    deps = deps or M.deps()
    local root = deps and deps.root
    if type(root) ~= "table" then return end
    root.settings = type(root.settings) == "table" and root.settings or {}
    local featureSettings = BG.BGNext.FeatureSettings
    if featureSettings and type(featureSettings.setEnabled) == "function" then
        featureSettings.setEnabled(root, "role_overview", value and true or false)
    else
        root.settings.roleOverviewEnabled = value and true or false
    end
    local entry = deps.entry or BG.BGNext.RoleOverviewEntry
    if entry and type(entry.setAvailable) == "function" then
        entry.setAvailable(value == true and M.isAvailable(deps))
    end
    if value then
        M.collectAndStore(deps)
    else
        -- A transient harvest observation belongs only to the currently
        -- enabled session. Do not let it survive a disable/re-enable cycle
        -- and become a false completion after the daily reset.
        deps._farmHarvestObservedAt = nil
        M.setVisible(deps, false)
    end
end

function M.refreshFeatureState(deps)
    deps = deps or M.deps()
    local enabled = M.isEnabled(deps) and M.isAvailable(deps)
    local entry = deps and (deps.entry or BG.BGNext.RoleOverviewEntry)
    if entry and type(entry.setAvailable) == "function" then entry.setAvailable(enabled) end
    if not enabled then M.setVisible(deps, false) end
    return enabled
end

local function cancelVisibleTicker(deps)
    local ticker = deps and deps._visibleTicker
    if ticker and type(ticker.Cancel) == "function" then pcall(ticker.Cancel, ticker) end
    if deps then deps._visibleTicker = nil end
end

function M.refreshVisible(deps)
    deps = deps or M.deps()
    if not M.isEnabled(deps) then return end
    local now = (type(deps.now) == "function" and deps.now) or defaultNow
    if deps.model and deps.root then deps.model.expireRaidStates(deps.root, now()) end
    refreshUIIfVisible(deps)
end

function M.setVisible(deps, visible)
    deps = deps or M.deps()
    cancelVisibleTicker(deps)
    if visible ~= true or not M.isEnabled(deps) then return end
    M.refreshVisible(deps)
    local newTicker = deps.newTicker
    if type(newTicker) == "function" then
        deps._visibleTicker = newTicker(60, function() M.refreshVisible(deps) end)
    end
end

function M.setColumnVisible(deps, section, columnId, visible)
    deps = deps or M.deps()
    local settings = deps.settings or BG.BGNext.RoleOverviewSettings
    if not settings or type(settings.setVisible) ~= "function" then return false end
    if type(deps.root) ~= "table" or type(deps.family) ~= "string" then return false end
    if section ~= "raid" and section ~= "resource" then return false end
    if type(columnId) ~= "string" or columnId == "" then return false end
    settings.setVisible(deps.root, deps.family, section, columnId, visible == true)
    refreshUIIfVisible(deps)
    return true
end

-- The one safe collection path. Returns the stored snapshot, or nil when the
-- module is disabled or the client cannot identify the logged-in character.
function M.collectAndStore(deps, sections)
    deps = deps or M.deps()
    if not M.isEnabled(deps) or not M.isAvailable(deps) then return nil end

    local adapters = deps.adapters
    local collector = deps.collector
    local model = deps.model
    local root = deps.root
    if not (adapters and collector and model and root) then return nil end

    local family = deps.family or (adapters.detect and adapters.detect(deps.globals))
    local catalog = deps.catalog
    if not family or not catalog then return nil end

    local api = deps.api or _G
    local now = (type(deps.now) == "function" and deps.now) or defaultNow
    local stamp = now()

    local env = adapters.readers(family, api, catalog.raidColumns, catalog.resourceColumns)
    env.now = function() return stamp end

    -- On retail only, prefer the init-time identity over a live re-read. There
    -- the live UnitName/GetRealmID calls can be secret-protected even though BG
    -- already holds the validated current-character identity from load time.
    -- Every other family keeps the original live readers; the identity is
    -- re-read on every collect so a later event can succeed (no lockout).
    if family == "retail" and type(adapters.validatedIdentity) == "function" then
        local identity = adapters.validatedIdentity(deps.globals)
        if identity then
            env.playerName = function() return identity.playerName end
            env.realmId = function() return identity.realmId end
            if identity.realmName ~= nil then
                env.realmName = function() return identity.realmName end
            end
        end
    end

    local scoped = type(sections) == "table" and sections.full ~= true
    local snapshot = collector.collect(env, sections)
    local existing = snapshot and type(model.get) == "function"
        and model.get(root, family, snapshot.realmId, snapshot.player) or nil
    if snapshot and scoped then
        if not existing then
            snapshot = collector.collect(env)
            scoped = false
        end
    end

    local appliedFarmObservation = false
    if snapshot and family == "mop" and type(snapshot.activityStates) == "table" then
        local pendingAt = deps._farmHarvestObservedAt
        local getDailyReset = api and api.GetQuestResetTime
        local resetSeconds = type(getDailyReset) == "function"
            and adapters.safeCall(getDailyReset) or nil
        if type(pendingAt) == "number" and type(resetSeconds) == "number" and resetSeconds >= 0 then
            snapshot.activityStates.farmHarvest = {
                status = "completed",
                observedAt = pendingAt,
                resetsAt = stamp + resetSeconds,
            }
            appliedFarmObservation = true
        else
            local previous = type(existing) == "table" and type(existing.activityStates) == "table"
                and existing.activityStates.farmHarvest or nil
            if type(previous) == "table" and previous.status == "completed"
                and type(previous.resetsAt) == "number" and stamp < previous.resetsAt then
                snapshot.activityStates.farmHarvest = previous
            end
        end
    end
    if snapshot then
        if scoped and type(model.mergeSections) == "function" then
            model.mergeSections(root, family, snapshot, sections)
        else
            model.upsert(root, family, snapshot)
        end
        if appliedFarmObservation then deps._farmHarvestObservedAt = nil end
    end
    model.expireRaidStates(root, stamp)

    refreshUIIfVisible(deps)
    return snapshot
end

function M.requestRaidInfo(deps)
    deps = deps or M.deps()
    local api = deps.api or _G
    if type(api.RequestRaidInfo) == "function" then pcall(api.RequestRaidInfo) end
end

-- Converts one allowlisted live event into a scoped own-character refresh.
-- CHAT_MSG_LOOT is accepted only when the adapter proves that the localized
-- line belongs to the current player and contains a Sunsong Ranch harvest.
-- The raw message is discarded here and never reaches the snapshot model.
function M.observeEvent(deps, event, ...)
    deps = deps or M.deps()
    if not M.isEnabled(deps) or event ~= "CHAT_MSG_LOOT" or deps.family ~= "mop" then return nil end
    local settings = deps.settings or BG.BGNext.RoleOverviewSettings
    if settings and type(settings.isVisible) == "function"
        and settings.isVisible(deps.root, deps.family, "resource", "farmHarvest", deps.catalog) ~= true then
        return nil
    end
    local adapters = deps.adapters
    local isHarvest = adapters and adapters.isFarmHarvestLoot
    if type(isHarvest) ~= "function" then return nil end
    local ok, accepted = pcall(isHarvest, deps.api or _G, deps.family, ...)
    if not ok or accepted ~= true then return nil end
    local now = (type(deps.now) == "function" and deps.now) or defaultNow
    local observedAt = now()
    if type(observedAt) ~= "number" then return nil end
    deps._farmHarvestObservedAt = observedAt
    return { activities = true }
end

-- User refresh asks Blizzard for fresh saved-instance data once, then reads the
-- current cached snapshot. The later UPDATE_INSTANCE_INFO event performs the
-- second read without issuing another request.
function M.refresh(deps)
    deps = deps or M.deps()
    M.requestRaidInfo(deps)
    return M.collectAndStore(deps)
end

function M.clearFamily(deps, family)
    deps = deps or M.deps()
    family = family or deps.family
    if deps.model and family then
        deps.model.clearFamily(deps.root, family)
    end
    refreshUIIfVisible(deps)
end

function M.clearAll(deps)
    deps = deps or M.deps()
    if deps.model then deps.model.clearAll(deps.root) end
    refreshUIIfVisible(deps)
end

-- Installs the reviewed event allowlist plus one immediate collection. Called
-- once from the main-frame setup at PLAYER_ENTERING_WORLD.
local installed = false
function M.install(deps)
    deps = deps or M.deps()
    if not M.isAvailable(deps) then
        local entry = deps and (deps.entry or BG.BGNext.RoleOverviewEntry)
        if entry and type(entry.setAvailable) == "function" then entry.setAvailable(false) end
        return nil
    end
    if installed then return deps.frame end
    installed = true

    local frame = deps.frame or (type(CreateFrame) == "function" and CreateFrame("Frame") or nil)

    if deps.collector and frame then
        deps.collector.installEvents({
            frame = frame,
            family = deps.family,
            after = deps.after,
            observeEvent = function(event, ...)
                return M.observeEvent(deps, event, ...)
            end,
        }, function(sections)
            M.collectAndStore(deps, sections)
        end)
    end

    M.requestRaidInfo(deps)
    M.collectAndStore(deps)
    return frame
end

BG.BGNext.OwnCharactersRuntime = M
return M
