return function(T)
    local names = {'BG','C_Timer','GetTime','IsInRaid','IsInGroup','UnitIsGroupLeader',
        'InCombatLockdown','GetNumGroupMembers','UnitGUID','SendChatMessage','CreateFrame'}
    local old = {}; for _, key in ipairs(names) do old[key] = _G[key] end
    local events, callbacks, sent = {}, {}, {}
    local roster, leader, combat, raid, instance, clock = {'self','old'}, true, false, true, false, 0
    BG = {BGNext = { DB = {settings = {raidWelcome = {enabled = true, text = 'YY 123'}}}}}
    BG.RegisterEvent = function(list, callback)
        if type(list) == 'string' then list = {list} end
        for _, key in ipairs(list) do events[key] = callback end
    end
    GetTime = function() return clock end
    IsInRaid = function(category) T.eq(category, 1); return raid end
    IsInGroup = function(category) T.eq(category, 2); return instance end
    UnitIsGroupLeader = function(unit, category) T.eq(unit, 'player'); T.eq(category, 1); return leader end
    InCombatLockdown = function() return combat end
    GetNumGroupMembers = function() return #roster end
    UnitGUID = function(unit) return unit == 'player' and 'self' or roster[tonumber(unit:match('%d+'))] end
    C_Timer = {NewTimer = function(delay, callback)
        local timer = {callback = callback, delay = delay}
        function timer:Cancel() self.cancelled = true end
        callbacks[#callbacks + 1] = timer; return timer
    end}
    SendChatMessage = function(text, channel, language, target)
        T.eq(channel, 'RAID'); T.eq(target, nil); T.eq(language, nil)
        sent[#sent + 1] = text
    end
    local M = dofile('Core/BGNext/RaidWelcome.lua')
    local completeGUID = UnitGUID
    UnitGUID = function(unit) if unit ~= 'raid2' then return completeGUID(unit) end end
    T.eq(M.snapshot().raid, false, 'partial roster is not accepted')
    UnitGUID = completeGUID
    local completeCount = GetNumGroupMembers
    GetNumGroupMembers = function() return 0 end
    T.eq(M.snapshot().raid, false, 'empty roster is not a reliable baseline')
    GetNumGroupMembers = completeCount
    local rosterReads = 0
    GetNumGroupMembers = function() rosterReads = rosterReads + 1; return #roster end
    BG.BGNext.DB.settings.raidWelcome.enabled = false
    M.snapshot()
    T.eq(rosterReads, 0, 'disabled feature does not read roster identities')
    BG.BGNext.DB.settings.raidWelcome.enabled = true
    GetNumGroupMembers = completeCount
    M.install(); M.install()
    events.PLAYER_ENTERING_WORLD()
    roster[3] = 'new'; events.GROUP_ROSTER_UPDATE()
    T.eq(#callbacks, 1)
    clock = 3; callbacks[1].callback(); T.eq(#sent, 1)
    roster[4] = 'later'; events.GROUP_ROSTER_UPDATE()
    T.eq(callbacks[2].delay, 30)
    events.PLAYER_LEAVING_WORLD()
    T.eq(callbacks[2].cancelled, true)
    roster[5] = 'during-loading'; events.GROUP_ROSTER_UPDATE()
    roster[6] = 'also-loading'; events.GROUP_ROSTER_UPDATE()
    T.eq(#callbacks, 2, 'world leave suppresses subsequent roster events')
    clock = 60; callbacks[2].callback(); T.eq(#sent, 1, 'stale cancelled callback cannot send')
    events.PLAYER_ENTERING_WORLD(); events.GROUP_ROSTER_UPDATE()
    T.eq(#callbacks, 2, 'entering world never welcomes the baseline')
    roster[7] = 'after-loading'; events.GROUP_ROSTER_UPDATE()
    leader = false -- Revalidate even if the roster event has not yet fired.
    clock = 63; callbacks[3].callback(); T.eq(#sent, 1)
    events.GROUP_ROSTER_UPDATE(); leader = true; events.GROUP_ROSTER_UPDATE()
    roster[8] = 'send-fails'; events.GROUP_ROSTER_UPDATE()
    SendChatMessage = function() error('send unavailable') end
    clock = 100; callbacks[4].callback()
    events.GROUP_ROSTER_UPDATE(); T.eq(#callbacks, 4, 'no retry after a send exception')
    local root = BG.BGNext.DB
    T.eq(root.settings.raidWelcome.members, nil, 'roster is memory only')

    -- Exercise the real settings callbacks, including invalid draft + disable.
    local controls = {}
    local function frame()
        local f = {scripts = {}, width = 1, height = 1}
        function f:SetScript(key, value) self.scripts[key] = value end
        function f:HookScript(key, value) self.scripts[key] = value end
        function f:SetText(value) self.text = value end
        function f:GetText() return self.text or '' end
        function f:SetChecked(value) self.checked = value end
        function f:GetChecked() return self.checked end
        function f:SetSize(w,h) self.width = w; self.height = h end
        function f:GetWidth() return self.width end
        function f:GetHeight() return self.height end
        function f:GetStringHeight() return 60 end
        function f:SetWidth(value) self.width = value end
        function f:ClearFocus() self.focusCleared = true end
        for _, key in ipairs({'SetFont','SetPoint','SetJustifyH','SetAutoFocus','SetMaxBytes'}) do f[key] = function() end end
        function f:CreateFontString() return frame() end
        return f
    end
    CreateFrame = function(kind)
        local f = frame(); f.Text = frame(); controls[kind] = f; return f
    end
    local parent = frame()
    M.buildPanel(parent, -800)
    T.eq(parent:GetHeight() > 1000, true, 'scroll child includes new controls')
    local edit, check = controls.EditBox, controls.CheckButton
    edit:SetText('Updated YY'); edit.scripts.OnEnterPressed()
    T.eq(M.read(root).text, 'Updated YY')
    edit:SetText('|invalid'); check:SetChecked(false); check.scripts.OnClick(check)
    T.eq(M.read(root).enabled, false, 'invalid unsaved draft cannot block disable')
    T.eq(M.read(root).text, 'Updated YY')
    parent.scripts.OnHide(); T.eq(edit.focusCleared, true)
    for _, key in ipairs(names) do _G[key] = old[key] end
end
