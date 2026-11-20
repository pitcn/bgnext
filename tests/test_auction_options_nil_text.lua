-- Leader auction settings: an unset BiaoGe.Auction value (resetThreshold is
-- never initialised) must not reach EditBox:SetText(nil), which raises
-- "bad argument #1 to 'SetText'". Defaults and auction logic stay unchanged.

local function read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

return function(test)
    local options = read("Core/Options.lua")

    test.eq(options:find("SetText(BiaoGe.Auction.resetThreshold)", 1, true), nil,
        "reset threshold is not passed to SetText unguarded")
    test.eq(options:find("SetText(BiaoGe.Auction[name])", 1, true), nil,
        "auction edit boxes do not pass a raw value to SetText")
    test.eq(options:find("SetText(BiaoGe.Auction[", 1, true), nil,
        "no other raw BiaoGe.Auction[...] value reaches SetText")

    -- The helper used instead: nil -> "", numbers -> tostring.
    local body = options:match("local function AuctionEditText%((.-)\n%s*end")
    test.eq(body ~= nil, true, "AuctionEditText helper exists")
    local chunk = assert(loadstring and loadstring("local function AuctionEditText(" .. body .. "\nend return AuctionEditText")
        or load("local function AuctionEditText(" .. body .. "\nend return AuctionEditText"))
    local AuctionEditText = chunk()
    test.eq(AuctionEditText(nil), "", "nil becomes an empty string")
    test.eq(AuctionEditText(20), "20", "a number becomes its text")
    test.eq(AuctionEditText("40"), "40", "a string stays unchanged")
end
