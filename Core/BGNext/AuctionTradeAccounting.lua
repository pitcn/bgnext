BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Pure accounting helpers shared by the auction-result writer and the trade
-- completion path. Amounts are always expressed in whole gold, matching the
-- existing BiaoGe/BGLite bill schema.
local M = {}
local billRows = setmetatable({}, { __mode = "k" })

local function text(value)
    if value == nil then return "" end
    return tostring(value)
end

function M.rowKind(auction, row, sameItem, samePlayer)
    if type(auction) ~= "table" or type(row) ~= "table"
        or type(sameItem) ~= "function" or type(samePlayer) ~= "function" then
        return nil
    end
    if row.debt ~= nil then return nil end

    local auctionItem = auction.link or auction.zhuangbei
    local auctionBuyer = auction.player or auction.maijia
    local auctionAmount = auction.money or auction.jine
    if not sameItem(row.item, auctionItem) then return nil end

    local buyer, amount = text(row.buyer), text(row.amount)
    if buyer == "" and amount == "" then
        return "empty"
    end
    if buyer ~= "" and samePlayer(buyer, auctionBuyer)
        and tonumber(amount) ~= nil
        and tonumber(amount) == tonumber(auctionAmount) then
        return "prefilled"
    end
    return nil
end

function M.allocateDebt(records, totalDebt)
    local remaining = math.max(tonumber(totalDebt) or 0, 0)
    if type(records) ~= "table" then return remaining end

    for _, record in ipairs(records) do
        local amount = math.max(tonumber(record.money or record.jine) or 0, 0)
        local debt = math.min(remaining, amount)
        record.qiankuan = debt
        remaining = remaining - debt
    end
    if remaining > 0 and records[#records] then
        records[#records].qiankuan = (records[#records].qiankuan or 0) + remaining
        remaining = 0
    end
    return remaining
end

-- Bill coordinates are deliberately runtime-only. Auction log records live in
-- the existing SavedVariables tree, so adding coordination fields to those
-- records would silently expand the persisted schema.
function M.linkBillRow(record, boss, slot)
    if type(record) ~= "table" or type(boss) ~= "number" or type(slot) ~= "number" then
        return false
    end
    billRows[record] = { boss = boss, slot = slot }
    return true
end

function M.billRow(record)
    local row = type(record) == "table" and billRows[record] or nil
    if not row then return nil, nil end
    return row.boss, row.slot
end

BG.BGNext.AuctionTradeAccounting = M
return M
