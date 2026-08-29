local currentAddonName = ...

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}
local knownNames = { BGLite = true, BiaoGe = true, BGNext = true }

function M.isKnownFamily(addon)
    if type(addon) ~= "table" then return false end
    if knownNames[addon.name] then return true end
    if addon.project == "BGNext" or addon.project == "BGLite" then return true end
    return type(addon.upstream) == "string" and addon.upstream:match("^BGLite[%s%-]?") ~= nil
end

function M.findConflicts(selfAddonName, addons)
    local result = {}
    for _, addon in ipairs(addons or {}) do
        if addon.name ~= selfAddonName
            and (addon.enabled == true or addon.loaded == true)
            and M.isKnownFamily(addon)
        then
            result[#result + 1] = addon
        end
    end
    table.sort(result, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return result
end

function M.conflictNames(conflicts)
    local names = {}
    for _, addon in ipairs(conflicts or {}) do
        names[#names + 1] = tostring(addon.name)
    end
    return table.concat(names, "、")
end

function M.disableConfirmed(conflicts, disableAddon, reloadUI)
    assert(type(disableAddon) == "function", "disableAddon callback required")
    assert(type(reloadUI) == "function", "reloadUI callback required")
    for _, addon in ipairs(conflicts or {}) do
        if disableAddon(addon.name) ~= true then
            return false
        end
    end
    reloadUI()
    return true
end

function M.buildInventory(runtime)
    local inventory = {}
    if type(runtime) ~= "table"
        or type(runtime.getNumAddOns) ~= "function"
        or type(runtime.getAddOnInfo) ~= "function"
    then
        return inventory
    end

    for index = 1, runtime.getNumAddOns() do
        local first, second = runtime.getAddOnInfo(index)
        local name, title
        if type(first) == "table" then
            name = first.name
            title = first.title
        else
            name = first
            title = second
        end

        if type(name) == "string" and name ~= "" then
            local enabled = type(runtime.getEnableState) == "function"
                and (runtime.getEnableState(name, index) or 0) > 0
                or false
            inventory[#inventory + 1] = {
                name = name,
                title = title,
                project = type(runtime.getMetadata) == "function" and runtime.getMetadata(name, "X-Project") or nil,
                upstream = type(runtime.getMetadata) == "function" and runtime.getMetadata(name, "X-Upstream") or nil,
                enabled = enabled,
                loaded = type(runtime.isLoaded) == "function" and runtime.isLoaded(name) == true or false,
            }
        end
    end
    return inventory
end

function M.installRuntime(selfAddonName, runtime)
    if type(runtime) ~= "table"
        or type(runtime.defineDialog) ~= "function"
        or type(runtime.onLogin) ~= "function"
        or type(runtime.showPopup) ~= "function"
    then
        return false
    end

    runtime.defineDialog(function(conflicts)
        if type(runtime.disableAddon) ~= "function" or type(runtime.reloadUI) ~= "function" then
            if runtime.notify then
                runtime.notify("无法自动禁用冲突插件，请手动禁用：" .. M.conflictNames(conflicts))
            end
            return false
        end
        local ok = M.disableConfirmed(conflicts, runtime.disableAddon, runtime.reloadUI)
        if not ok and runtime.notify then
            runtime.notify("无法自动禁用冲突插件，请手动禁用：" .. M.conflictNames(conflicts))
        end
        return ok
    end)

    local prompted = false
    runtime.onLogin(function()
        if prompted then return end
        local inventory = runtime.inventory or M.buildInventory(runtime)
        local conflicts = M.findConflicts(selfAddonName, inventory)
        if #conflicts == 0 then return end
        prompted = true
        runtime.showPopup(M.conflictNames(conflicts), conflicts)
    end)
    return true
end

local function createWoWRuntime()
    if type(CreateFrame) ~= "function"
        or type(StaticPopupDialogs) ~= "table"
        or type(StaticPopup_Show) ~= "function"
    then
        return nil
    end

    local modern = C_AddOns
    local getNumAddOns = modern and modern.GetNumAddOns or GetNumAddOns
    local getAddOnInfo = modern and modern.GetAddOnInfo or GetAddOnInfo
    local getMetadata = modern and modern.GetAddOnMetadata or GetAddOnMetadata
    local isLoaded = modern and modern.IsAddOnLoaded or IsAddOnLoaded
    if type(getNumAddOns) ~= "function" or type(getAddOnInfo) ~= "function" then
        return nil
    end

    local runtime = {
        getNumAddOns = getNumAddOns,
        getAddOnInfo = getAddOnInfo,
        getMetadata = getMetadata,
        isLoaded = isLoaded,
    }

    runtime.getEnableState = function(name)
        local player = UnitName and UnitName("player") or nil
        if modern and type(modern.GetAddOnEnableState) == "function" then
            return modern.GetAddOnEnableState(name, player)
        elseif type(GetAddOnEnableState) == "function" then
            return GetAddOnEnableState(player, name)
        end
        return 0
    end

    runtime.disableAddon = function(name)
        local player = UnitName and UnitName("player") or nil
        if modern and type(modern.DisableAddOn) == "function" then
            return pcall(modern.DisableAddOn, name, player)
        elseif type(DisableAddOn) == "function" then
            return pcall(DisableAddOn, name, player)
        end
        return false
    end

    runtime.reloadUI = ReloadUI
    runtime.notify = function(message)
        if print then print("<BGNext> " .. message) end
    end
    runtime.defineDialog = function(onAccept)
        StaticPopupDialogs.BGNEXT_DUPLICATE_ADDON = {
            text = "检测到多个表格/BGLite 系列插件同时启用：%s\n\n它们可能共用存档入口和团队通信协议，同时运行可能造成重复界面、重复消息或拍卖状态异常。建议只启用 BGNext。",
            button1 = "只保留 BGNext 并重载",
            button2 = "暂不处理",
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnAccept = function(_, conflicts)
                onAccept(conflicts)
            end,
        }
    end
    runtime.onLogin = function(callback)
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("PLAYER_LOGIN")
        frame:SetScript("OnEvent", callback)
    end
    runtime.showPopup = function(names, conflicts)
        StaticPopup_Show("BGNEXT_DUPLICATE_ADDON", names, nil, conflicts)
    end
    return runtime
end

if currentAddonName then
    local runtime = createWoWRuntime()
    if runtime then
        M.installRuntime(currentAddonName, runtime)
    end
end

BG.BGNext.ConflictGuard = M
return M
