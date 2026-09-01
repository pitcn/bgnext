return function(test)
    BG = { BGNext = {} }
    BG.BGNext.UITheme = dofile("Core/BGNext/UITheme.lua")
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
        end
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
        local background = fakeTexture(0.01, 0.01, 0.01, 0.8)
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
            fakeTab(false, 0, 0, 0, 0.58, 1, 0.82, 0, 1),
            fakeTab(true, 0.4, 0.4, 0.4, 1, 1, 1, 1, 1),
        }
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

    test.eq(Skin.apply("preview", registry, 0.58), true, "preview applies")
    local afterFirst = registry.visualState()
    test.eq(Skin.apply("preview", registry, 0.58), true, "repeat apply succeeds")
    eqTable(registry.visualState(), afterFirst, "repeat apply is idempotent")
    test.eq(Skin.apply("classic", registry, 0.58), true, "classic restores")
    eqTable(registry.visualState(), before, "classic is byte-for-byte visual restore")

    registry.background.mutateGeometryOnStyle = true
    test.eq(Skin.apply("preview", registry, 0.58), false, "geometry change rolls back")
    eqTable(registry.visualState(), before, "failed apply restores classic")

    local source = read("Core/BGNext/LegacyLedgerSkin.lua")
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

    warnCount = 0
    test.eq(Skin.applySavedPreference(), true, "missing preference applies classic")
    test.eq(Skin.getRuntimeTheme(), "classic", "missing preference stays classic")
    BiaoGe.BGNext.settings.uiTheme = "future"
    test.eq(Skin.applySavedPreference(), true, "invalid preference applies classic")
    test.eq(Skin.getRuntimeTheme(), "classic", "invalid preference stays classic")

    test.eq(BiaoGe.options.alpha, 0.58, "no runtime path writes legacy alpha")
    test.eq(source:find("options%.alpha%s*="), nil, "skin source never assigns options.alpha")

    BiaoGe = nil
end
