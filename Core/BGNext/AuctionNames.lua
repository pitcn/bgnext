BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Canonical player-name handling for the auction features.
--
-- A single, unified source of truth for turning a possibly-bare or cross-realm
-- name into one canonical full name ("Name-Realm"). The state machine, the
-- message adapter's team validation and the runtime all use this same function,
-- so "Me" and "Me-Realm" resolve identically while "Me-OtherRealm" stays a
-- different player. This module is pure string math: no frames, no messages.
local M = {}

-- Canonical full name. A bare name gains the caller's realm; a name that already
-- carries a realm suffix is kept verbatim. An empty or missing name is nil.
function M.fullName(name, realm)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local base = name:match("^([^%-]+)%-(.+)$")
    if base then
        return name
    end
    if realm == nil or realm == "" then
        return name
    end
    return name .. "-" .. realm
end

-- True when two (possibly bare or cross-realm) names denote the same player.
function M.isSamePlayer(a, b, realm)
    local fa, fb = M.fullName(a, realm), M.fullName(b, realm)
    if fa == nil or fb == nil then
        return false
    end
    return fa == fb
end

BG.BGNext.AuctionNames = M

return M
