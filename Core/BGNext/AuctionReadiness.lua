BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Pure, memory-only helpers for the current raid's auction readiness summary.
-- The runtime owns all WoW API access and protocol messages; this module only
-- classifies current roster entries and bounds locally initiated checks.
local M = {}

M.READY = "ready"
M.ADDON_ONLY = "addon-only"
M.NO_RESPONSE = "no-response"
M.OFFLINE = "offline"
M.REQUEST_COOLDOWN = 15

function M.status(member, addonVersions, auctionVersions)
    if type(member) ~= "table" or type(member.name) ~= "string" or member.name == "" then
        return M.NO_RESPONSE
    end
    if member.online == false then return M.OFFLINE end
    if type(auctionVersions) == "table" and auctionVersions[member.name] then
        return M.READY
    end
    if type(addonVersions) == "table" and addonVersions[member.name] then
        return M.ADDON_ONLY
    end
    return M.NO_RESPONSE
end

function M.summarize(roster, addonVersions, auctionVersions)
    local ready = 0
    local total = 0
    for _, member in ipairs(roster or {}) do
        if type(member) == "table" and type(member.name) == "string" and member.name ~= "" then
            total = total + 1
            if M.status(member, addonVersions, auctionVersions) == M.READY then
                ready = ready + 1
            end
        end
    end
    return ready, total
end

function M.prune(addonVersions, auctionVersions, roster, compatibleAddonVersions)
    local current = {}
    for _, member in ipairs(roster or {}) do
        if type(member) == "table" and type(member.name) == "string" and member.name ~= "" then
            current[member.name] = true
        end
    end
    for name in pairs(addonVersions or {}) do
        if not current[name] then addonVersions[name] = nil end
    end
    for name in pairs(auctionVersions or {}) do
        if not current[name] then auctionVersions[name] = nil end
    end
    for name in pairs(compatibleAddonVersions or {}) do
        if not current[name] then compatibleAddonVersions[name] = nil end
    end
end

function M.requestDelay(state, now, isController)
    if type(state) ~= "table" or type(now) ~= "number" or not isController then return nil end
    local last = state.lastRequestAt
    if type(last) == "number" then
        if now < last then return nil end
        local remaining = M.REQUEST_COOLDOWN - (now - last)
        if remaining > 0 then return remaining end
    end
    return 0
end

function M.takeRequest(state, now, isController)
    if M.requestDelay(state, now, isController) ~= 0 then return false end
    state.lastRequestAt = now
    return true
end

BG.BGNext.AuctionReadiness = M
return M
