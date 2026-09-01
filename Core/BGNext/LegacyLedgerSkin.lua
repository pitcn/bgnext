BG = BG or {}
BG.BGNext = BG.BGNext or {}

local UITheme = BG.BGNext.UITheme

local M = {}

-- In-memory classic snapshot. Captured once on the first successful apply and
-- kept only in this run; it is never written to SavedVariables.
local snapshot = nil
local runtimeTheme = "classic"

local function hexRGB(hex)
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    return r, g, b
end

-- colorRGBA reads the RGBA of either a Blizzard ColorMixin (production) or a
-- plain table exposing r/g/b/a (tests). It returns nothing when unreadable.
local function colorRGBA(color)
    if type(color) == "table" and color.r ~= nil then
        return color.r, color.g, color.b, color.a
    end
    return nil
end

-- makeColor builds a gradient color argument; it prefers the client's own
-- CreateColor and falls back to a plain table when that global is absent.
local function makeColor(r, g, b, a)
    if type(CreateColor) == "function" then
        return CreateColor(r, g, b, a)
    end
    return { r = r, g = g, b = b, a = a }
end

-- Read helpers return nil when a value cannot be read exactly, so the skin can
-- leave that property untouched rather than guess a classic value.
local function readBorder(frame)
    if type(frame) == "table" and type(frame.GetBackdropBorderColor) == "function" then
        local ok, r, g, b, a = pcall(frame.GetBackdropBorderColor, frame)
        if ok and r ~= nil then return { r, g, b, a } end
    end
    return nil
end

local function readColor(tex)
    if type(tex) == "table" and type(tex.GetColorTexture) == "function" then
        local ok, r, g, b, a = pcall(tex.GetColorTexture, tex)
        if ok and r ~= nil then return { r, g, b, a } end
    end
    return nil
end

local function readAlpha(tex)
    if type(tex) == "table" and type(tex.GetAlpha) == "function" then
        local ok, a = pcall(tex.GetAlpha, tex)
        if ok and a ~= nil then return a end
    end
    return nil
end

local function readGradient(tex)
    if type(tex) == "table" and type(tex.GetGradient) == "function" then
        local ok, minC, maxC = pcall(tex.GetGradient, tex)
        if ok and minC then
            local minR, minG, minB, minA = colorRGBA(minC)
            local maxR, maxG, maxB, maxA = colorRGBA(maxC)
            if minR and maxR then
                return { minR, minG, minB, minA, maxR, maxG, maxB, maxA }
            end
        end
    end
    return nil
end

local function readTextColor(font)
    if type(font) == "table" and type(font.GetTextColor) == "function" then
        local ok, r, g, b, a = pcall(font.GetTextColor, font)
        if ok and r ~= nil then return { r, g, b, a } end
    end
    return nil
end

local function snapshotTexture(tex)
    return {
        color = readColor(tex),
        alpha = readAlpha(tex),
        gradient = readGradient(tex),
    }
end

local function snapshotMain(frame)
    return { border = readBorder(frame) }
end

local function fontOf(tab)
    if type(tab) == "table" and type(tab.GetFontString) == "function" then
        local ok, font = pcall(tab.GetFontString, tab)
        if ok then return font end
    end
    return nil
end

local function snapshotTab(tab)
    local bg = type(tab) == "table" and tab.bg or nil
    return {
        bg = snapshotTexture(bg),
        text = readTextColor(fontOf(tab)),
    }
end

local function mapTabs(tabs)
    if type(tabs) ~= "table" then return {} end
    local out = {}
    for index, tab in ipairs(tabs) do
        out[index] = snapshotTab(tab)
    end
    return out
end

local function captureSnapshot(registry)
    return {
        main = snapshotMain(registry.main),
        background = snapshotTexture(registry.background),
        title = snapshotTexture(registry.title),
        moduleTabs = mapTabs(registry.moduleTabs),
        raidTabs = mapTabs(registry.raidTabs),
    }
end

local function restoreBorder(frame, state)
    if type(frame) ~= "table" or type(state) ~= "table" or not state.border then return end
    if type(frame.SetBackdropBorderColor) ~= "function" then return end
    local b = state.border
    pcall(frame.SetBackdropBorderColor, frame, b[1], b[2], b[3], b[4])
end

local function restoreTexture(tex, state)
    if type(tex) ~= "table" or type(state) ~= "table" then return end
    if state.gradient and type(tex.SetGradient) == "function" then
        local g = state.gradient
        pcall(tex.SetGradient, tex, "VERTICAL",
            makeColor(g[1], g[2], g[3], g[4]), makeColor(g[5], g[6], g[7], g[8]))
    elseif state.color and type(tex.SetColorTexture) == "function" then
        local c = state.color
        pcall(tex.SetColorTexture, tex, c[1], c[2], c[3], c[4])
    end
    if state.alpha ~= nil and type(tex.SetAlpha) == "function" then
        pcall(tex.SetAlpha, tex, state.alpha)
    end
end

local function restoreTab(tab, state)
    if type(tab) ~= "table" or type(state) ~= "table" then return end
    restoreTexture(tab.bg, state.bg)
    if state.text then
        local font = fontOf(tab)
        if type(font) == "table" and type(font.SetTextColor) == "function" then
            local t = state.text
            pcall(font.SetTextColor, font, t[1], t[2], t[3], t[4])
        end
    end
end

local function restoreSnapshot(registry, snap)
    restoreBorder(registry.main, snap.main)
    restoreTexture(registry.background, snap.background)
    restoreTexture(registry.title, snap.title)
    for index, tab in ipairs(registry.moduleTabs or {}) do
        restoreTab(tab, snap.moduleTabs and snap.moduleTabs[index])
    end
    for index, tab in ipairs(registry.raidTabs or {}) do
        restoreTab(tab, snap.raidTabs and snap.raidTabs[index])
    end
end

local function buildGeometryFrames(registry)
    local frames = { main = registry.main }
    for index, tab in ipairs(registry.moduleTabs or {}) do
        frames["moduleTab" .. index] = tab
    end
    for index, tab in ipairs(registry.raidTabs or {}) do
        frames["raidTab" .. index] = tab
    end
    return frames
end

local function styleTabs(tabs, alpha, tokens, snapTabs)
    if type(tabs) ~= "table" then return end
    for index, tab in ipairs(tabs) do
        if type(tab) == "table" then
            local enabled = true
            if type(tab.IsEnabled) == "function" then
                local ok, e = pcall(tab.IsEnabled, tab)
                if ok then enabled = e end
            end
            local snapTab = snapTabs and snapTabs[index]
            local bg = tab.bg
            if type(bg) == "table" then
                local snapBg = snapTab and snapTab.bg
                if enabled and snapBg and snapBg.color and type(bg.SetColorTexture) == "function" then
                    local r, g, b = hexRGB(tokens.colors.raised)
                    bg:SetColorTexture(r, g, b, alpha)
                elseif snapBg and snapBg.color and type(bg.SetColorTexture) == "function" then
                    -- active tab keeps its background; only its text is restyled.
                end
                if snapBg and snapBg.alpha ~= nil and type(bg.SetAlpha) == "function" then
                    if enabled then
                        bg:SetAlpha(alpha)
                    end
                end
            end
            local font = fontOf(tab)
            if snapTab and snapTab.text and type(font) == "table" and type(font.SetTextColor) == "function" then
                if enabled then
                    local r, g, b = hexRGB(tokens.colors.gold)
                    font:SetTextColor(r, g, b, 1)
                else
                    local r, g, b = hexRGB(tokens.colors.cyan)
                    font:SetTextColor(r, g, b, 1)
                end
            end
        end
    end
end

local function applyPreview(registry, alpha)
    local tokens = UITheme.tokens.preview
    local colors = tokens.colors
    local lift = tokens.localAlphaLift or 0.14

    local main = registry.main
    if snapshot and snapshot.main and snapshot.main.border
        and type(main) == "table" and type(main.SetBackdropBorderColor) == "function" then
        main:SetBackdropBorderColor(0.141, 0.267, 0.369, 1)
    end

    local bg = registry.background
    if type(bg) == "table" and snapshot and snapshot.background then
        if snapshot.background.color and type(bg.SetColorTexture) == "function" then
            local r, g, b = hexRGB(colors.window)
            bg:SetColorTexture(r, g, b, alpha)
        end
        if snapshot.background.alpha ~= nil and type(bg.SetAlpha) == "function" then
            bg:SetAlpha(alpha)
        end
    end

    local title = registry.title
    if type(title) == "table" and snapshot and snapshot.title then
        local titleAlpha = math.min(1, alpha + lift)
        if snapshot.title.gradient and type(title.SetGradient) == "function" then
            local r1, g1, b1 = hexRGB(colors.surface)
            local r2, g2, b2 = hexRGB(colors.raised)
            title:SetGradient("VERTICAL", makeColor(r1, g1, b1, 1), makeColor(r2, g2, b2, 1))
            if type(title.SetAlpha) == "function" then
                title:SetAlpha(titleAlpha)
            end
        elseif snapshot.title.color and type(title.SetColorTexture) == "function" then
            local r, g, b = hexRGB(colors.raised)
            title:SetColorTexture(r, g, b, titleAlpha)
        end
    end

    styleTabs(registry.moduleTabs, alpha, tokens, snapshot and snapshot.moduleTabs)
    styleTabs(registry.raidTabs, alpha, tokens, snapshot and snapshot.raidTabs)
end

function M.apply(themeId, registry, legacyAlpha)
    themeId = UITheme.normalize(themeId)
    if type(registry) ~= "table" or registry.main == nil
        or registry.background == nil or registry.title == nil then
        runtimeTheme = "classic"
        return false, "ledger-not-ready"
    end
    if snapshot == nil then
        snapshot = captureSnapshot(registry)
    end

    if themeId == "classic" then
        restoreSnapshot(registry, snapshot)
        runtimeTheme = "classic"
        return true
    end

    local alpha = UITheme.clampAlpha(legacyAlpha)
    local frames = buildGeometryFrames(registry)
    local geometryBefore = UITheme.captureGeometry(frames)

    local ok = pcall(applyPreview, registry, alpha)
    if not ok then
        restoreSnapshot(registry, snapshot)
        runtimeTheme = "classic"
        return false, "apply-error"
    end

    if not UITheme.geometryMatches(geometryBefore, frames) then
        restoreSnapshot(registry, snapshot)
        runtimeTheme = "classic"
        return false, "geometry-mismatch"
    end

    runtimeTheme = "preview"
    return true
end

function M.buildRuntimeRegistry()
    if type(BG) ~= "table" then return nil, "ledger-not-ready" end
    local main = BG.MainFrame
    local background = type(main) == "table" and main.Bg or nil
    local title = type(main) == "table" and main.titleBg or nil
    if not (main and background and title) then
        return nil, "ledger-not-ready"
    end

    local moduleTabs = {}
    if type(BG.tabButtons) == "table" then
        for _, v in ipairs(BG.tabButtons) do
            if type(v) == "table" and v.button then
                moduleTabs[#moduleTabs + 1] = v.button
            end
        end
    end

    local raidTabs = {}
    if type(BG.FBtable2) == "table" then
        for _, v in ipairs(BG.FBtable2) do
            if type(v) == "table" and v.FB then
                local btn = BG["Button" .. v.FB]
                if btn then
                    raidTabs[#raidTabs + 1] = btn
                end
            end
        end
    end

    return {
        main = main,
        background = background,
        title = title,
        moduleTabs = moduleTabs,
        raidTabs = raidTabs,
    }, nil
end

function M.applySavedPreference()
    local themeId = "classic"
    local legacyAlpha = nil
    if type(BiaoGe) == "table" then
        if type(BiaoGe.BGNext) == "table" and type(BiaoGe.BGNext.settings) == "table" then
            themeId = UITheme.normalize(BiaoGe.BGNext.settings.uiTheme)
        end
        if type(BiaoGe.options) == "table" then
            legacyAlpha = BiaoGe.options.alpha
        end
    end
    local registry, err = M.buildRuntimeRegistry()
    if not registry then
        return false, err
    end
    return M.apply(themeId, registry, legacyAlpha)
end

function M.getRuntimeTheme()
    return runtimeTheme
end

BG.BGNext.LegacyLedgerSkin = M
return M
