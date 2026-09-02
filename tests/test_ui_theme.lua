return function(test)
    BG = { BGNext = {} }
    local Theme = dofile("Core/BGNext/UITheme.lua")

    test.eq(Theme.normalize(nil), "classic", "missing preference stays classic")
    test.eq(Theme.normalize("classic"), "classic", "classic is accepted")
    test.eq(Theme.normalize("preview"), "preview", "preview is accepted")
    test.eq(Theme.normalize("future"), "classic", "unknown value safely falls back")
    test.eq(Theme.clampAlpha(-1), 0, "alpha lower bound")
    test.eq(Theme.clampAlpha(2), 1, "alpha upper bound")
    test.eq(Theme.clampAlpha(nil), 0.8, "missing alpha uses legacy default")

    local p = Theme.tokens.preview
    test.eq(p.colors.window, "010F23", "brand navy")
    test.eq(p.colors.surface, "07182A", "brand surface")
    test.eq(p.colors.raised, "0C2033", "brand raised surface")
    test.eq(p.colors.gold, "F5B230", "brand gold")
    test.eq(p.colors.cyan, "00E6FF", "brand cyan")
    test.eq(p.colors.text, "E8F1F8", "brand text")

    local frame = {
        GetParent = function() return "parent" end,
        GetNumPoints = function() return 1 end,
        GetPoint = function() return "TOP", "relative", "BOTTOM", 3, -4 end,
        GetWidth = function() return 900 end,
        GetHeight = function() return 700 end,
    }
    local before = Theme.captureGeometry({ main = frame })
    test.eq(Theme.geometryMatches(before, { main = frame }), true, "unchanged geometry passes")
    frame.GetWidth = function() return 901 end
    test.eq(Theme.geometryMatches(before, { main = frame }), false, "changed width fails")
    test.eq(Theme.geometryMatches(before, {}), false, "missing key frame fails")
end
