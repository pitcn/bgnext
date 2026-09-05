BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

local function catalog()
    return BG.BGNext.FeatureCatalog
end

local function ensureSettings(root)
    if type(root) ~= "table" then return nil end
    root.settings = type(root.settings) == "table" and root.settings or {}
    root.settings.features = type(root.settings.features) == "table" and root.settings.features or {}
    return root.settings
end

local function explicitValue(root, id)
    local settings = type(root) == "table" and root.settings or nil
    local features = type(settings) == "table" and settings.features or nil
    if type(features) == "table" and type(features[id]) == "boolean" then
        return features[id]
    end
    if id == "role_overview" and type(settings) == "table" and type(settings.roleOverviewEnabled) == "boolean" then
        return settings.roleOverviewEnabled
    end
    return nil
end

function M.savedValue(root, id)
    return explicitValue(root, id)
end

local function enabled(root, id, family, visiting)
    local featureCatalog = catalog()
    local entry = featureCatalog and featureCatalog.get(id) or nil
    if not entry or not featureCatalog.available(entry, family) then return false end
    if entry.policy == "required" then return true end
    local value = explicitValue(root, id)
    if value == false then return false end
    if value == nil and entry.defaultEnabled == false then return false end
    visiting = visiting or {}
    if visiting[id] then return false end
    visiting[id] = true
    for _, dependency in ipairs(entry.depends or {}) do
        if not enabled(root, dependency, family, visiting) then
            visiting[id] = nil
            return false
        end
    end
    visiting[id] = nil
    return true
end

function M.isEnabled(root, id, family)
    return enabled(root, id, family, {})
end

function M.currentFamily(globals)
    globals = globals or BG
    local adapters = BG.BGNext and BG.BGNext.OwnCharactersAdapters
    if adapters and type(adapters.detect) == "function" then
        local family = adapters.detect(globals)
        if family then return family end
    end
    if globals.IsRetail then return "retail" end
    if globals.IsMOP then return "mop" end
    if globals.IsCTM then return "cata" end
    if globals.IsTitan then return "titan" end
    if globals.IsWLK then return "wrath" end
    if globals.IsTBC then return "tbc" end
    if globals.IsVanilla then return "vanilla" end
end

function M.isCurrentEnabled(id, globals, root)
    local family = M.currentFamily(globals)
    if not family then return false end
    return M.isEnabled(root or (BG.BGNext and BG.BGNext.DB), id, family)
end

function M.setEnabled(root, id, value)
    local featureCatalog = catalog()
    local entry = featureCatalog and featureCatalog.get(id) or nil
    if not entry then return false, "unknown" end
    if entry.policy == "required" then return false, "required" end
    if type(value) ~= "boolean" then return false, "invalid" end
    local settings = ensureSettings(root)
    if not settings then return false, "invalid-root" end
    settings.features[id] = value
    if id == "role_overview" then settings.roleOverviewEnabled = value end
    return true
end

function M.applyMode(root, mode, family)
    if mode ~= "basic" and mode ~= "full" then return false, "unknown-mode" end
    local featureCatalog = catalog()
    if not featureCatalog then return false, "missing-catalog" end
    local settings = ensureSettings(root)
    if not settings then return false, "invalid-root" end
    for _, entry in ipairs(featureCatalog.all()) do
        if entry.policy == "optional" and featureCatalog.available(entry, family) then
            local value = mode == "full" or entry.basic == true
            settings.features[entry.id] = value
            if entry.id == "role_overview" then settings.roleOverviewEnabled = value end
        end
    end
    return true
end

function M.mode(root, family)
    local featureCatalog = catalog()
    if not featureCatalog then return "custom" end
    local full, basic = true, true
    for _, entry in ipairs(featureCatalog.all()) do
        if entry.policy == "optional" and featureCatalog.available(entry, family) then
            local value = M.isEnabled(root, entry.id, family)
            if value ~= true then full = false end
            if value ~= (entry.basic == true) then basic = false end
        end
    end
    if full then return "full" end
    if basic then return "basic" end
    return "custom"
end

function M.sanitize(root)
    local settings = ensureSettings(root)
    local featureCatalog = catalog()
    if not settings or not featureCatalog then return root end
    local clean = {}
    for _, entry in ipairs(featureCatalog.all()) do
        if entry.policy == "optional" and type(settings.features[entry.id]) == "boolean" then
            clean[entry.id] = settings.features[entry.id]
        end
    end
    settings.features = clean
    if type(settings.roleOverviewEnabled) ~= "boolean" then settings.roleOverviewEnabled = nil end
    return root
end

BG.BGNext.FeatureSettings = M

if BG.Init then
    BG.Init(function()
        local root = BG.BGNext.DB
        if not root and type(BiaoGe) == "table" then root = BiaoGe.BGNext end
        if root then M.sanitize(root) end
    end)
end

return M
