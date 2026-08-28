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

local function lifecycle()
    return BG.BGNext and BG.BGNext.DataLifecycle
end

local function tradeStore()
    return BG.BGNext and BG.BGNext.CurrentTrade
end

local function mailStore()
    return BG.BGNext and BG.BGNext.CurrentMail
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
    local raidId = M.raidId(context)
    if raidId and type(now) == "number" then
        life.beginSettlement(root, raidId, now)
    end
    if type(now) == "number" then
        life.purgeExpired(root, now)
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
    if not raidId or not store then
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
    return written
end

function M.recordMail(root, context, mail)
    if type(mail) ~= "table" or mail.sent ~= true then
        return false
    end
    local player = mail.player
    if type(player) ~= "string" or not player:find("%S") then
        return false
    end
    local raidId = activeSettlement(root, context)
    local store = mailStore()
    if not raidId or not store then
        return false
    end
    return store.append(root, {
        raidId = raidId,
        player = player,
        itemId = type(mail.itemId) == "number" and mail.itemId or nil,
        amount = tonumber(mail.amount),
        time = context.now,
        status = "sent",
        direction = "outgoing",
    })
end

-- Live wiring. Everything below only runs inside the game.
local function liveContext()
    local fb = BG.FB1
    local roster
    if type(fb) == "string" and type(BiaoGe) == "table" and type(BiaoGe[fb]) == "table" then
        roster = BiaoGe[fb].raidRoster
    end
    return {
        fb = fb,
        roster = roster,
        realm = BG.realmName,
        inRaid = IsInRaid and IsInRaid(1) and true or false,
        now = time(),
    }
end

M.liveContext = liveContext

-- Called by the batch mail flow at its own confirmed send result.
function M.notifyMailSent(player, amount)
    local root = BG.BGNext and BG.BGNext.DB
    if not root then
        return false
    end
    return M.recordMail(root, liveContext(), {
        sent = true,
        player = player,
        amount = amount,
    })
end

if BG.Init then
    BG.Init(function()
        -- Memory-only guard so one trade cannot be booked twice if the client
        -- repeats the completion message.
        local booked = false

        BG.RegisterEvent({ "TRADE_SHOW", "TRADE_CLOSED" }, function()
            booked = false
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
    end)
end

BG.BGNext.CurrentSettlementRuntime = M
return M
