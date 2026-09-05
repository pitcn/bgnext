return function(test)
    BG = { BGNext = {} }
    local loaded, MailSendAttempt = pcall(dofile, "Core/BGNext/MailSendAttempt.lua")
    test.eq(loaded, true, "mail send-attempt module loads")
    if not loaded then return end

    local tracker = MailSendAttempt.new()
    local enteredGold = 300
    local snapshot = tracker:begin({
        fullName = "收件人-本服",
        name = "收件人",
        colorName = "|cff00ff00收件人|r",
        money = enteredGold * 10000,
    })
    test.eq(snapshot.money, 3000000, "the attempted copper amount is frozen")

    -- Editing the UI after SendMail must not change the pending attempt.
    enteredGold = 999
    test.eq(tracker:consume("OTHER_MESSAGE", "ERR_MAIL_SENT"), nil,
        "unrelated UI messages do not consume the attempt")
    local confirmed = tracker:consume("ERR_MAIL_SENT", "ERR_MAIL_SENT")
    test.eq(confirmed.fullName, "收件人-本服", "success returns the frozen recipient")
    test.eq(confirmed.money, 3000000, "success returns the frozen amount, not the edited input")
    test.eq(confirmed.money / 10000, 300, "the settlement amount stays in gold")
    test.eq(enteredGold, 999, "the test actually changed the later input value")
    test.eq(tracker:consume("ERR_MAIL_SENT", "ERR_MAIL_SENT"), nil,
        "a success event consumes one attempt exactly once")

    local first = tracker:begin({ fullName = "先发送", name = "先发送", colorName = "先发送", money = 1000000 })
    local overlapping = tracker:begin({ fullName = "后发送", name = "后发送", colorName = "后发送", money = 2000000 })
    test.eq(first.fullName, "先发送", "the first mail becomes the only in-flight attempt")
    test.eq(overlapping, nil, "a second mail cannot start before the first has a result")
    test.eq(tracker:isPending(), true, "the active attempt is explicitly observable")
    local confirmedFirst = tracker:consume("ERR_MAIL_SENT", "ERR_MAIL_SENT")
    test.eq(confirmedFirst.fullName, "先发送", "success stays paired with the active recipient")
    test.eq(tracker:isPending(), false, "success releases the single-flight gate")
    local second = tracker:begin({ fullName = "后发送", name = "后发送", colorName = "后发送", money = 2000000 })
    test.eq(second.fullName, "后发送", "the next mail can start after confirmation")

    tracker:clear()
    test.eq(tracker:consume("ERR_MAIL_SENT", "ERR_MAIL_SENT"), nil,
        "stopping after a failed send rejects its late success")
    local afterFailure = tracker:begin({ fullName = "另一人", name = "另一人", colorName = "另一人", money = 5000000 })
    test.eq(afterFailure.fullName, "另一人", "a later batch is not poisoned by the failed send")
    test.eq(tracker:consume("ERR_MAIL_SENT", "ERR_MAIL_SENT").fullName, "另一人",
        "the later success is attributed to the later recipient")
end
