return function(test)
    BG = { BGNext = {} }
    local Scale = dofile("Core/BGNext/MainFrameScale.lua")

    -- Pure computation: the preferred scale is the ceiling, never enlarged; the
    -- table is shrunk only enough to fit the logical screen minus safe margins.
    --
    --   actualScale = min(preferredScale, widthLimit, heightLimit)
    --   widthLimit  = (screenWidth  - marginX) / tableWidth
    --   heightLimit = (screenHeight - marginY) / tableHeight

    -- Width limit shrinks a wide table on a narrow screen.
    local wide = Scale.compute(1, 1685, 810, 1280, 800, 0, 0)
    test.eq(wide, 1280 / 1685, "wide table is constrained by the width limit")

    -- Height limit binds when the table is tall relative to the screen.
    local tall = Scale.compute(1, 1275, 900, 2560, 800, 0, 0)
    test.eq(tall, 800 / 900, "tall table is constrained by the height limit")

    -- The preferred scale is retained when the table already fits.
    test.eq(Scale.compute(0.6, 1275, 810, 2560, 1600, 0, 0), 0.6,
        "preferred scale is retained when it fits")

    -- A small preferred scale is never enlarged.
    test.eq(Scale.compute(0.5, 100, 100, 10000, 10000, 0, 0), 0.5,
        "a small preferred scale is never enlarged")

    -- Switching from a wide to a narrow table recovers the preferred scale.
    local wideScale = Scale.compute(1, 1685, 810, 1600, 900, 0, 0)
    local narrowScale = Scale.compute(1, 1275, 810, 1600, 900, 0, 0)
    test.eq(narrowScale > wideScale, true, "narrow table recovers a larger scale")
    test.eq(narrowScale, 1, "narrow table recovers the full preferred scale")

    -- Invalid or zero preferred scale yields no scale.
    test.eq(Scale.compute(nil, 1685, 810, 1280, 800), nil, "nil preferred is invalid")
    test.eq(Scale.compute(0, 1685, 810, 1280, 800), nil, "zero preferred is invalid")
    test.eq(Scale.compute(-1, 1685, 810, 1280, 800), nil, "negative preferred is invalid")
    test.eq(Scale.compute("x", 1685, 810, 1280, 800), nil, "non-number preferred is invalid")

    -- Zero or invalid dimensions skip that axis's limit rather than error.
    test.eq(Scale.compute(1, 0, 100, 1280, 800), 1, "zero table width skips the width limit")
    test.eq(Scale.compute(1, 100, 0, 1280, 800), 1, "zero table height skips the height limit")
    test.eq(Scale.compute(1, 1685, 100, 0, 800), 1, "zero screen width skips the width limit")
    test.eq(Scale.compute(1, 100, 810, 1280, 0), 1, "zero screen height skips the height limit")

    -- Safe margins reduce the usable screen area.
    local withMargin = Scale.compute(1, 2000, 100, 1280, 800, 80, 0)
    test.eq(withMargin, (1280 - 80) / 2000, "horizontal margin reduces the width limit")
    local noMargin = Scale.compute(1, 2000, 100, 1280, 800, 0, 0)
    test.eq(withMargin < noMargin, true, "margin lowers the width limit")

    -- Default margins are applied when the caller leaves them unspecified.
    test.eq(Scale.compute(1, 1685, 810, 1600, 900),
        math.min(1, (1600 - Scale.MARGIN_X) / 1685, (900 - Scale.MARGIN_Y) / 810),
        "default margins are applied")

    -- A frame can be clipped even while its centre remains on-screen. Boundary
    -- checks therefore use all four scaled edges rather than only GetCenter().
    test.eq(Scale.isOutsideScreen(-10, 100, 1190, 700, 1280, 800), true,
        "a clipped left edge is outside even when the centre is visible")
    test.eq(Scale.isOutsideScreen(100, -5, 1200, 700, 1280, 800), true,
        "a clipped bottom edge is outside")
    test.eq(Scale.isOutsideScreen(100, 100, 1290, 700, 1280, 800), true,
        "a clipped right edge is outside")
    test.eq(Scale.isOutsideScreen(100, 100, 1200, 810, 1280, 800), true,
        "a clipped top edge is outside")
    test.eq(Scale.isOutsideScreen(100, 100, 1200, 700, 1280, 800), false,
        "a frame whose four edges fit is not outside")
    test.eq(Scale.isOutsideScreen(nil, 100, 1200, 700, 1280, 800), false,
        "unavailable geometry does not force a destructive recenter")

    -- Source assembly: the only place that scales the main frame is the unified
    -- adapter. The slider, its reset and the resize handle no longer set scale
    -- directly, so every user entry funnels through the same formula.
    local function read(path)
        local f = assert(io.open(path, "rb"))
        local s = f:read("*a")
        f:close()
        return s
    end

    local biaoGe = read("Core/BiaoGe.lua")
    test.eq(biaoGe:find("function BG.ApplyMainFrameScale", 1, true) ~= nil, true,
        "the unified adapter is defined")
    test.eq(biaoGe:find("BG.ApplyMainFrameScale()", 1, true) ~= nil, true,
        "the adapter is wired into OnShow")
    test.eq(biaoGe:find('"UI_SCALE_CHANGED"', 1, true) ~= nil, true,
        "the adapter reacts to UI scale changes")
    test.eq(biaoGe:find('"DISPLAY_SIZE_CHANGED"', 1, true) ~= nil, true,
        "the adapter reacts to display-size changes")

    local options = read("Core/Options.lua")
    test.eq(options:find("BG.MainFrame:SetScale", 1, true) == nil, true,
        "the scale slider and reset no longer set the main frame scale directly")

    local fn1 = read("Core/function1.lua")
    test.eq(fn1:find(":GetParent():SetScale", 1, true) == nil, true,
        "the resize handle no longer sets the parent scale directly")
end
