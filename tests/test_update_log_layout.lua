return function(test)
    BG = { BGNext = {} }
    local layout = dofile("Core/BGNext/UpdateLogLayout.lua")

    test.eq(layout.height({ 18, 36, 54 }, 15, 35, 20, 100), 193,
        "popup height includes wrapped text, inter-line gaps and bottom padding")
    test.eq(layout.height({}, 15, 35, 20, 100), 100,
        "empty popup respects minimum height")
    test.eq(layout.height({ 18, -5, "bad" }, 10, 30, 20, 0), 88,
        "invalid measured heights cannot shrink or break the popup")
end
