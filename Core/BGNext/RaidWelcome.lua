BG = BG or {}
BG.BGNext = BG.BGNext or {}
local _, ns = ...
local L = ns and ns.L or setmetatable({}, { __index = function(_, key) return key end })
local M = {}

-- One ordinary chat line, with no markup or executable/template syntax.
function M.validText(text)
    return type(text) == 'string' and #text <= 240 and text:find('%S') ~= nil
        and not text:find('[%c|]')
end

function M.new(env)
    local previous, pending, timer, config, active, generation, lastSent = nil, {}, nil, nil, false, 0, -30
    local controller = {}
    local function cancel()
        generation = generation + 1
        if timer then timer:Cancel(); timer = nil end
        pending = {}
    end
    local function eligible(s)
        return s.enabled == true and s.leader == true and s.raid == true
            and not s.instance and not s.combat and type(s.members) == 'table' and M.validText(s.text)
    end
    local function copyRoster(s)
        local result = {}
        for member in pairs(s.members or {}) do result[member] = true end
        return result
    end
    function controller:reset()
        cancel(); previous = nil; active = false; config = nil
    end
    function controller:update()
        local s = env.snapshot()
        local allowed = eligible(s)
        if not allowed or not active or config ~= s.text then
            cancel()
            previous, active, config = copyRoster(s), allowed, s.text
            return
        end
        local exists = false
        for member in pairs(s.members) do
            if not previous[member] then pending[member] = true end
        end
        for member in pairs(pending) do
            if not s.members[member] then pending[member] = nil else exists = true end
        end
        previous = copyRoster(s)
        if not exists then cancel(); return end
        if timer then return end
        local token = generation
        timer = env.schedule(math.max(3, lastSent + 30 - env.now()), function()
            if token ~= generation then return end
            timer = nil
            local current, newcomer = env.snapshot(), false
            if eligible(current) and current.text == config then
                for member in pairs(pending) do
                    if current.members[member] then newcomer = true; break end
                end
            end
            cancel()
            if newcomer then
                lastSent = env.now()
                -- Consumed before sending: no retry, including a thrown send error.
                pcall(env.send, current.text, 'RAID')
            end
        end)
    end
    return controller
end

function M.read(root)
    local settings = type(root) == 'table' and root.settings
    local value = type(settings) == 'table' and settings.raidWelcome
    return type(value) == 'table' and value or {}
end

function M.configure(root, enabled, text)
    if type(root) ~= 'table' or type(text) ~= 'string' then return false end
    if not enabled and text ~= '' and not M.validText(text) then
        local prior = M.read(root).text
        text = M.validText(prior) and prior or ''
    end
    if enabled and not M.validText(text) then return false end
    root.settings = type(root.settings) == 'table' and root.settings or {}
    root.settings.raidWelcome = { enabled = enabled == true, text = text }
    if M.controller then M.controller:reset(); M.controller:update() end
    return true
end

-- Appended to Other Features, avoiding another crowded settings tab.
function M.buildPanel(parent, y)
    local function label(text, offset)
        local font = parent:CreateFontString(nil, 'OVERLAY')
        font:SetFont(BIAOGE_TEXT_FONT, 14, 'OUTLINE')
        font:SetPoint('TOPLEFT', parent, 20, y + offset)
        font:SetWidth(570); font:SetJustifyH('LEFT'); font:SetText(L[text])
        return font
    end
    label('入团欢迎语', 0)
    local note = label('仅团长开启后，新人入团时自动发到团队频道；多人入团合并发送，至少间隔30秒。内容对全团可见，请勿填写个人敏感信息。', -30)
    local offset = -40 - note:GetStringHeight()
    local check = CreateFrame('CheckButton', nil, parent, 'ChatConfigCheckButtonTemplate')
    check:SetPoint('TOPLEFT', parent, 20, y + offset)
    check.Text:SetFont(BIAOGE_TEXT_FONT, 14, 'OUTLINE')
    check.Text:SetText(L['启用入团欢迎语'])
    local edit = CreateFrame('EditBox', nil, parent, 'InputBoxTemplate')
    edit:SetPoint('TOPLEFT', parent, 25, y + offset - 40)
    edit:SetSize(550, 28); edit:SetAutoFocus(false); edit:SetMaxBytes(240)
    local status = label('填写一行欢迎语（最多240字节），按回车保存；不支持换行或颜色链接。', offset - 80)
    local function refresh()
        local config = M.read(BG.BGNext.DB)
        check:SetChecked(config.enabled == true)
        edit:SetText(type(config.text) == 'string' and config.text or '')
    end
    local function save(enabled)
        local ok = M.configure(BG.BGNext.DB, enabled, edit:GetText())
        status:SetText(L[ok and '欢迎语已保存。' or '请填写有效的一行欢迎语，最多240字节，不含颜色、链接或控制字符。'])
        if not ok then check:SetChecked(M.read(BG.BGNext.DB).enabled == true) end
        edit:ClearFocus()
    end
    check:SetScript('OnClick', function(self) save(self:GetChecked() and true or false) end)
    edit:SetScript('OnEnterPressed', function() save(check:GetChecked() and true or false) end)
    edit:SetScript('OnEscapePressed', function() edit:ClearFocus(); refresh() end)
    parent:HookScript('OnShow', refresh)
    parent:HookScript('OnHide', function() edit:ClearFocus(); refresh() end)
    refresh()
    local bottom = y + offset - 120 - status:GetStringHeight()
    parent:SetSize(math.max(600, parent:GetWidth()), math.max(parent:GetHeight(), -bottom + 20))
    return bottom
end

function M.snapshot()
    local value = M.read(BG.BGNext.DB)
    local s = { enabled = value.enabled, text = value.text, members = {} }
    if s.enabled ~= true or not M.validText(s.text) then return s end
    s.raid = type(IsInRaid) == 'function' and IsInRaid(1) == true
    s.leader = type(UnitIsGroupLeader) == 'function' and UnitIsGroupLeader('player', 1) == true
    s.instance = type(IsInGroup) ~= 'function' or IsInGroup(2) == true
    s.combat = type(InCombatLockdown) ~= 'function' or (InCombatLockdown() and true or false)
    if not s.leader or s.instance or s.combat then return s end
    if s.raid and type(GetNumGroupMembers) == 'function' and type(UnitGUID) == 'function' then
        local count = GetNumGroupMembers(1)
        if type(count) ~= 'number' or count < 1 or count > 40 or count % 1 ~= 0 then
            s.raid = false
            return s
        end
        for index = 1, count do
            local id = UnitGUID('raid' .. index)
            if type(id) ~= 'string' or id == '' or s.members[id] then s.raid = false; break end
            s.members[id] = true
        end
        local ownID = UnitGUID('player')
        if not ownID or not s.members[ownID] then s.raid = false end
    else s.raid = false end
    return s
end

function M.install()
    if M.controller or not BG.RegisterEvent or not C_Timer or not C_Timer.NewTimer
        or type(GetTime) ~= 'function' or type(SendChatMessage) ~= 'function' then return end
    local leavingWorld = false
    M.controller = M.new({ snapshot = function()
            if leavingWorld then return {enabled = false, members = {}} end
            return M.snapshot()
        end, now = GetTime,
        schedule = function(delay, callback) return C_Timer.NewTimer(delay, callback) end,
        send = function(text, channel) SendChatMessage(text, channel) end })
    BG.RegisterEvent({'GROUP_ROSTER_UPDATE', 'PLAYER_REGEN_DISABLED', 'PLAYER_REGEN_ENABLED'}, function()
        M.controller:update()
    end)
    BG.RegisterEvent('PLAYER_LEAVING_WORLD', function()
        leavingWorld = true
        M.controller:reset()
    end)
    BG.RegisterEvent('PLAYER_ENTERING_WORLD', function()
        leavingWorld = false
        M.controller:reset()
        M.controller:update()
    end)
end

BG.BGNext.RaidWelcome = M
if BG.Init then BG.Init(M.install) end
return M
