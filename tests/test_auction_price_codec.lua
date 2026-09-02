return function(test)
    BG = { BGNext = {} }
    local life = dofile("Core/BGNext/DataLifecycle.lua")
    local store = dofile("Core/BGNext/AuctionPriceStore.lua")
    local codec = dofile("Core/BGNext/AuctionPriceCodec.lua")

    local function freshRoot()
        return life.ensureRoot({})
    end

    local knownItems = { [1001] = true, [1002] = true, [1003] = true, [2001] = true }

    -- Leader round-trip (current).
    local src = freshRoot()
    local raid = store.ensureLeaderRaid(src, "titan", "ULD", 777)
    local active = raid.activePresetId
    store.renamePreset(src, "titan", "ULD", active, "普通团")
    store.setLeaderItemPrice(src, "titan", "ULD", active, 1001, 500)
    store.setLeaderItemPrice(src, "titan", "ULD", active, 1002, 0)

    local text = codec.exportLeader("titan", "ULD", raid, "current")
    test.eq(type(text), "string", "leader export returns text")
    test.eq(codec.exportLeader("titan", "ULD", raid, "current"), text, "leader export deterministic")

    local preview = codec.parse(text, "leader", knownItems)
    test.eq(preview.ok, true, "leader parse ok")
    test.eq(preview.type, "leader", "leader type")
    test.eq(preview.clientFamily, "titan", "leader family")
    test.eq(preview.raidId, "ULD", "leader raid")
    test.eq(preview.presetCount, 1, "leader preset count")
    test.eq(preview.presets[active].name, "普通团", "name round trip")
    test.eq(preview.presets[active].basePrice, 777, "base round trip")
    test.eq(preview.presets[active].itemPrices[1001], 500, "item price round trip")
    test.eq(preview.presets[active].itemPrices[1002], 0, "zero round trip")

    -- Apply leader as new to a fresh root.
    local dst = freshRoot()
    test.eq(codec.applyLeader(dst, preview, { mode = "new" }), true, "apply leader new")
    test.eq(store.resolveLeaderPrice(dst, "titan", "ULD", 1001), 500, "applied item resolves")

    -- One-way compatibility import for the previous BGLite price string. The
    -- decoder is injected by the UI so the codec remains deterministic here.
    local legacy = codec.parse("ULD:encoded", "leader", knownItems, {
        clientFamily = "titan",
        defaultBasePrice = 1000,
        isBase64 = function(text) return text == "encoded" end,
        decodeBase64 = function() return "1001-500-note,1002-0-," end,
    })
    test.eq(legacy.ok, true, "legacy leader price string parses")
    test.eq(legacy.sourceFormat, "bglite-legacy", "legacy source is disclosed in preview")
    test.eq(legacy.clientFamily, "titan", "legacy import is scoped to the current client")
    test.eq(legacy.raidId, "ULD", "legacy raid prefix is retained")
    test.eq(legacy.presets.p1.basePrice, 1000, "legacy import uses the current safe fallback")
    test.eq(legacy.presets.p1.itemPrices[1001], 500, "legacy item price is converted")
    test.eq(legacy.presets.p1.itemPrices[1002], 0, "legacy explicit zero is retained")

    -- Exercise the bundled Base64 implementation against a real legacy string,
    -- not only a stub decoder. The globals below mirror WoW's string aliases.
    local oldGlobals = {
        wipe = wipe, format = format, strsub = strsub, strchar = strchar, strbyte = strbyte,
    }
    wipe = function(tbl) for key in pairs(tbl) do tbl[key] = nil end return tbl end
    format, strsub, strchar, strbyte = string.format, string.sub, string.char, string.byte
    local base64 = {}
    assert(loadfile("Libs/LibBase64/LibBase64.lua"))(nil, base64)
    wipe, format, strsub, strchar, strbyte =
        oldGlobals.wipe, oldGlobals.format, oldGlobals.strsub, oldGlobals.strchar, oldGlobals.strbyte
    local realLegacy = codec.parse("ULD:MTAwMS01MDAtbm90ZSwxMDAyLTAtLA==", "leader", knownItems, {
        clientFamily = "titan",
        raidId = "ULD",
        defaultBasePrice = 1000,
        isBase64 = base64.IsBase64,
        decodeBase64 = base64.Decode,
    })
    test.eq(realLegacy.ok, true, "bundled Base64 decodes a real legacy price string")
    test.eq(realLegacy.presets.p1.itemPrices[1001], 500, "real legacy string retains the 500 price")
    test.eq(codec.parse("ULD:not base64", "leader", knownItems, {
        clientFamily = "titan", raidId = "ULD", defaultBasePrice = 1000,
        isBase64 = base64.IsBase64, decodeBase64 = base64.Decode,
    }).ok, false, "malformed legacy encoding is rejected")
    test.eq(codec.parse("NAXX:MTAwMS01MDAtLA==", "leader", knownItems, {
        clientFamily = "titan", raidId = "ULD", defaultBasePrice = 1000,
        isBase64 = base64.IsBase64, decodeBase64 = base64.Decode,
    }).ok, false, "legacy import cannot cross the selected raid")
    test.eq(codec.parse("ULD:MTAwMS01MDAtLDEwMDEtNjAwLSw=", "leader", knownItems, {
        clientFamily = "titan", raidId = "ULD", defaultBasePrice = 1000,
        isBase64 = base64.IsBase64, decodeBase64 = base64.Decode,
    }).ok, false, "duplicate legacy item ids are rejected")

    -- Type isolation: leader text cannot parse as personal and vice versa.
    test.eq(codec.parse(text, "personal", knownItems).ok, false, "leader rejected as personal")
    local ptext = codec.exportPersonal("titan", "ULD", { [1001] = 900 })
    test.eq(codec.parse(ptext, "leader", knownItems).ok, false, "personal rejected as leader")

    -- Personal round-trip.
    local ppreview = codec.parse(ptext, "personal", knownItems)
    test.eq(ppreview.ok, true, "personal parse ok")
    test.eq(ppreview.raidId, "ULD", "personal raid")
    test.eq(ppreview.itemPrices[1001], 900, "personal item round trip")

    local pdst = freshRoot()
    local pctx = { clientFamily = "titan", realmId = 123, player = "Leader", raidId = "ULD" }
    test.eq(codec.applyPersonal(pdst, pctx, ppreview, { mode = "merge" }), true, "apply personal merge")
    test.eq(store.getPersonalPrice(pdst, "titan", 123, "Leader", "ULD", 1001), 900, "personal applied")

    -- Personal merge overwrites and replace clears.
    test.eq(store.setPersonalPrice(pdst, "titan", 123, "Leader", "ULD", 1002, 10), true, "seed personal")
    local ppreview2 = codec.parse(codec.exportPersonal("titan", "ULD", { [1002] = 20 }), "personal", knownItems)
    test.eq(codec.applyPersonal(pdst, pctx, ppreview2, { mode = "merge" }), true, "merge personal")
    test.eq(store.getPersonalPrice(pdst, "titan", 123, "Leader", "ULD", 1002), 20, "merge overwrites")
    test.eq(store.getPersonalPrice(pdst, "titan", 123, "Leader", "ULD", 1001), 900, "merge keeps other items")
    test.eq(codec.applyPersonal(pdst, pctx, ppreview2, { mode = "replace" }), true, "replace personal")
    test.eq(store.getPersonalPrice(pdst, "titan", 123, "Leader", "ULD", 1001), nil, "replace clears old")

    -- Invalid input never mutates the root.
    local before = store.getPersonalPrice(pdst, "titan", 123, "Leader", "ULD", 1002)
    test.eq(codec.parse("garbage", "leader", knownItems).ok, false, "garbage rejected")
    test.eq(store.getPersonalPrice(pdst, "titan", 123, "Leader", "ULD", 1002), before, "root unchanged on bad parse")

    -- 64 KB limit.
    local big = "BGNP-L1\nversion=1\nfamily=titan\nraid=ULD\npreset=p1\nname=x\nbase=100\n" .. string.rep("item=1001:100\n", 6000)
    test.eq(codec.parse(big, "leader", knownItems).ok, false, "over 64 KB rejected")

    -- Unsupported version.
    local badVersion = "BGNP-L1\nversion=2\nfamily=titan\nraid=ULD\n"
    test.eq(codec.parse(badVersion, "leader", knownItems).ok, false, "unsupported version rejected")

    -- Duplicate preset key.
    local dup = "BGNP-L1\nversion=1\nfamily=titan\nraid=ULD\npreset=p1\nname=a\nbase=100\npreset=p1\nname=b\nbase=100\n"
    test.eq(codec.parse(dup, "leader", knownItems).ok, false, "duplicate preset rejected")

    -- Over-limit money.
    local badMoney = "BGNP-L1\nversion=1\nfamily=titan\nraid=ULD\npreset=p1\nname=a\nbase=10000001\n"
    test.eq(codec.parse(badMoney, "leader", knownItems).ok, false, "over-max money rejected")

    -- Over-limit name (25 chars).
    local longName = "BGNP-L1\nversion=1\nfamily=titan\nraid=ULD\npreset=p1\nname=" .. string.rep("名", 25) .. "\nbase=100\n"
    test.eq(codec.parse(longName, "leader", knownItems).ok, false, "25-char name rejected")

    -- Client/raid mismatch at apply time.
    local mctx = { clientFamily = "wrath", realmId = 123, player = "Leader", raidId = "ULD" }
    test.eq(codec.applyPersonal(pdst, mctx, ppreview2, { mode = "merge" }), false, "client mismatch refused")
    local badRealmCtx = { clientFamily = "titan", realmId = "123", player = "Leader", raidId = "ULD" }
    test.eq(codec.applyPersonal(pdst, badRealmCtx, ppreview2, { mode = "merge" }), false, "string realm refused")

    -- Unknown items are skipped on apply.
    local unkPreview = codec.parse(codec.exportPersonal("titan", "ULD", { [1001] = 1, [9999] = 2 }), "personal", knownItems)
    test.eq(unkPreview.ok, true, "unknown items parse ok")
    test.eq(unkPreview.unknownItems[9999], true, "unknown item flagged")
    test.eq(codec.applyPersonal(pdst, pctx, unkPreview, { mode = "replace" }), true, "apply with unknown")
    test.eq(store.getPersonalPrice(pdst, "titan", 123, "Leader", "ULD", 1001), 1, "known item applied")
    test.eq(store.getPersonalPrice(pdst, "titan", 123, "Leader", "ULD", 9999), nil, "unknown item skipped")

    -- Same-name suffix on leader import.
    local src2 = freshRoot()
    local raid2 = store.ensureLeaderRaid(src2, "titan", "ULD", 100)
    store.renamePreset(src2, "titan", "ULD", raid2.activePresetId, "普通团")
    local clashText = codec.exportLeader("titan", "ULD", raid2, "current")
    local clashPreview = codec.parse(clashText, "leader", knownItems)
    local dst2 = freshRoot()
    local baseRaid = store.ensureLeaderRaid(dst2, "titan", "ULD", 100)
    store.renamePreset(dst2, "titan", "ULD", baseRaid.activePresetId, "普通团")
    test.eq(codec.applyLeader(dst2, clashPreview, { mode = "new" }), true, "clashing import accepted")
    local names = {}
    for _, preset in pairs(store.ensureLeaderRaid(dst2, "titan", "ULD", 100).presets) do
        names[preset.name] = true
    end
    test.eq(names["普通团（导入）"], true, "clashing name gains suffix")

    -- 20-scheme limit is atomic on apply.
    local manyText = "BGNP-L1\nversion=1\nfamily=titan\nraid=ULD\n"
    for i = 1, 21 do
        manyText = manyText .. "preset=p" .. i .. "\nname=方案" .. i .. "\nbase=100\n"
    end
    local manyPreview = codec.parse(manyText, "leader", knownItems)
    test.eq(manyPreview.ok, false, "21 schemes rejected at parse")
end
