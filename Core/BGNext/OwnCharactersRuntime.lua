-- BGNext own-character runtime bootstrap.
--
-- This is the single place that connects the live Blizzard current-character
-- APIs to the collector, the model and the renderer:
--
--     readers -> Collector.collect -> OwnCharacters.upsert
--              -> OwnCharacters.expireRaidStates -> OwnCharactersUI.Refresh
--
-- It also owns refresh, the per-family and global clears and the module-disable
-- switch. It never reads another player, never registers a chat/combat/inspect
-- event and never sends a message.

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

-- The module-disable switch lives under root.settings.roleOverviewEnabled. A
-- missing value means enabled (backward-compatible default).
function M.isEnabled(deps)
    deps = deps or M.deps()
    local settings = deps and deps.root and type(deps.root.settings) == "table" and deps.root.settings or nil
    if not settings or type(settings.roleOverviewEnabled) ~= "boolean" then return true end
    return settings.roleOverviewEnabled
end

function M.setEnabled(deps, value)
    deps = deps or M.deps()
    local root = deps and deps.root
    if type(root) ~= "table" then return end
    root.settings = type(root.settings) == "table" and root.settings or {}
    root.settings.roleOverviewEnabled = value and true or false
    local entry = deps.entry or BG.BGNext.RoleOverviewEntry
    if entry and type(entry.setAvailable) == "function" then
        entry.setAvailable(value and true or false)
    end
    if value then
        M.collectAndStore(deps)
    else
        M.setVisible(deps, false)
    end
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
    if deps.ui and type(deps.ui.Refresh) == "function" then deps.ui.Refresh() end
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

-- The one safe collection path. Returns the stored snapshot, or nil when the
-- module is disabled or the client cannot identify the logged-in character.
function M.collectAndStore(deps)
    deps = deps or M.deps()
    if not M.isEnabled(deps) then return nil end

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

    local env = adapters.readers(family, api, catalog.raidColumns)
    env.now = function() return stamp end

    local snapshot = collector.collect(env)
    if snapshot then
        model.upsert(root, family, snapshot)
    end
    model.expireRaidStates(root, stamp)

    if deps.ui and type(deps.ui.Refresh) == "function" then deps.ui.Refresh() end
    return snapshot
end

function M.requestRaidInfo(deps)
    deps = deps or M.deps()
    local api = deps.api or _G
    if type(api.RequestRaidInfo) == "function" then pcall(api.RequestRaidInfo) end
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
    if deps.ui and type(deps.ui.Refresh) == "function" then deps.ui.Refresh() end
end

function M.clearAll(deps)
    deps = deps or M.deps()
    if deps.model then deps.model.clearAll(deps.root) end
    if deps.ui and type(deps.ui.Refresh) == "function" then deps.ui.Refresh() end
end

-- Installs the reviewed event allowlist plus one immediate collection. Called
-- once from the main-frame setup at PLAYER_ENTERING_WORLD.
local installed = false
function M.install(deps)
    deps = deps or M.deps()
    if installed then return deps.frame end
    installed = true

    local frame = deps.frame or (type(CreateFrame) == "function" and CreateFrame("Frame") or nil)

    if deps.collector and frame then
        deps.collector.installEvents({
            frame = frame,
            family = deps.family,
            after = deps.after,
        }, function()
            M.collectAndStore(deps)
        end)
    end

    M.requestRaidInfo(deps)
    M.collectAndStore(deps)
    return frame
end

BG.BGNext.OwnCharactersRuntime = M
return M
