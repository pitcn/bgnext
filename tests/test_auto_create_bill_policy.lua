return function(test)
    local file = assert(io.open("Core/Module/AuctionLog.lua", "rb"))
    local source = file:read("*a")
    file:close()

    local body = assert(source:match("function BG%.IsAutoCreateBill%(%)(.-)\n%s*end"),
        "BG.IsAutoCreateBill implementation not found")
    local compile = loadstring or load
    local factory = assert(compile("return function()" .. body .. "\nend"))
    local isAutoCreateBill = factory()

    local oldBiaoGe, oldBG = BiaoGe, BG
    local ok, err = pcall(function()
        BiaoGe = { options = { autoCreateBill = 1 } }
        BG = { IsML = true }
        test.eq(isAutoCreateBill(), true,
            "checked auto-create bill remains active for the raid leader/master looter")

        BG.IsML = nil
        test.eq(isAutoCreateBill(), true,
            "checked auto-create bill remains active for ordinary raid members")

        BiaoGe.options.autoCreateBill = 0
        BG.IsML = true
        test.eq(isAutoCreateBill(), false,
            "unchecked auto-create bill remains disabled")
    end)
    BiaoGe, BG = oldBiaoGe, oldBG
    if not ok then error(err, 0) end
end
