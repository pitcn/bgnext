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

-- Decides whether a slash argument is the role command and, when it is, hands
-- off to the entry's own toggle so the original BGNEXT handler can skip
-- toggling the main table. Returns true when the command was consumed.
function M.dispatchSlash(message, entry)
    entry = type(entry) == "table" and entry or M
    if M.parseCommand(message) == "role" then
        if type(entry.togglePinned) == "function" then entry.togglePinned() end
        return true
    end
    return false
end

function M.showAllRealms(state)
    state = type(state) == "table" and state or {}
    return state.shift == true
end

function M.entryPresentation(classFile)
    local classKey = type(classFile) == "string" and classFile:lower() or "warrior"
    return {
        point = "BOTTOMRIGHT",
        relativePoint = "BOTTOMRIGHT",
        x = -20,
        y = 1,
        height = 25,
        text = "|A:GarrMission_ClassIcon-" .. classKey .. ":0:0|a" .. L["角色总览"],
    }
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

-- The confirmation text shown before a row delete. Names the exact character
-- and realm so a same-name cross-realm character can never be removed by
-- surprise. Returns a plain string free of format placeholders.
function M.deleteDialogText(request, row)
    if type(request) ~= "table" then return "" end
    local name = request.player or ""
    local realm = (type(row) == "table" and type(row.realmName) == "string" and row.realmName ~= "")
        and row.realmName or tostring(request.realmId or "")
    return string.format(L["确认删除角色 %s（%s）的记录？此操作不可撤销。"], name, realm)
end

-- Refresh re-reads the logged-in character and rebuilds the view. It does not
-- scan other players and sends nothing.
function M.refreshPlan()
    return { rereadCurrentCharacter = true, scanOtherPlayers = false, sendsMessage = false }
end

-- The left-to-right control order the window displays. The close control is
-- last so it sits at the far-right corner where users expect to dismiss.
function M.controlOrder()
    return { "settings", "refresh", "close" }
end

local VALID_ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local ANCHOR_X = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = 0.5, CENTER = 0.5,
    BOTTOM = 0.5, TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1 }
local ANCHOR_Y = { BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0, LEFT = 0.5, CENTER = 0.5,
    RIGHT = 0.5, TOPLEFT = 1, TOP = 1, TOPRIGHT = 1 }

-- Keeps only the serializable parts of a window anchor. GetPoint returns
-- (point, relativeTo, relativePoint, x, y); the middle frame can never go into
-- SavedVariables, so it is dropped and everything else is validated.
function M.sanitizePoint(point, relativeTo, relativePoint, x, y)
    if type(point) ~= "string" or not VALID_ANCHORS[point] then return nil end
    if type(relativePoint) ~= "string" or not VALID_ANCHORS[relativePoint] then return nil end
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    if x ~= x or y ~= y then return nil end
    return { point = point, relativePoint = relativePoint, x = x, y = y }
end

-- Reapplies a saved anchor only when every value is the expected type and the
-- position is somewhere a user could see it. Anything else yields nil so the
-- caller falls back to a sane default instead of restoring a bad position.
function M.restorePoint(saved, viewport)
    if type(saved) ~= "table" then return nil end
    if type(saved.point) ~= "string" or not VALID_ANCHORS[saved.point] then return nil end
    if type(saved.relativePoint) ~= "string" or not VALID_ANCHORS[saved.relativePoint] then return nil end
    if type(saved.x) ~= "number" or type(saved.y) ~= "number" then return nil end
    if saved.x ~= saved.x or saved.y ~= saved.y then return nil end
    if type(viewport) == "table" then
        local width, height = viewport.width, viewport.height
        local windowWidth, windowHeight = viewport.windowWidth or 0, viewport.windowHeight or 0
        if type(width) ~= "number" or type(height) ~= "number"
            or type(windowWidth) ~= "number" or type(windowHeight) ~= "number" then return nil end
        local targetX = width * ANCHOR_X[saved.relativePoint] + saved.x
        local targetY = height * ANCHOR_Y[saved.relativePoint] + saved.y
        local left = targetX - windowWidth * ANCHOR_X[saved.point]
        local bottom = targetY - windowHeight * ANCHOR_Y[saved.point]
        if left < 0 or bottom < 0 or left + windowWidth > width or bottom + windowHeight > height then
            return nil
        end
    elseif math.abs(saved.x) > 100000 or math.abs(saved.y) > 100000 then
        return nil
    end
    return { point = saved.point, relativePoint = saved.relativePoint, x = saved.x, y = saved.y }
end

--------------------------------------------------------------------------
-- Runtime wiring (inside the game only)
--------------------------------------------------------------------------

local pinned = false
local state = { pinned = pinned }
local window
local entryButton

function M.canOpen(runtime)
    runtime = runtime or BG.BGNext.OwnCharactersRuntime
    if runtime and type(runtime.isEnabled) == "function" then
        return runtime.isEnabled() == true
    end
    return true
end

local function provider()
    if not M.canOpen() then return nil end
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
    window:SetSize(480, 200)
    window:SetMovable(true)
    if window.SetClampedToScreen then window:SetClampedToScreen(true) end
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self) self:StartMoving() end)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local root = BG.BGNext.DB
        if root then
            root.settings = type(root.settings) == "table" and root.settings or {}
            local centerX, centerY = self:GetCenter()
            local parentX, parentY = UIParent:GetCenter()
            if type(centerX) == "number" and type(centerY) == "number"
                and type(parentX) == "number" and type(parentY) == "number" then
                local x = centerX - parentX
                local y = centerY - parentY
                root.settings.roleOverviewPoint = M.sanitizePoint("CENTER", UIParent, "CENTER", x, y)
            end
        end
    end)

    -- Restore the saved anchor when it is still valid; otherwise reset to a
    -- sensible default so a corrupt or off-screen position never strands the
    -- window where the user cannot reach it.
    window:ClearAllPoints()
    local root = BG.BGNext.DB
    local saved = root and type(root.settings) == "table" and root.settings.roleOverviewPoint
    local anchor = M.restorePoint(saved, {
        width = UIParent:GetWidth(),
        height = UIParent:GetHeight(),
        windowWidth = window:GetWidth(),
        windowHeight = window:GetHeight(),
    })
    if anchor then
        local ok = pcall(window.SetPoint, window, anchor.point, UIParent, anchor.relativePoint, anchor.x, anchor.y)
        if not ok then window:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
    else
        window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    local ui = BG.BGNext.OwnCharactersUI
    if ui then
        ui.SetFrame(window)
        ui.SetProvider(provider)
        ui.SetRowHandler(M.onRowRightClick)
    end

    -- Listed in the left-to-right order from M.controlOrder, then placed
    -- right-to-left so the close control lands at the far-right corner.
    local textures = ui and ui.textures or {}
    local order = M.controlOrder()
    local last
    for index = #order, 1, -1 do
        local id = order[index]
        local button = CreateFrame("Button", nil, window)
        button:SetSize(16, 16)
        if id == "close" then
            button:SetNormalFontObject(BG.FontWhite15)
            button:SetText("x")
        else
            button:SetNormalTexture(textures[id])
        end
        if last then
            button:SetPoint("TOPRIGHT", last, "TOPLEFT", -3, 0)
        else
            button:SetPoint("TOPRIGHT", window, "TOPRIGHT", -3, -3)
        end
        last = button
        button.action = id
        button:SetScript("OnClick", function(self)
            if self.action == "settings" then
                if BG.OpenOption then BG.OpenOption() end
                -- Switch straight to the 角色总览 settings page rather than
                -- dropping the user at whatever tab was open last.
                if BG.ButtonOptions_roleOverview then
                    BG.ButtonOptions_roleOverview:Click()
                end
            elseif self.action == "refresh" then
                local runtime = BG.BGNext.OwnCharactersRuntime
                if runtime and type(runtime.refresh) == "function" then
                    runtime.refresh()
                elseif ui and ui.Refresh then
                    ui.Refresh()
                end
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
    if pinned and not window then ensureWindow() end
    if window then
        window:SetShown(pinned)
        if pinned and BG.BGNext.OwnCharactersUI and BG.BGNext.OwnCharactersUI.Refresh then
            BG.BGNext.OwnCharactersUI.Refresh()
        end
    end
    local runtime = BG.BGNext.OwnCharactersRuntime
    if runtime and type(runtime.setVisible) == "function" then runtime.setVisible(nil, pinned) end
end

function M.isPinned()
    return pinned
end

function M.togglePinned()
    if not M.canOpen() then
        M.setPinned(false)
        return
    end
    M.setPinned(not pinned)
end

function M.showPreview()
    if not M.canOpen() then return end
    ensureWindow()
    if not pinned then
        window:SetShown(true)
        local runtime = BG.BGNext.OwnCharactersRuntime
        if runtime and type(runtime.setVisible) == "function" then runtime.setVisible(nil, true) end
        if BG.BGNext.OwnCharactersUI and BG.BGNext.OwnCharactersUI.Refresh then
            BG.BGNext.OwnCharactersUI.Refresh()
        end
    end
end

function M.setAvailable(value)
    local available = value and true or false
    if entryButton then entryButton:SetShown(available) end
    if not available then M.setPinned(false) end
end

function M.hidePreview()
    if not pinned then
        if window then window:Hide() end
        local runtime = BG.BGNext.OwnCharactersRuntime
        if runtime and type(runtime.setVisible) == "function" then runtime.setVisible(nil, false) end
    end
end

-- Right-clicking a row asks for the exact character's delete and, after the
-- built-in confirmation dialog is accepted, removes that one row and re-reads
-- the current character. Nothing else is scanned or sent.
function M.onRowRightClick(section, row)
    if type(section) ~= "string" or type(row) ~= "table" then return end
    local family = BG.BGNext.OwnCharactersAdapters and BG.BGNext.OwnCharactersAdapters.detect(BG)
    local request = M.deleteRequest(row, family)
    if not request then return end
    M.confirmDelete(request, row)
end

function M.confirmDelete(request, row)
    if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then return end
    StaticPopupDialogs["BGNextRoleOverviewDelete"] = {
        text = M.deleteDialogText(request, row),
        button1 = L["删除"],
        button2 = L["取消"],
        OnAccept = function()
            local root = BG.BGNext.DB
            if M.applyDelete(root, request, true) then
                if BG.BGNext.OwnCharactersUI and BG.BGNext.OwnCharactersUI.Refresh then
                    BG.BGNext.OwnCharactersUI.Refresh()
                end
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("BGNextRoleOverviewDelete")
end

-- Builds the bottom-right "角色总览" entry next to the existing bottom button
-- chain. Uses only BGLite's own helpers and Blizzard textures.
function M.installEntry(mainFrame)
    if type(mainFrame) ~= "table" then return end
    if type(CreateFrame) ~= "function" then return end

    if entryButton then return entryButton end
    local classFile
    if type(UnitClass) == "function" then
        local _, detected = UnitClass("player")
        classFile = detected
    end
    local presentation = M.entryPresentation(classFile)
    local button = CreateFrame("Button", nil, mainFrame)
    button:SetSize(20, presentation.height)
    button:SetPoint(presentation.point, mainFrame, presentation.relativePoint,
        presentation.x, presentation.y)
    if BG.FontYellow13 then button:SetNormalFontObject(BG.FontYellow13) end
    if BG.FontWhite13 then button:SetHighlightFontObject(BG.FontWhite13) end
    button:SetText(presentation.text)
    if button.GetFontString and button:GetFontString() then
        button:SetWidth(button:GetFontString():GetStringWidth())
    end
    BG.ButtonRoleOverview = button
    entryButton = button
    M.setAvailable(M.canOpen())

    button:SetScript("OnEnter", M.showPreview)
    button:SetScript("OnLeave", M.hidePreview)
    button:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton == "MiddleButton" or (mouseButton == "LeftButton" and IsControlKeyDown()) then
            M.togglePinned()
        end
    end)
    button:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "RightButton" then
            if BG.OpenOption then BG.OpenOption() end
            if BG.MainFrame and BG.MainFrame.Hide then BG.MainFrame:Hide() end
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

BG.BGNext.RoleOverviewEntry = M
return M
