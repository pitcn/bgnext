return function(test)
    BG = { BGNext = {} }
    dofile("Core/BGNext/AuctionPresetStore.lua")
    local UI = dofile("Core/BGNext/AuctionBidUI.lua")

    -- Chinese labels for every visible control.
    test.eq(UI.LABELS.increment, "每次加价", "increment label")
    test.eq(UI.LABELS.cap, "心理最高价", "cap label")
    test.eq(UI.LABELS.arm, "启用自动出价", "arm button label")
    test.eq(UI.LABELS.stop, "停止自动出价", "stop button label")

    -- The two inputs are editable only while not armed.
    test.eq(UI.inputsLocked("idle"), false, "idle inputs are editable")
    test.eq(UI.inputsLocked("armed"), true, "armed inputs are locked")
    test.eq(UI.inputsLocked("stopped"), false, "stopped inputs are editable again")
    test.eq(UI.inputsLocked("ended"), false, "ended inputs are editable")
    test.eq(UI.inputsLocked("cap"), false, "cap inputs are editable")
    test.eq(UI.inputsLocked("invalid"), false, "invalid inputs are editable")
    test.eq(UI.inputsLocked(nil), false, "a missing status is treated as editable")

    -- The button toggles between arming and stopping.
    test.eq(UI.buttonText("armed"), "停止自动出价", "armed shows the stop label")
    test.eq(UI.buttonText("idle"), "启用自动出价", "idle shows the arm label")
    test.eq(UI.buttonText("stopped"), "启用自动出价", "stopped shows the arm label")
    test.eq(UI.isArmed("armed"), true, "armed is detected")
    test.eq(UI.isArmed("idle"), false, "idle is not armed")

    -- The built-in auto-bid blocks my arm button (mutual exclusion).
    test.eq(UI.armBlocked(nil), nil, "no frame is not blocked")
    test.eq(UI.armBlocked({ isAuto = false }), nil, "an idle built-in state is not blocked")
    test.eq(UI.armBlocked({ isAuto = true }), "内置自动出价已开启，请先关闭", "a running built-in auto-bid blocks my arm")

    -- Reading the two inputs validates and normalises them locally.
    local ok = UI.readConfig("100", "5000")
    test.eq(ok.increment, 100, "a valid increment is read")
    test.eq(ok.cap, 5000, "a valid cap is read")
    test.eq(ok.error, nil, "no error on valid input")
    test.eq(UI.readConfig("100", "5000").increment, 100, "numeric strings are coerced")
    test.eq(UI.readConfig("0", "5000").error, "increment", "a zero increment is rejected")
    test.eq(UI.readConfig("abc", "5000").error, "increment", "a non-numeric increment is rejected")
    test.eq(UI.readConfig("100", "nope").error, "cap", "a non-numeric cap is rejected")
    test.eq(UI.readConfig("100", "0").error, "cap", "a zero cap is rejected")
    test.eq(UI.readConfig("5000", "100").error, "cap-too-small", "a cap below the increment is rejected")

    -- Every rejected input has a Chinese explanation.
    test.eq(UI.errorText("increment"), "每次加价金额无效", "increment error text")
    test.eq(UI.errorText("cap"), "心理最高价无效", "cap error text")
    test.eq(UI.errorText("cap-too-small"), "心理最高价不能低于每次加价", "cap-too-small error text")
    test.eq(UI.errorText(nil), "", "an unknown error has no text")

    -- Layout is a single source of numeric constants, compact enough to fit the bid frame.
    test.eq(type(UI.layout), "table", "layout constants are centralised")
    test.eq(type(UI.layout.regionWidth), "number", "the region width is numeric")
    test.eq(type(UI.layout.regionHeight), "number", "the region height is numeric")
    test.eq(UI.layout.regionWidth <= 310, true, "the region fits the bid frame width")

    -- Boundary test: every control fits inside the region and none overlaps another.
    local r = UI.rects()
    local rects = { r.incrementLabel, r.incrementEdit, r.capLabel, r.capEdit, r.button, r.status }
    local function overlaps(a, b)
        return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
    end
    for i, rc in ipairs(rects) do
        test.eq(rc.x >= 0 and rc.y >= 0, true, "rect " .. i .. " starts inside the region")
        test.eq(rc.x + rc.w <= UI.layout.regionWidth, true, "rect " .. i .. " fits the region width")
        test.eq(rc.y + rc.h <= UI.layout.regionHeight, true, "rect " .. i .. " fits the region height")
    end
    for i = 1, #rects do
        for j = i + 1, #rects do
            test.eq(overlaps(rects[i], rects[j]), false, "rect " .. i .. " and " .. j .. " do not overlap")
        end
    end
    test.eq(r.incrementLabel.w, UI.layout.labelWidth, "labelWidth is used by the increment label")
    test.eq(r.capLabel.w, UI.layout.labelWidth, "labelWidth is used by the cap label")

    -- Source-level invariants: the UI is presentation only, no side effects.
    local handle = io.open("Core/BGNext/AuctionBidUI.lua", "r")
    local source = handle:read("*a")
    handle:close()
    for _, forbidden in ipairs({
        "BiaoGe", "CreateFrame", "SendAddonMessage", "SendChatMessage",
        "C_ChatInfo", "RegisterEvent", "C_Timer", "random", "SetPoint",
    }) do
        test.eq(string.find(source, forbidden, 1, true), nil, "UI never uses " .. forbidden)
    end
end
