return function(test)
    local loaded, layout = pcall(dofile, "Core/BGNext/LeaderToolsLayout.lua")
    test.eq(loaded, true, "leader-tools layout module loads")
    if not loaded then return end

    test.eq(layout.WIDTH, 720, "window uses the reviewed logical width")
    test.eq(layout.HEIGHT, 500, "window uses the reviewed logical height")
    test.eq(layout.scaleFor(800, 600), 1, "roomy screens keep native scale")
    test.eq(layout.scaleFor(680, 470) < 1, true, "narrow screens scale the whole window down")
    test.eq(layout.scaleFor(400, 300), 0.70, "very small screens use the readable lower bound")
    test.eq(layout.scaleFor(nil, nil), 1, "missing screen geometry degrades safely")

    for _, page in ipairs({ "templates", "history", "auctions", "settlement" }) do
        local region = layout.pageRegion(page)
        test.eq(region.top < region.footerTop, true, page .. " body ends before its footer")
        test.eq(region.footerTop < region.bottom, true, page .. " footer stays inside content")
    end
    test.eq(layout.auctionVisibleRows(layout.CONTENT_HEIGHT) <= 20, true,
        "auction row pool remains bounded")
    test.eq(layout.auctionVisibleRows(layout.CONTENT_HEIGHT) >= 1, true,
        "auction page keeps at least one visible row")
end
