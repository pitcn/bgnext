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

-- Decides which raid id the leader start may use for one item, honoring the
-- entry's explicit provenance before falling back to the catalog. `options` is
-- the caller-provided entry context (`{ source, raidId }`); `currentRaid` is the
-- active table raid; `activeRaids` is the set of recognized raids; `itemId` is
-- the item; and `resolveItemRaid(itemId)` maps the item to its catalog-unique
-- raid (nil when unknown or ambiguous). Returns the raid id, or nil plus a
-- reason code ("scope" when a proven source is no longer active, "no-raid" when
-- the source cannot be established).
function M.resolveEntryRaid(options, currentRaid, activeRaids, itemId, resolveItemRaid)
    local source = type(options) == "table" and options.source or nil
    local raidId = type(options) == "table" and options.raidId or nil
    if type(raidId) == "string" and raidId ~= "" then
        if type(activeRaids) == "table" and activeRaids[raidId] then
            return raidId
        end
        return nil, "scope"
    end
    if source == "loot" or source == "auctionlog" then
        if type(currentRaid) == "string" and currentRaid ~= ""
            and type(activeRaids) == "table" and activeRaids[currentRaid] then
            return currentRaid
        end
        return nil, "scope"
    end
    local itemRaid = type(resolveItemRaid) == "function" and resolveItemRaid(itemId) or nil
    if itemRaid == nil then return nil, "no-raid" end
    local raid = M.resolveRaid(currentRaid, activeRaids, itemRaid)
    if not raid then return nil, "no-raid" end
    return raid
end

-- Returns the saved personal price only when it clears the current auction
-- floor; a missing price, or one below the floor (an invalid bid), leaves the
-- bid box untouched.
function M.choosePersonalPrefill(savedMoney, floor)
    if type(savedMoney) ~= "number" then return nil end
    if type(floor) == "number" and savedMoney < floor then return nil end
    return savedMoney
end

-- Fills the bidder's existing money EditBox with the resolved personal price.
-- Touches only `myMoneyEdit:SetText`; it never clicks a send button, toggles
-- auto-bid, starts a timer, or writes the value back to storage.
function M.prefillPersonalText(frame, savedMoney, floor)
    if type(frame) ~= "table" then return false end
    if type(frame.myMoneyEdit) ~= "table" then return false end
    local value = M.choosePersonalPrefill(savedMoney, floor)
    if value == nil then return false end
    frame.myMoneyEdit:SetText(tostring(value))
    return true
end

-- Applies a resolved leader price to the existing auction editor. Direct start
-- deliberately reuses that frame's original OnClick handler, so every existing
-- permission, validation, sound, message and close path remains authoritative.
function M.applyLeaderPrefill(frame, money, directStart)
    if type(frame) ~= "table" or type(money) ~= "number" then return false end
    if type(frame.Edit2) ~= "table" or type(frame.Edit2.SetText) ~= "function" then return false end
    local start
    if directStart then
        if type(frame.bt) ~= "table" or type(frame.bt.GetScript) ~= "function" then return false end
        start = frame.bt:GetScript("OnClick")
        if type(start) ~= "function" then return false end
        -- Bind the approved amount so the reused OnClick sends exactly this
        -- price, never a stale global default left in BiaoGe.Auction.money.
        frame.bt.money = money
    end
    frame.Edit2:SetText(tostring(money))
    if start then start(frame.bt) end
    return true
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
    local L = ns and ns.L or setmetatable({}, { __index = function(_, key) return tostring(key) end })

    -- Short local reasons shown only when a direct start is refused; the dialog
    -- is always left open for the leader to confirm manually.
    local DIRECT_REASON_TEXT = {
        permission = L["无权限发起拍卖"],
        combat = L["战斗状态下无法发起拍卖"],
        ["auction-busy"] = L["已有拍卖进行中"],
        ["no-price"] = L["请手动输入起拍价"],
        scope = L["团队或表格已变更"],
        ["no-raid"] = L["无法确定该装备所属副本，已保留确认窗口。"],
    }

    local function showReason(reason)
        if type(reason) ~= "string" then return end
        local text = DIRECT_REASON_TEXT[reason]
        if text and type(BG.SendSystemMessage) == "function" then
            BG.SendSystemMessage(text)
        end
    end

    -- Mirrors the queue's authoritative pre-send gate so a direct start is
    -- re-checked for permission, combat and an in-progress auction at the exact
    -- send moment, inside the reused OnClick closure.
    local function directGate()
        local isController = BG.IsML == true
            or (type(BG.ImMLorLeader) == "function" and BG.ImMLorLeader())
        if not isController then return "permission" end
        if InCombatLockdown and InCombatLockdown() then return "combat" end
        if type(BGA) == "table" and type(BGA.Frames) == "table" then
            for _, f in pairs(BGA.Frames) do
                if type(f) == "table" and not f.IsEnd then return "auction-busy" end
            end
        end
        return nil
    end

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

    -- Fills the existing starting-price box only when every item resolves to a
    -- proven recognized raid and to one unanimous price. `options` carries the
    -- entry's explicit source/raid contract; a proven source wins over the
    -- catalog so a cross-raid-duplicate item still resolves. On an Alt+right
    -- direct start the resolved price is written and the existing OnClick is
    -- reused under the authoritative pre-send gate; any unresolved item keeps
    -- the window open with a short local reason instead of guessing.
    local function prefillLeaderFrame(frame, context, directStart, options)
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

        local function resolveItemRaid(itemId)
            return Catalog.resolveRaidForItem(modelsByRaid, itemId)
        end

        local prices = {}
        local reason
        local complete = true
        for _, item in ipairs(items) do
            local itemId = item and item.id
            if type(itemId) ~= "number" then
                complete = false
                break
            end
            local raid, blocked = M.resolveEntryRaid(options, raidId, activeRaids, itemId, resolveItemRaid)
            if not raid then
                reason = blocked
                complete = false
                break
            end
            local price = Store.resolveLeaderPrice(root, family, raid, itemId)
            if price == nil then
                reason = "no-price"
                complete = false
                break
            end
            prices[#prices + 1] = price
        end

        if not complete then
            if directStart then showReason(reason) end
            return
        end

        local common = M.chooseLeaderPrefill(prices)
        if common == nil then
            if directStart then showReason(reason or "no-price") end
            return
        end

        if directStart then
            if type(frame.bt) == "table" then
                frame.bt.onPreSend = function()
                    local blocked = directGate()
                    if blocked then
                        showReason(blocked)
                        return false
                    end
                    return true
                end
            end
            M.applyLeaderPrefill(frame, common, true)
        else
            M.applyLeaderPrefill(frame, common, false)
        end
    end

    -- Fills the bidder's existing money EditBox from the saved personal price
    -- for the current character, realm, and raid. A missing price, or a price
    -- below the current auction floor, leaves the box untouched. Only
    -- `myMoneyEdit:SetText` is called; the value is never written back.
    local function prefillPersonalFrame(frame, context)
        if not frame then return end
        local itemId = frame.itemID
        if type(itemId) ~= "number" then return end
        if type(context) ~= "table" then return end
        local root = context.root
        local family = context.clientFamily
        local realm = context.realmId
        local player = context.player
        local raidId = context.raidId
        if type(root) ~= "table" then return end
        if type(family) ~= "string" or family == "" then return end
        if not Store.isValidRealmId(realm) then return end
        if type(player) ~= "string" or player == "" then return end
        if type(raidId) ~= "string" or raidId == "" then return end
        local savedMoney = Store.getPersonalPrice(root, family, realm, player, raidId, itemId)
        M.prefillPersonalText(frame, savedMoney, frame.money)
    end

    local installed = false
    BG.Init(function()
        if installed then return end
        if type(BG.StartAuction) ~= "function" then return end
        installed = true
        local original = BG.StartAuction
        BG.StartAuction = function(...)
            local previous = BG.StartAucitonFrame
            local directStart = select(5, ...) == true
            local options = select(8, ...)
            local result = original(...)
            -- Only prefill the frame the original call actually created; an
            -- early return (permission gate, no item, over max count) leaves
            -- BG.StartAucitonFrame unchanged and is ignored.
            if BG.StartAucitonFrame ~= previous then
                prefillLeaderFrame(BG.StartAucitonFrame, contextProvider(), directStart, options)
            end
            return result
        end
    end)

    local personalInstalled = false
    BG.Init(function()
        if personalInstalled then return end
        if type(BG.HookCreateAuction) ~= "function" then return end
        personalInstalled = true
        local previous = BG.HookCreateAuction
        BG.HookCreateAuction = function(frame)
            if previous then previous(frame) end
            prefillPersonalFrame(frame, contextProvider())
        end
    end)
end

BG.BGNext.AuctionPriceRuntime = M
return M
