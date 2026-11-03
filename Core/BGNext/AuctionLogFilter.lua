BG = BG or {}
BG.BGNext = BG.BGNext or {}
local Identity = assert(BG.BGNext.PlayerIdentity, 'PlayerIdentity must load first')
local M = {}

-- A read-only projection of existing current-table records. Pending payment
-- remains a successful auction; filtering never changes accounting facts.
function M.include(record, choice, player, realm, ownCharacters)
    if type(record) ~= 'table' then return false end
    if choice == 1 then return true end
    if choice == 2 then return record.type == 1 end
    if choice == 3 then return record.type == 2 end
    if choice == 5 then return record.type == 1 and not record.trade end
    if choice == 6 then
        if record.type ~= 1 then return false end
        if Identity.same(record.maijia, player, realm) then return true end
        for name,info in pairs(type(ownCharacters)=='table' and ownCharacters or {}) do
            if info and Identity.same(record.maijia, name, realm) then return true end
        end
        return false
    end
    return false
end

BG.BGNext.AuctionLogFilter = M
return M
