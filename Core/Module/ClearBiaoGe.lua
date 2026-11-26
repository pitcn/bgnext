if BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local L = ns.L

local SetClassCFF = ns.SetClassCFF
local AddTexture = ns.AddTexture

local Maxb = ns.Maxb
local HopeMaxn = ns.HopeMaxn
local HopeMaxi = ns.HopeMaxi

local realmID = GetRealmID()
local player = BG.playerName
local IsAddOnLoaded = IsAddOnLoaded or C_AddOns.IsAddOnLoaded
local GetLootMethod = GetLootMethod or C_PartyInfo.GetLootMethod

function BG.ClearBiaoGeUI()
    function BG.ClearBiaoGeByIndex(FB, b)
        if b <= Maxb[FB] and BG.InvalidatePendingLoot then
            BG.InvalidatePendingLoot(FB)
        end
        if b == Maxb[FB] + 1 then
            for i = 1, BG.Maxi + 10 do -- 清空支出
                if BG.Frame[FB]["boss" .. Maxb[FB] + 1]["zhuangbei" .. i] then
                    if BiaoGe.options["retainExpenses"] ~= 1 then
                        BG.Frame[FB]["boss" .. Maxb[FB] + 1]["zhuangbei" .. i]:SetText("")
                        BiaoGe[FB]["boss" .. Maxb[FB] + 1]["zhuangbei" .. i] = nil
                    end
                    if not (BiaoGe.options["retainExpenses"] == 1 and BiaoGe.options["retainExpensesMoney"] == 1) then
                        BG.Frame[FB]["boss" .. Maxb[FB] + 1]["jine" .. i]:SetText("")
                        BiaoGe[FB]["boss" .. Maxb[FB] + 1]["jine" .. i] = nil
                    end
                    BG.Frame[FB]["boss" .. Maxb[FB] + 1]["maijia" .. i]:SetText("")
                    BiaoGe[FB]["boss" .. Maxb[FB] + 1]["maijia" .. i] = nil
                end
            end
        elseif b <= Maxb[FB] then
            for i = 1, math.max(BG.Maxi + 10, BG.GetMaxi(FB, b)) do
                -- 表格
                if BG.Frame[FB]["boss" .. b]["zhuangbei" .. i] then
                    BG.Frame[FB]["boss" .. b]["zhuangbei" .. i]:SetText("")
                    BG.Frame[FB]["boss" .. b]["maijia" .. i]:SetText("")
                    BG.Frame[FB]["boss" .. b]["jine" .. i]:SetText("")
                    BG.Frame[FB]["boss" .. b]["qiankuan" .. i]:Hide()
                    BG.Frame[FB]["boss" .. b]["guanzhu" .. i]:Hide()
                end
                BiaoGe[FB]["boss" .. b]["zhuangbei" .. i] = nil
                BiaoGe[FB]["boss" .. b]["maijia" .. i] = nil
                BiaoGe[FB]["boss" .. b]["jine" .. i] = nil
                BiaoGe[FB]["boss" .. b]["qiankuan" .. i] = nil
                BiaoGe[FB]["boss" .. b]["guanzhu" .. i] = nil
                BiaoGe[FB]["boss" .. b]["loot" .. i] = nil
                BiaoGe[FB]["boss" .. b]["itemLevel" .. i] = nil
                BiaoGe[FB]["boss" .. b]["bindOnEquip" .. i] = nil
                for k, v in pairs(BG.playerClass) do
                    BiaoGe[FB]["boss" .. b][k .. i] = nil
                end
                -- 对账
                if BG.DuiZhangFrame[FB]["boss" .. b]["zhuangbei" .. i] then
                    BG.DuiZhangFrame[FB]["boss" .. b]["zhuangbei" .. i]:SetText("")
                    BG.DuiZhangFrame[FB]["boss" .. b]["myjine" .. i]:SetText("")
                end
            end
        end
    end

    -- Automatic new-lockout cleanup may target one instance inside a table
    -- shared by several raids. Keep this path separate from the explicit
    -- whole-table button so rows belonging to another instance survive.
    function BG.ClearBiaoGeRange(FB, startB, endB)
        if not FB or type(startB) ~= "number" or type(endB) ~= "number"
            or startB < 1 or endB < startB or endB > Maxb[FB]
        then
            return false
        end
        for b = startB, endB do
            BG.ClearBiaoGeByIndex(FB, b)
        end
        return true
    end

    local function RecordClearBiaoGeMoney(FB)
        local money = floor(GetMoney() / 1e4)
        BiaoGe.clearBiaoGeMoney = BiaoGe.clearBiaoGeMoney or {}
        BiaoGe.clearBiaoGeMoney[FB] = {
            FB = FB,
            realmID = realmID,
            name = player,
            money = money,
            time = GetServerTime()
        }
        BG.UpdateButtonClearBiaoGeMoney()
    end

    function BG.ClearBiaoGe(_type, FB)
        if not FB then return end
        if _type == "biaoge" then
            for b = 1, Maxb[FB] + 1 do
                BG.ClearBiaoGeByIndex(FB, b)
            end
            BiaoGe[FB].tradeTbl = {}
            BiaoGe[FB].raidRoster = nil
            if BG.BGNext and BG.BGNext.CurrentSettlementRuntime then
                BG.BGNext.CurrentSettlementRuntime.onTableCleared(BG.BGNext.DB, FB)
            end
            BiaoGe[FB].auctionLog = nil
            BiaoGe[FB].leaderInfo = nil
            if BG.IsForever and BG.BGNext and BG.BGNext.BillResetPrompt and type(BG.BGNext.DB) == "table" then
                BG.BGNext.BillResetPrompt.onTableCleared(BG.BGNext.DB, FB)
            end
            BG.UpdateAuctionLogFrame()
            BG.auctionLogFrame.changeFrame:Hide()

            local num -- 分钱人数
            if BG.IsVanilla then
                num = BG.GetFBinfo(FB, "maxplayers") or 40
            elseif BG.IsTBC then
                num = BG.GetFBinfo(FB, "maxplayers") or 25
            elseif BG.IsTitan then
                if BiaoGe.options["QingKongPeople"] == 1
                    and tonumber(BiaoGe.options["MaxPlayers_Titan"])
                    and FB ~= "Worldtitan"
                then
                    num = tonumber(BiaoGe.options["MaxPlayers_Titan"])
                else
                    num = BG.GetFBinfo(FB, "maxplayers") or 25
                end
            elseif BG.IsRetail then
                num = BG.GetFBinfo(FB, "maxplayers") or 20
            else
                num = 25
                local nanduID = GetRaidDifficultyID()
                if nanduID == 3 or nanduID == 175 then
                    num = (BiaoGe.options["QingKongPeople"] == 1 and BiaoGe.options["10MaxPlayers"]) or 10
                elseif nanduID == 4 or nanduID == 176 then
                    num = (BiaoGe.options["QingKongPeople"] == 1 and BiaoGe.options["25MaxPlayers"]) or 25
                elseif nanduID == 5 or nanduID == 193 then
                    num = (BiaoGe.options["QingKongPeople"] == 1 and BiaoGe.options["10MaxPlayers"]) or 10
                elseif nanduID == 6 or nanduID == 194 then
                    num = (BiaoGe.options["QingKongPeople"] == 1 and BiaoGe.options["25MaxPlayers"]) or 25
                end
            end
            if num then
                BG.Frame[FB]["boss" .. Maxb[FB] + 2]["jine4"]:SetText(num)
                BiaoGe[FB]["boss" .. Maxb[FB] + 2]["jine4"] = num
            end

            RecordClearBiaoGeMoney(FB)
            return num
        end
    end

    -- 清空按钮
    do
        local bt = BG.CreateButton(BG.FBMainFrame)
        bt:SetSize(120, 25)
        bt:SetPoint("BOTTOMLEFT", BG.MainFrame, "BOTTOMLEFT", 30, 38)
        bt:SetText(L["清空表格"])
        bt:RegisterForClicks("AnyUp")
        BG.ButtonQingKong = bt
        -- 按钮触发
        bt:SetScript("OnClick", function(self, button)
            BG.PlaySound(1)
            if button == "LeftButton" then
                StaticPopup_Show("QINGKONGBIAOGE")
            elseif button == "RightButton" then
                GameTooltip:Hide()
                BG.CreateFreeClearBiaoGeFrame()
            end
        end)
        bt:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L["清空表格"], 1, 1, 1, true)
            GameTooltip:AddLine(L["一键清空全部装备、买家、金额，同时还清空关注和欠款。如果有自动拍卖记录，则也会被清空。"], 1, 0.82, 0, true)
            GameTooltip:AddLine(" ", 1, 0.82, 0, true)
            GameTooltip:AddLine(AddTexture("LEFT") .. L["清空全部"], 1, 0.82, 0, true)
            GameTooltip:AddLine(AddTexture("RIGHT") .. L["清空部分内容（自选）"], 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        BG.GameTooltip_Hide(bt)

        StaticPopupDialogs["QINGKONGBIAOGE"] = {
            text = L["确定清空表格？"],
            button1 = L["是"],
            button2 = L["否"],
            OnAccept = function()
                local num = BG.ClearBiaoGe("biaoge", BG.FB1)
                if num then
                    BG.SendSystemMessage(BG.STC_b1(format(
                        L["已清空表格< %s >，分钱人数已改为%s人。"], BG.GetFBinfo(BG.FB1, "shortName"), num)))
                else
                    BG.SendSystemMessage(BG.STC_b1(format(
                        L["已清空表格< %s >。"], BG.GetFBinfo(BG.FB1, "shortName"))))
                end
                BG.PlaySound(2)
            end,
            OnCancel = function()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            showAlert = true,
        }
    end

    -- 自动清空表格
    do
        local teamText = ''
        local function IsNotSameTeam(FB)
            FB = FB or BG.FB1
            if not IsInRaid(1) then
                teamText = L['不在团队里。']
                return true
            end
            -- 没有历史成员名单
            if not BiaoGe[FB].raidRoster then
                teamText = L['表格没有历史成员名单。']
                return true
            end
            -- 超过x天了
            if GetServerTime() - BiaoGe[FB].raidRoster.time >= 86400 * 1 then
                teamText = L['表格的历史成员名单的创建时间已超过1天，判断为现在是新团队。']
                return true
            end
            -- 服务器不同
            if BG.realmName ~= BiaoGe[FB].raidRoster.realm then
                teamText = L['表格的历史成员名单服务器是[%s]，与当前服务器[%s]不同，判断为现在是新团队。']:format(BiaoGe[FB].raidRoster.realm or '', BG.realmName or '')
                return true
            end
            local maxCount = max(#BG.raidRosterInfo, #BiaoGe[FB].raidRoster.roster)
            local sameCount = 0
            for _, vv in ipairs(BG.raidRosterInfo) do
                for _, name in ipairs(BiaoGe[FB].raidRoster.roster) do
                    if vv.name == name then
                        sameCount = sameCount + 1
                    end
                end
            end
            if sameCount / maxCount < 0.6 then
                teamText = L['表格的历史成员人数为%s，当前团队人数为%s，相同成员的占比低于60%%，判断为现在是新团队。']:format(#BiaoGe[FB].raidRoster.roster, #BG.raidRosterInfo)
                return true
            end
            return false
        end
        BG.IsNotSameTeam = IsNotSameTeam
        local function SendTips(FB)
            if (FB == "ZUG" or FB == "ZUGsod") and BG.IsVanilla and IsInRaid(1) and UnitIsGroupLeader("player") then
                BG.SendSystemMessage(L["提醒团长：如果你没有物品分配权，将会导致交易的相关功能失效。"])
            end
        end

        -- Re-checks whether the captured table still holds old content. A table
        -- that was emptied or cleared meanwhile must not be cleared again.
        local function StillHasContent(pending)
            if not pending then return false end
            if pending.clearType == 2 then
                return BG.BiaoGeHavedItem(pending.fb, "onlyboss")
            end
            return BG.BiaoGeHavedItem(pending.fb, "autoQingKong", pending.instanceID)
        end

        local function StillHasAnyContent(pending)
            return pending and BG.BiaoGeHavedItem(pending.fb) or false
        end

        -- Only tables that actually combine distinct instance ranges may offer
        -- the whole-phase action. A phase can contain several independent
        -- tables, and clearing one of them must never be labelled as clearing
        -- every raid in that phase.
        local function HasMultipleInstanceRanges(FB)
            local ranges = {}
            local count = 0
            for instanceID, mappedFB in pairs(BG.FBIDtable or {}) do
                if mappedFB == FB then
                    local range = BG.bossPositionStartEnd and BG.bossPositionStartEnd[instanceID]
                    if range and type(range[1]) == "number" and type(range[2]) == "number" then
                        local key = range[1] .. ":" .. range[2]
                        if not ranges[key] then
                            ranges[key] = true
                            count = count + 1
                            if count > 1 then return true end
                        end
                    end
                end
            end
            return false
        end

        local function DoAutoClear(FB, clearType, startB, endB, teamText)
            if clearType == 1 then
                if not BG.ClearBiaoGeRange(FB, startB, endB) then return end
                RecordClearBiaoGeMoney(FB)
                BG.SendSystemMessage(format(L["已自动清空表格< %s >的当前副本区间（Boss %s-%s），其他副本记录已保留。"],
                    BG.GetFBinfo(FB, "shortName"), startB, endB))
                BG.SendSystemMessage(L['自动清空表格的原因：1.当前副本你是新CD；2.%s']:format(
                    L['当前副本所在的表格BOSS编号（%s-%s）格子中存在旧记录。']:format(startB, endB)))
            elseif clearType == 2 then
                local num = BG.ClearBiaoGe("biaoge", FB)
                BG.SendSystemMessage(format(L["已自动清空表格< %s >，分钱人数已改为%s人。"], BG.GetFBinfo(FB, "shortName"), num))
                BG.SendSystemMessage(L['自动清空表格的原因：1.当前副本你是新CD；2.%s']:format(
                    teamText))
            elseif clearType == 3 or clearType == 4 then
                local num = BG.ClearBiaoGe("biaoge", FB)
                if clearType == 3 then
                    BG.SendSystemMessage(format(L["已清理所有%s副本，并清除共享的杂项、罚款和当前团结算记录；支出按现有清表设置处理。"],
                        BG.GetFBinfo(FB, "phase") or BG.GetFBinfo(FB, "shortName")))
                end
                BG.SendSystemMessage(format(L["已自动清空表格< %s >，分钱人数已改为%s人。"],
                    BG.GetFBinfo(FB, "shortName"), num))
            end
            BG.PlaySound("qingkong")
        end

        -- Instead of clearing directly, asks the user first. The request is
        -- memory-only; nothing is cleared on refuse, Esc or cancel.
        local function ShowAutoClearConfirm(FB, clearType, startB, endB, teamText, instanceID)
            local Guard = BG.BGNext and BG.BGNext.AutoClearGuard
            if not Guard then
                -- Guard failed to load: fail closed. Never auto-clear without
                -- the confirmation gate; warn and leave the table and settlement intact.
                BG.SendSystemMessage(L["自动清空保护模块未加载，已跳过自动清空以避免误删；如需清空请手动操作。"])
                return
            end
            local pending = Guard.createPending(FB, clearType, {
                instanceID = instanceID,
                startB = startB,
                endB = endB,
            })
            if not pending then return end
            pending.teamText = teamText
            pending.canClearWholeTable = clearType == 1
            pending.hasMultipleInstanceRanges = HasMultipleInstanceRanges(FB)
            local shortName = BG.GetFBinfo(FB, "shortName")
            local phase = BG.GetFBinfo(FB, "phase") or shortName
            local message
            if clearType == 1 then
                if pending.hasMultipleInstanceRanges then
                    message = format(L["检测到新副本进度，表格< %s >的当前副本区间（Boss %s-%s）仍有内容。只清当前副本时，其他副本、杂项、罚款、支出和当前团结算记录会保留；如需开始整个新阶段，请选择“清理所有%s副本”。"],
                        shortName, startB, endB, phase)
                else
                    message = format(L["检测到新副本进度，表格< %s >的当前副本区间（Boss %s-%s）仍有内容。只清当前副本会保留杂项、罚款、支出和当前团结算记录；选择“清空表格”可同时清除这些记录，支出按现有清表设置处理。"],
                        shortName, startB, endB)
                end
            else
                message = format(L["检测到新副本进度，表格< %s >仍有未结算内容，清空将同时清除表格内容与当前团的结算记录。是否清空？"], shortName)
            end
            local dialogInfo = StaticPopupDialogs["AUTO_QINGKONG_CONFIRM"]
            if dialogInfo then
                dialogInfo.button1 = clearType == 1 and L["只清当前副本"] or L["清空表格"]
                dialogInfo.button3 = pending.canClearWholeTable and
                    (pending.hasMultipleInstanceRanges and format(L["清理所有%s副本"], phase) or L["清空表格"]) or nil
            end
            StaticPopup_Show("AUTO_QINGKONG_CONFIRM", message, nil, pending)
        end

        StaticPopupDialogs["AUTO_QINGKONG_CONFIRM"] = {
            text = "%s",
            button1 = L["清空表格"],
            button2 = L["取消"],
            OnAccept = function(self, data)
                local pending = data
                if not pending then return end
                local Guard = BG.BGNext and BG.BGNext.AutoClearGuard
                local hasContent = StillHasContent(pending)
                local currentInstanceID = select(8, GetInstanceInfo())
                local decision = Guard and Guard.accept(pending, hasContent, currentInstanceID) or "skip"
                if decision == "clear" then
                    DoAutoClear(pending.fb, pending.clearType, pending.startB, pending.endB, pending.teamText)
                end
            end,
            OnCancel = function(self, data)
                local pending = data
                local Guard = BG.BGNext and BG.BGNext.AutoClearGuard
                if Guard and pending then
                    Guard.refuse(pending)
                end
            end,
            OnAlt = function(self, data)
                local pending = data
                if not pending or pending.clearType ~= 1 or not pending.canClearWholeTable then return end
                local Guard = BG.BGNext and BG.BGNext.AutoClearGuard
                local hasContent = StillHasAnyContent(pending)
                local currentInstanceID = select(8, GetInstanceInfo())
                local decision = Guard and Guard.accept(pending, hasContent, currentInstanceID) or "skip"
                if decision == "clear" then
                    DoAutoClear(pending.fb, pending.hasMultipleInstanceRanges and 3 or 4,
                        pending.startB, pending.endB, pending.teamText)
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            showAlert = true,
        }

        local notCheckMaxPlayer = BG.verOver4
        local notCheckDiff = not BG.IsRetail
        -- Forever only: the lockout popup above is replaced by an addon-owned
        -- "clear the previous bill?" question (BillResetPrompt/BillResetPromptUI).
        -- It only asks; clearing reuses DoAutoClear -> BG.ClearBiaoGe after the
        -- guard re-checks the table. Other clients never reach this code.
        local function ForeverPromptEnabled()
            local value = BiaoGe.options["foreverBillResetPrompt"]
            if value == nil then
                -- Not chosen yet: inherit the old switch, defaulting to on.
                return BiaoGe.options["autoQingKong"] ~= 0
            end
            return value == 1
        end

        local promptState
        local function GetPrompt()
            local N = BG.BGNext
            local root = N and N.DB
            if N and N.BillResetPrompt and N.BillResetPromptUI and type(root) == "table" then
                promptState = promptState or N.BillResetPrompt.newState()
                return N.BillResetPrompt, N.BillResetPromptUI, root, promptState
            end
        end

        local function FindLastBillFB()
            local ids = {}
            for _, raid in ipairs(BG.ForeverRaids or {}) do ids[#ids + 1] = raid.id end
            if #ids == 0 then ids = BG.FBtable or {} end
            local best, bestTime
            for _, fb in ipairs(ids) do
                local t = BiaoGe[fb] and BiaoGe[fb].raidRoster and BiaoGe[fb].raidRoster.time
                if type(t) == "number" and (not bestTime or t > bestTime) and BG.BiaoGeHavedItem(fb, "onlyboss") then
                    best, bestTime = fb, t
                end
            end
            if not best and BG.FB1 and BiaoGe[BG.FB1] and BG.BiaoGeHavedItem(BG.FB1, "onlyboss") then
                best = BG.FB1
            end
            return best
        end

        -- Existing timestamps only; never player data.
        local function BillStamp(fb)
            local t = BiaoGe[fb].raidRoster and BiaoGe[fb].raidRoster.time
            if type(t) ~= "number" then
                local m = BiaoGe.clearBiaoGeMoney and BiaoGe.clearBiaoGeMoney[fb]
                t = m and m.time
            end
            return type(t) == "number" and t or 0
        end

        local function EvaluateBillPrompt(spec)
            local P, UI, root, state = GetPrompt()
            if not P or not ForeverPromptEnabled() then return end
            if InCombatLockdown() then
                P.defer(state, spec)
                return
            end
            local ok = pcall(function()
                local lastBill = FindLastBillFB()
                local fb = spec.kind == "reset" and spec.fb or lastBill
                if not fb or not BiaoGe[fb] then return end
                -- The new-team question belongs to the last bill only. A reset
                -- of another raid's table asks about the reset alone, so the
                -- two answers never overwrite each other.
                local c = {
                    forever = true,
                    enabled = true,
                    fb = fb,
                    hasContent = BG.BiaoGeHavedItem(fb, "onlyboss") and true or false,
                    billStamp = BillStamp(fb),
                    newTeam = (fb == lastBill and IsInRaid(1) and type(BG.raidRosterInfo) == "table"
                        and #BG.raidRosterInfo > 0 and IsNotSameTeam(fb)) and true or false,
                }
                if spec.kind == "reset" then
                    c.reset = { instanceID = spec.instanceID, locked = spec.locked, lockoutId = spec.lockoutId }
                end
                local req, observe = P.shouldAsk(c, root.billResetPrompt)
                if observe then P.observe(root, c, observe, GetServerTime()) end
                if not req then return end
                local Guard = BG.BGNext.AutoClearGuard
                if not Guard or not P.begin(state, req) then return end
                local function answered()
                    P.finish(state)
                    P.markAsked(root, req, GetServerTime())
                end
                local shown = UI.show({
                    fbName = BG.GetFBinfo(fb, "shortName"),
                    newTeam = req.newTeam,
                    reset = req.reset,
                    onClear = function()
                        answered()
                        local pending = Guard.createPending(fb, 4)
                        if Guard.accept(pending, StillHasAnyContent(pending), nil) == "clear" then
                            DoAutoClear(fb, 4)
                        end
                    end,
                    onKeep = answered,
                })
                if not shown then P.finish(state) end
            end)
            if not ok and not UI.isShown() then P.finish(state) end
        end

        local function SpecStillValid(spec)
            if spec.kind == "reset" then
                return IsInInstance() and select(8, GetInstanceInfo()) == spec.instanceID
            end
            return IsInRaid(1) and true or false
        end

        local notCheckMaxPlayerF, notCheckDiffF = BG.verOver4, not BG.IsRetail
        local function ForeverCheckCD()
            -- Every game call is guarded: a missing or odd API means no prompt.
            local ok, spec = pcall(function()
                local _, _, diffID, _, maxPlayers, _, _, instanceID = GetInstanceInfo()
                local FB = BG.FBIDtable[instanceID]
                if not (FB and IsInInstance()) then return nil end
                if BG.ForeverRaidActive and not BG.ForeverRaidActive(FB, IsInRaid()) then return nil end
                local locked, lockoutId = false, nil
                local rows, rowsWithId = GetNumSavedInstances(), 0
                for i = 1, rows do
                    local _, _lockId, _, _diffID, _locked, _, _, _, _maxPlayers, _, _, _, _, _instanceID = GetSavedInstanceInfo(i)
                    if type(_instanceID) == "number" then rowsWithId = rowsWithId + 1 end
                    if _locked and instanceID == _instanceID
                        and (notCheckMaxPlayerF or maxPlayers == _maxPlayers)
                        and (notCheckDiffF or diffID == _diffID)
                    then
                        locked, lockoutId = true, _lockId
                        break
                    end
                end
                -- Rows without a numeric instance id (unverified Forever return
                -- layout) cannot tell locked from unlocked: fail closed.
                if rows > 0 and rowsWithId == 0 then return nil end
                if not locked then BG.ClickFBbutton(FB) end
                return { kind = "reset", fb = FB, instanceID = instanceID, locked = locked,
                    lockoutId = type(lockoutId) == "number" and lockoutId or nil }
            end)
            if ok and spec then EvaluateBillPrompt(spec) end
        end

        if BG.IsForever then
            local wasInRaid, lastCount, debounce = false, 0, 0
            local function QueueTeamCheck()
                debounce = debounce + 1
                local mine = debounce
                BG.After(3, function()
                    if mine == debounce then EvaluateBillPrompt({ kind = "team" }) end
                end)
            end
            BG.RegisterEvent("GROUP_ROSTER_UPDATE", function()
                local inRaid = IsInRaid(1) and true or false
                local count = inRaid and (GetNumGroupMembers() or 0) or 0
                local joined = inRaid and (not wasInRaid or math.abs(count - lastCount) >= 5)
                wasInRaid, lastCount = inRaid, count
                if joined and ForeverPromptEnabled() then QueueTeamCheck() end
            end)
            BG.RegisterEvent("GROUP_LEFT", function()
                wasInRaid, lastCount = false, 0
                local P, _, root, state = GetPrompt()
                if P then
                    P.onGroupLeft(root)
                    P.clearDeferred(state)
                end
            end)
            BG.RegisterEvent("PLAYER_ENTERING_WORLD", function()
                wasInRaid = IsInRaid(1) and true or false
                lastCount = wasInRaid and (GetNumGroupMembers() or 0) or 0
                -- Leaving while offline or logging in another character never
                -- fires GROUP_LEFT: arriving outside any group ends the party.
                local grouped = wasInRaid or (type(IsInGroup) == "function" and IsInGroup()) or false
                if not grouped then
                    local P, _, root = GetPrompt()
                    if P then P.onGroupLeft(root) end
                end
                if wasInRaid and ForeverPromptEnabled() then QueueTeamCheck() end
            end)
            BG.RegisterEvent("PLAYER_REGEN_ENABLED", function()
                local P, _, _, state = GetPrompt()
                local spec = P and P.takeDeferred(state)
                if spec and SpecStillValid(spec) then EvaluateBillPrompt(spec) end
            end)
        end

        local needCheck
        local function CheckCD()
            if BG.IsForever then
                BG.After(3, ForeverCheckCD)
                return
            end
            BG.After(3, function()
                local _, _, diffID, _, maxPlayers, _, _, instanceID = GetInstanceInfo()
                local FB = BG.FBIDtable[instanceID]
                SendTips(FB)
                if BG.IsTBCFB(FB) and not ns.canShowTBC then return end
                if not (FB and IsInInstance()) then return end
                local newCD = true
                for i = 1, GetNumSavedInstances() do
                    local _, _, _, _diffID, locked, _, _, _, _maxPlayers, _, _, _, _, _instanceID = GetSavedInstanceInfo(i)
                    if locked and (instanceID == _instanceID)
                        and (notCheckMaxPlayer or maxPlayers == _maxPlayers)
                        and (notCheckDiff or diffID == _diffID)
                    then
                        newCD = false
                        break
                    end
                end
                -- 如果是新CD
                if newCD then
                    BG.ClickFBbutton(FB)
                    -- 有这些场景：1 打完NAXX，然后进黑龙（不要清空表格）。2 上CD打过黑龙 这CD进NAXX

                    -- 如果当前副本对应的BOSS格子有东西（除了杂项） 就清空整个表格
                    -- 如果当前副本对应的BOSS格子没东西但其他格子有东西，且当前团队成员跟当前副本的历史成员名单不同 就清空整个表格
                    local clearType
                    local startB = BG.bossPositionStartEnd[instanceID][1]
                    local endB = BG.bossPositionStartEnd[instanceID][2]
                    if BG.BiaoGeHavedItem(FB, "autoQingKong", instanceID) then
                        clearType = 1
                    end
                    if not clearType and BG.BiaoGeHavedItem(FB, "onlyboss") and IsNotSameTeam(FB) then
                        clearType = 2
                    end

                    if clearType then
                        local Guard = BG.BGNext and BG.BGNext.AutoClearGuard
                        local enabled = BiaoGe.options["autoQingKong"] == 1
                        if not Guard or Guard.needsConfirmation(enabled, newCD, true) then
                            ShowAutoClearConfirm(FB, clearType, startB, endB, teamText, instanceID)
                        end
                    end
                end
            end)
        end
        BG.RegisterEvent("RAID_INSTANCE_WELCOME", function(self, event, ...)
            if BG.IsForever then
                if not ForeverPromptEnabled() then return end
            elseif BiaoGe.options["autoQingKong"] ~= 1 then
                return
            end
            needCheck = true
            if BG.IsForever then pcall(RequestRaidInfo) else RequestRaidInfo() end
        end)
        BG.RegisterEvent("UPDATE_INSTANCE_INFO", function()
            if needCheck then
                needCheck = nil
                CheckCD()
            end
        end)
    end

    -- 清空时记录身上金币
    do
        local poit

        local function OnEnter(self)
            local FB = BG.FB1
            local p = SetClassCFF(BiaoGe.clearBiaoGeMoney[FB].name)
            local f = BG.GetFBinfo(BiaoGe.clearBiaoGeMoney[FB].FB, "shortName")
            local t = date("%m-%d %H:%M", BiaoGe.clearBiaoGeMoney[FB].time)
            local m = GetMoneyString(BiaoGe.clearBiaoGeMoney[FB].money .. "0000", true)
            GameTooltip:SetOwner(poit, "ANCHOR_TOPLEFT", 0, 0)
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L["清空表格时携带的金币"], 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine(L["角色："], p, 1, 0.82, 0, 1, 0.82, 0)
            GameTooltip:AddDoubleLine(L["表格："], f, 1, 0.82, 0, 1, 0.82, 0)
            GameTooltip:AddDoubleLine(L["时间："], t, 1, 0.82, 0, 1, 0.82, 0)
            GameTooltip:AddDoubleLine(L["金币："], m, 1, 0.82, 0, 1, 0.82, 0)
            GameTooltip:Show()
        end

        function BG.UpdateButtonClearBiaoGeMoney()
            local FB = BG.FB1
            local f = BG.ButtonClearBiaoGeMoney
            if not (BiaoGe.clearBiaoGeMoney and BiaoGe.clearBiaoGeMoney[FB]) then
                f:Hide()
            else
                local jine = BG.Frame[FB]["boss" .. Maxb[FB] + 2].jine5
                f:Show()
                f:ClearAllPoints()
                f:SetPoint("TOPRIGHT", jine, "BOTTOMRIGHT", 1, -1)
                f.Text:SetText(BiaoGe.clearBiaoGeMoney[FB].money)
                if BiaoGe.clearBiaoGeMoney[FB].realmID == realmID and BiaoGe.clearBiaoGeMoney[FB].name == player then
                    f.Text:SetTextColor(1, .82, 0)
                    f.title.Text:SetTextColor(1, .82, 0)
                else
                    f.Text:SetTextColor(.5, .5, .5)
                    f.title.Text:SetTextColor(.5, .5, .5)
                end
            end
        end

        local jine = BG.Frame[BG.FB1]["boss" .. Maxb[BG.FB1] + 2].jine5
        local f = CreateFrame("Frame", nil, BG.FBMainFrame, "BackdropTemplate")
        f:SetSize(jine:GetWidth(), 20)
        BG.ButtonClearBiaoGeMoney = f
        local t = f:CreateFontString()
        t:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
        t:SetAllPoints()
        t:SetJustifyH("LEFT")
        t:SetTextColor(1, .82, 0)
        f.Text = t
        f:SetScript("OnEnter", OnEnter)
        f:SetScript("OnLeave", GameTooltip_Hide)

        local f = CreateFrame("Frame", nil, BG.ButtonClearBiaoGeMoney, "BackdropTemplate")
        f:SetSize(0, 20)
        f:SetPoint("RIGHT", BG.ButtonClearBiaoGeMoney, "LEFT", 0, 0)
        poit = f
        BG.ButtonClearBiaoGeMoney.title = f
        local t = f:CreateFontString()
        t:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
        t:SetPoint("RIGHT")
        t:SetTextColor(1, .82, 0)
        t:SetJustifyH("RIGHT")
        t:SetText(L["清空表格时的金币："])
        t:SetWordWrap(false)
        f:SetWidth(min(t:GetStringWidth() + 20, 160))
        f.Text = t
        f:SetScript("OnEnter", OnEnter)
        f:SetScript("OnLeave", GameTooltip_Hide)

        BG.UpdateButtonClearBiaoGeMoney()
    end

    -- 自定义清空
    function BG.CreateFreeClearBiaoGeFrame()
        if BG.freeClearBiaoGeFrame and BG.freeClearBiaoGeFrame:IsVisible() then
            BG.freeClearBiaoGeFrame:Hide()
            return
        end
        if BG.exportFrame then
            BG.exportFrame:Hide()
        end
        local FB = BG.FB1
        local parent = BG["Frame" .. FB]
        local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        f:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeSize = 1,
        })
        f:SetBackdropColor(0, 0, 0, 0.9)
        f:SetBackdropBorderColor(1, 1, 1, BG.borderAlpha)
        f:SetPoint("BOTTOMLEFT", BG.ButtonQingKong, "TOPLEFT", 0, 5)
        f:SetSize(350, 450)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:SetFrameStrata("HIGH")
        f.buttons = {}
        f:SetScript("OnHide", function(self)
            self:Hide()
        end)
        f:SetScript("OnMouseUp", function(self)
            self:StopMovingOrSizing()
        end)
        f:SetScript("OnMouseDown", function(self)
            self:StartMoving()
        end)
        BG.freeClearBiaoGeFrame = f

        BG.CreateCloseButton(f)

        local l = f:CreateLine()
        l:SetColorTexture(1, 1, 1, BG.borderAlpha)
        l:SetStartPoint("TOPLEFT", 1, -21)
        l:SetEndPoint("TOPRIGHT", -1, -21)
        l:SetThickness(1)

        f.titleText = f:CreateFontString()
        f.titleText:SetPoint("CENTER", f, "TOP", 0, -11)
        f.titleText:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
        f.titleText:SetFormattedText(L["清空表格（%s）"], BG.GetFBinfo(FB, "shortName"))

        local function CreateCheckButton(b, text)
            local bt = CreateFrame("CheckButton", nil, f, "ChatConfigCheckButtonTemplate")
            bt:SetSize(30, 30)
            if next(f.buttons) then
                bt:SetPoint("TOPLEFT", f.buttons[#f.buttons], "BOTTOMLEFT", 0, 0)
            else
                bt:SetPoint("TOPLEFT", 10, -30)
            end
            bt.Text:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
            bt.Text:SetText(text)
            bt:SetHitRectInsets(0, -bt.Text:GetWidth(), 0, 0)
            bt.id = b
            tinsert(f.buttons, bt)
            bt:HookScript("OnClick", function()
                f.sureButton:Update()
            end)
        end

        for b = 1, Maxb[FB] + 1 do
            local bossName = BG.Boss[FB]["boss" .. b].name2
            local color = BG.Boss[FB]["boss" .. b].color
            local text = "|cff" .. color .. bossName
            CreateCheckButton(b, text)
        end
        CreateCheckButton("auctionLog", L["自动拍卖记录"])
        f:SetHeight(#f.buttons * 30 + 40)

        local function OnClick(self)
            BG.PlaySound(1)
            for i, bt in ipairs(f.buttons) do
                bt:SetChecked(self.choose)
            end
            f.sureButton:Update()
        end

        local bt = BG.CreateButton(f)
        bt:SetSize(110, 25)
        bt:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -30)
        bt:SetText(L["全选"])
        bt.choose = true
        f.chooseAllButton = bt
        bt:SetScript("OnClick", OnClick)

        local bt = BG.CreateButton(f)
        bt:SetSize(110, 25)
        bt:SetPoint("TOP", f.chooseAllButton, "BOTTOM", 0, -5)
        bt:SetText(L["取消全选"])
        f.cancelAllButton = bt
        bt:SetScript("OnClick", OnClick)

        local bt = BG.CreateButton(f)
        bt:SetSize(110, 25)
        bt:SetPoint("TOP", f.cancelAllButton, "BOTTOM", 0, -40)
        bt:SetText(L["确定清空表格"])
        f.sureButton = bt
        bt:SetScript("OnClick", function(self)
            for i, bt in ipairs(f.buttons) do
                if bt:GetChecked() then
                    local b = bt.id
                    if b == "auctionLog" then
                        BiaoGe[FB].auctionLog = nil
                        BG.UpdateAuctionLogFrame()
                        BG.auctionLogFrame.changeFrame:Hide()
                    elseif type(b) == "number" then
                        BG.ClearBiaoGeByIndex(FB, bt.id)
                    end
                end
            end
            BG.PlaySound(2)
            f:Hide()
        end)
        function f.sureButton:Update()
            self:Disable()
            for i, bt in ipairs(f.buttons) do
                if bt:GetChecked() then
                    self:Enable()
                end
            end
        end

        f.sureButton:Update()
    end

end
