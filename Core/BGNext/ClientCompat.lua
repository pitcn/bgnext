-- Capability-based adapters for shared client paths. No storage or sending.
BG.BGNext = BG.BGNext or {}
local M = {}

function M.bagLink(button, api)
    api = api or _G
    if not button or type(button.GetID) ~= "function" then return nil end
    local bag
    if type(button.GetBagID) == "function" then
        bag = button:GetBagID()
    elseif type(button.GetParent) == "function" then
        local parent = button:GetParent()
        if parent and type(parent.GetID) == "function" then bag = parent:GetID() end
    end
    local slot = button:GetID()
    local container = api.C_Container
    if type(bag) ~= "number" or type(slot) ~= "number" or not container
        or type(container.GetContainerItemLink) ~= "function" then return nil end
    return container.GetContainerItemLink(bag, slot)
end

function M.hookBagEvent(event, callback, api, retail)
    api = api or _G
    local hook = api.hooksecurefunc
    if type(hook) ~= "function" then return false end
    local globals = {
        click = retail and "ContainerFrameItemButton_OnClick" or "ContainerFrameItemButton_OnModifiedClick",
        enter = "ContainerFrameItemButton_OnEnter",
        leave = retail and "GameTooltip_Hide" or "ContainerFrameItemButton_OnLeave",
    }
    local name = globals[event]
    if name and type(api[name]) == "function" then
        hook(name, callback)
        return true
    end
    if event == "leave" and type(api.GameTooltip_Hide) == "function" then
        hook("GameTooltip_Hide", callback)
        return true
    end
    local method = ({ click = "OnClick", enter = "OnEnter", leave = "OnLeave" })[event]
    local mixin = api.ContainerFrameItemButtonMixin
    if method and type(mixin) == "table" and type(mixin[method]) == "function"
        and type(mixin.OnLoad) == "function" then
        -- Mixin methods were already copied onto existing buttons. Hook their
        -- actual scripts, then attach the same script to newly created buttons.
        local attached = setmetatable({}, { __mode = "k" })
        local function attach(button)
            if not attached[button] and type(button.HookScript) == "function" then
                button:HookScript(method, callback)
                attached[button] = true
            end
        end
        hook(mixin, "OnLoad", attach)
        local function scan(frame)
            if frame and type(frame.EnumerateItems) == "function" then
                for _, button in frame:EnumerateItems() do attach(button) end
            end
        end
        if type(api.ContainerFrameUtil_EnumerateContainerFrames) == "function" then
            for _, frame in api.ContainerFrameUtil_EnumerateContainerFrames() do scan(frame) end
        else
            scan(api.ContainerFrameCombinedBags)
            for i = 1, api.NUM_CONTAINER_FRAMES or 13 do scan(api["ContainerFrame" .. i]) end
        end
        return true
    end
    return false
end

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end

function M.talentIndex(flags, api)
    api = api or _G
    local namespace = api.C_SpecializationInfo
    if flags.IsForever or flags.verOver4 then
        local get = type(namespace) == "table" and namespace.GetSpecialization or api.GetSpecialization
        local index = safe(get)
        if type(api.issecretvalue) == "function" and api.issecretvalue(index) then return nil end
        if type(index) == "number" and index >= 1 and index <= 4 then return index end
        return nil
    end
    if type(api.GetTalentTabInfo) ~= "function" then return nil end
    local group = safe(api.GetActiveTalentGroup)
    local maximum, index = 0, nil
    for tree = 1, 3 do
        local ok, _, _, _, _, points = pcall(api.GetTalentTabInfo, tree, nil, nil, group)
        if ok and type(points) == "number" and points > 0 and points >= maximum then
            maximum, index = points, tree
        end
    end
    return index
end

BG.BGNext.ClientCompat = M
return M
