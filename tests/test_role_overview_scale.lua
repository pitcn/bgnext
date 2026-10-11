return function(test)
    local env = setmetatable({ BG = { BGNext = {} } }, { __index = _G })
    local function load(path)
        local chunk = assert(loadfile(path)); setfenv(chunk, env); return chunk()
    end
    local settings = load("Core/BGNext/RoleOverviewSettings.lua")
    local root = { settings = { roleOverviewEnabled = false }, ownCharacters = { marker = true } }
    test.eq(settings.scale(root), 1, "existing installs default to 100 percent")
    test.eq(root.settings.roleOverviewScale, nil, "reading a default does not migrate old settings")
    test.eq(settings.setScale(root, 1.25), true, "player can select 125 percent")
    settings = load("Core/BGNext/RoleOverviewSettings.lua")
    test.eq(settings.scale(root), 1.25, "saved scale survives module reload")
    test.eq(root.settings.roleOverviewEnabled, false, "scaling never enables collection")
    test.eq(root.ownCharacters.marker, true, "scaling preserves existing snapshots")
    for _, invalid in ipairs({ false, "1.25", {}, 0/0, math.huge, -math.huge, 0 }) do
        test.eq(settings.setScale(root, invalid), false, "invalid input never overwrites player preference")
        test.eq(settings.scale({ settings = { roleOverviewScale = invalid } }), 1,
            "malformed saved scale uses the safe default")
    end
    test.eq(settings.scale(root), 1.25, "invalid writes retain the prior valid value")
    settings.setScale(root, 2)
    test.eq(settings.scale(root), 1.5, "scale is bounded at 150 percent")
    settings.setScale(root, 0.1)
    test.eq(settings.scale(root), 0.5, "scale is bounded at 50 percent")
    settings.setScale(root, 1.234)
    test.eq(settings.scale(root), 1.23, "slider values save with a one-percent step")
    test.eq(settings.setScale(nil, 1), false, "missing storage is safe")

    -- Drive the real window, renderer and settings panel with a small frame API.
    local frames = {}
    local function frame(kind, name, parent)
        local f = { kind = kind, name = name, parent = parent, scripts = {}, scale = 1, shown = false }
        function f:SetScript(event, callback) self.scripts[event] = callback end
        function f:HookScript(event, callback) self.scripts[event] = callback end
        function f:SetSize(w, h) self.width, self.height = w, h end
        function f:SetWidth(w) self.width = w end
        function f:SetHeight(h) self.height = h end
        function f:GetWidth() return self.width end
        function f:GetHeight() return self.height end
        function f:SetText(text) self.text = text end
        function f:GetStringWidth() return #(self.text or "") * 7 end
        function f:SetScale(value) self.scale = value end
        function f:GetScale() return self.scale end
        function f:GetEffectiveScale() return self.scale * (rawget(self, "parent") and self.parent:GetEffectiveScale() or 0.8) end
        function f:GetCenter()
            if rawget(self, "dragCenter") then return self.dragCenter[1] / self.scale, self.dragCenter[2] / self.scale end
            local p = rawget(self, "point")
            if p and p[1] == "CENTER" then return 960 / self.scale + p[4], 540 / self.scale + p[5] end
            return 960, 540
        end
        function f:SetPoint(...) self.point = { ... } end
        function f:ClearAllPoints() self.point = nil end
        function f:Show() self.shown = true end
        function f:Hide() self.shown = false end
        function f:SetShown(value) self.shown = value end
        function f:IsShown() return self.shown end
        function f:IsVisible() return self.shown end
        function f:IsMouseOver() return true end
        function f:SetValue(value)
            self.value = value
            if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
        end
        function f:GetValue() return self.value end
        function f:SetMinMaxValues(low, high) self.low, self.high = low, high end
        function f:SetValueStep(value) self.step = value end
        function f:CreateFontString() return frame("FontString", nil, self) end
        setmetatable(f, { __index = function() return function() end end })
        frames[#frames + 1] = f
        return f
    end
    env.CreateFrame = function(kind, name, parent)
        local f = frame(kind, name, parent)
        if kind == "Slider" then f.Low, f.High, f.Text = frame(), frame(), frame() end
        if kind == "CheckButton" then f.Text = frame() end
        return f
    end
    env.UIParent = frame(); env.UIParent:SetSize(1920, 1080)
    env.min = math.min
    env.BIAOGE_TEXT_FONT = "test font"
    root.settings.roleOverviewScale = 1.25
    root.settings.roleOverviewPoint = { point = "CENTER", relativePoint = "CENTER", x = 100, y = -40 }
    local bg = env.BG
    bg.BGNext.DB = root
    bg.Init2 = function(callback) callback() end
    bg.STC_g1 = function(text) return text end
    bg.CreateButton = function(parent) return frame("Button", nil, parent) end
    bg.BGNext.OwnCharacters = { listOrdered = function() return {} end }
    bg.BGNext.OwnCharactersAdapters = { detect = function() return "titan" end }
    bg.BGNext.OwnCharactersCatalog = { forFamily = function() return { raidColumns = {}, resourceColumns = {} } end }
    bg.BGNext.OwnCharactersRuntime = { isEnabled = function() return true end, setVisible = function() end }
    bg.MainFrame = frame(); bg.MainFrame:SetScale(0.7)
    local auction = frame(); auction:SetScale(0.9)
    env.BGA = { AuctionMainFrame = auction }
    env.BiaoGe = { options = { scale = 0.7, autoAuctionScale = 0.9 } }
    load("Core/BGNext/MainFrameScale.lua")
    local ui = load("Core/BGNext/OwnCharactersUI.lua")
    local entry = load("Core/BGNext/RoleOverviewEntry.lua")
    entry.setPinned(true)
    local overview = ui.GetFrame()
    test.eq(overview:GetScale(), 1.25, "saved preference applies when the fixed window first opens")
    test.eq(overview.point[4], 80, "saved UIParent coordinate converts to scaled window units")
    overview.dragCenter = { 1100, 600 }
    overview.scripts.OnDragStop(overview)
    test.eq(root.settings.roleOverviewPoint.x, 140, "drag saves x in UIParent units at non-default UI scale")
    test.eq(root.settings.roleOverviewPoint.y, 60, "drag saves y in UIParent units at non-default UI scale")
    overview.dragCenter = nil
    entry.setPinned(false); entry.setPinned(true)
    test.eq(overview.point[4], 112, "reopening restores the dragged position without drift")

    -- GetCenter uses each frame's own scaled coordinate system. Compare
    -- centers only after conversion to UIParent units, as GetScaledCenter does.
    for _, percent in ipairs({ 0.5, 1, 1.25, 1.5 }) do
        settings.setScale(root, percent)
        entry.RefreshScale()
        overview.dragCenter = { 1060, 580 }
        overview.scripts.OnDragStop(overview)
        overview.dragCenter = nil
        local x, y = overview:GetCenter()
        local ratio = overview:GetEffectiveScale() / env.UIParent:GetEffectiveScale()
        test.eq(math.abs(x * ratio - 1060) < 0.000001, true, "drag round trip retains physical x across scales")
        test.eq(math.abs(y * ratio - 580) < 0.000001, true, "drag round trip retains physical y across scales")
    end
    settings.setScale(root, 1.25)
    entry.RefreshScale()

    local panel = frame()
    settings.BuildPanel(panel)
    local slider, reset
    for _, control in ipairs(frames) do
        if control.kind == "Slider" then slider = control end
        if control.text == "恢复默认缩放" then reset = control end
    end
    test.eq(type(slider), "table", "settings exposes an independent scale slider")
    test.eq(slider:GetValue(), 125, "slider reflects saved percentage")
    test.eq(slider.low, 50, "slider starts at 50 percent")
    test.eq(slider.high, 150, "slider stops at 150 percent")
    slider:SetValue(140)
    test.eq(settings.scale(root), 1.4, "slider change persists immediately")
    test.eq(overview:GetScale(), 1.4, "slider updates an already open window")
    reset.scripts.OnClick(reset)
    test.eq(overview:GetScale(), 1, "reset restores 100 percent immediately")
    test.eq(slider:GetValue(), 100, "reset synchronizes the slider")
    slider:SetValue(150)
    ui.Draw({ width = 1600, height = 300, sections = {} })
    test.eq(overview:GetScale(), 1880/1600, "expanded layout automatically fits screen width")
    test.eq(settings.scale(root), 1.5, "screen fitting never overwrites chosen percentage")
    ui.Draw({ width = 600, height = 300, sections = {} })
    test.eq(overview:GetScale(), 1.5, "narrower layout restores preferred percentage")
    local dragAnchor = overview.point
    overview.scripts.OnDragStart(overview)
    ui.Draw({ width = 600, height = 300, sections = {} })
    test.eq(overview.point, dragAnchor, "periodic redraw never resets anchors during a drag")
    overview.dragCenter = { 1060, 580 }
    overview.scripts.OnDragStop(overview)
    overview.dragCenter = nil
    env.UIParent:SetSize(900, 600)
    overview.scripts.OnEvent(overview, "DISPLAY_SIZE_CHANGED")
    test.eq(overview:GetScale(), 860/600, "display resize recomputes actual scale")
    test.eq(settings.scale(root), 1.5, "display resize preserves preference")
    env.UIParent:SetSize(1920, 1080)
    overview.scripts.OnEvent(overview, "UI_SCALE_CHANGED")
    test.eq(overview:GetScale(), 1.5, "larger screen restores saved scale")
    entry.setPinned(false)
    entry.RefreshScale()
    test.eq(overview:IsShown(), false, "applying scale never opens a hidden window")
    overview.scripts.OnEvent(overview, "DISPLAY_SIZE_CHANGED")
    overview.scripts.OnEvent(overview, "UI_SCALE_CHANGED")
    test.eq(overview:IsShown(), false, "display and UI scale events never reveal a hidden window")
    env.C_Timer = { After = function(_, callback) callback() end }
    local minimap = frame(); minimap:Show()
    entry.hoverEnter(minimap, "minimap")
    test.eq(overview:GetScale(), 1.5, "hover preview shares the selected percentage")
    test.eq(overview.point[1], "TOPRIGHT", "preview retains its minimap anchor")
    test.eq(bg.MainFrame:GetScale(), 0.7, "ledger scale is unchanged")
    test.eq(auction:GetScale(), 0.9, "auction window scale is unchanged")
    test.eq(env.BiaoGe.options.scale, 0.7, "ledger preference is unchanged")
    test.eq(env.BiaoGe.options.autoAuctionScale, 0.9, "auction preference is unchanged")
    test.eq(root.ownCharacters.marker, true, "all window interactions preserve character snapshots")
end
