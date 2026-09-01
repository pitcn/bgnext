BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Thin runtime hooks that prefill the existing auction price EditBoxes from the
-- locally saved price presets. This module never sends a message, never toggles
-- auto-bid, never bypasses an existing permission gate and never writes back to
-- the saved root after the player edits a box. Everything above the guard is a
-- pure decision helper; the frame touch lives in a single wrap of an existing
-- BG entry point below it.
local M = {}

-- Returns the single price only when every resolved price is an identical
-- number; any nil (unresolved) or differing value blocks the prefill.
function M.chooseLeaderPrefill(prices)
    local common
    for _, price in ipairs(prices or {}) do
        if type(price) ~= "number" then return nil end
        if common == nil then
            common = price
        elseif common ~= price then
            return nil
        end
    end
    return common
end

-- Decides whether the leader prefill may use `raidId` (the current table's
-- raid). `activeRaids` is the set of recognized raids; `activeRaidOverride` is
-- the raid a specific item resolves to from the approved catalog (nil when
-- unknown or ambiguous). Returns `raidId` only when it is recognized and the
-- item does not point to a different raid.
function M.resolveRaid(raidId, activeRaids, activeRaidOverride)
    if type(raidId) ~= "string" or raidId == "" then return nil end
    if type(activeRaids) ~= "table" or not activeRaids[raidId] then return nil end
    if type(activeRaidOverride) == "string" and activeRaidOverride ~= ""
        and activeRaidOverride ~= raidId then
        return nil
    end
    return raidId
end

local _, ns = ...

local function runtimeReady()
    return ns ~= nil
        and BG.Init ~= nil
        and BG.BGNext.AuctionPriceStore ~= nil
        and BG.BGNext.AuctionPriceCatalog ~= nil
end

if runtimeReady() then
    local Store = BG.BGNext.AuctionPriceStore
    local Catalog = BG.BGNext.AuctionPriceCatalog

    -- Canonical client families, strongest flag first (see AuctionPriceUI).
    local FAMILY_ORDER = {
        { flag = "IsRetail", family = "retail" },
        { flag = "IsMOP", family = "mop" },
        { flag = "IsCTM", family = "cata" },
        { flag = "IsTitan", family = "titan" },
        { flag = "IsWLK", family = "wrath" },
        { flag = "IsTBC", family = "tbc" },
        { flag = "IsVanilla", family = "vanilla" },
    }

    local function clientFamily()
        for _, entry in ipairs(FAMILY_ORDER) do
            if BG[entry.flag] then return entry.family end
        end
        return nil
    end

    local function contextProvider()
        return {
            root = BG.BGNext and BG.BGNext.DB,
            clientFamily = clientFamily(),
            realmId = BG.realmID,
            player = BG.playerName,
            raidId = BG.FB1,
        }
    end

    -- Minimal item -> raid ownership index built once, on first use, from the
    -- approved loot catalog. Empty boss lists keep the build cheap; only
    -- `byItem` is used for ownership lookup.
    local modelsByRaid
    local function buildIndex()
        local models = {}
        for _, raidId in ipairs(BG.FBtable or {}) do
            local model = Catalog.build({
                raidId = raidId,
                bosses = {},
                loot = (BG.Loot and BG.Loot[raidId]) or {},
            })
            if model then models[raidId] = model end
        end
        return models
    end

    -- Fills the existing starting-price box only when every item resolves to
    -- the current recognized raid and to one unanimous price. Any unknown or
    -- ambiguous item, differing price, or invalid data leaves the box untouched.
    local function prefillLeaderFrame(frame, context)
        if not frame then return end
        local items = frame.bt and frame.bt.items
        if type(items) ~= "table" or #items == 0 then return end
        if type(context) ~= "table" then return end
        local root = context.root
        local family = context.clientFamily
        local raidId = context.raidId
        if type(root) ~= "table" or type(family) ~= "string" or family == "" then return end
        if type(raidId) ~= "string" or raidId == "" then return end

        local activeRaids = {}
        for _, rid in ipairs(BG.FBtable or {}) do activeRaids[rid] = true end

        if not modelsByRaid then modelsByRaid = buildIndex() end

        local prices = {}
        for _, item in ipairs(items) do
            local itemId = item and item.id
            if type(itemId) ~= "number" then return end
            local itemRaid = Catalog.resolveRaidForItem(modelsByRaid, itemId)
            if itemRaid == nil then return end
            local raid = M.resolveRaid(raidId, activeRaids, itemRaid)
            if not raid then return end
            local price = Store.resolveLeaderPrice(root, family, raid, itemId)
            if price == nil then return end
            prices[#prices + 1] = price
        end

        local common = M.chooseLeaderPrefill(prices)
        if type(common) == "number" and frame.Edit2 then
            frame.Edit2:SetText(tostring(common))
        end
    end

    local installed = false
    BG.Init(function()
        if installed then return end
        if type(BG.StartAuction) ~= "function" then return end
        installed = true
        local original = BG.StartAuction
        BG.StartAuction = function(...)
            local previous = BG.StartAucitonFrame
            local result = original(...)
            -- Only prefill the frame the original call actually created; an
            -- early return (permission gate, no item, over max count) leaves
            -- BG.StartAucitonFrame unchanged and is ignored.
            if BG.StartAucitonFrame ~= previous then
                prefillLeaderFrame(BG.StartAucitonFrame, contextProvider())
            end
            return result
        end
    end)
end

BG.BGNext.AuctionPriceRuntime = M
return M
