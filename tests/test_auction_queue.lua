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

    -- --- Cleanup boundary ---------------------------------------------------

    test.eq(queue.scopeChanged(q, "raid:ULD"), false, "same scope is retained")
    test.eq(queue.scopeChanged(q, "raid:ICC"), true, "a different raid/table scope is a change")
    queue.clear(q)
    test.eq(queue.size(q), 0, "clear empties the queue")
    test.eq(#queue.project(q, resolvePrice), 0, "projected after clear is empty")
end
