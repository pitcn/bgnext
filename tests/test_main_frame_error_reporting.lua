return function(test)
    local callback, reported
    local env = setmetatable({
        BG = { BGNext = {}, Init = function(fn) callback = fn end,
            Init2 = function() end, RegisterEvent = function() end },
        C_AddOns = { IsAddOnLoaded = function() return false end },
        C_PartyInfo = {},
        CreateFrame = function() error("fixture main-frame construction failure") end,
        geterrorhandler = function() return function(message) reported = message end end,
    }, { __index = _G })
    local chunk = assert(loadfile("Core/BiaoGe.lua")); setfenv(chunk, env)
    chunk("BGNext", {})
    test.eq(type(callback), "function", "real main initialization callback captured")
    callback()
    test.eq(type(reported), "string", "failed construction reaches the game's error handler")
    test.eq(reported:find("fixture main-frame construction failure", 1, true) ~= nil, true,
        "original failure is reported instead of disappearing behind a generic label")
end
