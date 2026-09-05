return function(test)
    BG = { BGNext = {} }
    local store = dofile("Core/BGNext/LeaderToolsStore.lua")
    local root = {}

    local clean = store.ensure(root, 1000)
    test.eq(type(clean.expenseTemplates), "table", "template store is initialized")
    test.eq(type(clean.localHistory), "table", "history store is initialized")
    test.eq(clean.historyRetentionDays, 90, "history defaults to ninety days")

    local ok, reason = store.upsertTemplate(root, {
        name = "常用补贴",
        items = { { name = "T补贴", amount = 500 }, { name = "指挥补贴", amount = 300 } },
    }, false)
    test.eq(ok, true, reason or "valid template is stored")
    test.eq(#store.listTemplates(root), 1, "one template stored")
    test.eq(store.upsertTemplate(root, { name = "常用补贴", items = { { name = "重复", amount = 1 } } }, false), false,
        "duplicate name needs explicit replacement")
    test.eq(store.upsertTemplate(root, { name = "坏金额", items = { { name = "项目", amount = -1 } } }, false), false,
        "negative amount rejected")
    test.eq(store.upsertTemplate(root, { name = "小数", items = { { name = "项目", amount = 1.5 } } }, false), false,
        "fractional amount rejected")
    test.eq(store.replaceTemplate(root, 1, { name = "团长常用", items = { { name = "T补贴", amount = 500 }, { name = "指挥补贴", amount = 300 } } }), true,
        "selected template can be atomically renamed and replaced")
    test.eq(store.listTemplates(root)[1].name, "团长常用", "replacement updates selected template")

    local plan = store.planExpenseApply(store.listTemplates(root)[1], {
        { name = "已有", amount = 50 }, { name = "", amount = "" }, { name = "", amount = nil },
    })
    test.eq(#plan, 2, "application plans only enough empty rows")
    test.eq(plan[1].row, 2, "existing row is never overwritten")
    test.eq(plan[2].amount, 300, "amount is preserved")
    local noPlan, noReason = store.planExpenseApply(store.listTemplates(root)[1], { { name = "", amount = "" } })
    test.eq(noPlan, nil, "insufficient rows reject the entire operation")
    test.eq(noReason, "insufficient-space", "insufficient rows are explained")

    local exported = store.exportTemplates(root)
    local preview = store.previewImport(exported)
    test.eq(#preview, 1, "own export previews")
    test.eq(preview[1].items[1].name, "T补贴", "round trip keeps item name")
    local before = #store.listTemplates(root)
    test.eq(store.importTemplates(root, "BGNT-E1\ntemplate\t坏\nitem\t坏\t-1", true), false,
        "invalid import is rejected")
    test.eq(#store.listTemplates(root), before, "invalid import is atomic")
    test.eq(store.importTemplates(root, exported, false), true, "preview does not mutate")
    test.eq(#store.listTemplates(root), before, "preview keeps existing templates")

    test.eq(store.appendHistory(root, { itemId = 123, amount = 500, sourceFb = "ICC", time = 1000, mine = true }, false, 1000), false,
        "disabled history records nothing")
    test.eq(store.appendHistory(root, { itemId = 123, amount = 500, sourceFb = "ICC", time = 1000, mine = true }, true, 1000), true,
        "enabled history accepts minimal row")
    test.eq(store.appendHistory(root, { itemId = 123, amount = 500, sourceFb = "ICC", time = 1000, mine = true }, true, 1000), false,
        "identical history row is deduplicated")
    test.eq(root.leaderTools.localHistory[1].player, nil, "history never keeps player names")
    test.eq(store.appendHistory(root, { itemId = 123, amount = 700, sourceFb = "ICC", time = 1100, mine = false }, true, 1100), true,
        "second price is accepted")
    local summary = store.summarizeHistory(root, 1200)
    test.eq(summary.items[123].count, 2, "summary counts transactions")
    test.eq(summary.items[123].min, 500, "summary has minimum")
    test.eq(summary.items[123].max, 700, "summary has maximum")
    test.eq(summary.mineTotal, 500, "self total uses boolean identity only")

    root.leaderTools.historyRetentionDays = 30
    store.purgeHistory(root, 1000 + 31 * 86400)
    test.eq(#root.leaderTools.localHistory, 0, "retention purges old rows")
    store.clearTemplates(root, true)
    test.eq(#store.listTemplates(root), 0, "confirmed clear deletes templates")
end
