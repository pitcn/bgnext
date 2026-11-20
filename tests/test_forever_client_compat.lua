return function(test)
    local function read(path)
        local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
    end
    BG = { IsForever = true, BGNext = {} }
    local loader = loadfile("Core/BGNext/ClientCompat.lua")
    if loader then loader() end
    local calls, hooks = {}, {}
    local mixin = { OnClick = function() end, OnEnter = function() end, OnLeave = function() end,
        OnLoad = function() end }
    local env = setmetatable({
        BG = BG, ContainerFrameItemButtonMixin = mixin,
        IsAltKeyDown = function() return true end,
        IsShiftKeyDown = function() return true end,
        C_Container = { GetContainerItemLink = function(bag, slot)
            test.eq(bag, 4, "modern button's bag ID wins over container parent")
            test.eq(slot, 2, "correct slot")
            return "item:12930"
        end },
        hooksecurefunc = function(target, method, callback)
            if type(target) == "string" then error("missing legacy bag global: " .. target) end
            test.eq(type(target[method]), "function", "hook target exists")
            local previous = target[method]
            target[method] = function(...) previous(...); callback(...) end
        end,
        Insert = function(link) calls.insert = link end,
        OnHide = function() calls.hide = true end,
        BiaoGe = { options = { HighOnterItem = 1 } },
        dalayFrame = { Show = function() calls.enter = true end, Hide = function() end },
    }, { __index = _G })
    env._G = env
    local button = { GetID = function() return 2 end, GetBagID = function() return 4 end,
        HookScript = function(_, method, callback) hooks[#hooks + 1] = { method = method, callback = callback } end,
        GetParent = function() return { GetID = function() return 99 end } end }
    env.ContainerFrameUtil_EnumerateContainerFrames = function()
        error("addon code must not initialize Blizzard lazy container enumerator")
    end
    env.NUM_CONTAINER_FRAMES = 1
    env.ContainerFrame1 = { EnumerateItems = function() return ipairs({ button }) end }
    local function run(block)
        local fn = assert(loadstring(block)); setfenv(fn, env); fn()
    end
    BG.StartAuction = function(link, _, _, _, right) calls.auction, calls.right = link, right end
    -- Real callback registration blocks, not facsimiles of the call sites.
    local source = read("Core/Module/Auction.lua")
    local block = assert(source:match("%-%- ALT点击背包生效(.-)\n    end"))
    run(block)
    test.eq(#hooks, 1, "one auction hook, no duplicate click delivery")
    mixin.OnLoad(button)
    mixin.OnLoad(button)
    test.eq(#hooks, 1, "reused button never gets a duplicate callback")
    local future = { HookScript = button.HookScript }
    mixin.OnLoad(future)
    test.eq(#hooks, 2, "newly created buttons receive the callback too")
    hooks[1].callback(button, "RightButton")
    test.eq(calls.auction, "item:12930", "Alt-click still starts the existing manual flow")
    test.eq(calls.right, true, "right-click choice survives")

    hooks = {}
    source = read("Core/BiaoGe.lua")
    run(assert(source:match("%-%- 背包\r?\n(.-)\n    end")))
    hooks[1].callback(button, "LeftButton")
    test.eq(calls.insert, "item:12930", "Shift-click inserts the same item")

    hooks = {}
    source = read("Core/Module/hooks.lua")
    run(assert(source:match("(local function OnEnter%(self, button%).-)\n        end\r?\n    end")))
    for _, hook in ipairs(hooks) do hook.callback(button) end
    test.eq(calls.enter, true, "hover highlight receives the modern item location")
    test.eq(calls.hide, true, "hover leave clears highlights")

    source = read("Core/DB/DB.lua")
    env.BiaoGe = { playerInfo = { [1] = { Fixture = {} } } }
    env.realmID, env.player = 1, "Fixture"
    env.C_SpecializationInfo = { GetSpecialization = function() return 2 end }
    block = assert(source:match("(local function GetTalent%(_, event%).-)\n            local f = CreateFrame"))
    run(block .. "\nGetTalent()")
    test.eq(env.BiaoGe.playerInfo[1].Fixture.talent, 2, "Forever uses namespaced specialization")
    env.C_SpecializationInfo.GetSpecialization = function() return 0 end
    run(block .. "\nGetTalent()")
    test.eq(env.BiaoGe.playerInfo[1].Fixture.talent, nil, "unselected talent is unknown")

    local compat = BG.BGNext.ClientCompat
    test.eq(compat.bagLink({}, env), nil, "missing item location is safe")
    local oldApi = { GetTalentTabInfo = function(i) return nil, nil, nil, nil, i * 3 end }
    test.eq(compat.talentIndex({}, oldApi), 3, "legacy talent tree still works without group API")
    test.eq(compat.talentIndex({}, {}), nil, "missing talent API does not interrupt login")
    local legacyHooks = 0
    local legacyApi = { ContainerFrameItemButton_OnModifiedClick = function() end,
        hooksecurefunc = function(name) test.eq(name, "ContainerFrameItemButton_OnModifiedClick"); legacyHooks = legacyHooks + 1 end }
    compat.hookBagEvent("click", function() end, legacyApi, false)
    test.eq(legacyHooks, 1, "existing classic hook retained")
end
