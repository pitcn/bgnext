BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

local groups = {
    { id = "personal", titleKey = "个人工具" },
    { id = "auction", titleKey = "拍卖工具" },
    { id = "settlement", titleKey = "结算工具" },
    { id = "interface", titleKey = "界面与隐私" },
}

local allClients = {
    vanilla = true, tbc = true, wrath = true, cata = true,
    titan = true, mop = true, retail = true,
}

local function clients()
    local result = {}
    for family, enabled in pairs(allClients) do result[family] = enabled end
    return result
end

local entries = {
    { id = "wishlist", group = "personal", policy = "optional", basic = false,
        nameKey = "心愿清单", summaryKey = "记录装备需求，并用备选、次 BIS、BIS 表示优先级。",
        clients = clients(), commands = {}, interactions = { "wishlist_mouse_wheel" } },
    { id = "role_overview", group = "personal", policy = "optional", basic = false,
        nameKey = "角色总览", summaryKey = "集中查看自己登录过的角色信息和进度。",
        clients = clients(), commands = { "/bgn role" }, interactions = {} },
    { id = "equipment_filter", group = "personal", policy = "optional", basic = false,
        nameKey = "装备过滤", summaryKey = "按角色与专精减少不相关装备显示。",
        clients = clients(), commands = {}, interactions = {} },
    { id = "compatibility", group = "auction", policy = "required", basic = true,
        nameKey = "基础兼容", summaryKey = "保持与官方 BGLite 的表格和团队流程兼容。",
        clients = clients(), commands = { "/bgn", "/bgnext", "/bgo", "/bgm" },
        interactions = { "table_right_click", "table_ctrl_right_click", "table_alt_right_click", "table_shift_right_click" } },
    { id = "auction_safety", group = "auction", policy = "required", basic = true,
        nameKey = "开拍安全检查", summaryKey = "发送拍卖前复核权限、团队、战斗状态和价格。",
        clients = clients(), commands = {}, interactions = {} },
    { id = "auction_prices", group = "auction", policy = "optional", basic = false,
        nameKey = "价格预设", summaryKey = "保存团本起拍价方案和单件价格。",
        clients = clients(), commands = {}, interactions = {} },
    { id = "auction_queue", group = "auction", policy = "optional", basic = false,
        nameKey = "待拍队列", summaryKey = "把多件装备加入队列，逐件确认后开拍。",
        clients = clients(), commands = { "/bgnqueue", "/bgnq" }, interactions = { "loot_auction_button" } },
    { id = "trade_capture", group = "settlement", policy = "required", basic = true,
        nameKey = "交易事实采集", summaryKey = "在本地记录当前团的实际交易结果。",
        clients = clients(), commands = {}, interactions = {} },
    { id = "data_lifecycle", group = "settlement", policy = "required", basic = true,
        nameKey = "数据生命周期", summaryKey = "限制当前结算数据的范围和保留时间。",
        clients = clients(), commands = {}, interactions = {} },
    { id = "settlement_tools", group = "settlement", policy = "optional", basic = false,
        nameKey = "结算记录与检查", summaryKey = "查看当前团交易、邮件、退货标记和结算前检查。",
        clients = clients(), commands = {}, interactions = {} },
    { id = "trade_announcement", group = "settlement", policy = "optional", basic = false,
        nameKey = "交易通报", summaryKey = "交易完成后按设置发送团队通报。",
        clients = clients(), commands = {}, interactions = {} },
    { id = "storage_privacy", group = "interface", policy = "required", basic = true,
        nameKey = "存储与隐私", summaryKey = "说明本地保存内容，并提供清理控制。",
        clients = clients(), commands = {}, interactions = {} },
    { id = "appearance", group = "interface", policy = "optional", basic = false,
        nameKey = "外观增强", summaryKey = "使用 BGNext 的主题、缩放和界面优化。",
        clients = clients(), commands = {}, interactions = {} },
}

local entryById = {}
for _, entry in ipairs(entries) do entryById[entry.id] = entry end

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    return result
end

function M.all() return copy(entries) end
function M.get(id) return entryById[id] and copy(entryById[id]) or nil end
function M.groups() return copy(groups) end

function M.available(entryOrId, family)
    local entry = type(entryOrId) == "table" and entryOrId or entryById[entryOrId]
    return entry ~= nil and entry.clients ~= nil and entry.clients[family] == true
end

function M.publicActions()
    return copy({
        commands = { "/bgn", "/bgnext", "/bgo", "/bgm", "/bgnqueue", "/bgnq" },
        interactions = {
            "table_right_click", "table_ctrl_right_click", "table_alt_right_click",
            "table_shift_right_click", "wishlist_mouse_wheel", "loot_auction_button",
        },
    })
end

function M.validate()
    local errors, groupSeen, idSeen = {}, {}, {}
    for _, group in ipairs(groups) do groupSeen[group.id] = true end
    for _, entry in ipairs(entries) do
        if type(entry.id) ~= "string" or entry.id == "" or idSeen[entry.id] then
            errors[#errors + 1] = "duplicate or invalid feature id: " .. tostring(entry.id)
        end
        idSeen[entry.id] = true
        if not groupSeen[entry.group] then errors[#errors + 1] = "unknown group: " .. tostring(entry.group) end
        if entry.policy ~= "required" and entry.policy ~= "optional" then
            errors[#errors + 1] = "invalid policy: " .. tostring(entry.id)
        end
        if entry.policy == "required" and entry.basic ~= true then
            errors[#errors + 1] = "required feature must be in basic mode: " .. tostring(entry.id)
        end
        for _, dependency in ipairs(entry.depends or {}) do
            if not entryById[dependency] then errors[#errors + 1] = "unknown dependency: " .. tostring(dependency) end
        end
    end
    return #errors == 0, errors
end

BG.BGNext.FeatureCatalog = M
return M
