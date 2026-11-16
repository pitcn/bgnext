return function(test)
    local f = assert(io.open("Core/Module/hooks.lua", "rb"))
    local source = f:read("*a"); f:close()
    local block = assert(source:match("%-%- 执行%s+do(.-)\n    end\r?\nend%)"))
    BG = { BGNext = {}, IsForever = true }
    local compat = dofile("Core/BGNext/ClientCompat.lua")
    local posts, seen = {}, {}
    local tooltip = {
        HasScript = function() return false end,
        HookScript = function() error("unsupported tooltip script (real Forever failure)") end,
        GetUnit = function() return "Fixture", "player" end,
        GetItem = function() return "Fixture Item", "item:12930" end,
    }
    BG.InBoss = function() return false end
    BG.IsSecret = function() return false end
    BG.GN = function() return "Fixture" end
    BG.GetLeiTingItem = function(id) return id end
    local env = setmetatable({ BG = BG, GameTooltip = tooltip,
        TooltipDataProcessor = { AddTooltipPostCall = function(kind, callback) posts[kind] = callback end },
        Enum = { TooltipDataType = { Unit = 1, Item = 2 } },
        InCombatLockdown = function() return false end,
        UnitIsPlayer = function() return true end,
        GetItemID = function() return 12930 end,
        unitFucs = { function(_, unit) seen.unit = unit end },
        itemFucs = { function(_, id) seen.item = id end },
    }, { __index = _G })
    env._G = env
    local fn = assert(loadstring(block)); setfenv(fn, env); fn()
    test.eq(type(posts[1]), "function", "unit callback uses data processor on Forever")
    test.eq(type(posts[2]), "function", "item callback uses data processor on Forever")
    posts[1](tooltip); posts[2](tooltip)
    test.eq(seen.unit, "player", "unit callback still reaches existing debt functions")
    test.eq(seen.item, 12930, "item callback still reaches existing item functions")
    seen.item = nil
    posts[2]({})
    test.eq(seen.item, nil, "unrelated tooltips do not enter GameTooltip item flow")

    local scripts = {}
    local legacy = { GameTooltip = {
        HasScript = function(_, name) return name == "OnTooltipSetItem" end,
        HookScript = function(_, name, callback) scripts[name] = callback end,
    } }
    local callback = function() end
    test.eq(compat.hookTooltip("Item", callback, legacy), true, "old client keeps supported script")
    test.eq(scripts.OnTooltipSetItem, callback, "old callback preserved")
    test.eq(compat.hookTooltip("Unit", callback, legacy), false, "unsupported script is not registered")
    test.eq(compat.hookTooltip("Item", callback, {}), false, "missing APIs are safe")
end
