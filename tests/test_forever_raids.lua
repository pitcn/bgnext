return function(test)
    local function read(path)
        local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
    end
    local function detect(interface, engraving)
        BG = {}
        local source = read("Core/DB/Init.lua")
        local block = assert(source:match("local ver = select%(4, GetBuildInfo%(%)%)(.-)BG.IsNewUI = true"))
        local fn = assert(loadstring("local ver = " .. interface .. block))
        setfenv(fn, setmetatable({ C_Engraving = { IsEngravingEnabled = function() return engraving end } }, { __index = _G }))
        fn(); return BG
    end
    local flags = detect(16001, false)
    test.eq(flags.IsForever, true, "Forever is identified independently")
    test.eq(flags.IsVanilla, true, "shared classic functionality stays enabled")
    test.eq(flags.IsVanilla_60, nil, "Forever does not load Era raids and drops")
    test.eq(detect(11509, false).IsVanilla_60, true, "Era routing stays unchanged")
    test.eq(detect(11509, true).IsVanilla_Sod, true, "SoD routing stays unchanged")
    test.eq(detect(38002, false).IsTitan, true, "Titan routing stays unchanged")
    test.eq(detect(50505, false).IsMOP, true, "Mists routing stays unchanged")
    test.eq(detect(120100, false).IsRetail, true, "Retail routing stays unchanged")
    local adapters = dofile("Core/BGNext/OwnCharactersAdapters.lua")
    local catalog = dofile("Core/BGNext/OwnCharactersCatalog.lua")
    test.eq(adapters.familyFromFlags(flags), "forever", "own-character data is isolated from Era")
    local ownRaids = catalog.forFamily("forever").raidColumns
    test.eq(#ownRaids, 3, "only actual P1 raids are tracked as raid lockouts")
    test.eq(ownRaids[1].source.instanceIds[1], 3052, "Barrow Deeps lockout")

    BG = flags
    local ns = { L = setmetatable({}, { __index = function(_, k) return k end }) }
    assert(loadfile("Core/BGNext/ForeverRaids.lua"))("BGNext", ns)
    local raids = BG.ForeverRaids
    BG.Boss = { MC = { legacy = true } }
    BG.FormatBossName = function(name) return name, 0 end
    assert(loadfile("Core/DB/DB_BossName_Forever.lua"))("BGNext", ns)
    test.eq(BG.Boss.BDforever.boss1.name2, "寒嚎", "client's Barrow Deeps name")
    test.eq(BG.Boss.HSforever.boss13.name2, "荒野之王", "client's Hyjal final boss")
    test.eq(BG.Boss.MC.legacy, true, "existing boss catalog is untouched")
    test.eq(#raids, 4, "exactly four Forever raids")
    test.eq(raids[1].phase, "P0", "UBRS is P0")
    test.eq(raids[1].id, "UBRSforever", "independent ledger key")
    test.eq(raids[1].mapID, 229, "Blackrock Spire map")
    test.eq(#raids[2].bosses, 8, "eight Barrow Deeps encounters")
    test.eq(#raids[3].bosses, 13, "thirteen Hyjal Summit encounters")
    test.eq(#raids[4].bosses, 1, "standalone Onyxia")
    for i = 2, 4 do test.eq(raids[i].phase, "P1", "P1 raid") end

    -- Execute the actual database layout and registration branches used by UI creation.
    local source = read("Core/DB/DB.lua")
    local blocks = {}
    for block in source:gmatch("if BG%.IsForever then(.-)\n        end") do blocks[#blocks + 1] = block end
    test.eq(#blocks >= 2, true, "Forever layouts and raid registration are wired")
    local configs, registrations = {}, {}
    local env = setmetatable({ BG = BG, L = ns.L, mainFrameWidth = 1275, mainFrameWidth2 = 1685,
        AddDB = function(id, width, height, columns, maxb, splits, _, _, slots)
            slots[#slots + 1], slots[#slots + 2] = 8, 5
            configs[id] = { maxb = maxb, splits = splits, slots = slots, columns = columns }
        end }, { __index = _G })
    local fn = assert(loadstring(blocks[1])); setfenv(fn, env); fn()
    test.eq(configs.HSforever.columns, 4, "Hyjal leaves room for long boss labels")
    BG.FBtable2, BG.FBfromBossPosition = {}, {}
    env.AddDB = function(id, map, phase, players, quality, _, range, shortName)
        registrations[id] = { map = map, phase = phase, players = players, quality = quality }
        BG.FBtable2[#BG.FBtable2 + 1] = { localName = shortName }
        BG.FBfromBossPosition[id] = {}
        for b = 1, configs[id].maxb do BG.FBfromBossPosition[id][b] = {} end
    end
    fn = assert(loadstring(blocks[2])); setfenv(fn, env); fn()
    test.eq(BG.FB1, "UBRSforever", "default opens P0")
    for _, raid in ipairs(raids) do
        local config = configs[raid.id]
        test.eq(config.maxb, #raid.bosses + 2, "misc and fines precede footer rows")
        test.eq(#config.slots, #raid.bosses + 4, "every boss and footer has capacity")
        test.eq(registrations[raid.id].phase, raid.phase, "registered phase")
    end

    BG.Loot = {}
    for _, raid in ipairs(raids) do BG.Loot[raid.id] = { N = { Quest = {} }, ExchangeItems = {} } end
    assert(loadfile("Core/DB/DB_Loot_Forever.lua"))("BGNext", ns)
    test.eq(#BG.Loot.UBRSforever.N.boss1 > 0, true, "P0 has reference drops")
    test.eq(BG.Loot.encounterID.UBRSforever[6][1], 3063, "Rend event maps to Rend, not Gyth")
    local Wishlist = dofile("Core/BGNext/Wishlist.lua")
    local Price = dofile("Core/BGNext/AuctionPriceCatalog.lua")
    local bosses = {}
    for b = 1, #raids[1].bosses do
        bosses[b] = { id = "boss" .. b, name = raids[1].bosses[b] }
        local seen = {}
        for _, item in ipairs(BG.Loot.UBRSforever.N["boss" .. b]) do
            test.eq(seen[item], nil, "reference pool has no duplicate per boss")
            seen[item] = true
            local found = Wishlist.resolveDrop(item, { "N" }, BG.Loot.UBRSforever,
                #raids[1].bosses + 1, function(a, c) return a == c end, 1, b)
            test.eq(found.bossIndex, b, "reference drop resolves through existing wishlist")
        end
    end
    local prices = Price.build({ raidId = "UBRSforever", difficulties = { "N" },
        bosses = bosses, loot = BG.Loot.UBRSforever })
    test.eq(prices.byItem[12930] ~= nil, true, "Briarwood Reed reaches existing auction presets")
    for i = 2, 4 do
        for b = 1, #raids[i].bosses do
            test.eq(#BG.Loot[raids[i].id].N["boss" .. b], 0, "P1 has no invented drops")
        end
    end
    BG = { IsVanilla_60 = true }
    assert(loadfile("Core/BGNext/ForeverRaids.lua"))("BGNext", ns)
    assert(loadfile("Core/DB/DB_Loot_Forever.lua"))("BGNext", ns)
    test.eq(BG.ForeverRaids, nil, "other clients do not load Forever data")
    test.eq(BG.Loot, nil, "other client loot stays untouched")
end
