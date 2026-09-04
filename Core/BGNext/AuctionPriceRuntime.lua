BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Thin runtime hooks that prefill the existing auction price EditBoxes from the
-- locally saved price presets. This module never sends a message, never toggles
-- auto-bid, never bypasses an existing permission gate and never writes back to
-- the saved root after the player edits a box. Everything above the guard is a
-- pure decision helper; the frame touch lives in a single wrap of an existing
-- BG entry point below it.
local M = {}

-- WoW UI objects expose methods and writable addon fields but are represented as
-- userdata on some client builds. Treat both Lua tables and native UI userdata
-- as frame-like objects; callers still validate the exact methods they use.
local function isFrameObject(value)
    local kind = type(value)
    return kind == "table" or kind == "userdata"
end

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
    if not isFrameObject(frame) then return false end
    if not isFrameObject(frame.myMoneyEdit) or type(frame.myMoneyEdit.SetText) ~= "function" then return false end
    local value = M.choosePersonalPrefill(savedMoney, floor)
    if value == nil then return false end
    frame.myMoneyEdit:SetText(tostring(value))
    return true
end

-- Applies a resolved leader price to the existing auction editor. When
-- `bindMoney` is true it also pins the approved amount onto the start button so
-- the reused OnClick sends exactly this price, never a stale global default left
-- in BiaoGe.Auction.money. It never invokes the start handler: the outer queue
-- wrapper arms the shared pre-send gate and clicks only after both wrappers have
-- returned.
function M.applyLeaderPrefill(frame, money, bindMoney)
    if not isFrameObject(frame) or type(money) ~= "number" then return false end
    if not isFrameObject(frame.Edit2) or type(frame.Edit2.SetText) ~= "function" then return false end
    if bindMoney then
        if not isFrameObject(frame.bt) then return false end
        frame.bt.money = money
    end
    frame.Edit2:SetText(tostring(money))
    return true
end

local _, ns = ...

local function runtimeReady()
    return ns ~= nil
        and BG.Init ~= nil
        and BG.BGNext.AuctionPriceStore ~= nil
        and BG.BGNext.AuctionPriceCatalog ~= nil
        and BG.BGNext.AuctionPreSend ~= nil
end

if runtimeReady() then
    local Store = BG.BGNext.AuctionPriceStore
    local Catalog = BG.BGNext.AuctionPriceCatalog
    local PreSend = BG.BGNext.AuctionPreSend
    local L = ns and ns.L or setmetatable({}, { __index = function(_, key) return tostring(key) end })

    -- Short local reasons shown only when a direct start is refused; the dialog
    -- is always left open for the leader to confirm manually. The gate reasons
    -- reuse the shared pre-send reason codes.
    local DIRECT_REASON_TEXT = {
        [PreSend.REASON_NO_PERMISSION] = L["无权限发起拍卖"],
        [PreSend.REASON_COMBAT] = L["战斗状态下无法发起拍卖"],
        [PreSend.REASON_AUCTION_BUSY] = L["已有拍卖进行中"],
        [PreSend.REASON_PRICE_UNRESOLVED] = L["请手动输入起拍价"],
        [PreSend.REASON_SCOPE_CHANGED] = L["团队或表格已变更"],
        [PreSend.REASON_PRICE_CHANGED] = L["起拍价已变更，请重新确认"],
        [PreSend.REASON_SCHEME_CHANGED] = L["起拍价方案已变更，请重新确认"],
        [PreSend.REASON_FAMILY_CHANGED] = L["客户端版本已变更，请重新确认"],
        ["no-raid"] = L["无法确定该装备所属副本，已保留确认窗口。"],
    }

    local function showReason(reason)
        if type(reason) ~= "string" then return end
        local text = DIRECT_REASON_TEXT[reason]
        if text and type(BG.SendSystemMessage) == "function" then
            BG.SendSystemMessage(text)
        end
    end

    local function contextProvider()
        return {
            root = BG.BGNext and BG.BGNext.DB,
            clientFamily = PreSend.clientFamily(),
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
    -- direct start the resolved price is written and an approval snapshot is
    -- recorded on the frame; the outer queue wrapper then arms the shared
    -- pre-send gate (reading that snapshot) and only then invokes the reused
    -- OnClick. Any unresolved item keeps the window open with a short local
    -- reason instead of guessing.
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
        local approvals = {}
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
                reason = blocked == "scope" and PreSend.REASON_SCOPE_CHANGED or blocked
                complete = false
                break
            end
            local approval = Store.resolveLeaderApproval(root, family, raid, itemId)
            if approval == nil or type(approval.price) ~= "number" then
                reason = PreSend.REASON_PRICE_UNRESOLVED
                complete = false
                break
            end
            prices[#prices + 1] = approval.price
            approvals[#approvals + 1] = {
                itemId = itemId,
                raidId = raid,
                price = approval.price,
                source = approval.source,
                activePresetId = approval.activePresetId,
            }
        end

        if not complete then
            if directStart then showReason(reason) end
            return
        end

        local common = M.chooseLeaderPrefill(prices)
        if common == nil then
            if directStart then showReason(reason or PreSend.REASON_PRICE_UNRESOLVED) end
            return
        end

        if directStart then
            -- Record the approval snapshot but defer the click. The outer queue
            -- wrapper reads `bgnextDirectApproval`, arms the shared pre-send gate
            -- and only then invokes the reused OnClick, so every direct start is
            -- re-checked (permission, combat, auction, family, scope, scheme and
            -- price) before any send.
            frame.bgnextDirectApproval = {
                clientFamily = family,
                scopeKey = PreSend.scopeKey(),
                items = approvals,
            }
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
