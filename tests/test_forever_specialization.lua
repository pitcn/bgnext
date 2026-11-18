return function(test)
    BG = { IsForever = true, IsVanilla = true, BGNext = {} }
    local adapter = dofile("Core/BGNext/SpecializationAdapter.lua")
    test.eq(adapter.detect(), "forever", "Forever never borrows vanilla specialization catalog")
    local api = { C_SpecializationInfo = {
        GetSpecialization = function() return 2 end,
        GetSpecializationInfo = function() return 987654, "Fixture specialization" end,
    } }
    test.eq(adapter.resolve("forever", api, "MAGE").specKey, "spec:987654", "Forever reads stable modern ID")
    local catalog = dofile("Core/BGNext/EquipmentFilterSpecializations.lua")
    test.eq(catalog.getDefault("forever", "MAGE", "spec:987654"), nil, "no guessed Forever catalog")
    local function read(path)
        local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
    end
    local function run(source, env)
        local fn = assert(loadstring(source)); setfenv(fn, setmetatable(env, { __index = _G })); return fn()
    end
    local events, callback, frame = {}, nil, {}
    function frame:RegisterEvent(event) events[event] = true end
    function frame:SetScript(kind, fn) self[kind] = fn end
    BG.BGNext.ClientCompat = dofile("Core/BGNext/ClientCompat.lua")
    local env = { BG = BG, CreateFrame = function() return frame end,
        BiaoGe = { playerInfo = { [1] = { Fixture = {} } } }, realmID = 1, player = "Fixture",
        C_SpecializationInfo = api.C_SpecializationInfo }
    env._G = env
    run(assert(read("Core/DB/DB.lua"):match("(local function GetTalent%(_, event%).-)\n            function BG.GetTalentIcon")), env)
    test.eq(events.PLAYER_SPECIALIZATION_CHANGED, true, "legacy playerInfo registers Forever spec event")
    frame.OnEvent(frame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    frame.OnUpdate(frame, 2)
    test.eq(env.BiaoGe.playerInfo[1].Fixture.talent, 2, "spec event refreshes current player talent index")

    local runtime = dofile("Core/BGNext/EquipmentFilterRuntime.lua")
    local current, refreshes = 987654, 0
    api.C_SpecializationInfo.GetSpecializationInfo = function() return current, "Fixture specialization" end
    local state = { selectionMode = "follow-spec", selectedId = "custom", profiles = { custom = {} } }
    local model = dofile("Core/BGNext/EquipmentFilter.lua")
    local controller = runtime.new({ adapter = adapter, catalog = catalog, model = model,
        globals = BG, api = api, getClassToken = function() return "MAGE" end,
        getState = function() return state end, refresh = function() refreshes = refreshes + 1 end })
    controller:onEvent("PLAYER_ENTERING_WORLD"); controller:flush()
    local previous = refreshes
    current = 987655
    controller:onEvent("PLAYER_SPECIALIZATION_CHANGED"); controller:flush()
    test.eq(refreshes, previous + 1, "unmapped Forever spec change still refreshes visible status")
    test.eq(state.selectedId, "custom", "unmapped specialization preserves selected profile")
    controller:onEvent("PLAYER_TALENT_UPDATE"); controller:flush()
    test.eq(refreshes, previous + 1, "duplicate unchanged events coalesce")

    events = {}
    BG.Init = function(fn) callback = fn end
    BG.realmID, BG.playerName = 1, "Fixture Surname"
    BG.BGNext.DB = { equipmentFilters = {} }
    BG.BGNext.EquipmentFilter = { ensureCharacter = function() end }
    UnitClass = function() return "Mage", "MAGE" end
    local oldCreateFrame = CreateFrame
    CreateFrame = function() return frame end
    dofile("Core/BGNext/EquipmentFilterRuntime.lua")
    callback()
    CreateFrame = oldCreateFrame
    UnitClass = nil
    test.eq(events.PLAYER_SPECIALIZATION_CHANGED, true, "live filter binding registers Forever spec event")
    test.eq(events.ACTIVE_TALENT_GROUP_CHANGED, true, "live filter binding registers talent-group event")

    local tooltip, onEnter = {}, nil
    local label = "无限服专精默认方案待验证，沿用当前方案"
    local uiEnv = { BG = BG, resolveFollowTarget = function() return nil end,
        L = setmetatable({}, { __index = function(_, key) return key end }),
        followButton = { SetScript = function(_, _, fn) onEnter = fn end },
        GameTooltip = { SetOwner = function() end, Show = function() end,
            AddLine = function(_, text) tooltip[#tooltip + 1] = text end } }
    run(assert(read("Core/BGNext/EquipmentFilterUI.lua"):match('(followButton:SetScript%("OnEnter".-)\n            followButton:SetScript%("OnLeave"')), uiEnv)
    onEnter({})
    test.eq(tooltip[1], label, "Forever explicitly labels unverified defaults")

end
