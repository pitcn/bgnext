return function(test)
    BG = { BGNext = {} }
    dofile("Core/BGNext/AuctionNames.lua")
    local SM = dofile("Core/BGNext/ControlledAutoBid.lua")

    -- nextBid is the pure amount calculation: one increment over the current bid.
    test.eq(SM.nextBid(100, 100, 1000), 200, "next bid adds one increment")
    test.eq(SM.nextBid(900, 100, 1000), 1000, "a bid exactly at the cap is allowed")
    test.eq(SM.nextBid(950, 100, 1000), nil, "a bid over the cap stops")
    test.eq(SM.nextBid(1000, 100, 1000), nil, "bidding past the cap stops")
    test.eq(SM.nextBid(0, 0, 1000), nil, "a zero increment is invalid")
    test.eq(SM.nextBid(nil, 100, 1000), nil, "a missing current price is invalid")
    test.eq(SM.nextBid(100, "100", 1000), nil, "a non-numeric increment is invalid")

    -- A fresh state is unarmed and will never bid.
    local idle = SM.new()
    test.eq(idle.status, "idle", "a new state starts unarmed")
    test.eq(SM.onPrice(idle, { auctionId = "12", price = 300, bidder = "Other" }, 0), nil,
        "no bid is ever made before arming")

    -- Arming with nobody having bid yet opens at the starting price; leadership is
    -- only confirmed once my own bid echoes back (SendAddonMessage returns no signal).
    local opened = SM.new()
    local decision = SM.arm(opened, {
        auctionId = "12", itemId = "item:123", increment = 100, cap = 1000,
        currentPrice = 100, currentBidder = nil, selfName = "Me", realm = "R",
    }, 0)
    test.eq(decision.bid, 100, "the opening bid is the starting price")
    test.eq(opened.status, "armed", "arming keeps the state armed")
    test.eq(opened.leading, false, "the opening bid is not yet confirmed leading")
    SM.markSent(opened, 0)
    test.eq(opened.leading, false, "a send alone never confirms leadership")
    test.eq(SM.statusText(opened), "自动出价中", "before the echo it reports auto-bidding in progress")
    local echo = SM.onPrice(opened, { auctionId = "12", price = 100, bidder = "Me" }, 0)
    test.eq(echo.hold, true, "my own echo confirms leadership")
    test.eq(opened.leading, true, "after the echo I am leading")
    test.eq(SM.statusText(opened), "当前本人领先", "after the echo it reports leading")

    -- An empty-string bidder is also "nobody has bid yet".
    local empty = SM.new()
    local openEmpty = SM.arm(empty, {
        auctionId = "12", increment = 100, cap = 1000,
        currentPrice = 100, currentBidder = "", selfName = "Me", realm = "R",
    }, 0)
    test.eq(openEmpty.bid, 100, "an empty-string bidder opens at the starting price")

    -- Arming when I am already the highest bidder holds instead of re-bidding.
    local already = SM.new()
    local held = SM.arm(already, {
        auctionId = "12", increment = 100, cap = 1000,
        currentPrice = 500, currentBidder = "Me", selfName = "Me", realm = "R",
    }, 0)
    test.eq(held.hold, true, "already leading means no opening bid")
    test.eq(already.leading, true, "already leading is reflected")

    -- Cross-realm self-leading: my own realm suffix is still me, never outbid.
    local cross = SM.new()
    local crossHeld = SM.arm(cross, {
        auctionId = "12", increment = 100, cap = 1000,
        currentPrice = 500, currentBidder = "Me-R", selfName = "Me", realm = "R",
    }, 0)
    test.eq(crossHeld.hold, true, "a same-realm full name holds as self")
    test.eq(cross.leading, true, "cross-realm self is recognised as leading")

    -- The same short name on a different realm is a different player.
    local foreign = SM.new()
    local foreignBid = SM.arm(foreign, {
        auctionId = "12", increment = 100, cap = 1000,
        currentPrice = 500, currentBidder = "Me-OtherRealm", selfName = "Me", realm = "R",
    }, 0)
    test.eq(foreignBid.bid, 600, "a same short name on another realm is outbid")

    -- A cross-realm self echo also confirms leadership without re-bidding.
    local crossEcho = SM.new()
    SM.arm(crossEcho, {
        auctionId = "12", increment = 100, cap = 1000,
        currentPrice = 500, currentBidder = "Other", selfName = "Me", realm = "R",
    }, 0)
    SM.markSent(crossEcho, 0)
    local ce = SM.onPrice(crossEcho, { auctionId = "12", price = 600, bidder = "Me-R" }, 10)
    test.eq(ce.hold, true, "a cross-realm self echo confirms without re-bidding")
    test.eq(crossEcho.leading, true, "the cross-realm echo marks me leading")

    -- Arming against an outbid computes one increment over the other bidder.
    local chasing = SM.new()
    local chase = SM.arm(chasing, {
        auctionId = "12", increment = 100, cap = 1000,
        currentPrice = 500, currentBidder = "Other", selfName = "Me", realm = "R",
    }, 0)
    test.eq(chase.bid, 600, "arming against an outbid counters one increment")

    -- Invalid configuration never arms.
    local bad = SM.new()
    test.eq(SM.arm(bad, { auctionId = "12", increment = 0, cap = 1000, currentPrice = 100 }, 0), nil,
        "a zero increment is rejected")
    test.eq(bad.status, "invalid", "a zero increment marks the data invalid")
    test.eq(SM.statusText(bad), "当前拍卖数据无效", "invalid data has its own text")
    test.eq(SM.arm(SM.new(), { auctionId = "12", increment = 200, cap = 100, currentPrice = 100 }, 0), nil,
        "an increment larger than the cap is rejected")
    test.eq(SM.arm(SM.new(), { increment = 100, cap = 1000, currentPrice = 100 }, 0), nil,
        "a missing auction id is rejected")

    -- An outbid from someone else triggers a counter-bid, then my echo confirms it.
    local run = SM.new()
    SM.arm(run, {
        auctionId = "12", increment = 100, cap = 1000,
        currentPrice = 500, currentBidder = "Other", selfName = "Me", realm = "R",
    }, 0)
    SM.markSent(run, 0)
    local r1 = SM.onPrice(run, { auctionId = "12", price = 700, bidder = "Other" }, 10)
    test.eq(r1.bid, 800, "an outbid is answered with one increment")
    SM.markSent(run, 10)
    test.eq(run.currentPrice, 800, "my counter-bid becomes the current price")
    test.eq(run.leading, false, "a sent counter-bid is not yet confirmed leading")
    local r2 = SM.onPrice(run, { auctionId = "12", price = 800, bidder = "Me" }, 10)
    test.eq(r2.hold, true, "my own echoed bid confirms leadership")
    test.eq(run.leading, true, "the echo makes me leading")

    -- The same price event is never answered twice.
    local dedup = SM.new()
    SM.arm(dedup, { auctionId = "12", increment = 100, cap = 1000, currentPrice = 500, currentBidder = "Other", selfName = "Me", realm = "R" }, 0)
    SM.markSent(dedup, 0)
    SM.onPrice(dedup, { auctionId = "12", price = 700, bidder = "Other" }, 10)
    SM.markSent(dedup, 10)
    test.eq(SM.onPrice(dedup, { auctionId = "12", price = 700, bidder = "Other" }, 10), nil,
        "the same price is never answered twice")

    -- A lower or stale price is ignored.
    local stale = SM.new()
    SM.arm(stale, { auctionId = "12", increment = 100, cap = 1000, currentPrice = 500, currentBidder = "Other", selfName = "Me", realm = "R" }, 0)
    SM.markSent(stale, 0)
    test.eq(SM.onPrice(stale, { auctionId = "12", price = 400, bidder = "Other" }, 10), nil,
        "a lower price is ignored")

    -- A message about another auction is rejected.
    local wrongAuction = SM.new()
    SM.arm(wrongAuction, { auctionId = "12", increment = 100, cap = 1000, currentPrice = 500, currentBidder = "Other", selfName = "Me", realm = "R" }, 0)
    SM.markSent(wrongAuction, 0)
    test.eq(SM.onPrice(wrongAuction, { auctionId = "99", price = 700, bidder = "Other" }, 10), nil,
        "a message for another auction is rejected")

    -- Reaching the cap stops and reports it.
    local capped = SM.new()
    SM.arm(capped, { auctionId = "12", increment = 100, cap = 1000, currentPrice = 900, currentBidder = "Other", selfName = "Me", realm = "R" }, 0)
    SM.markSent(capped, 0)
    test.eq(capped.currentPrice, 1000, "the final bid at the cap is placed")
    test.eq(SM.onPrice(capped, { auctionId = "12", price = 1001, bidder = "Other" }, 10), nil,
        "a price past the cap does not bid")
    test.eq(capped.status, "cap", "past the cap the state stops")
    test.eq(SM.statusText(capped), "已达心理价位", "the cap has its own text")

    -- Throttling: sends within one second are flagged as too soon.
    local throttle = SM.new()
    SM.arm(throttle, { auctionId = "12", increment = 100, cap = 1000, currentPrice = 500, currentBidder = "Other", selfName = "Me", realm = "R" }, 0)
    SM.markSent(throttle, 0)
    test.eq(SM.canSend(throttle, 0.5), false, "a send within one second is throttled")
    test.eq(SM.canSend(throttle, 1.0), true, "a send at one second is allowed")
    test.eq(SM.canSend(throttle, 5.0), true, "a later send is allowed")

    -- Manual stop ends the auto-bid and blocks further bids.
    local manual = SM.new()
    SM.arm(manual, { auctionId = "12", increment = 100, cap = 1000, currentPrice = 500, currentBidder = "Other", selfName = "Me", realm = "R" }, 0)
    SM.stop(manual, "user")
    test.eq(manual.status, "stopped", "a manual stop sets the stopped state")
    test.eq(SM.statusText(manual), "已手动停止", "the stopped state has its own text")
    test.eq(SM.onPrice(manual, { auctionId = "12", price = 700, bidder = "Other" }, 10), nil,
        "a stopped state never bids again")

    -- Every terminal reason maps to the right state and clears the runtime.
    local function stopped(reason, expected)
        local s = SM.new()
        SM.arm(s, { auctionId = "12", increment = 100, cap = 1000, currentPrice = 500, currentBidder = "Other", selfName = "Me", realm = "R" }, 0)
        SM.markSent(s, 0)
        SM.stop(s, reason)
        test.eq(s.status, expected, reason .. " maps to " .. expected)
        test.eq(s.auctionId, nil, reason .. " clears the auction id")
        test.eq(s.increment, nil, reason .. " clears the increment")
        test.eq(s.currentPrice, nil, reason .. " clears the current price")
    end
    stopped("success", "ended")
    stopped("unsold", "ended")
    stopped("cancel", "ended")
    stopped("change", "idle")
    stopped("leave", "idle")
    stopped("reload", "idle")
    stopped("disabled", "idle")
    stopped("hidden", "idle")
    stopped("send-failed", "send-failed")
    stopped("protocol", "protocol")
    stopped("not-raid", "protocol")
    stopped("no-sender", "protocol")
    stopped("invalid-sender", "protocol")

    -- Fresh states are independent memory-only objects.
    local a = SM.new()
    SM.arm(a, { auctionId = "12", increment = 100, cap = 1000, currentPrice = 100, currentBidder = nil, selfName = "Me", realm = "R" }, 0)
    test.eq(SM.new().status, "idle", "a new state is always unarmed regardless of another state's activity")

    -- The seven required UI states (plus the failure states) all have Chinese text.
    test.eq(SM.statusText({ status = "idle" }), "未启用", "idle text")
    test.eq(SM.statusText({ status = "armed", leading = false }), "自动出价中", "armed text")
    test.eq(SM.statusText({ status = "armed", leading = true }), "当前本人领先", "leading text")
    test.eq(SM.statusText({ status = "cap" }), "已达心理价位", "cap text")
    test.eq(SM.statusText({ status = "stopped" }), "已手动停止", "stopped text")
    test.eq(SM.statusText({ status = "ended" }), "拍卖已结束", "ended text")
    test.eq(SM.statusText({ status = "invalid" }), "当前拍卖数据无效", "invalid text")
    test.eq(SM.statusText({ status = "send-failed" }), "发送失败", "send-failed text")
    test.eq(SM.statusText({ status = "protocol" }), "协议异常", "protocol text")

    -- Source-level invariants: the state machine never communicates or persists.
    local handle = io.open("Core/BGNext/ControlledAutoBid.lua", "r")
    local source = handle:read("*a")
    handle:close()
    for _, forbidden in ipairs({
        "BiaoGe", "SendAddonMessage", "SendChatMessage", "C_ChatInfo",
        "CreateFrame", "RegisterEvent", "C_Timer", "SendMail", "random",
    }) do
        test.eq(string.find(source, forbidden, 1, true), nil, "state machine never uses " .. forbidden)
    end
end
