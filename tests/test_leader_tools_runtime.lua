return function(test)
    BG = { BGNext = {} }
    BG.BGNext.LeaderToolsStore = dofile("Core/BGNext/LeaderToolsStore.lua")
    BG.BGNext.LeaderToolsView = dofile("Core/BGNext/LeaderToolsView.lua")
    local runtime = dofile("Core/BGNext/LeaderToolsRuntime.lua")

    local saved = {
        boss1 = { zhuangbei1 = "Item A", maijia1 = "Me", jine1 = "500" },
        boss2 = { zhuangbei1 = "T补贴", jine1 = "100", zhuangbei2 = "", jine2 = "" },
        boss3 = { jine4 = "2" },
    }
    local frames = {
        boss2 = {
            zhuangbei1 = { GetText = function() return "T补贴" end, SetText = function() end },
            jine1 = { GetText = function() return "100" end, SetText = function() end },
            zhuangbei2 = { GetText = function() return "" end, SetText = function(self, value) self.value = value end },
            jine2 = { GetText = function() return "" end, SetText = function(self, value) self.value = value end },
        },
    }
    local rows = runtime.collectExpenseRows({ table = saved, frames = frames, expenseBoss = 2, slots = 2 })
    test.eq(rows[1].name, "T补贴", "expense adapter reads existing row")
    local ok, reason = runtime.applyExpenseTemplate({
        table = saved, frames = frames, expenseBoss = 2, slots = 2,
    }, { name = "单项", items = { { name = "指挥补贴", amount = 300 } } })
    test.eq(ok, true, reason or "template applies")
    test.eq(saved.boss2.zhuangbei2, "指挥补贴", "template writes saved bill")
    test.eq(saved.boss2.jine2, "300", "template amount is written as gold text")
    test.eq(frames.boss2.zhuangbei2.value, "指挥补贴", "visible row updates")

    local root = { leaderTools = { expenseTemplates = {}, localHistory = {}, historyRetentionDays = 90 } }
    local count = runtime.captureHistory({
        root = root, enabled = true, now = 1000, fb = "ICC", table = saved, bosses = 1,
        slotsOf = function() return 1 end,
        itemIdOf = function() return 123 end,
        isMine = function(buyer) return buyer == "Me" end,
    })
    test.eq(count, 1, "explicit capture saves one valid sale")
    test.eq(root.leaderTools.localHistory[1].mine, true, "capture stores only self boolean")

    local sent = 0
    local button = {
        owner = nil,
        enabled = true,
        GetScript = function(self) return self.original end,
        SetScript = function(self, _, fn) self.click = fn end,
        IsEnabled = function(self) return self.enabled end,
    }
    local frame = {
        money = 500, IsEnd = false, ButtonSendMyMoney = button,
        myMoneyEdit = { GetText = function() return "5000" end },
    }
    button.owner = frame
    button.original = function() sent = sent + 1 end
    local asked
    runtime.wrapBidButton(frame, {
        featureEnabled = function() return true end,
        confirm = function(pending) asked = pending return true end,
    })
    button.click(button)
    test.eq(sent, 0, "risky bid waits for confirmation")
    test.eq(type(asked), "table", "risky bid creates bounded pending action")
    frame.money = 600
    test.eq(runtime.acceptRisk(asked), false, "changed price invalidates old confirmation")
    test.eq(sent, 0, "invalidated confirmation sends nothing")
    frame.money = 500
    button.click(button)
    test.eq(runtime.acceptRisk(asked), true, "unchanged risky bid can be accepted")
    test.eq(sent, 1, "accept reuses original send handler once")
    test.eq(runtime.acceptRisk(asked), false, "the same confirmation cannot send twice")

    button.click(button)
    frame.isPaused = true
    test.eq(runtime.acceptRisk(asked), false, "confirmation opened before a pause cannot send")
    test.eq(sent, 1, "paused auction leaves send count unchanged")
    frame.isPaused = false
    button.click(button)
    frame.remaining = 1
    test.eq(runtime.acceptRisk(asked), false, "confirmation cannot send after the bidding UI closes")
    test.eq(sent, 1, "closed bidding window leaves send count unchanged")
    frame.remaining = 10

    for _, path in ipairs({
        "Core/BGNext/LeaderToolsStore.lua", "Core/BGNext/LeaderToolsView.lua",
        "Core/BGNext/LeaderToolsRuntime.lua", "Core/BGNext/LeaderToolsUI.lua",
    }) do
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a") file:close()
        for _, forbidden in ipairs({ "SendAddonMessage", "SendChatMessage", "C_ChatInfo", "CHAT_MSG" }) do
            test.eq(source:find(forbidden, 1, true), nil, path .. " adds no communication: " .. forbidden)
        end
    end
end
