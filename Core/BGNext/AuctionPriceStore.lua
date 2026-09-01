BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Validated storage and price resolution for the two local price-preset features:
-- leader starting-price schemes and per-character personal expectations. This
-- module never creates frames, never reads the retired auto-bid presets and
-- never communicates. All writes rebuild records from a strict whitelist.
local M = {}

M.MAX_MONEY = 10000000
M.MAX_PRESETS = 20
M.MAX_ITEMS = 500
M.MAX_NAME_CHARS = 24

-- Fresh-install global starting-price defaults per canonical BGNext client
-- family (matches OwnCharactersAdapters.families). Only used when the local
-- BiaoGe.Auction.money is missing or invalid; an existing user value is never
-- overwritten.
local DEFAULTS = {
    vanilla = 100, tbc = 100, wrath = 1000, titan = 100,
    cata = 100000, mop = 10000, retail = 100000,
}

function M.defaultGlobalPrice(clientFamily)
    return DEFAULTS[clientFamily]
end

BG.BGNext.AuctionPriceStore = M
return M
