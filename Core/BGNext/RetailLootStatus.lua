-- BGNext retail loot-data readiness.
--
-- Core/DB/DB_Loot_Retail.lua ships verified item data for the retail raids that
-- have actually been adapted. A raid that is registered in DB.lua and mapped by
-- DB_BossName.lua / DB_EncounterID.lua, but whose loot buckets are still empty,
-- must be reported as "pending" rather than as a working equipment library.
-- This module is the single source of truth for that distinction, so the
-- wishlist empty-loot prompt can explain how to add items by hand instead of
-- implying the whole plugin has no data.

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

-- Raid id -> data state.
--   available : loot buckets are populated for every enabled difficulty.
--   pending   : the raid and boss mapping exist but the item data has not been
--               adapted yet; the wishlist must explain how to add items by hand.
--   hidden    : not enabled / not mapped on this client; never shown.
local DECLARED = {
    VS = "available",
    VA = "pending",
}

function M.state(fb)
    if type(fb) ~= "string" then return "hidden" end
    return DECLARED[fb] or "hidden"
end

function M.isAvailable(fb)
    return M.state(fb) == "available"
end

function M.isPending(fb)
    return M.state(fb) == "pending"
end

-- Validation invariant: a raid is "populated" only when every difficulty in its
-- difficulty table has at least one non-empty primary boss bucket ("bossN").
-- An empty bucket, an absent difficulty, or exchange-only ("bossNother") data is
-- not real loot and never counts as supported.
function M.lootPopulated(raidLoot, difficultyTable)
    if type(raidLoot) ~= "table" or type(difficultyTable) ~= "table" then return false end
    if #difficultyTable == 0 then return false end
    for _, hard in ipairs(difficultyTable) do
        local bucket = type(hard) == "string" and raidLoot[hard] or nil
        if type(bucket) ~= "table" then return false end
        local populated = false
        for key, loot in pairs(bucket) do
            if type(key) == "string" and key:match("^boss%d+$") and type(loot) == "table" and #loot > 0 then
                populated = true
                break
            end
        end
        if not populated then return false end
    end
    return true
end

BG.BGNext.RetailLootStatus = M
return M
