BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}
local seen = {}

function M.matchEvent(wishItems, itemId, raidId, eventId)
    if type(itemId) ~= "number" or type(eventId) ~= "string" or eventId == "" then
        return { matched = false }
    end
    for _, wishItemId in ipairs(wishItems or {}) do
        if wishItemId == itemId then
            return {
                matched = true,
                raidId = raidId,
                itemId = itemId,
                key = eventId .. ":" .. itemId,
            }
        end
    end
    return { matched = false }
end

function M.shouldNotify(seenEvents, key)
    return type(seenEvents) == "table" and type(key) == "string" and seenEvents[key] ~= true
end

function M.markNotified(seenEvents, key)
    if type(seenEvents) == "table" and type(key) == "string" then
        seenEvents[key] = true
        return true
    end
    return false
end

function M.notify(kind, itemId, raidId, eventId, itemLink, level)
    local wishlist = BG.BGNext.Wishlist
    local root = BG.BGNext.DB
    if not wishlist or not root or not wishlist.contains(root, BG.realmID, BG.playerName, raidId, itemId) then
        return false
    end
    local key = tostring(kind) .. ":" .. tostring(eventId) .. ":" .. tostring(itemId)
    if not M.shouldNotify(seen, key) then return false end
    M.markNotified(seen, key)

    local display = itemLink or tostring(itemId)
    local message
    if kind == "loot" then
        message = string.format("你的心愿达成啦！！！>>>>> %s(%s) <<<<<", display, tostring(level or ""))
    else
        message = "你心愿的装备开始拍卖了：" .. display
    end
    if BG.FrameLootMsg and BG.FrameLootMsg.AddMessage then
        BG.FrameLootMsg:AddMessage(BG.STC_g1 and BG.STC_g1(message) or message)
    elseif BG.SendSystemMessage then
        BG.SendSystemMessage(message)
    end
    if BG.PlaySound then BG.PlaySound("hope") end
    return true
end

BG.BGNext.WishlistReminder = M
return M
