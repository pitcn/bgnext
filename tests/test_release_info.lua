return function(test)
    BG = { BGNext = {} }
    dofile("Core/BGNext/Identity.lua")
    local info = dofile("Core/BGNext/ReleaseInfo.lua")

    test.eq(info.projectName, "BGNext", "project name")
    test.eq(info.version, "0.3.1", "BGNext version is independent")
    test.eq(info.upstreamVersion, "2.4.0", "upstream version remains disclosed")
    test.eq(info.protocolVersion, "2.4.0", "mixed-group protocol version remains compatible")
    test.eq(info.author, "国服社区共创", "community author")
    test.eq(info.official, false, "independent project")
    test.eq(type(info.changelog), "table", "local changelog")
    local changelogItems = table.concat(info.changelog, "\n")
    test.eq(changelogItems:find("Alt 右键", 1, true) ~= nil, true,
        "in-game changelog includes table auction shortcut fix")
    test.eq(changelogItems:find("团长自己", 1, true) ~= nil, true,
        "in-game changelog includes leader self-accounting fix")
    test.eq(changelogItems:find("职业颜色", 1, true) ~= nil, true,
        "in-game changelog includes auction class colors")
    test.eq(changelogItems:find("红叉按钮", 1, true) ~= nil, true,
        "in-game changelog includes global filter bypass")
    test.eq(type(info.credits.upstream), "table", "upstream credits")

    local about = dofile("Core/BGNext/About.lua")
    local aboutText = about.buildText("about", info)
    test.eq(aboutText:find("非官方", 1, true) ~= nil, true, "independent status disclosed")
    test.eq(aboutText:find("BGLite 2.4.0", 1, true) ~= nil, true, "upstream foundation disclosed")
    test.eq(aboutText:find("新增功能代码由社区独立原创实现", 1, true) ~= nil, true,
        "original enhancement scope disclosed")
    test.eq(aboutText:find("不生成他人的历史信息记录", 1, true) ~= nil, true,
        "other-player history boundary disclosed")
    test.eq(aboutText:find("不建立第三方排名", 1, true) ~= nil, true,
        "third-party ranking boundary disclosed")
    test.eq(aboutText:find("全部捐赠", 1, true) ~= nil, true, "charity commitment disclosed")
    test.eq(aboutText:find(info.activityUrl, 1, true) ~= nil, true, "public activity link disclosed")

    local changelogText = about.buildText("changelog", info)
    test.eq(changelogText:find("BGNext " .. info.version, 1, true) ~= nil, true, "release version rendered")
    test.eq(changelogText:find(info.changelog[1], 1, true) ~= nil, true, "changelog rendered")
    test.eq(changelogText:find("Lua 5.1", 1, true), nil, "player changelog avoids implementation jargon")
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
    test.eq(auctionSource:find('L["兼容插件版本"]', 1, true), nil,
        "the ambiguous compatibility-version census is removed")
    test.eq(auctionSource:find('L["团队拍卖就绪检查"]', 1, true) ~= nil, true,
        "the mixed-client check describes auction readiness")

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
