return function(test)
    BG = { BGNext = {} }
    local queue = dofile("Core/BGNext/AuctionQueue.lua")

    -- A fake scheme resolver: item 1001 is an override, 1002 falls back to the
    -- base price, and anything else is unresolved (requires manual input).
    local function resolvePrice(itemId)
        if itemId == 1001 then return { price = 900, source = "override" } end
        if itemId == 1002 then return { price = 500, source = "base" } end
        return nil
    end

    -- --- Add / remove / reorder -------------------------------------------

    local q = queue.create("raid:ULD")
    test.eq(queue.size(q), 0, "new queue is empty")

    local a = queue.add(q, { itemId = 1001, link = "item:1001", quantity = 1 })
    local b = queue.add(q, { itemId = 1002, link = "item:1002" })
    local c = queue.add(q, { itemId = 1003, link = "item:1003", quantity = 2 })
    test.eq(type(a), "number", "add returns an id")
    test.eq(queue.size(q), 3, "three items queued")
    test.eq(q.order[1], a, "first added stays first")
    test.eq(q.order[3], c, "third added stays third")
    test.eq(q.items[b].quantity, 1, "quantity defaults to one")

    -- Invalid item id and invalid quantity are rejected without mutating.
    test.eq(queue.add(q, { itemId = 0, link = "item:0" }), nil, "zero item id rejected")
    test.eq(queue.add(q, { itemId = 1.5, link = "item:1" }), nil, "fractional id rejected")
    test.eq(queue.add(q, { itemId = 2000, quantity = 0 }), nil, "zero quantity rejected")
    test.eq(queue.size(q), 3, "rejected adds do not grow the queue")

    test.eq(queue.remove(q, b), true, "remove middle item")
    test.eq(queue.size(q), 2, "size after remove")
    test.eq(q.order[1], a, "order preserved after remove")
    test.eq(q.order[2], c, "remaining order compacted")
    test.eq(queue.remove(q, b), false, "removing twice is a no-op")

    -- Re-queue the middle item and exercise relative moves.
    b = queue.add(q, { itemId = 1002, link = "item:1002" }) -- order [a, c, b]
    test.eq(queue.move(q, b, -1), true, "move b up")
    test.eq(q.order[1], a, "a still first")
    test.eq(q.order[2], b, "b moved up to middle")
    test.eq(q.order[3], c, "c shifted down")
    test.eq(queue.move(q, a, -1), false, "moving first up clamps")
    test.eq(q.order[1], a, "first unchanged after clamp")
    test.eq(queue.move(q, c, 1), false, "moving last down clamps")
    test.eq(q.order[3], c, "last unchanged after clamp")
    test.eq(queue.move(q, 999, 1), false, "unknown id is a no-op")

    test.eq(queue.moveTo(q, c, 1), true, "moveTo front")
    test.eq(q.order[1], c, "c at front after moveTo")
    test.eq(q.order[3], b, "b at back after moveTo")

    -- --- Projection: price prefill + source --------------------------------

    local rows = queue.project(q, resolvePrice)
    test.eq(#rows, 3, "projects every queued item in order")
    test.eq(rows[1].itemId, 1003, "projection preserves queue order")
    test.eq(rows[1].price, nil, "unresolved item has no price")
    test.eq(rows[1].source, "manual", "unresolved item asks for manual input")
    test.eq(rows[2].itemId, 1001, "second row is the override item")
    test.eq(rows[2].price, 900, "override price resolved")
    test.eq(rows[2].source, "override", "override source kept")
    test.eq(rows[3].itemId, 1002, "third row is the base item")
    test.eq(rows[3].price, 500, "base price resolved")
    test.eq(rows[3].source, "base", "base source kept")
    test.eq(rows[2].link, "item:1001", "link surfaced for tooltip")
    test.eq(rows[1].quantity, 2, "quantity surfaced")

    -- A numeric resolver (source omitted) is treated as a base price.
    local plainRows = queue.project(q, function(itemId)
        if itemId == 1002 then return 500 end
        return nil
    end)
    test.eq(plainRows[3].price, 500, "numeric resolver accepted")
    test.eq(plainRows[3].source, "base", "numeric resolver defaults to base")

    -- --- Per-item manual confirm gating ------------------------------------

    local allowed = { isController = true, inCombat = false, auctionInProgress = false }
    test.eq(queue.gate(rows[2], allowed), nil, "controller with a resolved price is allowed")
    test.eq(queue.gate(rows[3], allowed), nil, "base price is allowed too")

    test.eq(queue.gate(rows[2], { isController = false }), "no-permission", "non-controller blocked")
    test.eq(queue.gate(rows[2], { isController = true, inCombat = true }),
        "combat", "combat blocks confirm")
    test.eq(queue.gate(rows[2], { isController = true, auctionInProgress = true }),
        "auction-busy", "an in-progress auction blocks confirm")
    test.eq(queue.gate(rows[1], allowed), "price-unresolved",
        "an unresolved price blocks confirm and asks for manual input")
    test.eq(queue.gate(nil, allowed), "invalid-item", "a missing row is an invalid item")

    -- New gate reasons: an in-flight pending confirm and a changed scope both
    -- block a confirm, and a non-positive non-integer price is invalid.
    test.eq(queue.gate(rows[2], { isController = true, inCombat = false, auctionInProgress = false, pendingStart = true }),
        "pending-start", "an existing pending start blocks confirm")
    test.eq(queue.gate(rows[2], { isController = true, inCombat = false, auctionInProgress = false, scopeChanged = true }),
        "scope-changed", "a changed raid/table scope blocks confirm")
    local fractional = { id = 1, itemId = 1001, link = "item:1001", quantity = 1, price = 100.5, source = "base" }
    test.eq(queue.gate(fractional, allowed), "invalid-item", "a fractional price is invalid")

    -- --- Consume / quantity / manual price ----------------------------------

    local d = queue.create("raid:ULD")
    local q2 = queue.add(d, { itemId = 1001, link = "item:1001", quantity = 2 })
    test.eq(queue.decrement(d, q2), 1, "decrement from two leaves one")
    test.eq(d.items[q2].quantity, 1, "quantity reduced by exactly one")
    test.eq(queue.decrement(d, q2), nil, "decrement from one removes the row")
    test.eq(queue.size(d), 0, "row removed at quantity zero")
    test.eq(queue.decrement(d, q2), false, "decrement on an unknown id is a no-op")

    local q3 = queue.add(d, { itemId = 1002, link = "item:1002", quantity = 1 })
    test.eq(queue.setQuantity(d, q3, 4), true, "setQuantity accepts a valid value")
    test.eq(d.items[q3].quantity, 4, "setQuantity writes the exact value")
    test.eq(queue.setQuantity(d, q3, 0), false, "setQuantity rejects zero")
    test.eq(queue.setQuantity(d, q3, 1.5), false, "setQuantity rejects a fraction")
    test.eq(queue.adjustQuantity(d, q3, -1), 3, "adjustQuantity decrements")
    test.eq(queue.adjustQuantity(d, q3, 1), 4, "adjustQuantity increments")
    test.eq(queue.adjustQuantity(d, q3, -999), false, "adjustQuantity clamps below the valid range")

    test.eq(queue.setPrice(d, q3, 1200), true, "setPrice records a manual price")
    test.eq(d.items[q3].manualPrice, 1200, "manual price stored on the row")
    test.eq(queue.setPrice(d, q3, 0), false, "setPrice rejects a non-positive price")
    test.eq(queue.setPrice(d, q3, 12.5), false, "setPrice rejects a fractional price")
    test.eq(queue.setPrice(d, q3, nil), true, "setPrice clears the manual price")
    test.eq(d.items[q3].manualPrice, nil, "manual price cleared")

    -- Manual price resolves an otherwise unresolved row in projection.
    local manual = queue.create("raid:ULD")
    local qm = queue.add(manual, { itemId = 1003, link = "item:1003" })
    local projected = queue.project(manual, resolvePrice)
    test.eq(projected[1].price, nil, "unresolved row has no price")
    test.eq(projected[1].source, "manual", "unresolved row asks for manual input")
    queue.setPrice(manual, qm, 1500)
    projected = queue.project(manual, resolvePrice)
    test.eq(projected[1].price, 1500, "manual price resolves the row")
    test.eq(projected[1].source, "manual", "manual price keeps the manual source")

    -- --- Cleanup boundary ---------------------------------------------------

    test.eq(queue.scopeChanged(q, "raid:ULD"), false, "same scope is retained")
    test.eq(queue.scopeChanged(q, "raid:ICC"), true, "a different raid/table scope is a change")
    queue.clear(q)
    test.eq(queue.size(q), 0, "clear empties the queue")
    test.eq(#queue.project(q, resolvePrice), 0, "projected after clear is empty")
end
