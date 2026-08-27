-- BGNext role-overview entry, pinning, commands and deletion.
--
-- Owns the interaction decisions as pure functions (testable in plain Lua)
-- and, inside the game only, the bottom-right entry on the BGLite main frame,
-- the hover preview, the pin/drag window and the /bgn role, /bgnext role
-- commands.
--
-- It never reads another player, never inspects, never registers a chat,
-- combat-log or group-roster event, and never sends a message.

local AddonName, ns = ...
local L = ns and ns.L or setmetatable({}, { __index = function(_, key) return tostring(key) end })

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local Model = BG.BGNext.OwnCharacters

local M = {}

--------------------------------------------------------------------------
-- Pure interaction decisions
--------------------------------------------------------------------------

-- Maps an interaction to an intent. `state` carries the current pinned flag
-- and any modifier keys, never storage.
function M.intent(action, state)
    state = type(state) == "table" and state or {}
    if action == "hover" then
        return state.pinned and "keep" or "preview"
    end
    if action == "leave" then
        return state.pinned and "keep" or "hide"
    end
    if action == "middle-click" or action == "left-click" then
        if action == "left-click" and not state.ctrl then return nil end
        return state.pinned and "unpin" or "pin"
    end
    if action == "slash-role" then return "toggle-pinned" end
    if action == "close" then return "unpin" end
    if action == "refresh" then return "refresh" end
    if action == "settings" then return "settings" end
    return nil
end

-- The documented subcommand for /bgn and /bgnext.
function M.parseCommand(message)
    if type(message) ~= "string" then return nil end
    local word = message:match("^%s*(%S+)")
    if not word then return nil end
    word = word:lower()
    if word == "role" or word == "角色总览" then return "role" end
    return nil
end

function M.showAllRealms(state)
    state = type(state) == "table" and state or {}
    return state.shift == true
end

-- A delete request is always keyed by family, realm and name together so a
-- same-name character on another realm can never be removed by mistake.
function M.deleteRequest(row, family)
    if type(row) ~= "table" then return nil end
    if type(family) ~= "string" or type(row.player) ~= "string" or row.realmId == nil then
        return nil
    end
    return { family = family, realmId = row.realmId, player = row.player }
end

function M.applyDelete(root, request, confirmed)
    if confirmed ~= true then return false end
    if type(request) ~= "table" then return false end
    if not Model then return false end
    return Model.delete(root, request.family, request.realmId, request.player)
end

-- Refresh re-reads the logged-in character and rebuilds the view. It does not
-- scan other players and sends nothing.
function M.refreshPlan()
    return { rereadCurrentCharacter = true, scanOtherPlayers = false, sendsMessage = false }
end

--------------------------------------------------------------------------
-- Runtime wiring (inside the game only)
--------------------------------------------------------------------------

local pinned = false
local state = { pinned = pinned }
local window

local function provider()
    local family = BG.BGNext.OwnCharactersAdapters and BG.BGNext.OwnCharactersAdapters.detect(BG)
    local catalog = family and BG.BGNext.OwnCharactersCatalog and BG.BGNext.OwnCharactersCatalog.forFamily(family)
    local root = BG.BGNext.DB
    if not family or not catalog or not root then return nil end

    local view = BG.BGNext.OwnCharactersView
    local settings = BG.BGNext.RoleOverviewSettings
    local snapshots = Model and Model.list(root, family) or {}

    return view.project({
        family = family,
        catalog = catalog,
        snapshots = snapshots,
        currentRealmId = BG.realmID or (type(GetRealmID) == "function" and GetRealmID()),
        showAllRealms = state.shift,
        now = type(time) == "function" and time() or nil,
        visibility = settings and settings.visibilityFor(root, family) or {},
        available = settings and settings.availableColumns(family, catalog) or nil,
    })
end

local function ensureWindow()
    if window then return window end
    window = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    window:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = 1,
    })
    window:SetBackdropColor(0, 0, 0, 0.85)
    window:SetBackdropBorderColor(0, 0, 0, 1)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self) self:StartMoving() end)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local root = BG.BGNext.DB
        if root then
            root.settings = type(root.settings) == "table" and root.settings or {}
            root.settings.roleOverviewPoint = { self:GetPoint(1) }
        end
    end)

    local ui = BG.BGNext.OwnCharactersUI
    if ui then
        ui.SetFrame(window)
        ui.SetProvider(provider)
    end

    local controls = {
        { id = "settings", texture = ui and ui.textures.settings, action = "settings" },
        { id = "refresh", texture = ui and ui.textures.refresh, action = "refresh" },
        { id = "close", texture = nil, action = "close" },
    }
    local last
    for _, control in ipairs(controls) do
        local button = CreateFrame("Button", nil, window)
        button:SetSize(16, 16)
        if control.texture then
            button:SetNormalTexture(control.texture)
        else
            button:SetNormalFontObject(BG.FontWhite15)
            button:SetText("x")
        end
        if last then
            button:SetPoint("TOPRIGHT", last, "TOPLEFT", -3, 0)
        else
            button:SetPoint("TOPRIGHT", window, "TOPRIGHT", -3, -3)
        end
        last = button
        button.action = control.action
        button:SetScript("OnClick", function(self)
            if self.action == "settings" then
                if BG.OpenOption then
                    BG.OpenOption()
                    if BiaoGe and BiaoGe.options then BiaoGe.options.lastFrame = "FrameOptions_roleOverview" end
                end
            elseif self.action == "refresh" then
                M.refreshPlan()
                if ui and ui.Refresh then ui.Refresh() end
            else
                M.setPinned(false)
            end
        end)
    end

    return window
end

function M.setPinned(value)
    pinned = value and true or false
    state.pinned = pinned
    if window then
        window:SetShown(pinned)
        if pinned and BG.BGNext.OwnCharactersUI and BG.BGNext.OwnCharactersUI.Refresh then
            BG.BGNext.OwnCharactersUI.Refresh()
        end
    end
end

function M.isPinned()
    return pinned
end

function M.togglePinned()
    M.setPinned(not pinned)
end

function M.showPreview()
    ensureWindow()
    if not pinned then
        window:SetShown(true)
        if BG.BGNext.OwnCharactersUI and BG.BGNext.OwnCharactersUI.Refresh then
            BG.BGNext.OwnCharactersUI.Refresh()
        end
    end
end

function M.hidePreview()
    if not pinned then
        if window then window:Hide() end
    end
end

-- Builds the bottom-right "角色总览" entry next to the existing bottom button
-- chain. Uses only BGLite's own helpers and Blizzard textures.
function M.installEntry(mainFrame)
    if type(mainFrame) ~= "table" then return end
    if type(CreateFrame) ~= "function" then return end

    local button = BG.CreateButton(mainFrame)
    button:SetSize(60, 25)
    button:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -350, 38)
    button:SetText(L["角色总览"])
    BG.ButtonRoleOverview = button

    button:SetScript("OnEnter", M.showPreview)
    button:SetScript("OnLeave", M.hidePreview)
    button:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton == "MiddleButton" or (mouseButton == "LeftButton" and IsControlKeyDown()) then
            M.togglePinned()
        end
    end)

    -- Hold Shift to widen the preview to every local realm.
    local modifier = CreateFrame("Frame")
    modifier:RegisterEvent("MODIFIER_STATE_CHANGED")
    modifier:SetScript("OnEvent", function(_, _, key)
        if key == "LSHIFT" or key == "RSHIFT" then
            state.shift = IsShiftKeyDown()
            if window and window:IsVisible() and BG.BGNext.OwnCharactersUI and BG.BGNext.OwnCharactersUI.Refresh then
                BG.BGNext.OwnCharactersUI.Refresh()
            end
        end
    end)

    return button
end

-- Hooks /bgn and /bgnext so "role" opens the pinned overview instead of
-- toggling the main table. The original handler keeps toggling the main frame
-- for every other argument.
function M.installSlash()
    if type(hooksecurefunc) ~= "function" then return end
    hooksecurefunc("SlashCmdList", function(slash)
        if slash == "BGNEXT" then
            local original = SlashCmdList["BGNEXT"]
            if type(original) == "function" then
                SlashCmdList["BGNEXT"] = function(message)
                    if M.parseCommand(message) == "role" then
                        M.togglePinned()
                        return
                    end
                    original(message)
                end
            end
        end
    end)
end

BG.BGNext.RoleOverviewEntry = M
return M
