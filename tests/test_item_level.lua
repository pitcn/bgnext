return function(test)
    BG = { BGNext = {} }
    local itemLevel = dofile("Core/BGNext/ItemLevel.lua")

    local titan = itemLevel.new({
        getDetailedItemLevel = function(link)
            test.eq(link, "item:legendary", "the exact item link is queried")
            return 284
        end,
    })
    test.eq(titan:resolve("item:legendary", 245), 284,
        "the client-provided effective item level wins over the legacy sparse level")

    local production = itemLevel.production({
        C_Item = {
            GetDetailedItemLevelInfo = function(link)
                test.eq(link, "item:titan-orange", "the namespaced Titan API receives the item link")
                return 291
            end,
        },
    })
    test.eq(production:resolve("item:titan-orange", 0), 291,
        "the production adapter uses the namespaced detailed-level API")

    local legacyClient = itemLevel.production({
        GetDetailedItemLevelInfo = function() return 226 end,
    })
    test.eq(legacyClient:resolve("item:legacy", 213), 226,
        "clients exposing only the historical global API remain supported")

    local unavailable = itemLevel.new({
        getDetailedItemLevel = function() error("not available for this item") end,
    })
    test.eq(unavailable:resolve("item:ordinary", 245), 245,
        "an unavailable detailed API preserves the legacy item level")
    test.eq(titan:resolve(nil, 238), 238,
        "a missing item link preserves the legacy item level")

    local detailedCalls = 0
    local gated = itemLevel.new({
        getDetailedItemLevel = function()
            detailedCalls = detailedCalls + 1
            return 300
        end,
    })
    test.eq(gated:displayLevel("item:armor", 245, 4), 300,
        "equipment labels use the effective item level")
    test.eq(gated:displayLevel("item:material", 1, 7), nil,
        "non-equipment keeps the historical hidden-label behavior")
    test.eq(gated:displayLevel("", nil, nil), nil,
        "empty table rows stay hidden")
    test.eq(detailedCalls, 1,
        "the detailed API is not queried for empty rows or non-equipment")

    local fullLink = "|cffff8000|Hitem:123:0:0:0|h[Legendary]|h|r"
    local observedLink
    local hyperlinkAdapter = itemLevel.new({
        getDetailedItemLevel = function(link)
            observedLink = link
            return 300
        end,
    })
    test.eq(hyperlinkAdapter:resolve(fullLink, 245), 300,
        "full colored hyperlinks resolve to their effective item level")
    test.eq(observedLink, fullLink,
        "the compatibility adapter preserves item-link bonus data")

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end
    local toc = read("BGLite.toc")
    local adapterAt = toc:find("Core\\BGNext\\ItemLevel.lua", 1, true)
    local tableAt = toc:find("Core\\function2.lua", 1, true)
    test.eq(adapterAt ~= nil and tableAt ~= nil and adapterAt < tableAt, true,
        "the item-level adapter loads before the shared table widgets")

    local widgetSource = read("Core/function2.lua")
    test.eq(widgetSource:find("BG.DisplayItemLevel(bt:GetText(), level, typeID)", 1, true) ~= nil, true,
        "table item-level labels use the shared compatibility adapter")

    for _, integration in ipairs({
        { "Core/FBUI/FBUIfunction.lua", "BG.ResolveItemLevel(link or itemText, level)" },
        { "Core/TongBao/LiuPai.lua", "BG.ResolveItemLevel(link or zb:GetText(), level)" },
        { "Core/Module/AuctionWAEvent.lua", "BG.ResolveItemLevel(link or itemID, itemLevel)" },
        { "Core/Module/AuctionLog.lua", "BG.DisplayItemLevel(v.zhuangbei, v.itemlevel, typeID)" },
        { "Core/Module/Loot.lua", "BG.ResolveItemLevel(link, level)" },
        { "Core/Module/Trade.lua", "BG.ResolveItemLevel(info.hyperlink or vv.itemID, level)" },
    }) do
        test.eq(read(integration[1]):find(integration[2], 1, true) ~= nil, true,
            integration[1] .. " uses the shared effective item level")
    end
end
