return function(test)
    BG = { BGNext = {} }
    dofile("Core/BGNext/Identity.lua")
    local info = dofile("Core/BGNext/ReleaseInfo.lua")

    test.eq(info.projectName, "BGNext", "project name")
    test.eq(info.version, "0.1.0", "BGNext version is independent")
    test.eq(info.upstreamVersion, "2.4.0", "upstream version remains disclosed")
    test.eq(info.protocolVersion, "2.4.0", "mixed-group protocol version remains compatible")
    test.eq(info.author, "国服社区共创", "community author")
    test.eq(info.official, false, "independent project")
    test.eq(type(info.changelog), "table", "local changelog")
    test.eq(type(info.credits.upstream), "table", "upstream credits")

    local about = dofile("Core/BGNext/About.lua")
    test.eq(about.buildText("about", info):find("非官方", 1, true) ~= nil, true, "independent status disclosed")
    test.eq(about.buildText("changelog", info):find(info.changelog[1], 1, true) ~= nil, true, "changelog rendered")
    test.eq(about.buildText("credits", info):find(info.credits.upstream[1], 1, true) ~= nil, true, "credits rendered")

    local aboutFile = assert(io.open("Core/BGNext/About.lua", "rb"))
    local aboutSource = aboutFile:read("*a")
    aboutFile:close()
    test.eq(aboutSource:find('button:SetPoint("RIGHT", BG.ButtonExportHope, "LEFT", -12, 0)', 1, true) ~= nil,
        true, "community buttons start to the left of wishlist controls")

    local auctionFile = assert(io.open("Core/Module/Auction.lua", "rb"))
    local auctionSource = auctionFile:read("*a")
    auctionFile:close()
    test.eq(auctionSource:find('guild.title = L["BGLite版本"]', 1, true), nil,
        "mixed-client version census is not mislabeled as BGLite-only")
    test.eq(auctionSource:find('L["BGLite版本"]', 1, true), nil,
        "all mixed-client census tooltip paths avoid the BGLite-only label")
    test.eq(auctionSource:find('L["兼容插件版本"]', 1, true) ~= nil, true,
        "mixed-client version census has a neutral compatibility label")

    local tocFile = assert(io.open("BGLite.toc", "rb"))
    local toc = tocFile:read("*a")
    tocFile:close()
    test.eq(toc:find("## Author: 国服社区共创", 1, true) ~= nil, true, "community author metadata")
    test.eq(toc:find("## X-Upstream-Author: CQZS (Lite)", 1, true) ~= nil, true, "upstream author metadata")

    for _, path in ipairs({ "Locales/zhCN.lua", "Locales/zhTW.lua", "Locales/enUS.lua" }) do
        local file = assert(io.open(path, "rb"))
        local text = file:read("*a")
        file:close()
        test.eq(text:find("/bgn", 1, true) ~= nil, true, path .. " documents /bgn")
        test.eq(text:find("/bgnext", 1, true) ~= nil, true, path .. " documents /bgnext")
        test.eq(text:find("/gbg", 1, true) == nil, true, path .. " removes /gbg")
    end
end
