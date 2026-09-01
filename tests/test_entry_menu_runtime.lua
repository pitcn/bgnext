return function(test)
    local mainShown = false
    local mainToggleCount = 0
    BG = {
        BGNext = {},
        dropDown = {},
        MainFrame = {
            IsVisible = function() return mainShown end,
            SetShown = function(_, shown)
                mainShown = shown
                mainToggleCount = mainToggleCount + 1
            end,
        },
        PlaySound = function() end,
    }
    dofile("Core/BGNext/EntryInteractions.lua")
    dofile("Core/BGNext/EntryMenuLifecycle.lua")
    local hoverEnterCalls = {}
    local hoverLeaveCalls = 0
    BG.BGNext.RoleOverviewEntry = {
        canOpen = function() return true end,
        isPinned = function() return false end,
        togglePinned = function() end,
        hoverEnter = function(source, kind)
            hoverEnterCalls[#hoverEnterCalls + 1] = { source = source, kind = kind }
        end,
        hoverLeave = function() hoverLeaveCalls = hoverLeaveCalls + 1 end,
    }

    UIParent = { GetEffectiveScale = function() return 1 end }
    BiaoGe = { options = { miniMap = 1 } }
    C_Timer = { After = function() end }
    GetCursorPosition = function() return 400, 300 end

    local frames = {}
    function CreateFrame(_, _, parent)
        local frame = { scripts = {}, parent = parent, shown = false, mouseOver = false }
        function frame:SetScript(name, callback) self.scripts[name] = callback end
        function frame:RegisterEvent() end
        function frame:SetSize(width, height) self.width, self.height = width, height end
        function frame:SetHeight(height) self.height = height end
        function frame:SetFrameStrata() end
        function frame:SetClampedToScreen() end
        function frame:EnableMouse(enabled) self.mouseEnabled = enabled end
        function frame:ClearAllPoints() end
        function frame:SetPoint(...) self.point = { ... } end
        function frame:SetText(text) self.text = text end
        function frame:IsShown() return self.shown end
        function frame:IsMouseOver() return self.mouseOver end
        function frame:Show() self.shown = true end
        function frame:Hide()
            local wasShown = self.shown
            self.shown = false
            if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function frame:CreateTexture()
            return {
                SetAllPoints = function() end,
                SetColorTexture = function() end,
            }
        end
        frames[#frames + 1] = frame
        return frame
    end
    local fontReady = false
    function BG.CreateButton(parent)
        assert(fontReady, "the shared button font is not initialized before ADDON_LOADED")
        return CreateFrame("Button", nil, parent)
    end

    local plugin
    local broker = {}
    function broker:NewDataObject(_, value)
        plugin = value
        return value
    end

    local minimapButton = { IsMouseOver = function() return false end }
    local icon = {
        Register = function() end,
        GetMinimapButton = function() return minimapButton end,
        Hide = function() end,
    }
    local requestedSharedDropdown = false
    local sharedCloseCalls = 0
    local globalCloseCalls = 0
    CloseDropDownMenus = function() globalCloseCalls = globalCloseCalls + 1 end
    local sharedDropdown = {
        CloseDropDownMenus = function() sharedCloseCalls = sharedCloseCalls + 1 end,
    }
    local libStub = {}
    function libStub:GetLibrary(name)
        if name == "LibDataBroker-1.1" then return broker end
        if name == "BiaoGe-LibUIDropDownMenu-4.0" then
            requestedSharedDropdown = true
            return sharedDropdown
        end
    end
    setmetatable(libStub, {
        __call = function(_, name)
            if name == "LibDBIcon-1.0" then return icon end
        end,
    })
    LibStub = libStub

    local chunk = assert(loadfile("Core/Module/minimap.lua"))
    chunk("BGNext", { L = setmetatable({}, { __index = function(_, key) return key end }) })
    test.eq(#frames, 1, "loading the module defers private menu controls until login")
    fontReady = true
    frames[1].scripts.OnEvent()

    local entryMenu = frames[2]
    local watcher = frames[3]
    local firstButton = frames[4]

    plugin:OnClick("RightButton")
    test.eq(requestedSharedDropdown, false, "the entry menu never requests the shared dropdown library")
    test.eq(entryMenu:IsShown(), true, "right click opens the private entry menu")
    test.eq(entryMenu.parent, UIParent, "the private entry menu has its own UIParent owner")
    test.eq(entryMenu.mouseEnabled, true, "the private menu absorbs clicks on its padding and row gaps")
    test.eq(type(watcher.scripts.OnUpdate), "function", "opening the entry menu arms its watcher")

    entryMenu.mouseOver = true
    watcher.scripts.OnUpdate(watcher, 1)
    test.eq(entryMenu:IsShown(), true, "the private entry menu remains open while the pointer is inside")

    entryMenu.mouseOver = false
    watcher.scripts.OnUpdate(watcher, 0.3)
    test.eq(entryMenu:IsShown(), false, "moving outside dismisses the private entry menu")
    test.eq(globalCloseCalls, 0, "outside dismissal never invokes Blizzard's global dropdown closer")
    test.eq(sharedCloseCalls, 0, "outside dismissal never invokes the shared addon's dropdown closer")
    test.eq(watcher.scripts.OnUpdate, nil, "the watcher stops after dismissing the entry menu")

    plugin:OnClick("RightButton")
    plugin:OnClick("RightButton")
    test.eq(entryMenu:IsShown(), false, "a second right click closes the private entry menu")
    test.eq(watcher.scripts.OnUpdate, nil, "a second right click stops the watcher immediately")

    plugin:OnClick("RightButton")
    firstButton.scripts.OnClick()
    test.eq(mainToggleCount, 1, "selecting an entry action executes it exactly once")
    test.eq(entryMenu:IsShown(), false, "selecting an entry action closes the private menu")
    test.eq(watcher.scripts.OnUpdate, nil, "a menu action leaves no background watcher")

    -- Hovering the minimap button delegates to the shared role-overview entry
    -- so the preview, timer and window stay in one place.
    -- LibDBIcon calls data-object callbacks with a dot call:
    -- obj.OnEnter(minimapButton). Match that exact contract so an accidental
    -- extra method parameter cannot turn the real hover source into nil.
    plugin.OnEnter(minimapButton)
    test.eq(#hoverEnterCalls, 1, "hovering the minimap delegates to the shared entry")
    test.eq(hoverEnterCalls[1].source, minimapButton, "the minimap button is the shared hover source")
    test.eq(hoverEnterCalls[1].kind, "minimap", "the minimap passes its anchor kind")

    plugin.OnLeave(minimapButton)
    test.eq(hoverLeaveCalls, 1, "leaving the minimap delegates to the shared entry")
end
