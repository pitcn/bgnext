return function(test)
    BG = { BGNext = {} }
    local Store = dofile("Core/BGNext/AuctionPresetStore.lua")

    -- Amounts must be positive integers (numbers or digit-only strings).
    test.eq(Store.validateMoney(100), 100, "a positive integer is valid")
    test.eq(Store.validateMoney("100"), 100, "a numeric string is coerced")
    test.eq(Store.validateMoney("0007"), 7, "leading zeros still parse as a number")
    test.eq(Store.validateMoney(0), nil, "zero is rejected")
    test.eq(Store.validateMoney(-5), nil, "a negative amount is rejected")
    test.eq(Store.validateMoney(1.5), nil, "a fractional amount is rejected")
    test.eq(Store.validateMoney("abc"), nil, "a non-numeric string is rejected")
    test.eq(Store.validateMoney(""), nil, "an empty string is rejected")
    test.eq(Store.validateMoney("12.5"), nil, "a fractional string is rejected")
    test.eq(Store.validateMoney(nil), nil, "a missing amount is rejected")
    test.eq(Store.validateMoney(2147483647), 2147483647, "the copper cap is allowed")
    test.eq(Store.validateMoney(2147483648), nil, "an amount over the copper cap is rejected")
    test.eq(Store.validateIncrement(50), 50, "an increment follows the same rules")
    test.eq(Store.validateIncrement(0), nil, "a zero increment is rejected")

    -- get returns the two configured fields, defaulting missing ones to nil.
    test.eq(Store.get({}).increment, nil, "an empty store has no increment")
    test.eq(Store.get({}).cap, nil, "an empty store has no cap")
    test.eq(Store.get({ increment = 100, cap = 5000 }).increment, 100, "get reads the increment")
    test.eq(Store.get({ increment = 100, cap = 5000 }).cap, 5000, "get reads the cap")
    test.eq(Store.get(nil).increment, nil, "a missing table is safe to read")

    -- set persists only the two whitelisted fields.
    local p = {}
    local saved = Store.set(p, { increment = 100, cap = 5000 })
    test.eq(saved.increment, 100, "set returns the saved increment")
    test.eq(saved.cap, 5000, "set returns the saved cap")
    test.eq(p.increment, 100, "the increment lands in the presets table")
    test.eq(p.cap, 5000, "the cap lands in the presets table")

    -- An illegal value is rejected without touching the stored value.
    test.eq(Store.set(p, { increment = 0 }), nil, "an illegal increment is rejected")
    test.eq(p.increment, 100, "a rejected increment leaves the old value")
    test.eq(Store.set(p, { cap = "nope" }), nil, "an illegal cap is rejected")
    test.eq(p.cap, 5000, "a rejected cap leaves the old value")

    -- Unknown fields are never written, even when a known field is also set.
    Store.set(p, { increment = 200, somethingElse = "x", history = {}, cap = 6000 })
    test.eq(p.increment, 200, "a whitelisted field still updates")
    test.eq(p.cap, 6000, "the cap still updates")
    test.eq(p.somethingElse, nil, "unknown fields are never written")
    test.eq(p.history, nil, "unrelated data is never written")

    -- reset clears both configured values.
    Store.reset(p)
    test.eq(p.increment, nil, "reset clears the increment")
    test.eq(p.cap, nil, "reset clears the cap")

    -- Source-level invariants: the store is pure local config with no side effects.
    local handle = io.open("Core/BGNext/AuctionPresetStore.lua", "r")
    local source = handle:read("*a")
    handle:close()
    for _, forbidden in ipairs({
        "BiaoGe", "SendAddonMessage", "SendChatMessage", "C_ChatInfo",
        "CreateFrame", "SendMail", "RegisterEvent",
    }) do
        test.eq(string.find(source, forbidden, 1, true), nil, "store never uses " .. forbidden)
    end
end
