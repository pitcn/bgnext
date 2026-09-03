-- Exercises the real Core/Module/ClearBiaoGe.lua popup wiring end to end,
-- including Blizzard's StaticPopup reuse semantics. The baseline file is
-- loaded through its TOC varargs and its real event path is driven
-- (RAID_INSTANCE_WELCOME -> UPDATE_INSTANCE_INFO -> CheckCD), so the pending
-- request must be bound to the dialog data and never cancelled by a stale
-- global slot.

local function fakeWidget()
    local w = {}
    function w:SetSize() return self end
    function w:SetPoint() return self end
    function w:SetText() return self end
    function w:SetFormattedText() return self end
    function w:RegisterForClicks() return self end
    function w:SetScript() return self end
    function w:GetWidth() return 100 end
    function w:GetStringWidth() return 80 end
    function w:SetWidth() return self end
    function w:SetFont() return self end
    function w:SetAllPoints() return self end
    function w:SetJustifyH() return self end
    function w:SetTextColor() return self end
    function w:SetWordWrap() return self end
    function w:ClearAllPoints() return self end
    function w:Show() return self end
    function w:Hide() return self end
    function w:CreateFontString() return fakeWidget() end
    return w
end

local function makePopup()
    local h = { dialogs = {}, visible = {}, events = {}, clearCalls = {}, messages = {}, sounds = {} }
    function h.show(which, text_arg1, text_arg2, data, data2)
        local info = h.dialogs[which]
        if h.visible[which] then
            -- Blizzard reuses the already-shown dialog for the same key: it
            -- tears the old one down first, firing OnCancel with the OLD data,
            -- then binds the new request.
            local old = h.visible[which]
            if info and info.OnCancel then
                info.OnCancel({ data = old.data, data2 = old.data2 }, old.data, old.data2)
            end
        end
        h.visible[which] = { data = data, data2 = data2, text_arg1 = text_arg1 }
        return which
    end
    function h.accept(which)
        local info = h.dialogs[which]
        local cur = h.visible[which]
        if info and info.OnAccept and cur then
            info.OnAccept({ data = cur.data, data2 = cur.data2 }, cur.data, cur.data2)
            h.visible[which] = nil
        end
    end
    function h.cancel(which)
        local info = h.dialogs[which]
        local cur = h.visible[which]
        if info and info.OnCancel and cur then
            info.OnCancel({ data = cur.data, data2 = cur.data2 }, cur.data, cur.data2)
            h.visible[which] = nil
        end
    end
    function h.esc(which)
        -- hideOnEscape hides without firing OnCancel; the dialog data (and any
        -- pending it owns) is dropped with the hidden dialog.
        h.visible[which] = nil
    end
    return h
end

return function(test)
    local h = makePopup()
    StaticPopupDialogs = h.dialogs
    StaticPopup_Show = h.show

    BG = { BGNext = {} }
    local L = setmetatable({}, { __index = function(_, k) return k end })

    -- Runtime namespace: register the guard exactly as a TOC load would.
    dofile("Core/BGNext/AutoClearGuard.lua")

    BG.IsVanilla = false
    BG.IsRetail = false
    BG.verOver4 = true
    BG.playerName = "Test"
    BG.FB1 = "MC"
    BG.FBMainFrame = fakeWidget()
    BG.MainFrame = fakeWidget()
    BG.CreateButton = function() return fakeWidget() end
    CreateFrame = function() return fakeWidget() end
    BG.GameTooltip_Hide = function() end
    BG.IsTBCFB = function() return false end
    BG.RegisterEvent = function(event, handler) h.events[event] = handler end
    BG.After = function(delay, cb) cb() end
    BG.FBIDtable = { [1234] = "MC", [5678] = "ZUG" }
    BG.bossPositionStartEnd = { [1234] = { 1, 2 }, [5678] = { 1, 2 } }
    BG.ClickFBbutton = function() end
    BG.SendSystemMessage = function(msg) h.messages[#h.messages + 1] = msg end
    BG.PlaySound = function(snd) h.sounds[#h.sounds + 1] = snd end
    BG.GetFBinfo = function(fb, key) return fb end
    BG.STC_b1 = function(s) return s end

    local Maxb = { ["MC"] = 5, ["ZUG"] = 5 }
    BG.Frame = {
        ["MC"] = { ["boss7"] = { jine5 = fakeWidget() } },
        ["ZUG"] = { ["boss7"] = { jine5 = fakeWidget() } },
    }

    local contentPresent = true
    BG.BiaoGeHavedItem = function() return contentPresent end

    BiaoGe = { options = { autoQingKong = 1 } }

    local currentInstanceID = 1234
    GetRealmID = function() return 1 end
    IsAddOnLoaded = function() end
    GetLootMethod = function() end
    BIAOGE_TEXT_FONT = "Font"
    min = math.min
    max = math.max
    format = string.format
    floor = math.floor
    date = os.date
    tinsert = table.insert
    GameTooltip_Hide = function() end
    GetInstanceInfo = function() return nil, nil, 14, nil, 25, nil, nil, currentInstanceID end
    GetNumSavedInstances = function() return 0 end
    RequestRaidInfo = function() end
    IsInInstance = function() return true end

    local ns = {
        L = L,
        SetClassCFF = function() end,
        AddTexture = function() end,
        Maxb = Maxb,
        HopeMaxn = {},
        HopeMaxi = {},
        canShowTBC = true,
    }

    local chunk = assert(loadfile("Core/Module/ClearBiaoGe.lua"))
    chunk("BGLite", ns)

    BG.ClearBiaoGeUI()

    -- Spy on the actual clear path so the popup wiring can be asserted without
    -- mutating any real table or settlement.
    BG.ClearBiaoGe = function(_type, FB)
        h.clearCalls[#h.clearCalls + 1] = FB
        return 25
    end

    local function fireCycle()
        h.events["RAID_INSTANCE_WELCOME"]()
        h.events["UPDATE_INSTANCE_INFO"]()
    end

    -- 1. Single event: the dialog is shown with the pending bound as its data.
    contentPresent = true
    fireCycle()
    local cur = h.visible["AUTO_QINGKONG_CONFIRM"]
    test.eq(cur ~= nil, true, "auto-clear dialog is shown")
    test.eq(cur.data ~= nil, true, "pending is bound as dialog data")
    test.eq(cur.data.fb, "MC", "pending captures the target table")
    h.accept("AUTO_QINGKONG_CONFIRM")
    test.eq(#h.clearCalls, 1, "accept clears exactly once")
    test.eq(h.clearCalls[1], "MC", "accept clears the captured table")

    -- 2. Accept revalidates: a table emptied meanwhile is not cleared again.
    h.clearCalls = {}
    contentPresent = true
    fireCycle()
    contentPresent = false
    h.accept("AUTO_QINGKONG_CONFIRM")
    test.eq(#h.clearCalls, 0, "an emptied table is not cleared again on accept")

    -- 3. Cancel preserves the table and settlement.
    h.clearCalls = {}
    contentPresent = true
    fireCycle()
    h.cancel("AUTO_QINGKONG_CONFIRM")
    test.eq(#h.clearCalls, 0, "cancel leaves the table intact")

    -- 4. Esc preserves the table and settlement.
    h.clearCalls = {}
    fireCycle()
    h.esc("AUTO_QINGKONG_CONFIRM")
    test.eq(#h.clearCalls, 0, "Esc leaves the table intact")

    -- 5. Same-target duplicate: the reused dialog must not cancel the newer
    --    request; accepting still clears exactly once.
    h.clearCalls = {}
    contentPresent = true
    fireCycle()
    fireCycle()
    test.eq(h.visible["AUTO_QINGKONG_CONFIRM"].data.fb, "MC", "duplicate still targets the table")
    h.accept("AUTO_QINGKONG_CONFIRM")
    test.eq(#h.clearCalls, 1, "a duplicate event clears exactly once")

    -- 6. Cross-target replacement: the newer target wins and clears once.
    h.clearCalls = {}
    contentPresent = true
    currentInstanceID = 1234
    fireCycle()
    currentInstanceID = 5678
    fireCycle()
    test.eq(h.visible["AUTO_QINGKONG_CONFIRM"].data.fb, "ZUG", "replacement binds the newer target")
    h.accept("AUTO_QINGKONG_CONFIRM")
    test.eq(#h.clearCalls, 1, "replacement clears once")
    test.eq(h.clearCalls[1], "ZUG", "replacement clears the newer table")

    -- 7. Missing guard must fail closed: no clear, a warning is announced.
    h.clearCalls = {}
    h.messages = {}
    BG.BGNext.AutoClearGuard = nil
    contentPresent = true
    fireCycle()
    test.eq(#h.clearCalls, 0, "missing guard never auto-clears")
    test.eq(#h.messages > 0, true, "missing guard announces a conservative warning")
end
