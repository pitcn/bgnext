local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

return function(test)
    local source = readAll("Core/Module/AuctionLog.lua")

    test.eq(source:find("prefix, msg, distType, sender", 1, true) ~= nil, true,
        "raid addon handlers read sender immediately after the distribution channel")
    test.eq(source:find("prefix, msg, channel, sender", 1, true) ~= nil, true,
        "refund addon handler reads sender immediately after the channel")
    test.eq(source:find("prefix, msg, distType, _, sender", 1, true), nil,
        "raid addon handlers never mistake the target payload for sender")
    test.eq(source:find("prefix, msg, channel, _, sender", 1, true), nil,
        "refund addon handler never mistakes the target payload for sender")
end
