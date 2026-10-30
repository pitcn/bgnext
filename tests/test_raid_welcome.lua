return function(T)
    BG = { BGNext = {} }
    local M = dofile('Core/BGNext/RaidWelcome.lua')
    local now, sent, timers = 0, {}, {}
    local state = { enabled = true, text = 'Welcome YY 123', leader = true, raid = true,
        members = { self = true, old = true } }
    local controller = M.new({
        snapshot = function() return state end,
        now = function() return now end,
        schedule = function(delay, callback)
            local timer = { at = now + delay, callback = callback }
            function timer:Cancel() self.cancelled = true end
            timers[#timers + 1] = timer
            return timer
        end,
        send = function(text, channel) sent[#sent + 1] = {text, channel} end,
    })
    local function advance(seconds)
        now = now + seconds
        local due = timers; timers = {}
        for _, timer in ipairs(due) do
            if not timer.cancelled then
                if timer.at <= now then timer.callback() else timers[#timers + 1] = timer end
            end
        end
    end
    controller:update()
    advance(5)
    T.eq(#sent, 0, 'existing roster is a baseline')
    state.members.new = true; controller:update()
    state.members.other = true; controller:update(); controller:update()
    advance(3)
    T.eq(#sent, 1, 'newcomers and repeated events merge')
    T.eq(sent[1][1], state.text); T.eq(sent[1][2], 'RAID')
    state.members.next = true; controller:update(); advance(3)
    T.eq(#sent, 1, '30 second rate limit')
    state.enabled = false; controller:update(); advance(30)
    T.eq(#sent, 1, 'disable cancels pending')
    state.enabled = true; controller:update(); advance(40)
    T.eq(#sent, 1, 'enable never replays joins')
    local function blocked(change, restore, label)
        state.members.candidate = true; controller:update()
        change(); controller:update(); advance(40)
        T.eq(#sent, 1, label)
        restore(); state.members.candidate = nil; controller:update()
    end
    blocked(function() state.leader = false end, function() state.leader = true end, 'lost leadership')
    blocked(function() state.raid = false end, function() state.raid = true end, 'raid leave')
    blocked(function() state.combat = true end, function() state.combat = false end, 'combat cancels')
    blocked(function() state.instance = true end, function() state.instance = false end, 'instance group rejected')
    blocked(function() state.text = 'Changed' end, function() state.text = 'Welcome YY 123' end, 'edit cancels')
    state.members.gone = true; controller:update()
    state.members.gone = nil; controller:update(); advance(40)
    T.eq(#sent, 1, 'departed newcomer is not welcomed')
    state.members.world = true; controller:update(); controller:reset(); advance(40)
    T.eq(#sent, 1, 'world reset cancels timer')
    controller:update(); advance(40)
    T.eq(#sent, 1, 'reset establishes a fresh baseline')
    state.members.final = true; controller:update(); advance(3)
    T.eq(#sent, 2, 'next valid join sends normally')
    state.members.authorityRace = true; controller:update()
    state.leader = false -- No roster event before the timer fires.
    advance(30)
    T.eq(#sent, 2, 'callback independently rechecks leadership')
    state.leader = true; controller:update()
    for _, text in ipairs({'', '  ', 'line\nbreak', '|Hitem:1|h', string.rep('a', 241)}) do
        T.eq(M.validText(text) and true or false, false, 'reject unsafe chat text')
    end
    T.eq(M.validText('欢迎入团 YY：123') and true or false, true)
    T.eq(M.read({}).enabled, nil, 'default off without writing settings')
    local saved = {}
    T.eq(M.configure(saved, true, 'Welcome'), true)
    T.eq(M.read(saved).enabled, true)
    T.eq(M.configure(saved, true, '|bad'), false)
    T.eq(M.read(saved).text, 'Welcome', 'invalid edit preserves existing configuration')
    T.eq(M.configure(saved, false, '|bad'), true, 'disable must work even with invalid unsaved text')
    T.eq(M.read(saved).enabled, false)
    T.eq(M.read(saved).text, 'Welcome', 'disable keeps last valid text')
    T.eq(M.configure(saved, false, ''), true, 'clear and disable')
end
