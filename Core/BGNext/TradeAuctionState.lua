BG = BG or {}
BG.BGNext = BG.BGNext or {}

local PlayerIdentity = assert(BG.BGNext.PlayerIdentity,
    "BGNext PlayerIdentity must load before TradeAuctionState")

local M = {}

function M.markDelivered(records, tradeName, localRealm, tradeItems, getItemId)
    if type(records) ~= "table" or type(tradeItems) ~= "table" or type(getItemId) ~= "function" then
        return 0
    end

    local requested = {}
    for _, traded in pairs(tradeItems) do
        if type(traded) ~= "table" or type(traded.count) ~= "number"
            or traded.count ~= traded.count or traded.count == math.huge or traded.count == -math.huge
            or traded.count <= 0 or traded.count % 1 ~= 0 or type(traded.link) ~= "string" then
            return 0
        end

        local tradedItemId = getItemId(traded.link)
        if not tradedItemId then return 0 end
        requested[tradedItemId] = (requested[tradedItemId] or 0) + traded.count
    end

    local recordItemIds = {}
    for _, record in pairs(records) do
        if type(record) ~= "table" then return 0 end
        if record.type == 1 and not record.trade
            and PlayerIdentity.same(record.maijia, tradeName, localRealm) then
            if type(record.zhuangbei) ~= "string" then return 0 end
            local recordItemId = getItemId(record.zhuangbei)
            if not recordItemId then return 0 end
            recordItemIds[record] = recordItemId
        end
    end

    local remaining = {}
    for itemId, count in pairs(requested) do
        remaining[itemId] = count
    end

    local toMark = {}
    for _, record in ipairs(records) do
        local recordItemId = recordItemIds[record]
        if recordItemId and remaining[recordItemId] and remaining[recordItemId] > 0 then
            toMark[#toMark + 1] = record
            remaining[recordItemId] = remaining[recordItemId] - 1
        end
    end

    for _, record in ipairs(toMark) do
        record.trade = true
    end
    return #toMark
end

BG.BGNext.TradeAuctionState = M
return M
