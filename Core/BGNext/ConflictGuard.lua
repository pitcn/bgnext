local currentAddonName = ...

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}
local knownNames = { BGLite = true, BiaoGe = true, BGNext = true }

function M.isKnownFamily(addon)
    if type(addon) ~= "table" then return false end
    if knownNames[addon.name] then return true end
    if addon.project == "BGNext" or addon.project == "BGLite" then return true end
    return type(addon.upstream) == "string" and addon.upstream:match("^BGLite[%s%-]?") ~= nil
end

function M.findConflicts(selfAddonName, addons)
    local result = {}
    for _, addon in ipairs(addons or {}) do
        if addon.name ~= selfAddonName
            and (addon.enabled == true or addon.loaded == true)
            and M.isKnownFamily(addon)
        then
            result[#result + 1] = addon
        end
    end
    table.sort(result, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return result
end

BG.BGNext.ConflictGuard = M
return M
