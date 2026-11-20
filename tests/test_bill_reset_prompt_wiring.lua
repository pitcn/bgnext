-- Loads the real Core/Module/ClearBiaoGe.lua and the real prompt modules and
-- drives the Forever event path end to end: RAID_INSTANCE_WELCOME ->
-- UPDATE_INSTANCE_INFO and GROUP_ROSTER_UPDATE. The old StaticPopup must stay
-- silent on Forever, the addon-owned frame must be the only prompt, and other
-- clients must keep the original popup path.

local function readFile(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local function newWidget(kind, name, registry)
    local w = { kind = kind, name = name, scripts = {}, text = "", shown = false }
    local function chain(self) return self end
    for _, m in ipairs({ "SetSize", "SetPoint", "ClearAllPoints", "SetFrameStrata", "SetBackdrop",
        "SetBackdropColor", "SetBackdropBorderColor", "EnableMouse", "SetFont", "SetTextColor",
        "SetJustifyH", "SetWordWrap", "SetWidth", "SetAllPoints", "RegisterForClicks", "SetFormattedText" }) do
        w[m] = chain
    end
    function w:SetText(t) self.text = t end
    function w:GetText() return self.text end
    function w:SetScript(n, f) self.scripts[n] = f end
    function w:Show() self.shown = true end
    function w:Hide()
        if self.shown then
            self.shown = false
            if self.scripts.OnHide then self.scripts.OnHide(self) end
        end
    end
    function w:GetWidth() return 100 end
    function w:GetStringWidth() return 80 end
    function w:GetStringHeight() return 30 end
    function w:CreateFontString() return newWidget("FontString", nil, registry) end
    function w:GetFontString() self.fontString = self.fontString or newWidget("FontString", nil, registry); return self.fontString end
    function w:Click() if self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end end
    if name and registry then registry[name] = w end
    return w
end

return function(test)
    local saved = {}
    local function setG(k, v) if saved[k] == nil then saved[k] = { _G[k] } end _G[k] = v end

    local env = { events = {}, clearCalls = {}, popups = {}, messages = {}, created = {}, frames = {} }
    setG("UIParent", {})
    setG("UISpecialFrames", {})
    setG("StaticPopupDialogs", {})
    setG("StaticPopup_Show", function(which) env.popups[#env.popups + 1] = which end)
    setG("CreateFrame", function(kind, name, parent, template)
        env.created[#env.created + 1] = name or kind
        return newWidget(kind, name, env.frames)
    end)

    local oldBG = BG
    BG = { BGNext = {} }
    local L = setmetatable({}, { __index = function(_, k) return k end })

    dofile("Core/BGNext/AutoClearGuard.lua")
    dofile("Core/BGNext/BillResetPrompt.lua")
    assert(loadfile("Core/BGNext/BillResetPromptUI.lua"))("BGLite", { L = L })

    BG.IsForever = true
    BG.IsVanilla, BG.IsRetail, BG.verOver4 = false, false, false
    BG.playerName = "Test Name"
    BG.realmName = "R"
    BG.FB1 = "MC"
    BG.FBtable = { "MC", "ZUG" }
    BG.FBMainFrame = newWidget("Frame")
    BG.MainFrame = newWidget("Frame")
    BG.CreateButton = function() return newWidget("Button", nil, nil) end
    BG.GameTooltip_Hide = function() end
    BG.IsTBCFB = function() return false end
    BG.RegisterEvent = function(event, handler) env.events[event] = handler end
    BG.After = function(delay, cb) cb() end
    BG.FBIDtable = { [1234] = "MC", [5678] = "ZUG" }
    BG.bossPositionStartEnd = { [1234] = { 1, 2 }, [5678] = { 1, 2 } }
    BG.ClickFBbutton = function() end
    BG.SendSystemMessage = function(msg) env.messages[#env.messages + 1] = msg end
    BG.PlaySound = function() end
    BG.GetFBinfo = function(fb, key)
        if key == "maxplayers" then return 25 end
        if key == "shortName" then return "Name-" .. fb end
        return fb
    end
    BG.STC_b1 = function(s) return s end
    local Maxb = { MC = 5, ZUG = 5, TINY = 0 }
    BG.Frame = {
        MC = { boss7 = { jine5 = newWidget("Frame") } },
        ZUG = { boss7 = { jine5 = newWidget("Frame") } },
    }
    local hasContent = { MC = true, ZUG = false }
    BG.BiaoGeHavedItem = function(fb) return hasContent[fb] end
    BG.raidRosterInfo = { { name = "A" }, { name = "B" }, { name = "C" } }

    BiaoGe = { options = {}, MC = { raidRoster = { time = 500, realm = "R", roster = { "X", "Y", "Z" } } }, ZUG = {} }
    BG.BGNext.DB = {}

    local inCombat, inRaid, inInstance, members = false, true, true, 25
    local currentInstanceID = 1234
    setG("GetRealmID", function() return 1 end)
    setG("GetMoney", function() return 10000 end)
    setG("GetServerTime", function() return 1000 end)
    setG("IsAddOnLoaded", function() end)
    setG("GetLootMethod", function() end)
    setG("BIAOGE_TEXT_FONT", "Font")
    setG("min", math.min); setG("max", math.max); setG("format", string.format)
    setG("floor", math.floor); setG("date", os.date); setG("tinsert", table.insert)
    setG("GameTooltip_Hide", function() end)
    setG("GetInstanceInfo", function() return nil, nil, 14, nil, 25, nil, nil, currentInstanceID end)
    setG("GetNumSavedInstances", function() return 0 end)
    setG("RequestRaidInfo", function() end)
    setG("IsInInstance", function() return inInstance end)
    setG("InCombatLockdown", function() return inCombat end)
    setG("IsInRaid", function() return inRaid end)
    setG("GetNumGroupMembers", function() return members end)

    local chunk = assert(loadfile("Core/Module/ClearBiaoGe.lua"))
    chunk("BGLite", { L = L, SetClassCFF = function() end, AddTexture = function() end, Maxb = Maxb,
        HopeMaxn = {}, HopeMaxi = {}, canShowTBC = true })
    BG.ClearBiaoGeUI()

    -- Any new Blizzard dialog registration from now on is a failure.
    setmetatable(StaticPopupDialogs, { __newindex = function(_, k) error("StaticPopupDialogs write: " .. tostring(k)) end })

    local realClear = BG.ClearBiaoGe
    BG.ClearBiaoGe = function(_, fb) env.clearCalls[#env.clearCalls + 1] = fb; return 25 end

    local function fireCycle()
        env.events["RAID_INSTANCE_WELCOME"]()
        env.events["UPDATE_INSTANCE_INFO"]()
    end
    local function frame() return env.frames["BGNextBillResetPromptFrame"] end
    local function esc()
        for _, name in ipairs(UISpecialFrames) do
            local f = env.frames[name]
            if f and f.shown then f:Hide() end
        end
    end
    local function closeAndForget()
        BG.BGNext.BillResetPromptUI.hide()
        BG.BGNext.DB.billResetPrompt = nil
        env.clearCalls, env.popups, env.messages = {}, {}, {}
    end

    -- Lazy creation: nothing is built before the first prompt.
    local createdBefore = #env.created
    BiaoGe.options.foreverBillResetPrompt = 1
    inCombat = false
    -- 9. Forever: the legacy StaticPopup stays silent, the own frame prompts.
    test.eq(frame(), nil, "no prompt frame before the first prompt")
    fireCycle()
    test.eq(#env.popups, 0, "Forever never shows AUTO_QINGKONG_CONFIRM")
    test.eq(frame() ~= nil and frame().shown, true, "addon-owned prompt frame is shown")
    test.eq(#env.created > createdBefore, true, "frame was created on demand")
    test.eq(frame().message.text:find("新团队", 1, true) ~= nil and frame().message.text:find("进度已重置", 1, true) ~= nil,
        true, "both reasons are named")
    test.eq(frame().message.text:find("Name-MC", 1, true) ~= nil, true, "table name is shown")
    test.eq(frame().clearButton.text, "清空上次账单", "clear button label")
    test.eq(frame().keepButton.text, "保留", "keep button label")
    local escCount = 0
    for _, n in ipairs(UISpecialFrames) do if n == "BGNextBillResetPromptFrame" then escCount = escCount + 1 end end
    test.eq(escCount, 1, "registered with UISpecialFrames exactly once")

    -- 11. Repeated events and clicks never double clear or double prompt.
    fireCycle()
    test.eq(#env.created > 0, true, "second event is tolerated")
    local clearBtn = frame().clearButton
    clearBtn:Click(); clearBtn:Click()
    test.eq(#env.clearCalls, 1, "clear runs exactly once")
    test.eq(env.clearCalls[1], "MC", "clear targets the prompted table")
    test.eq(frame().shown, false, "prompt closes after clear")
    test.eq(#env.popups, 0, "still no StaticPopup")
    test.eq(BG.BGNext.DB.billResetPrompt ~= nil, true, "answer recorded (real clear removes it)")

    -- 10. Keep, Esc and hide never clear and are not asked again.
    closeAndForget()
    fireCycle()
    frame().keepButton:Click()
    test.eq(#env.clearCalls, 0, "keep never clears")
    local marker = BG.BGNext.DB.billResetPrompt
    test.eq(marker.fb, "MC", "marker names the table only")
    fireCycle()
    test.eq(frame().shown, false, "answered question is not asked again")
    closeAndForget()
    fireCycle()
    esc()
    test.eq(#env.clearCalls, 0, "Esc never clears")
    test.eq(frame().shown, false, "Esc closes the prompt")
    fireCycle()
    test.eq(frame().shown, false, "Esc counts as keep")
    closeAndForget()
    fireCycle()
    frame():Hide()
    test.eq(#env.clearCalls, 0, "hide never clears")
    closeAndForget()

    -- Guard accept re-checks content: an emptied table is not cleared.
    fireCycle()
    hasContent.MC = false
    frame().clearButton:Click()
    test.eq(#env.clearCalls, 0, "emptied table is not cleared")
    hasContent.MC = true
    closeAndForget()

    -- Option gating and migration from the legacy switch.
    BiaoGe.options.foreverBillResetPrompt = 0
    fireCycle()
    test.eq(frame().shown, false, "disabled switch never prompts")
    BiaoGe.options.foreverBillResetPrompt = nil
    BiaoGe.options.autoQingKong = 0
    fireCycle()
    test.eq(frame().shown, false, "legacy switch off migrates to off")
    BiaoGe.options.autoQingKong = nil
    fireCycle()
    test.eq(frame().shown, true, "no stored choice defaults to on")
    closeAndForget()
    BiaoGe.options.foreverBillResetPrompt = 1
    BiaoGe.options.autoQingKong = 0
    fireCycle()
    test.eq(frame().shown, true, "new switch wins over the legacy one")
    closeAndForget()
    BiaoGe.options.autoQingKong = nil

    -- 7. Combat: never shown, re-evaluated after combat.
    inCombat = true
    fireCycle()
    test.eq(frame().shown, false, "no prompt in combat")
    inCombat = false
    env.events["PLAYER_REGEN_ENABLED"]()
    test.eq(frame().shown, true, "prompt appears after combat")
    closeAndForget()
    inCombat = true
    fireCycle()
    hasContent.MC = false
    inCombat = false
    env.events["PLAYER_REGEN_ENABLED"]()
    test.eq(frame().shown, false, "table cleared during combat drops the request")
    hasContent.MC = true
    inCombat = true
    fireCycle()
    inInstance = false
    inCombat = false
    env.events["PLAYER_REGEN_ENABLED"]()
    test.eq(frame().shown, false, "leaving the instance during combat drops the request")
    inInstance = true
    inCombat = true
    fireCycle()
    currentInstanceID = 5678
    inCombat = false
    env.events["PLAYER_REGEN_ENABLED"]()
    test.eq(frame().shown, false, "changing instance during combat drops the request")
    currentInstanceID = 1234
    -- Already visible when combat starts: it stays.
    fireCycle()
    inCombat = true
    test.eq(frame().shown, true, "a visible prompt survives combat")
    inCombat = false
    closeAndForget()

    -- Team trigger: entering a raid without entering an instance.
    inRaid, members = false, 0
    env.events["GROUP_LEFT"]()
    env.events["GROUP_ROSTER_UPDATE"]()
    test.eq(frame().shown, false, "not in a raid: nothing")
    inRaid, members = true, 25
    env.events["GROUP_ROSTER_UPDATE"]()
    test.eq(frame().shown, true, "joining a new raid prompts")
    test.eq(frame().message.text:find("进度已重置", 1, true), nil, "team prompt does not claim a reset")
    frame().keepButton:Click()
    env.events["GROUP_ROSTER_UPDATE"]()
    test.eq(frame().shown, false, "one prompt per party")
    members = 26
    env.events["GROUP_ROSTER_UPDATE"]()
    test.eq(frame().shown, false, "small roster churn does not re-ask")
    inRaid = false
    env.events["GROUP_LEFT"]()
    inRaid = true
    env.events["GROUP_ROSTER_UPDATE"]()
    test.eq(frame().shown, true, "leaving and joining another raid asks again")
    closeAndForget()
    -- Same team (high overlap, fresh roster) never asks.
    BiaoGe.MC.raidRoster = { time = 990, realm = "R", roster = { "A", "B", "C" } }
    inRaid = false
    env.events["GROUP_LEFT"]()
    inRaid = true
    env.events["GROUP_ROSTER_UPDATE"]()
    test.eq(frame().shown, false, "same team does not ask")
    -- PLAYER_ENTERING_WORLD while grouped evaluates too (marker de-duplicates).
    BiaoGe.MC.raidRoster = { time = 500, realm = "R", roster = { "X", "Y", "Z" } }
    env.events["PLAYER_ENTERING_WORLD"]()
    test.eq(frame().shown, true, "reload inside a raid evaluates once")
    frame().keepButton:Click()
    env.events["PLAYER_ENTERING_WORLD"]()
    test.eq(frame().shown, false, "reload does not re-ask after an answer")
    closeAndForget()

    -- Review fix: a reset prompt for another table (ZUG) must not wipe the
    -- new-team answer for the last bill (MC); a reload must stay silent.
    BiaoGe.ZUG = { raidRoster = { time = 100, realm = "R", roster = { "X", "Y", "Z" } } }
    hasContent.ZUG = true
    inRaid = false
    env.events["GROUP_LEFT"]()
    inRaid = true
    env.events["GROUP_ROSTER_UPDATE"]()
    test.eq(frame().shown, true, "joining a new raid asks about the last bill")
    test.eq(frame().message.text:find("Name-MC", 1, true) ~= nil, true, "team prompt names the last bill")
    frame().keepButton:Click()
    currentInstanceID = 5678
    fireCycle()
    test.eq(frame().shown, true, "a reset of another raid's table asks")
    test.eq(frame().message.text:find("Name-ZUG", 1, true) ~= nil, true, "reset prompt names the instance table")
    test.eq(frame().message.text:find("新团队", 1, true), nil,
        "the instance table is not the last bill, so it does not repeat the new-team reason")
    frame().keepButton:Click()
    env.events["PLAYER_ENTERING_WORLD"]()
    test.eq(frame().shown, false, "reload after both answers does not re-ask the last bill")
    fireCycle()
    test.eq(frame().shown, false, "reload after both answers does not re-ask the reset")
    currentInstanceID = 1234
    hasContent.ZUG = false
    BiaoGe.ZUG = {}
    closeAndForget()

    -- Review fix: leaving the group while offline (or logging another
    -- character in) never fires GROUP_LEFT. Arriving in the world outside any
    -- group ends the previous party, so the next raid is asked again.
    setG("IsInGroup", function() return inRaid end)
    inRaid = false
    env.events["GROUP_LEFT"]()
    inRaid = true
    env.events["GROUP_ROSTER_UPDATE"]()
    test.eq(frame().shown, true, "new raid asks")
    frame().keepButton:Click()
    inRaid = false
    env.events["PLAYER_ENTERING_WORLD"]()
    test.eq(BG.BGNext.DB.billResetPrompt.newTeamAsked, nil, "entering the world ungrouped ends the party answer")
    inRaid = true
    env.events["GROUP_ROSTER_UPDATE"]()
    test.eq(frame().shown, true, "a raid joined after an offline leave asks again")
    closeAndForget()

    -- Review fix: saved-instance rows without the instance id (14th return)
    -- cannot prove anything; the reset check must fail closed, not treat
    -- every entry as a fresh lockout.
    BiaoGe.MC.raidRoster = { time = 990, realm = "R", roster = { "A", "B", "C" } } -- same team
    setG("GetNumSavedInstances", function() return 1 end)
    setG("GetSavedInstanceInfo", function()
        return "MC", 900, 0, 14, true, false, false, false, 25
    end)
    fireCycle()
    test.eq(frame().shown, false, "saved instances without an instance id never claim a reset")
    setG("GetNumSavedInstances", function() return 0 end)
    BiaoGe.MC.raidRoster = { time = 500, realm = "R", roster = { "X", "Y", "Z" } }
    closeAndForget()

    -- Locked-on-entry: a changed lockout id is a reset, the first lock is a baseline.
    local lockId = 900
    setG("GetNumSavedInstances", function() return 1 end)
    setG("GetSavedInstanceInfo", function()
        return "MC", lockId, 0, 14, true, false, false, false, 25, nil, nil, nil, nil, 1234
    end)
    BiaoGe.MC.raidRoster = { time = 990, realm = "R", roster = { "A", "B", "C" } } -- same team
    fireCycle()
    test.eq(frame().shown, false, "first locked entry only records a baseline")
    fireCycle()
    test.eq(frame().shown, false, "same lockout id does not ask")
    lockId = 901
    fireCycle()
    test.eq(frame().shown, true, "a new lockout id asks")
    test.eq(frame().message.text:find("进度已重置", 1, true) ~= nil, true, "reset reason named")
    closeAndForget()
    setG("GetNumSavedInstances", function() return 0 end)

    -- Fail closed on API errors.
    setG("GetSavedInstanceInfo", nil)
    setG("GetNumSavedInstances", function() return 1 end)
    BiaoGe.MC.raidRoster = { time = 500, realm = "R", roster = { "X", "Y", "Z" } }
    local okCall = pcall(fireCycle)
    test.eq(okCall, true, "missing saved-instance API never raises")
    test.eq(frame().shown, false, "missing saved-instance API never prompts")
    setG("GetNumSavedInstances", function() return 0 end)
    closeAndForget()

    -- Other clients keep the original path and see no new prompt.
    BG.IsForever = false
    BiaoGe.options.autoQingKong = 1
    fireCycle()
    test.eq(#env.popups, 1, "non-Forever still uses the original StaticPopup")
    test.eq(env.popups[1], "AUTO_QINGKONG_CONFIRM", "original dialog key")
    test.eq(frame().shown, false, "non-Forever never shows the new frame")
    BiaoGe.options.autoQingKong = 0
    env.popups = {}
    fireCycle()
    test.eq(#env.popups, 0, "legacy switch still disables the original path")
    BiaoGe.options.autoQingKong = nil
    BG.IsForever = true

    -- Real clear removes the scoped marker.
    BG.ClearBiaoGe = realClear
    BG.Maxi, BG.playerClass = 0, {}
    BG.IsTitan = true
    BG.Frame.TINY = { boss1 = {}, boss2 = { jine4 = newWidget("Frame") } }
    BG.DuiZhangFrame = { TINY = {} }
    BG.UpdateAuctionLogFrame = function() end
    BG.auctionLogFrame = { changeFrame = newWidget("Frame") }
    BG.GetMaxi = function() return 0 end
    BiaoGe.TINY = { tradeTbl = { "old" }, raidRoster = {}, boss2 = {} }
    BiaoGe.clearBiaoGeMoney = nil
    BG.BGNext.DB.billResetPrompt = { fb = "MC", billStamp = 1, newTeamAsked = true, at = 1000 }
    BG.ClearBiaoGe("biaoge", "TINY")
    test.eq(BG.BGNext.DB.billResetPrompt ~= nil, true, "clearing another table keeps the marker")
    BG.BGNext.DB.billResetPrompt = { fb = "TINY", billStamp = 1, newTeamAsked = true, at = 1000 }
    BG.ClearBiaoGe("biaoge", "TINY")
    test.eq(BG.BGNext.DB.billResetPrompt, nil, "real ClearBiaoGe deletes the scoped marker")

    -- 12. Static guards on the new files.
    for _, path in ipairs({ "Core/BGNext/BillResetPrompt.lua", "Core/BGNext/BillResetPromptUI.lua" }) do
        local source = readFile(path)
        for _, pattern in ipairs({ "StaticPopupDialogs", "StaticPopup_", "hooksecurefunc", "ContainerFrameUtil_",
            "_G%[.-%]%s*=", "raidRoster%.roster", "EnableKeyboard", "SetPropagateKeyboardInput", "securecall",
            "UnitGUID", "UnitName", "GetRaidRosterInfo" }) do
            test.eq(source:find(pattern), nil, path .. " must not contain " .. pattern)
        end
        test.eq(source:find('SetFrameStrata%("DIALOG"') == nil and source:find('SetFrameStrata%("FULLSCREEN') == nil,
            true, path .. " stays below dialog strata")
    end
    local toc = readFile("BGLite.toc")
    local guardAt = toc:find("Core\\BGNext\\AutoClearGuard.lua", 1, true)
    local logicAt = toc:find("Core\\BGNext\\BillResetPrompt.lua", 1, true)
    local uiAt = toc:find("Core\\BGNext\\BillResetPromptUI.lua", 1, true)
    test.eq(guardAt ~= nil and logicAt ~= nil and uiAt ~= nil and guardAt < logicAt and logicAt < uiAt, true,
        "TOC loads both prompt files after AutoClearGuard")

    BG = oldBG
    for k, v in pairs(saved) do _G[k] = v[1] end
end
