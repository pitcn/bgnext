return function(test)
    BG = { BGNext = {} }
    local EntryMenuLifecycle = dofile("Core/BGNext/EntryMenuLifecycle.lua")

    local lifecycle = EntryMenuLifecycle.new(0.15)
    lifecycle:open()

    test.eq(lifecycle:update(0.15, true, false), true,
        "an open entry menu requests dismissal after the pointer remains outside")

    lifecycle:open()
    test.eq(lifecycle:update(1, true, true), false,
        "the entry menu remains open while the pointer is inside it")

    local resettable = EntryMenuLifecycle.new(0.2)
    resettable:open()
    test.eq(resettable:update(0.19, true, false), false,
        "a brief pointer transition does not dismiss the entry menu")
    test.eq(resettable:update(1, true, true), false,
        "returning to the entry menu resets the outside delay")
    test.eq(resettable:update(0.19, true, false), false,
        "the reset outside delay starts from zero")
    test.eq(resettable:update(0.02, true, false), true,
        "the entry menu dismisses after a fresh complete outside delay")

    resettable:open()
    test.eq(resettable:update(0, false, false), false,
        "a menu closed by its owner disarms without requesting another close")
    test.eq(resettable:update(1, true, false), false,
        "a disarmed lifecycle cannot close a later unrelated menu")

    local handle = assert(io.open("Core/Module/minimap.lua", "r"))
    local minimapSource = handle:read("*a")
    handle:close()
    test.eq(minimapSource:find("EntryMenuLifecycle", 1, true) ~= nil, true,
        "the minimap entry menu uses the shared lifecycle controller")
    test.eq(minimapSource:find("entryMenuLifecycle:update", 1, true) ~= nil, true,
        "the live entry-menu watcher delegates each frame to the lifecycle controller")
    test.eq(minimapSource:find("GetMinimapButton", 1, true) ~= nil, true,
        "the minimap button remains an inside target while moving into the menu")

    local tocHandle = assert(io.open("BGLite.toc", "r"))
    local toc = tocHandle:read("*a")
    tocHandle:close()
    local lifecyclePos = toc:find("Core\\BGNext\\EntryMenuLifecycle.lua", 1, true)
    local minimapPos = toc:find("Core\\Module\\minimap.lua", 1, true)
    test.eq(lifecyclePos ~= nil and minimapPos ~= nil and lifecyclePos < minimapPos, true,
        "the lifecycle controller loads before the minimap runtime")
end
