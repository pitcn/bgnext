local function read(path)
    local file = assert(io.open(path, "rb"))
    local value = file:read("*a")
    file:close()
    return value
end

local function reachableTableCount(value, seen)
    if type(value) ~= "table" then return 0 end
    seen = seen or {}
    if seen[value] then return 0 end
    seen[value] = true
    local count = 1
    for key, child in pairs(value) do
        count = count + reachableTableCount(key, seen)
        count = count + reachableTableCount(child, seen)
    end
    return count
end

local function largeHistory(size)
    local result = {}
    for index = 1, size do
        result[index] = {
            rows = {
                { player = "fixture", amount = index },
                { player = "fixture-2", amount = index * 2 },
            },
        }
    end
    return result
end

return function(test)
    BG = { BGNext = {} }
    local cleanup = dofile("Core/BGNext/LegacyHistoryCleanup.lua")

    local preserved = {
        options = { alpha = 0.5 },
        ICC = { boss = "current bill" },
        BGNext = {
            settings = { uiTheme = "preview" },
            wishlist = { localPlayer = true },
            currentSettlement = { raidId = "raid-current" },
            ownCharacters = { retail = {} },
        },
    }
    local saved = {
        History = largeHistory(250),
        HistoryList = largeHistory(250),
        tradeHistory = largeHistory(250),
        mailHistory = largeHistory(250),
        options = preserved.options,
        ICC = preserved.ICC,
        BGNext = preserved.BGNext,
    }

    local present, count = cleanup.detect(saved)
    test.eq(present, true, "legacy history presence is detected")
    test.eq(count, 4, "only the four legacy fields are counted")

    local beforeUnconfirmed = reachableTableCount(saved)
    local changed, reason = cleanup.clear(saved, false)
    test.eq(changed, false, "unconfirmed cleanup changes nothing")
    test.eq(reason, "confirmation-required", "unconfirmed cleanup explains refusal")
    test.eq(reachableTableCount(saved), beforeUnconfirmed, "unconfirmed history remains reachable")
    test.eq(saved.History ~= nil, true, "unconfirmed History remains")
    test.eq(saved.mailHistory ~= nil, true, "unconfirmed mailHistory remains")

    local beforeConfirmed = reachableTableCount(saved)
    changed, count = cleanup.clear(saved, true)
    test.eq(changed, true, "confirmed cleanup succeeds")
    test.eq(count, 4, "confirmed cleanup reports four removed roots")
    test.eq(saved.History, nil, "History is removed")
    test.eq(saved.HistoryList, nil, "HistoryList is removed")
    test.eq(saved.tradeHistory, nil, "tradeHistory is removed")
    test.eq(saved.mailHistory, nil, "mailHistory is removed")
    test.eq(saved.options, preserved.options, "legacy settings are preserved")
    test.eq(saved.ICC, preserved.ICC, "current tables are preserved")
    test.eq(saved.BGNext, preserved.BGNext, "all BGNext data is preserved")
    test.eq(saved.BGNext.wishlist.localPlayer, true, "wishlist is preserved")
    test.eq(saved.BGNext.currentSettlement.raidId, "raid-current", "settlement is preserved")
    test.eq(reachableTableCount(saved) < beforeConfirmed / 10, true,
        "large legacy structures become unreachable after confirmation")

    local reloadedSaved = {}
    for key, value in pairs(saved) do
        reloadedSaved[key] = value
    end
    BG = { BGNext = {} }
    cleanup = dofile("Core/BGNext/LegacyHistoryCleanup.lua")
    test.eq(cleanup.detect(reloadedSaved), false,
        "removed fields stay absent after a SavedVariables save/load simulation")

    local toc = read("BGLite.toc")
    test.eq(toc:find("Core\\BGNext\\LegacyHistoryCleanup.lua", 1, true) ~= nil, true,
        "cleanup module is loaded")
    test.eq(toc:find("Core\\Module\\History.lua", 1, true), nil,
        "legacy table history module stays unloaded")
    test.eq(toc:find("Core\\Module\\TradeHistory.lua", 1, true), nil,
        "legacy trade history module stays unloaded")
    test.eq(toc:find("Core\\Module\\MailHistory.lua", 1, true), nil,
        "legacy mail history module stays unloaded")

    local source = read("Core/BGNext/LegacyHistoryCleanup.lua")
    test.eq(source:find("pairs%(saved%)") == nil, true,
        "runtime does not enumerate the SavedVariables root")
    test.eq(source:find("ipairs%(saved") == nil, true,
        "runtime does not enumerate legacy history contents")
end
