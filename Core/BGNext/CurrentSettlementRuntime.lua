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
-- complete: the user is in a raid, a current table is selected, and BGLite has
-- already stamped that table's roster for this raid on the same realm. The
-- stamp is cleared whenever the user clears the table, so a cleared or
-- restarted raid yields a different identity.
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

local function itemIds(value, itemIdOf)
    local ids = {}
    if type(value) ~= "table" then
        return ids
    end
    for _, item in ipairs(value) do
        local id = resolveItemId(item, itemIdOf)
        if id then
            ids[#ids + 1] = id
        end
    end
    return ids
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

-- Only the gold one side actually put up counts as the settlement amount; it is
-- never derived from a bill row, a previous trade or a guess.
local function settlementAmount(trade)
    local theirs = tonumber(trade.targetmoney) or 0
    local mine = tonumber(trade.playermoney) or 0
    if theirs > 0 then
        return theirs, mine
    end
    if mine > 0 then
        return mine, mine
    end
    return nil, mine
end

-- Turns one confirmed trade into the rows that describe it. When both sides put
-- up items and neither put up gold, BGLite itself cannot tell who the buyer is,
-- so a single row is produced for manual reconciliation instead of inventing an
-- item or an amount.
function M.tradeRows(trade, itemIdOf)
    if type(trade) ~= "table" or trade.completed ~= true then
        return {}
    end
    local player = trade.target
    if type(player) ~= "string" or not player:find("%S") then
        return {}
    end

    local amount, myMoney = settlementAmount(trade)
    local theirItems = itemIds(trade.targetitems, itemIdOf)
    local myItems = itemIds(trade.playeritems, itemIdOf)

    local items
    if amount == nil then
        if #theirItems > 0 and #myItems > 0 then
            items = {}
        elseif #theirItems > 0 then
            items = theirItems
        elseif #myItems > 0 then
            items = myItems
        else
            return {}
        end
    else
        -- Gold moved: the settled items are the ones travelling the other way.
        items = myMoney > 0 and theirItems or myItems
        if #items == 0 then
            items = #theirItems > 0 and theirItems or myItems
        end
    end

    local status = amount ~= nil and "complete" or "pending"
    local rows = {}
    if #items == 0 then
        rows[1] = { player = player, itemId = nil, amount = amount, status = status }
    else
        for index, itemId in ipairs(items) do
            rows[index] = {
                player = player,
                itemId = itemId,
                -- The gold belongs to the trade, not to each packed item.
                amount = index == 1 and amount or nil,
                status = status,
            }
        end
    end
    return rows
end

function M.recordTrade(root, context, trade)
    local raidId = activeSettlement(root, context)
    local store = tradeStore()
    if not raidId or not store or not isRosterMember(root, context, trade and trade.target) then
        return 0
    end
    local now = context.now
    local written = 0
    for _, row in ipairs(M.tradeRows(trade, context.itemIdOf)) do
        if store.append(root, {
            raidId = raidId,
            player = row.player,
            itemId = row.itemId,
            amount = row.amount,
            time = now,
            status = row.status,
        }) then
            written = written + 1
        end
    end
    if written > 0 then
        refreshUI("trade")
    end
    return written
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
    local roster
    if type(fb) == "string" and type(BiaoGe) == "table" and type(BiaoGe[fb]) == "table" then
        roster = BiaoGe[fb].raidRoster
    end
    local sameTeam
    if inRaid and type(fb) == "string" and type(BG.IsNotSameTeam) == "function" then
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
        now = serverNow(),
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
        -- Memory-only guard so one trade cannot be booked twice if the client
        -- repeats the completion message.
        local booked = false

        BG.RegisterEvent("TRADE_SHOW", function()
            booked = false
        end)

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
            if text ~= ERR_TRADE_COMPLETE or booked then
                return
            end
            booked = true
            local root = BG.BGNext.DB
            local trade = BG.trade
            if not root or type(trade) ~= "table" then
                return
            end
            M.recordTrade(root, liveContext(), {
                completed = true,
                target = trade.target,
                targetmoney = trade.targetmoney,
                playermoney = trade.playermoney,
                targetitems = trade.targetitems,
                playeritems = trade.playeritems,
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
