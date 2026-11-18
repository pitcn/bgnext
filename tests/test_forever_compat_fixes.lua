return function(test)
    local function read(path)
        local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
    end
    local function run(source, env)
        local fn = assert(loadstring(source)); setfenv(fn, setmetatable(env, { __index = _G })); return fn()
    end
    local env = { BG = { IsForever = true }, UnitName = function() return "Fixture", "Surname" end,
        GetUnitName = function() return "Fixture" end }
    run(assert(read("Core/DB/Init.lua"):match("(function BG.GN%(unit%).-)\nBG.playerName")), env)
    test.eq(env.BG.GN(), "Fixture Surname", "Forever complete tuple wins over short display helper")
    BG = { IsForever = true, BGNext = {}, GN = env.BG.GN }
    dofile("Core/BGNext/PlayerIdentity.lua")
    dofile("Core/BGNext/LeaderToolsStore.lua")
    dofile("Core/BGNext/LeaderToolsView.lua")
    local runtime = dofile("Core/BGNext/LeaderToolsRuntime.lua")
    runtime.currentContext = function() return {} end
    runtime.captureHistory = function(context)
        test.eq(context.isMine("Fixture Surname"), true, "local summary recognizes full self name")
        test.eq(context.isMine("Fixture Other"), false, "same first name is another character")
        return 1
    end
    local oldUnitName, oldRealm = UnitName, GetRealmName
    UnitName, GetRealmName = env.UnitName, function() return "Realm" end
    runtime.captureCurrentHistory()
    UnitName, GetRealmName = oldUnitName, oldRealm
    env.BG.IsForever = false
    env.GetUnitName = function() return "Fixture-Realm" end
    test.eq(env.BG.GN(), "Fixture-Realm", "non-Forever full-name behavior unchanged")
    env.BG.IsForever = true
    env.GetUnitName = function() return "Fixture" end
    local mailName = run(assert(read("Core/Module/SendMail.lua"):match("(local player = [^\n]+)")) .. "\nreturn player", env)
    test.eq(mailName, "Fixture Surname", "mail self-exclusion and template share complete name")

    local tradeEnv = { BG = env.BG, UnitName = env.UnitName }
    local target = run(assert(read("Core/BGNext/TradeCapture.lua"):match("(local function readTradeTarget%(%)%-?.-)\nlocal function readTradeMoney")) .. "\nreturn readTradeTarget()", tradeEnv)
    test.eq(target, "Fixture Surname", "trade fallback keeps surname without preferred API")

    local realmEnv = { BG = env.BG, realmName = "Realm", UnitName = env.UnitName }
    local realm = run(assert(read("Core/DB/DB.lua"):match("(local function UnitRealm%(unit%).-)\n    local function UnitColor")) .. "\nreturn UnitRealm('player')", realmEnv)
    test.eq(realm, "Realm", "ledger realm is the server, never the surname")

    local addonEnv = { BG = env.BG, UnitName = env.UnitName, runtime = {}, modern = {
        GetAddOnEnableState = function(addon, player) test.eq(player, "Fixture Surname", "modern enable-state name is complete"); return 2 end,
        DisableAddOn = function(addon, player) test.eq(player, "Fixture Surname", "modern disable name is complete") end,
    } }
    run(assert(read("Core/BGNext/ConflictGuard.lua"):match("(    runtime.getEnableState = function.-)\n    runtime.reloadUI")), addonEnv)
    test.eq(addonEnv.runtime.getEnableState("BGLite"), 2)
    test.eq(addonEnv.runtime.disableAddon("BGLite"), true)
    addonEnv.modern = nil
    addonEnv.GetAddOnEnableState = function(player, addon) test.eq(player, "Fixture Surname", "legacy argument order and full name"); return 2 end
    addonEnv.DisableAddOn = function(addon, player) test.eq(player, "Fixture Surname", "legacy disable full name") end
    test.eq(addonEnv.runtime.getEnableState("BGLite"), 2)
    test.eq(addonEnv.runtime.disableAddon("BGLite"), true)

end
