return function(test)
    local function read(path)
        local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
    end
    local source = read("Core/BiaoGe.lua")
    -- Run the actual file's local API bindings together with its cache request.
    local header = assert(source:match("(local GetItemInfo = [^\r\n]+)"), "main file must bind the available item API")
    local instant = assert(source:match("(local GetItemInfoInstant = [^\r\n]+)"))
    local request = assert(source:match("(GetItemInfo%(itemID%)) %-%- 提前缓存"))
    local requested
    local env = setmetatable({ itemID = 49623,
        C_Item = { GetItemInfo = function(id) requested = id; return "Fixture", nil, 4, 60 end,
            GetItemInfoInstant = function() return 49623, "Weapon", "Sword", "INVTYPE_WEAPON" end },
    }, { __index = function(_, key) if key == "GetItemInfo" or key == "GetItemInfoInstant" then return nil end return _G[key] end })
    env._G = env
    local fn = assert(loadstring(header .. "\n" .. instant .. "\n" .. request .. "\nreturn GetItemInfo(itemID), GetItemInfoInstant(itemID)"))
    setfenv(fn, env)
    local name, id, kind, subtype, slot = fn()
    test.eq(requested, 49623, "uncached icon request reaches C_Item instead of crashing init")
    test.eq(name, "Fixture", "item name preserved")
    test.eq(id, 49623, "instant item ID preserved")
    test.eq(slot, "INVTYPE_WEAPON", "instant result tuple preserved")
    env.GetItemInfo = function() return "Legacy" end
    setfenv(fn, env)
    test.eq(fn(), "Legacy", "existing client global takes priority")
    env.GetItemInfo = nil
    env.C_Item.GetItemInfo = function() return nil end
    setfenv(fn, env)
    test.eq(fn(), nil, "uncached data stays nil")
    local countBinding = assert(read("Core/function1.lua"):match("(local GetItemCount = [^\r\n]+)"),
        "item counts use the same namespace fallback")
    local qualityBinding = assert(read("Core/Module/Auction.lua"):match("(local GetItemQualityColor = [^\r\n]+)"))
    env.C_Item.GetItemCount = function(id, bank) test.eq(id, 12930); test.eq(bank, true); return 2 end
    env.C_Item.GetItemQualityColor = function(q) test.eq(q, 4); return 0.5, 0.2, 1, "ff8040ff" end
    local calls = assert(loadstring(countBinding .. "\n" .. qualityBinding ..
        "\nreturn GetItemCount(12930, true), GetItemQualityColor(4)"))
    setfenv(calls, env)
    local count, r, g, b, hex = calls()
    test.eq(count, 2, "original count and bank arguments forwarded")
    test.eq(hex, "ff8040ff", "quality color tuple preserved")
end
