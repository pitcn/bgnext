local AddonName, ns = ...

BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Collection layer for the single current-raid settlement.
--
-- It only ever reacts to a success result that the loaded BGLite baseline has
-- already confirmed: `ERR_TRADE_COMPLETE` for a finished trade, and the batch
-- mail flow's own `ERR_MAIL_SENT` branch for a send the plugin performed
-- itself. There is no polling, no inbox scan, no chat capture and no new
-- communication. An event whose raid attribution cannot be proven is dropped
-- rather than guessed.
local M = {}

local MAX_AGE = 7 * 86400
local pendingMail

local function serverNow()
    if type(GetServerTime) == "function" then
        return GetServerTime()
    end
    return time()
end

local function lifecycle()
    return BG.BGNext and BG.BGNext.DataLifecycle
end

local function tradeStore()
    return BG.BGNext and BG.BGNext.CurrentTrade
end

local function mailStore()
    return BG.BGNext and BG.BGNext.CurrentMail
end

local function refreshUI(kind)
    local ui = BG.BGNext and BG.BGNext.CurrentSettlementUI
    if ui and type(ui.Refresh) == "function" then
        ui.Refresh(kind)
    end
end

-- A settlement identity may only be established while the evidence is
-- complete: the user is in a raid, a current table is detected, and the
-- current roster is known. Normally that evidence is BGLite's persisted roster
-- stamp. During the short window after entering another supported raid, the
-- live roster may provide the same bounded evidence before the first boss has
-- caused BGLite to persist a stamp.
function M.raidId(context)
    if type(context) ~= "table" then
        return nil
    end
    if context.inRaid ~= true then
        return nil
    end
    local fb = context.fb
    if type(fb) ~= "string" or not fb:find("%S") then
        return nil
    end
    local roster = context.roster
    if type(roster) ~= "table" or type(roster.time) ~= "number" then
        return nil
    end
    if type(context.realm) == "string" and type(roster.realm) == "string"
        and context.realm ~= roster.realm then
        return nil
    end
    -- A stamp older than the retention window can no longer describe the raid
    -- that is being settled now.
    if type(context.now) == "number" and context.now - roster.time >= MAX_AGE then
        return nil
    end
    return fb .. "@" .. string.format("%d", roster.time)
end

-- Establishes the settlement when the evidence allows it, then drops anything
-- that has expired. Returns the active settlement raid id, or nil when there is
-- no settlement to reconcile against.
local function activeSettlement(root, context)
    local life = lifecycle()
    if not life or type(root) ~= "table" then
        return nil
    end
    local now = type(context) == "table" and context.now or nil
    if type(now) == "number" then
        life.purgeExpired(root, now)
    end
    if type(context) == "table" and context.inRaid == true and context.sameTeam == false then
        if root.currentSettlement and root.currentSettlement.raidId ~= nil then
            life.clearSettlement(root)
        end
        return nil
    end
    local raidId = M.raidId(context)
    if raidId and type(now) == "number" then
        local current = root.currentSettlement
        local sameSource = current and current.raidId ~= nil
            and current.sourceFb == context.fb
            and (current.sourceRealm == nil or context.realm == nil or current.sourceRealm == context.realm)
        if not sameSource then
            life.beginSettlement(root, raidId, now, {
                fb = context.fb,
                realm = context.realm,
            })
        end
    end
    local settlement = root.currentSettlement
    if not settlement or settlement.raidId == nil then
        return nil
    end
    return settlement.raidId
end

local function resolveItemId(item, itemIdOf)
    if type(item) ~= "table" then
        return nil
    end
    if type(item.itemId) == "number" then
        return item.itemId
    end
    local link = item.link
    if type(link) ~= "string" then
        return nil
    end
    local resolver = itemIdOf or (ns and ns.GetItemID)
    if type(resolver) ~= "function" then
        return nil
    end
    local ok, id = pcall(resolver, link)
    if ok and type(id) == "number" then
        return id
    end
    return nil
end

-- Aggregates a trade slot list into one entry per distinct item id, summing
-- the slot quantities. `quantity` becomes nil when any contributing slot has
-- an unknown or invalid count, so a partially-known delivery is never read as
-- a specific count. `singleUnits` stays true only when every slot resolves to
-- exactly one unit, which preserves the existing proof rule (a stack or
-- unknown count can never prove a single sale).
local function itemIds(value, itemIdOf)
    local entries = {}
    local byIndex = {}
    local singleUnits = true
    if type(value) ~= "table" then
        return entries, singleUnits
    end
    for _, item in ipairs(value) do
        local id = resolveItemId(item, itemIdOf)
        local count = type(item) == "table" and tonumber(item.count) or nil
        if count ~= nil and (count < 1 or count % 1 ~= 0) then
            count = nil
        end
        if not id or count ~= 1 then
            singleUnits = false
        end
        if id then
            local slot = byIndex[id]
            if not slot then
                slot = { itemId = id, quantity = count }
                byIndex[id] = slot
                entries[#entries + 1] = slot
            elseif slot.quantity ~= nil and count ~= nil then
                slot.quantity = slot.quantity + count
            else
                slot.quantity = nil
            end
        end
    end
    return entries, singleUnits
end

local function normalizedName(context, name)
    if type(name) ~= "string" then
        return nil
    end
    local fn = context and context.normalizeName
    if type(fn) == "function" then
        local ok, value = pcall(fn, name)
        if ok and type(value) == "string" then
            return value
        end
    end
    return name
end

local function isRosterMember(root, context, player)
    local settlement = root and root.currentSettlement
    local roster = context and context.roster
    if not settlement or not settlement.raidId or type(roster) ~= "table"
        or type(roster.roster) ~= "table" then
        return false
    end
    if settlement.sourceFb and context.fb and settlement.sourceFb ~= context.fb then
        return false
    end
    if settlement.sourceRealm and roster.realm and settlement.sourceRealm ~= roster.realm then
        return false
    end
    local wanted = normalizedName(context, player)
    if not wanted then
        return false
    end
    for _, name in ipairs(roster.roster) do
        if normalizedName(context, name) == wanted then
            return true
        end
    end
    return false
end

-- Turns one confirmed trade into a single grouped transaction record that
-- keeps the actual paid/received facts: both gold directions, both item
-- directions, the counterparty and time, plus two independent dimensions — the
-- trade-completed fact (`completed`) and the reconciliation state (`status`).
-- Gold is never netted and never invented: an explicit 0 stays 0, an unknown
-- side stays nil. A shared total is stored once on the transaction, never
-- duplicated per item. A completed trade stays completed even while its
-- reconciliation is still pending.
function M.tradeRows(trade, itemIdOf)
    if type(trade) ~= "table" or trade.completed ~= true then
        return {}
    end
    local player = trade.target
    if type(player) ~= "string" or not player:find("%S") then
        return {}
    end

    local myGold = type(trade.playermoney) == "number" and trade.playermoney or nil
    local theirGold = type(trade.targetmoney) == "number" and trade.targetmoney or nil
    local myItems, mySingleUnits = itemIds(trade.playeritems, itemIdOf)
    local theirItems, theirSingleUnits = itemIds(trade.targetitems, itemIdOf)

    local mine = myGold or 0
    local theirs = theirGold or 0
    local anyGold = (myGold ~= nil and myGold ~= 0) or (theirGold ~= nil and theirGold ~= 0)
    local anyItems = #myItems > 0 or #theirItems > 0

    -- Neither gold nor an identifiable item: no event at all.
    if not anyGold and not anyItems then
        return {}
    end

    -- Reconciliation state. Only a clean single-direction delivery proves a
    -- settled sale: exactly one gold side, no barter, and every delivered unit
    -- a known single item. Everything else stays pending for manual review — a
    -- completed trade is never auto-settled, and a pending reconcile state
    -- never negates the completed fact.
    local status = "pending"
    if theirs > 0 and mine == 0 and #theirItems == 0 and #myItems > 0 and mySingleUnits then
        status = "complete"
    elseif mine > 0 and theirs == 0 and #myItems == 0 and #theirItems > 0 and theirSingleUnits then
        status = "complete"
    end

    local rows = {}
    rows[1] = {
        player = player,
        completed = true,
        status = status,
        myGold = myGold,
        theirGold = theirGold,
        myItems = myItems,
        theirItems = theirItems,
    }
    return rows
end

function M.recordTrade(root, context, trade)
    local raidId = activeSettlement(root, context)
    local store = tradeStore()
    if not raidId or not store or not isRosterMember(root, context, trade and trade.target) then
        return 0
    end
    local rows = M.tradeRows(trade, context.itemIdOf)
    if #rows == 0 then
        return 0
    end
    local row = rows[1]
    local written = store.append(root, {
        raidId = raidId,
        player = row.player,
        time = context.now,
        completed = row.completed,
        status = row.status,
        myGold = row.myGold,
        theirGold = row.theirGold,
        myItems = row.myItems,
        theirItems = row.theirItems,
    })
    if written then
        refreshUI("trade")
        return 1
    end
    return 0
end

function M.recordMail(root, context, mail)
    if type(mail) ~= "table" or mail.sent ~= true or mail.scope ~= "raid" then
        return false
    end
    local player = mail.player
    if type(player) ~= "string" or not player:find("%S") then
        return false
    end
    local raidId = activeSettlement(root, context)
    local store = mailStore()
    if not raidId or not store or not isRosterMember(root, context, player) then
        return false
    end
    local written = store.append(root, {
        raidId = raidId,
        player = player,
        itemId = type(mail.itemId) == "number" and mail.itemId or nil,
        amount = tonumber(mail.amount),
        time = context.now,
        status = "sent",
        direction = "outgoing",
    })
    if written then
        refreshUI("mail")
    end
    return written
end

-- Live wiring. Everything below only runs inside the game.
local function liveContext()
    local root = BG.BGNext and BG.BGNext.DB
    local settlement = root and root.currentSettlement
    local inRaid = IsInRaid and IsInRaid(1) and true or false
    local fb = inRaid and BG.FB2 or (settlement and settlement.sourceFb)
    local now = serverNow()
    local roster
    if type(fb) == "string" and type(BiaoGe) == "table" and type(BiaoGe[fb]) == "table" then
        roster = BiaoGe[fb].raidRoster
    end

    local persistedRoster = type(roster) == "table" and type(roster.time) == "number"
    if inRaid and not persistedRoster and type(BG.raidRosterInfo) == "table" then
        local names = {}
        for _, member in ipairs(BG.raidRosterInfo) do
            local name = type(member) == "table" and member.name or nil
            if type(name) == "string" and name:find("%S") then
                names[#names + 1] = name
            end
        end
        if #names > 0 then
            roster = {
                time = now,
                realm = BG.realmName,
                roster = names,
            }
        end
    end
    local sameTeam
    -- IsNotSameTeam intentionally reports "different" when the table has no
    -- saved roster. Do not apply that sentinel while the live roster is the
    -- evidence, or every trade before the first boss stamp is discarded.
    if inRaid and persistedRoster and type(fb) == "string" and type(BG.IsNotSameTeam) == "function" then
        local ok, isDifferent = pcall(BG.IsNotSameTeam, fb)
        if ok then
            sameTeam = not isDifferent
        end
    end
    return {
        fb = fb,
        roster = roster,
        realm = BG.realmName,
        inRaid = inRaid,
        normalizeName = BG.GSN,
        sameTeam = sameTeam,
        now = now,
    }
end

M.liveContext = liveContext

function M.onTableCleared(root, fb)
    local settlement = root and root.currentSettlement
    local life = lifecycle()
    if not settlement or not settlement.raidId or not life or settlement.sourceFb ~= fb then
        return false
    end
    life.clearSettlement(root)
    -- Derived views (checklist, tables) must drop the cleared scope at once.
    refreshUI("trade")
    return true
end

-- Called by the batch mail flow at its own confirmed send result.
function M.notifyMailAttempt(player, amount, scope)
    if scope ~= "raid" or type(player) ~= "string" or not player:find("%S") then
        pendingMail = nil
        return false
    end
    pendingMail = {
        player = player,
        amount = tonumber(amount),
        scope = scope,
    }
    return true
end

function M.notifyMailSent(player, amount, scope)
    local root = BG.BGNext and BG.BGNext.DB
    local pending = pendingMail
    pendingMail = nil
    if not root or not pending or pending.player ~= player
        or pending.amount ~= tonumber(amount) or pending.scope ~= scope then
        return false
    end
    return M.recordMail(root, liveContext(), {
        sent = true,
        scope = pending.scope,
        player = pending.player,
        amount = pending.amount,
    })
end

if BG.Init then
    BG.Init(function()
        -- At encounter start the player is confirmed inside the detected
        -- instance and BGLite has not yet replaced the table roster with the
        -- just-finished boss roster. This is the safe moment to distinguish a
        -- second group in the same instance. Leaving the instance and ordinary
        -- roster churn never run this check, so pending wage records survive.
        BG.RegisterEvent("ENCOUNTER_START", function()
            local root = BG.BGNext and BG.BGNext.DB
            if root then
                activeSettlement(root, liveContext())
                refreshUI("trade")
            end
        end)

        BG.RegisterEvent("UI_INFO_MESSAGE", function(_, _, _, text)
            if text ~= ERR_TRADE_COMPLETE then
                return
            end
            local root = BG.BGNext and BG.BGNext.DB
            local capture = BG.BGNext and BG.BGNext.TradeCapture
            if not root or not capture then
                return
            end
            -- TradeCapture registered its completion handler first, so by the
            -- time this handler runs the frozen snapshot is committed and
            -- published. Reading committed() (never the mutable BG.trade) keeps
            -- the settlement record identical to the bill and auction mark.
            local snap = capture.committed()
            if not snap then
                return
            end
            M.recordTrade(root, liveContext(), {
                completed = true,
                target = snap.target,
                targetmoney = snap.targetmoney,
                playermoney = snap.playermoney,
                targetitems = snap.targetitems,
                playeritems = snap.playeritems,
            })
        end)

        -- Clearing the active raid table must invalidate the settlement and
        -- every derived view at once.
        if type(hooksecurefunc) == "function" and type(BG.ClearBiaoGe) == "function" then
            hooksecurefunc(BG, "ClearBiaoGe", function(_, fb)
                local root = BG.BGNext and BG.BGNext.DB
                if root and M.onTableCleared(root, fb) then
                    refreshUI("trade")
                end
            end)
        end
    end)
end

BG.BGNext.CurrentSettlementRuntime = M
return M
