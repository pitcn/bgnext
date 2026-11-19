return function(test)
    BG = { BGNext = {} }
    local compat = dofile("Core/BGNext/ClientCompat.lua")
    local enumeratorCalls = 0
    local attached = {}
    local function newButton(name)
        return { HookScript = function(_, method) attached[#attached + 1] = name .. ":" .. method end }
    end
    local function frameWith(...)
        local items = { ... }
        return { EnumerateItems = function() return ipairs(items) end }
    end
    local mixin = { OnClick = function() end, OnEnter = function() end, OnLeave = function() end,
        OnLoad = function() end }
    local api = {
        hooksecurefunc = function() end,
        ContainerFrameItemButtonMixin = mixin,
        NUM_CONTAINER_FRAMES = 3,
        ContainerFrameUtil_EnumerateContainerFrames = function()
            enumeratorCalls = enumeratorCalls + 1
            return ipairs({})
        end,
        ContainerFrameCombinedBags = frameWith(newButton("combined")),
        ContainerFrame1 = frameWith(newButton("f1")),
        ContainerFrame3 = frameWith(newButton("f3")),
        ContainerFrame4 = frameWith(newButton("f4-out-of-range")),
    }
    test.eq(compat.hookBagEvent("enter", function() end, api), true, "mixin hook path used")
    test.eq(enumeratorCalls, 0, "never calls Blizzard lazy container enumerator")
    table.sort(attached)
    test.eq(table.concat(attached, ","), "combined:OnEnter,f1:OnEnter,f3:OnEnter",
        "scans combined bags and ContainerFrame1..N only")
    local source = assert(io.open("Core/BGNext/ClientCompat.lua", "rb")):read("*a")
    test.eq(source:find("ContainerFrameUtil_Enumerate", 1, true) ~= nil and
        source:find("api.ContainerFrameUtil_Enumerate", 1, true) ~= nil, false,
        "no code reference to the enumerator via api")
end
