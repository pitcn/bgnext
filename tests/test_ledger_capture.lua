return function(test)
    BG = { BGNext = {} }
    dofile("Core/BGNext/PlayerIdentity.lua")
    local Capture = dofile("Core/BGNext/LedgerCapture.lua")

    local state = Capture.new({
        maxLines = 2,
        maxEntries = 2,
        maxLineBytes = 10,
        timeout = 50,
    })
    test.eq(Capture.isActive(state, 100), false, "capture starts inactive")
    test.eq(Capture.appendLine(state, "ignored", 100), false, "inactive capture rejects chat")
    test.eq(Capture.parseMoney("500"), 500, "a bounded reconciliation amount is accepted")
    test.eq(Capture.parseMoney("1e309"), nil, "an infinite reconciliation amount is rejected")
    test.eq(Capture.parseMoney("1.5"), nil, "a fractional reconciliation amount is rejected")
    test.eq(Capture.parseMoney("10000001"), nil, "an excessive reconciliation amount is rejected")
    test.eq(Capture.parseItemID("123"), 123, "a bounded item id is accepted")
    test.eq(Capture.parseItemID("0"), nil, "a non-positive item id is rejected")
    test.eq(Capture.parseItemID("1e309"), nil, "an infinite item id is rejected")

    Capture.start(state, 100)
    test.eq(Capture.isActive(state, 100), true, "the user can start a capture")
    test.eq(Capture.bindSource(state, "Alice", "Realm", { "Alice", "Bob" }, 101), true,
        "the first current raid member becomes the source")
    test.eq(Capture.acceptSource(state, "Alice-Realm", "Realm", { "Alice" }, 102), true,
        "the canonical bound source is accepted")
    test.eq(Capture.acceptSource(state, "Bob", "Realm", { "Alice", "Bob" }, 102), false,
        "another raid member cannot inject into the capture")
    test.eq(Capture.acceptSource(state, "Alice", "Realm", { "Bob" }, 102), false,
        "a source that left the raid is rejected")

    test.eq(Capture.appendLine(state, "1234567890", 103), true, "a bounded chat line is accepted")
    test.eq(Capture.appendLine(state, "second", 104), true, "a second bounded chat line is accepted")
    test.eq(Capture.appendLine(state, "third", 105), false, "line capacity stops and clears capture")
    test.eq(Capture.isActive(state, 105), false, "overflow leaves capture inactive")
    test.eq(state.lineCount, 0, "overflow clears the chat counter")
    test.eq(state.lines, nil, "raw chat text is never retained")

    Capture.start(state, 200)
    test.eq(Capture.bindSource(state, "Alice", "Realm", { "Alice" }, 201), true,
        "a stopped capture can be started again")
    test.eq(Capture.appendLine(state, "12345678901", 202), false, "an oversized line is rejected")
    test.eq(Capture.isActive(state, 202), false, "an oversized line stops capture")

    Capture.start(state, 300)
    test.eq(Capture.bindSource(state, "Alice", "Realm", { "Alice" }, 301), true,
        "source binding works after reset")
    test.eq(Capture.appendEntry(state, { itemID = 1 }, 302), true, "a bounded entry is accepted")
    test.eq(Capture.appendEntry(state, { itemID = 2 }, 303), true, "a second entry is accepted")
    test.eq(state.entries, nil, "the policy counts entries without retaining their contents")
    test.eq(Capture.appendEntry(state, { itemID = 3 }, 304), false, "entry capacity stops capture")
    test.eq(state.entryCount, 0, "entry overflow clears the entry counter")

    Capture.start(state, 400)
    test.eq(Capture.isActive(state, 449), true, "capture stays active inside its timeout")
    test.eq(Capture.isActive(state, 450), false, "capture expires at its deadline")
    test.eq(state.sourceKey, nil, "expiry clears the bound source")

    Capture.start(state, 500)
    Capture.bindSource(state, "Alice", "Realm", { "Alice" }, 501)
    Capture.appendLine(state, "line", 502)
    Capture.stop(state)
    test.eq(Capture.isActive(state, 502), false, "manual stop deactivates capture")
    test.eq(state.lineCount, 0, "manual stop clears the chat counter")
    test.eq(state.entryCount, 0, "manual stop clears the entry counter")
end
