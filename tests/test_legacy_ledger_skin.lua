return function(test)
    BG = { BGNext = {} }
    BG.BGNext.UITheme = dofile("Core/BGNext/UITheme.lua")
    BG.BGNext.UIStyle = dofile("Core/BGNext/UIStyle.lua")
    local Skin = dofile("Core/BGNext/LegacyLedgerSkin.lua")

    local function read(path)
        local f = assert(io.open(path, "rb"))
        local s = f:read("*a")
        f:close()
        return s
    end

    local function eqTable(left, right, path)
        path = path or "root"
        test.eq(type(left), type(right), path .. " type")
        if type(left) ~= "table" then
            test.eq(left, right, path)
            return
        end
        for key, value in pairs(left) do
            eqTable(value, right[key], path .. "." .. tostring(key))
        end
        for key in pairs(right) do
            test.eq(left[key] ~= nil, true, path .. " has " .. tostring(key))
        end
    end

    local function fakeTexture(r, g, b, a)
        local tex = { color = { r, g, b, a }, alpha = a }
        function tex:GetColorTexture()
            return self.color[1], self.color[2], self.color[3], self.color[4]
        end
        function tex:SetColorTexture(rr, gg, bb, aa)
            self.color = { rr, gg, bb, aa }
            self.alpha = aa
            self.texture = nil
        end
        function tex:SetTexture(path) self.texture = path end
        function tex:GetAlpha() return self.alpha end
        function tex:SetAlpha(aa) self.alpha = aa end
        return tex
    end

    local function fakeGradientTexture(minR, minG, minB, minA, maxR, maxG, maxB, maxA)
        local tex = {
            gradMin = { minR, minG, minB, minA },
            gradMax = { maxR, maxG, maxB, maxA },
            alpha = 1,
        }
        function tex:GetGradient()
            return { r = self.gradMin[1], g = self.gradMin[2], b = self.gradMin[3], a = self.gradMin[4] },
                   { r = self.gradMax[1], g = self.gradMax[2], b = self.gradMax[3], a = self.gradMax[4] }
        end
        function tex:SetGradient(orientation, minC, maxC)
            self.gradMin = { minC.r, minC.g, minC.b, minC.a }
            self.gradMax = { maxC.r, maxC.g, maxC.b, maxC.a }
        end
        function tex:GetAlpha() return self.alpha end
        function tex:SetAlpha(aa) self.alpha = aa end
        return tex
    end

    local function fakeTab(enabled, bgR, bgG, bgB, bgA, textR, textG, textB, textA)
        local tab = { enabled = enabled, width = 90, height = 28 }
        local bg = fakeTexture(bgR, bgG, bgB, bgA)
        local font = { color = { textR, textG, textB, textA } }
        tab.bg = bg
        tab.font = font

        function tab:GetParent() return "tabsParent" end
        function tab:GetNumPoints() return 1 end
        function tab:GetPoint() return "TOPLEFT", "relative", "BOTTOMLEFT", 0, 0 end
        function tab:GetWidth() return self.width end
        function tab:GetHeight() return self.height end
        function tab:IsEnabled() return self.enabled end
        function tab:GetFontString() return self.font end

        function font:GetTextColor()
            return self.color[1], self.color[2], self.color[3], self.color[4]
        end
        function font:SetTextColor(rr, gg, bb, aa)
            self.color = { rr, gg, bb, aa }
        end
        return tab
    end

    local function tabVisual(tab)
        return {
            bg = {
                color = { tab.bg.color[1], tab.bg.color[2], tab.bg.color[3], tab.bg.color[4] },
                alpha = tab.bg.alpha,
            },
            text = { tab.font.color[1], tab.font.color[2], tab.font.color[3], tab.font.color[4] },
        }
    end

    local function fakeRegistry()
        local main = { width = 900, height = 700, border = { 1, 0, 0, 1 } }
        local background = fakeTexture(0.01, 0.01, 0.01, 1)
        background.alpha = 0.58
        background.mutateGeometryOnStyle = false
        local title = fakeGradientTexture(0.4, 0.4, 0.4, 0.2, 0.4, 0.4, 0.4, 0.0)

        function main:GetParent() return "parent" end
        function main:GetNumPoints() return 1 end
        function main:GetPoint() return "TOP", "relative", "BOTTOM", 3, -4 end
        function main:GetWidth() return self.width end
        function main:GetHeight() return self.height end
        function main:GetBackdropBorderColor()
            return self.border[1], self.border[2], self.border[3], self.border[4]
        end
        function main:SetBackdropBorderColor(r, g, b, a)
            self.border = { r, g, b, a }
        end

        -- mutateGeometryOnStyle makes background:SetColorTexture change main's
        -- reported width, simulating a geometry drift inside the transaction.
        local realSetColorTexture = background.SetColorTexture
        background.SetColorTexture = function(self, r, g, b, a)
            realSetColorTexture(self, r, g, b, a)
            if self.mutateGeometryOnStyle then
                main.width = main.width + 1
            end
        end

        local moduleTabs = {
            fakeTab(false, 0.4, 0.4, 0.4, 1, 1, 1, 1, 1),
            fakeTab(true, 0.01, 0.01, 0.01, 1, 1, 0.82, 0, 1),
        }
        moduleTabs[2].bg.alpha = 0.58
        local raidTabs = {
            fakeTab(false, 0, 0, 0, 0.58, 1, 0.82, 0, 1),
            fakeTab(true, 0.4, 0.4, 0.4, 1, 1, 1, 1, 1),
        }

        local registry = {
            main = main,
            background = background,
            title = title,
            moduleTabs = moduleTabs,
            raidTabs = raidTabs,
            classic = {
                main = { border = { 1, 0, 0, 1 } },
                background = { color = { 0.01, 0.01, 0.01, 1 }, alpha = 0.58 },
                title = {
                    gradient = { 0.4, 0.4, 0.4, 0.2, 0.4, 0.4, 0.4, 0.0 },
                    alpha = 1,
                },
                moduleTabs = {
                    { bg = { color = { 0.4, 0.4, 0.4, 1 }, alpha = 1 } },
                    { bg = { color = { 0.01, 0.01, 0.01, 1 }, alpha = 0.58 } },
                },
            },
        }

        function registry.visualState()
            return {
                main = { border = { main.border[1], main.border[2], main.border[3], main.border[4] } },
                background = {
                    color = { background.color[1], background.color[2], background.color[3], background.color[4] },
                    alpha = background.alpha,
                },
                title = {
                    gradient = {
                        title.gradMin[1], title.gradMin[2], title.gradMin[3], title.gradMin[4],
                        title.gradMax[1], title.gradMax[2], title.gradMax[3], title.gradMax[4],
                    },
                    alpha = title.alpha,
                },
                moduleTabs = { tabVisual(moduleTabs[1]), tabVisual(moduleTabs[2]) },
                raidTabs = { tabVisual(raidTabs[1]), tabVisual(raidTabs[2]) },
            }
        end

        return registry
    end

    local registry = fakeRegistry()
    local before = registry.visualState()

    -- Real WoW Texture regions expose setters for color textures and gradients,
    -- but the corresponding getters are not portable across supported clients.
    -- The runtime registry must therefore provide an explicit classic recipe.
    registry.background.GetColorTexture = nil
    registry.title.GetGradient = nil
    registry.moduleTabs[1].bg.GetColorTexture = nil
    registry.moduleTabs[2].bg.GetColorTexture = nil

    test.eq(Skin.apply("preview", registry, 0.58), true, "preview applies")
    local afterFirst = registry.visualState()
    test.eq(afterFirst.background.color[1] < before.background.color[1], true,
        "preview changes a background even without GetColorTexture")
    test.eq(afterFirst.background.color[4], 1,
        "preview color texture stays opaque before region alpha")
    test.eq(afterFirst.background.alpha, 0.58,
        "legacy alpha is applied once at the region level")
    test.eq(afterFirst.moduleTabs[2].bg.color[4], 1,
        "tab color texture stays opaque before region alpha")
    test.eq(afterFirst.moduleTabs[2].bg.alpha, 0.72,
        "inactive tab receives one bounded local alpha lift")
    test.eq(afterFirst.moduleTabs[2].bg.color[1] ~= before.moduleTabs[2].bg.color[1], true,
        "preview changes an inactive tab even without GetColorTexture")
    test.eq(afterFirst.title.gradient[1] ~= before.title.gradient[1], true,
        "preview changes a title even without GetGradient")
    test.eq(registry.moduleTabs[1]._BGNextVisualState, "selected",
        "disabled module tab uses selected state")
    test.eq(registry.moduleTabs[2]._BGNextVisualState, "normal",
        "enabled module tab uses inactive state")
    test.eq(registry.raidTabs[1]._BGNextVisualState, "selected",
        "disabled raid tab uses selected state")
    test.eq(registry.raidTabs[2]._BGNextVisualState, "normal",
        "enabled raid tab uses inactive state")

    registry.raidTabs[1].enabled = true
    registry.raidTabs[2].enabled = false
    test.eq(Skin.refreshRaidSelection(registry, 0.58), true,
        "raid selection refresh succeeds in preview theme")
    test.eq(registry.raidTabs[1]._BGNextVisualState, "normal",
        "preview refresh demotes the previous raid tab")
    test.eq(registry.raidTabs[2]._BGNextVisualState, "selected",
        "preview refresh promotes the selected raid tab")

    test.eq(Skin.apply("preview", registry, 0.58), true, "repeat apply succeeds")
    local afterSelection = registry.visualState()
    test.eq(Skin.apply("preview", registry, 0.58), true, "repeat apply succeeds")
    eqTable(registry.visualState(), afterSelection, "repeat apply is idempotent")

    registry.moduleTabs[2].enabled = false
    test.eq(Skin.refreshNavigation(registry, 0.58), true,
        "navigation refresh succeeds after selection changes")
    test.eq(registry.moduleTabs[2]._BGNextVisualState, "selected",
        "navigation refresh promotes the new selected tab")
    test.eq(registry.main.width, 900, "navigation refresh preserves width")
    test.eq(registry.main.height, 700, "navigation refresh preserves height")
    registry.moduleTabs[2].enabled = true
    test.eq(Skin.apply("classic", registry, 0.58), true, "classic restores")
    eqTable(registry.visualState(), before, "classic is byte-for-byte visual restore")

    registry.raidTabs[1].enabled = true
    registry.raidTabs[2].enabled = false
    test.eq(Skin.refreshRaidSelection(registry, 0.58), true,
        "raid selection refresh succeeds in classic theme")
    test.eq(registry.raidTabs[1].font.color[1], 0,
        "classic inactive raid tab returns to cyan")
    test.eq(registry.raidTabs[1].font.color[2], 0.75,
        "classic inactive raid tab uses the established cyan channel")
    test.eq(registry.raidTabs[2].font.color[1], 1,
        "classic selected raid tab uses white")
    test.eq(registry.raidTabs[2].font.color[2], 1,
        "classic selected raid tab uses white across channels")

    -- A user may still have one of the legacy tiled image backgrounds selected.
    -- Preview must replace it visually and classic must restore the saved path.
    local TextureSkin = dofile("Core/BGNext/LegacyLedgerSkin.lua")
    local textureRegistry = fakeRegistry()
    textureRegistry.background.GetColorTexture = nil
    textureRegistry.background.texture = "Interface/FrameGeneral/UI-Background-Marble"
    textureRegistry.classic.background = {
        texture = "Interface/FrameGeneral/UI-Background-Marble",
        horizTile = true,
        vertTile = true,
        alpha = 0.58,
    }
    test.eq(TextureSkin.apply("preview", textureRegistry, 0.58), true,
        "preview applies over a tiled image background")
    test.eq(textureRegistry.background.texture, nil,
        "preview replaces the tiled image with the brand color")
    test.eq(TextureSkin.apply("classic", textureRegistry, 0.58), true,
        "classic restores a tiled image background")
    test.eq(textureRegistry.background.texture,
        "Interface/FrameGeneral/UI-Background-Marble",
        "classic restores the exact saved texture path")

    registry.background.mutateGeometryOnStyle = true
    test.eq(Skin.apply("preview", registry, 0.58), false, "geometry change rolls back")
    eqTable(registry.visualState(), before, "failed apply restores classic")

    local source = read("Core/BGNext/LegacyLedgerSkin.lua")
    local ledgerSource = read("Core/BiaoGe.lua")
    test.eq(ledgerSource:find("BG.BGNext.LegacyLedgerSkin.refreshRaidSelection()", 1, true) ~= nil,
        true, "raid switches refresh theme-aware navigation state")
    for _, token in ipairs({
        "SetPoint", "ClearAllPoints", "SetSize", "SetWidth", "SetHeight",
        "SetParent", "SetFrameLevel", "SetFrameStrata", "SetScript",
        "HookScript", "hooksecurefunc", "OnUpdate", "C_Timer", "CreateFrame",
        "CreateTexture", "CreateFontString", "SendAddonMessage", "SendChatMessage",
    }) do
        test.eq(source:find(token, 1, true), nil, "skin source forbids " .. token)
    end

    -- Task 3: runtime wiring and one-time safe fallback.
    local toc = read("BGLite.toc")
    local function tocOffset(token)
        return toc:find(token, 1, true)
    end
    local initPos = tocOffset("Core\\BGNext\\Init.lua")
    local themePos = tocOffset("Core\\BGNext\\UITheme.lua")
    local ledgerPos = tocOffset("Core\\BiaoGe.lua")
    local skinPos = tocOffset("Core\\BGNext\\LegacyLedgerSkin.lua")
    local optionsPos = tocOffset("Core\\Options.lua")
    test.eq(themePos ~= nil, true, "TOC loads theme")
    test.eq(initPos and themePos and initPos < themePos, true, "theme loads after init")
    test.eq(themePos and ledgerPos and themePos < ledgerPos, true, "theme loads before ledger")
    test.eq(ledgerPos and skinPos and ledgerPos < skinPos, true, "skin loads after ledger")
    test.eq(skinPos and optionsPos and skinPos < optionsPos, true, "skin loads before options")

    registry.background.mutateGeometryOnStyle = false

    local callbacks = {}
    local warnCount = 0
    local function fakeInit2(fn) callbacks[#callbacks + 1] = fn end
    local function fakeWarn() warnCount = warnCount + 1 end
    Skin.installRuntime(fakeInit2, fakeWarn)
    Skin.installRuntime(fakeInit2, fakeWarn)
    test.eq(#callbacks, 1, "installRuntime registers exactly one callback")

    -- Force failure: BG has no MainFrame, so applySavedPreference cannot build a registry.
    BG.MainFrame = nil
    callbacks[1]()
    callbacks[1]()
    test.eq(warnCount, 1, "warn fires once only after forced failure")

    -- Missing/invalid saved preference applies classic without warning.
    BG.MainFrame = registry.main
    BG.MainFrame.Bg = registry.background
    BG.MainFrame.titleBg = registry.title
    BG.tabButtons = {
        { button = registry.moduleTabs[1] },
        { button = registry.moduleTabs[2] },
    }
    BG.FBtable2 = { { FB = "NAXX" }, { FB = "ULD" } }
    BG["ButtonNAXX"] = registry.raidTabs[1]
    BG["ButtonULD"] = registry.raidTabs[2]
    BiaoGe = { BGNext = { settings = {} }, options = { alpha = 0.58 } }

    callbacks[1]()
    BG.MainFrame = nil
    callbacks[1]()
    test.eq(warnCount, 1, "warning remains once per session after a later success")
    BG.MainFrame = registry.main

    test.eq(Skin.applySavedPreference(), true, "missing preference applies classic")
    test.eq(Skin.getRuntimeTheme(), "classic", "missing preference stays classic")
    BiaoGe.BGNext.settings.uiTheme = "future"
    test.eq(Skin.applySavedPreference(), true, "invalid preference applies classic")
    test.eq(Skin.getRuntimeTheme(), "classic", "invalid preference stays classic")

    test.eq(BiaoGe.options.alpha, 0.58, "no runtime path writes legacy alpha")
    test.eq(source:find("options%.alpha%s*="), nil, "skin source never assigns options.alpha")

    BiaoGe = nil
end
