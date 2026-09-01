if BG.IsBlackListPlayer then return end
local _, ns = ...

local LibBG = ns.LibBG
local L = ns.L

local RR = ns.RR
local NN = ns.NN
local RN = ns.RN
local Size = ns.Size
local RGB = ns.RGB
local GetClassRGB = ns.GetClassRGB
local SetClassCFF = ns.SetClassCFF
local Maxb = ns.Maxb
local HopeMaxn = ns.HopeMaxn
local HopeMaxb = ns.HopeMaxb
local HopeMaxi = ns.HopeMaxi
local AddTexture = ns.AddTexture
local GetItemID = ns.GetItemID

local pt = print

local linshi_duizhang
local h_item = "|c.-|Hitem.-|h|r"
local bigfootyes
local bigfootItem
local Capture = assert(BG.BGNext and BG.BGNext.LedgerCapture, "BGNext LedgerCapture must load before DuiZhang")
local captureState = Capture.new()
BG.sessionDuizhang = {}

local function GetRealm()
    return (GetRealmName and GetRealmName() or ""):gsub(" ", ""):gsub("%-", "")
end

local function GetRaidMemberNames()
    local members = {}
    for i = 1, GetNumGroupMembers() do
        local name = GetRaidRosterInfo(i)
        if name and name ~= "" then
            members[#members + 1] = name
        end
    end
    return members
end

local function ClearSessionResults()
    wipe(BG.sessionDuizhang)
    BG.lastduizhangNum = nil
    if BG.DuiZhangDropDown and BG.DuiZhangDropDown.DropDown then
        LibBG:UIDropDownMenu_SetText(BG.DuiZhangDropDown.DropDown, L["无"])
    end
    if BG.DuiZhang0 then BG.DuiZhang0() end
    if BG.DuiZhangList and BG.DuiZhangDropDown and BG.DuiZhangDropDown.DropDown then BG.DuiZhangList() end
    if BG.DuiZhangMainFrame and BG.DuiZhangMainFrame.ButtonCopy then
        BG.DuiZhangMainFrame.ButtonCopy:Disable()
    end
end

local function UpdateCaptureButton()
    local button = BG.DuiZhangMainFrame and BG.DuiZhangMainFrame.CaptureButton
    if button then
        button:SetText(Capture.isActive(captureState, GetTime()) and L["停止对账"] or L["开始对账"])
    end
end

local function StopCapture(clearResults)
    Capture.stop(captureState)
    linshi_duizhang = nil
    bigfootyes = nil
    bigfootItem = nil
    BG.IsSavingLedger = nil
    if clearResults then ClearSessionResults() end
    UpdateCaptureButton()
end

local function AbortCapture()
    StopCapture(true)
    BG.SendSystemMessage(L["对账数据超出安全限制或等待超时，已停止本次对账。"])
end

local locales = {
    --金团账本
    ["RaidLedger:.... 收入 ...."] = { "RaidLedger:.... 收入 ....", "RaidLedger:.... Credit ...." },
    ["(%d+)金"] = { "(%d+)金", "(%d+)gold" },
    ["平均每人收入:"] = { "平均每人收入:", "Per Member credit:" },
    --金团表格
    ["通报金团账单"] = { "—通报账单—", "—通报金团账单—", "—通報賬單—", "—通報金團帳單—", "—Announce Raid Ledger—", "- Bulletin Bills -" },
    ["感谢使用金团表格"] = { "感谢使用BiaoGe插件", "感谢使用金团表格", "感謝使用BiaoGe插件", "感謝使用金團表格", "-Thanks for using BiaoGe plugin-", "-Thanks for using Gold Raid Ledger-" },
    ["打包交易"] = { "打包交易", "打包交易", "PackingDeal" },
    ["表格：(.+)"] = { "表格：(.+)", "Table: (.+)" },
    --大脚金团助手
    ["事件：.-|c.-|Hitem.-|h|r"] = { "事件：.-|c.-|Hitem.-|h|r", },
    ["^收入为："] = { "^收入为：", "^收入為：", },
    ["^收入为：%d+。"] = { "^收入为：%d+。", "^收入為：%d+。", },
    ["-感谢使用大脚金团辅助工具-"] = { "-感谢使用大脚金团辅助工具-", "-感謝使用大脚金團輔助工具-", },
}
local function Default(player, time)
    BG.IsSavingLedger = true
    return {
        player = player,
        class = select(2, UnitClass(player)),
        FB = nil,
        zhangdan = {},
        yes = nil,
        sumjine = 0,
        time = date("%m-%d %H:%M:%S", GetServerTime()),
        t = time,
    }
end

local function CheckTimeOut(time)
    BG.After(50, function()
        if linshi_duizhang and linshi_duizhang.t then
            if time == linshi_duizhang.t then
                AbortCapture()
            end
        end
    end)
end

local function Send(num, sumMoney, FB)
    local FBtext = ""
    local FBName = BG.GetFBinfo(FB, "shortName")
    if FBName then
        FBtext = L["，"] .. BG.STC_b1(FBName)
    end
    local link = format(L["|Hgarrmission:BiaoGeDuiZhang:%s|h[点击：对账]（|cff00ff00装备总收入%s|r%s）"],
        num, BG.FormatNumber(sumMoney, 5), FBtext)
    SendSystemMessage(link)
    BG.After(0.1, function()
        local link = format(L["|Hgarrmission:BiaoGeDuiZhangCopy:%s:%s|h[ALT+点击：复制账单]（|cff00ff00仅对装备收入有效|r）"],
            num, FB)
        SendSystemMessage(link)
    end)
end

-- 已移除 SaveLeaderInfo：它从第三方付费模块 BiaoGeAI / BGAI 读取团长的
-- 装等（GetPlayerItemsLevel）、天赋（talentInfo）与全套装备（itemInfo）。
-- 该函数唯一的调用点原本就是注释掉的，属死代码；同时它也是本插件里
-- 采集他人信息最重的一处，随付费模块挂载点一并移除。

-- 用户主动开启后，临时识别当前团队账单。
BG.RegisterEvent({ "CHAT_MSG_RAID_WARNING", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID" }, function(self, event, msg, sender, ...)
    if BG.IsSecret(msg) then return end
    if not Capture.isActive(captureState, GetTime()) then return end
    local IsRaidLedger = BG.FindTableString(msg, locales["RaidLedger:.... 收入 ...."])
    local IsBiaoGe = BG.FindTableString(msg, locales["通报金团账单"])
    local IsBigFoot = BG.FindTableString(msg, locales["事件：.-|c.-|Hitem.-|h|r"])
    local _time = GetServerTime()
    sender = BG.GSN(sender)
    local realm = GetRealm()
    local members = GetRaidMemberNames()
    -- 判断是否一个账单
    if IsRaidLedger then -- 金团账本
        if linshi_duizhang then return end
        if not Capture.bindSource(captureState, sender, realm, members, GetTime()) then return end
        linshi_duizhang = Default(sender, _time)
        linshi_duizhang.yes = 1
        linshi_duizhang.addons = "raidledger"
        if not Capture.appendLine(captureState, msg, GetTime()) then AbortCapture() return end
        CheckTimeOut(_time)
        return
    elseif IsBiaoGe then -- 金团表格
        if linshi_duizhang then return end
        if not Capture.bindSource(captureState, sender, realm, members, GetTime()) then return end
        linshi_duizhang = Default(sender, _time)
        linshi_duizhang.yes = 2
        linshi_duizhang.addons = "biaoge"
        if not Capture.appendLine(captureState, msg, GetTime()) then AbortCapture() return end
        CheckTimeOut(_time)
        return
    elseif not bigfootyes and IsBigFoot then -- 大脚
        if linshi_duizhang then return end
        if not Capture.bindSource(captureState, sender, realm, members, GetTime()) then return end
        linshi_duizhang = Default(sender, _time)
        linshi_duizhang.addons = "bigfoot"
        bigfootyes = true
        bigfootItem = strmatch(msg, h_item)
        if not Capture.appendLine(captureState, msg, GetTime()) then AbortCapture() return end
        CheckTimeOut(_time)
        return
    end

    if not linshi_duizhang then return end
    if not Capture.acceptSource(captureState, sender, realm, members, GetTime()) then return end
    if not Capture.appendLine(captureState, msg, GetTime()) then AbortCapture() return end

    -- 识别表格
    local FB = BG.MatchTableString(msg, locales["表格：(.+)"])
    if linshi_duizhang.yes and sender == linshi_duizhang.player and FB then
        linshi_duizhang.FB = FB
    end

    -- 如果已经是账单了，则开始保存每个装备的价格
    if linshi_duizhang.yes and sender == linshi_duizhang.player and strfind(msg, h_item) then
        local item = strmatch(msg, h_item)
        local jine

        if linshi_duizhang.yes == 1 then -- 金团账本
            jine = BG.MatchTableString(msg, locales["(%d+)金"])
            jine = Capture.parseMoney(jine)
            if jine and jine ~= 0 then
                local aaa = {
                    zhuangbei = item,
                    jine = jine,
                }
                if not Capture.appendEntry(captureState, aaa, GetTime()) then AbortCapture() return end
                tinsert(linshi_duizhang.zhangdan, aaa)
            end
        elseif linshi_duizhang.yes == 2 then -- 金团表格
            local playerClass = {}
            local maijia = strmatch(msg, " (%S-) %S+$")
            if maijia == "" then
                maijia = nil
            end
            if maijia then
                for k, v in pairs(BG.playerClass) do
                    local value = select(v.select, v.func(maijia))
                    if value == 0 then value = nil end
                    playerClass[k] = value
                end
                if not playerClass.guild then
                    playerClass.realm = nil
                end
            end
            jine = strmatch(msg, " (%d+)$") or strmatch(msg, "：(%d+)$")
            local j
            if jine then
                j = Capture.parseMoney(jine)
                if not j then return end
            elseif BG.FindTableString(msg, locales["打包交易"]) then
                j = L["打包交易"]
            else
                j = 0
            end
            local a = {
                zhuangbei = item,
                maijia = maijia,
                jine = j,
            }
            for k, v in pairs(playerClass) do
                a[k] = v
            end
            if not Capture.appendEntry(captureState, a, GetTime()) then AbortCapture() return end
            tinsert(linshi_duizhang.zhangdan, a)
        end
        return
    elseif bigfootyes and sender == linshi_duizhang.player and BG.FindTableString(msg, locales["事件：.-|c.-|Hitem.-|h|r"]) then -- 大脚
        bigfootItem = strmatch(msg, h_item)
        return
    elseif bigfootyes and sender == linshi_duizhang.player and BG.FindTableString(msg, locales["^收入为："]) then
        local jine = Capture.parseMoney(strmatch(msg, "%d+"))
        if bigfootItem and jine and jine ~= 0 then
            local entry = {
                zhuangbei = bigfootItem,
                jine = jine,
            }
            if not Capture.appendEntry(captureState, entry, GetTime()) then AbortCapture() return end
            tinsert(linshi_duizhang.zhangdan, entry)
        end
        bigfootItem = nil
        return
    end

    -- 完成当前会话账单
    local yes
    if linshi_duizhang.yes and sender == linshi_duizhang.player and (BG.FindTableString(msg, locales["平均每人收入:"]) or BG.FindTableString(msg, locales["感谢使用金团表格"])) then
        yes = true
    elseif bigfootyes and sender == linshi_duizhang.player and BG.FindTableString(msg, locales["-感谢使用大脚金团辅助工具-"]) then -- 大脚
        yes = true
        bigfootyes = nil
        bigfootItem = nil
    end
    if yes then
        linshi_duizhang.yes = nil
        local sumMoney = 0
        for _, v in pairs(linshi_duizhang.zhangdan) do
            local jine = tonumber(v.jine) or 0
            sumMoney = sumMoney + jine
        end
        linshi_duizhang.sumjine = sumMoney
        local FB = linshi_duizhang.FB
        tinsert(BG.sessionDuizhang, linshi_duizhang)
        linshi_duizhang = nil
        BG.IsSavingLedger = nil
        Capture.stop(captureState)
        UpdateCaptureButton()
        BG.DuiZhangList()
        if FB then
            BG.After(0.1, function()
                Send(#BG.sessionDuizhang, sumMoney, FB)
            end)
            if BG.ShowYYPJ then
                BG.ShowYYPJ(sender)
            end
        end
        return
    end
end)

BG.RegisterEvent("CHAT_MSG_ADDON", function(self, event, ...)
    local prefix, msg, distType, sender = ...
    if not linshi_duizhang then return end
    if prefix == "BiaoGe" and distType == "RAID" and msg:match("^DuiZhang-") then
        sender = BG.GSN(sender)
        local realm = GetRealm()
        local members = GetRaidMemberNames()
        if not Capture.acceptSource(captureState, sender, realm, members, GetTime()) then return end
        if not Capture.appendLine(captureState, msg, GetTime()) then AbortCapture() return end
        linshi_duizhang.tradeTbl = linshi_duizhang.tradeTbl or {}
        local a = {}
        local maijia, text
        if BG.BGNext and BG.BGNext.PlayerIdentity then
            maijia, text = BG.BGNext.PlayerIdentity.parseDuiZhang(msg)
        else
            local _, legacyBuyer, legacyText = strsplit("-", msg)
            maijia, text = legacyBuyer, legacyText
        end
        if not maijia or not text then return end
        -- 24478 10000, 27854 t, 27503 t,
        for _, t in ipairs({ strsplit(",", text) }) do
            -- 24478 10000
            local itemID, jine = strsplit(" ", t)
            itemID = Capture.parseItemID(itemID)
            if itemID then
                if jine ~= "t" then
                    jine = Capture.parseMoney(jine)
                    if not jine then return end
                end
                local entry = {
                    maijia = maijia,
                    jine = jine,
                    itemID = itemID,
                }
                if not Capture.appendEntry(captureState, entry, GetTime()) then AbortCapture() return end
                tinsert(a, entry)
            end
        end
        tinsert(linshi_duizhang.tradeTbl, a)
    end
end)

BG.RegisterEvent("PLAYER_LOGOUT", function()
    StopCapture(true)
end)

BG.RegisterEvent("GROUP_ROSTER_UPDATE", function()
    StopCapture(true)
end)

------------------创建UI------------------
function BG.DuiZhangUI()
    BG.DuiZhangDropDown = {}
    local dropDown = LibBG:Create_UIDropDownMenu(nil, BG.DuiZhangMainFrame)
    dropDown:SetPoint("BOTTOM", BG.MainFrame, "BOTTOM", -40, 30)
    LibBG:UIDropDownMenu_SetWidth(dropDown, 450)
    LibBG:UIDropDownMenu_SetText(dropDown, L["无"])
    LibBG:UIDropDownMenu_SetAnchor(dropDown, 0, 0, "BOTTOM", dropDown, "TOP")
    BG.dropDownToggle(dropDown)
    BG.DuiZhangDropDown.DropDown = dropDown
    local text = dropDown:CreateFontString()
    text:SetPoint("RIGHT", dropDown, "LEFT", 10, 3)
    text:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
    text:SetTextColor(1, 1, 0)
    text:SetText(BG.STC_g1(L["对比的账单："]))
    BG.DuiZhangDropDown.BiaoTi = text

    local captureButton = BG.CreateButton(BG.DuiZhangMainFrame)
    captureButton:SetSize(90, 25)
    captureButton:SetPoint("RIGHT", text, "LEFT", -10, -3)
    captureButton:SetText(L["开始对账"])
    BG.DuiZhangMainFrame.CaptureButton = captureButton
    captureButton:SetScript("OnClick", function()
        BG.PlaySound(1)
        if Capture.isActive(captureState, GetTime()) then
            StopCapture(true)
            BG.SendSystemMessage(L["已停止对账并清空本次临时数据。"])
        else
            ClearSessionResults()
            Capture.start(captureState, GetTime())
            UpdateCaptureButton()
            BG.SendSystemMessage(L["已开始对账：仅临时读取当前团队接下来通报的一份账单。"])
        end
    end)
    captureButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["当前团队临时对账"], 1, 1, 1, true)
        GameTooltip:AddLine(L["只有点击开始后才会读取账单；数据不会写入插件保存文件，重载、离团或停止后立即清空。"], 1, .82, 0, true)
        GameTooltip:Show()
    end)
    captureButton:SetScript("OnLeave", GameTooltip_Hide)

    -- 删除账单
    hooksecurefunc(LibBG, "ToggleDropDownMenu", function(_, _, _, dropDown)
        if dropDown == BG.DuiZhangDropDown.DropDown then
            for i = 1, _G['L_DropDownList1'].numButtons do
                local button = _G["L_DropDownList1Button" .. i]
                if not button.deleteZhangDan then
                    local bt = CreateFrame("Button", nil, button)
                    bt:SetSize(20, 20)
                    bt:SetPoint("RIGHT", -2, 0)
                    bt:SetNormalTexture("interface/raidframe/readycheck-notready")
                    bt:SetHighlightTexture("interface/raidframe/readycheck-notready")
                    bt:RegisterForClicks("AnyUp")
                    bt.num = i
                    bt:Hide()
                    button.deleteZhangDan = bt
                    bt:SetScript("OnClick", function(self)
                        BG.PlaySound(1)
                        tremove(BG.sessionDuizhang, self.num)
                        BG.lastduizhangNum = nil
                        BG.DuiZhang0()
                        LibBG:UIDropDownMenu_SetText(BG.DuiZhangDropDown.DropDown, L["无"])
                        BG.DuiZhangMainFrame.ButtonCopy:Disable()
                        LibBG:CloseDropDownMenus()
                        LibBG:ToggleDropDownMenu(nil, nil, BG.DuiZhangDropDown.DropDown)
                    end)
                    bt:SetScript("OnEnter", function(self)
                        LibBG:UIDropDownMenu_StopCounting(self:GetParent():GetParent())
                        button.Highlight:Show()
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0)
                        GameTooltip:ClearLines()
                        GameTooltip:AddLine(L["删除该账单"], 1, 1, 1, true)
                        GameTooltip:Show()
                    end)
                    bt:SetScript("OnLeave", function(self)
                        LibBG:UIDropDownMenu_StartCounting(self:GetParent():GetParent())
                        button.Highlight:Hide()
                        GameTooltip:Hide()
                    end)
                end
                button.deleteZhangDan.num = i
                button.deleteZhangDan:SetShown(not (i == _G['L_DropDownList1'].numButtons))
            end
        else
            for i = 1, L_UIDROPDOWNMENU_MAXBUTTONS do
                local button = _G["L_DropDownList1Button" .. i]
                if button.deleteZhangDan then
                    button.deleteZhangDan:Hide()
                end
            end
        end
    end)

    -- 复制对方金额
    do
        local bt = BG.CreateButton(BG.DuiZhangMainFrame)
        bt:SetSize(100, 25)
        bt:SetPoint("LEFT", dropDown, "RIGHT", 0, 3)
        bt:SetText(L["复制对方账单"])
        bt:Disable()
        BG.DuiZhangMainFrame.ButtonCopy = bt
        bt:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L["复制对方账单"], 1, 1, 1, true)
            GameTooltip:AddLine(L["把对方账单的金额覆盖我当前表格的金额。如果对方是BGLite插件的账单，则也会复制其买家。"], 1, 0.82, 0, true)
            GameTooltip:AddLine(" ", 1, 0.82, 0, true)
            GameTooltip:AddLine(L["不会对漏记的装备和金额生效。"], 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        bt:SetScript("OnLeave", GameTooltip_Hide)
        bt:SetScript("OnClick", function(self)
            bt:Copy()
            BG.PlaySound(2)
        end)
        function bt:Copy()
            local addons = BG.sessionDuizhang[BG.lastduizhangNum].addons
            local FB = BG.FB1
            local tradeInfo = {}
            BiaoGe[FB].tradeTbl = {}
            for b = 1, Maxb[FB] - 1 do
                for i = 1, BG.GetMaxi(FB, b) do
                    local otherjine = BG.DuiZhangFrame[FB]["boss" .. b]["otherjine" .. i]
                    local myjine = BG.DuiZhangFrame[FB]["boss" .. b]["myjine" .. i]
                    local zhuangbei = BG.Frame[FB]["boss" .. b]["zhuangbei" .. i]
                    local maijia = BG.Frame[FB]["boss" .. b]["maijia" .. i]
                    local jine = BG.Frame[FB]["boss" .. b]["jine" .. i]
                    if zhuangbei then
                        myjine:SetText(otherjine:GetText())
                        jine:SetText(otherjine:GetText())
                        if otherjine:GetText() == "" then
                            BiaoGe[FB]["boss" .. b]["jine" .. i] = nil
                        else
                            BiaoGe[FB]["boss" .. b]["jine" .. i] = otherjine:GetText()
                        end

                        if addons == "biaoge" then
                            local duizhangmaijia = BG.DuiZhangFrame[FB]["boss" .. b]["maijia" .. i]
                            local duizhangcolor = BG.DuiZhangFrame[FB]["boss" .. b]["color" .. i]
                            BG.BGNext.BillBuyer.set(maijia, duizhangmaijia,
                                unpack(duizhangcolor or { 1, 1, 1 }))
                            for k in pairs(BG.playerClass) do
                                BiaoGe[FB]["boss" .. b][k .. i] = BG.DuiZhangFrame[FB]["boss" .. b][k .. i]
                            end

                            -- 打包交易
                            if otherjine.tradeTbl then
                                local notYes
                                for ii, vv in ipairs(tradeInfo) do
                                    for i, v in ipairs(otherjine.tradeTbl) do
                                        if vv.b == v.b and vv.i == v.i then
                                            notYes = true
                                            break
                                        end
                                    end
                                    if notYes then break end
                                end
                                if not notYes then
                                    local tradeTbl = BG.Copy(otherjine.tradeTbl)
                                    for i, v in ipairs(tradeTbl) do
                                        local zb = BG.Frame[FB]["boss" .. v.b]["zhuangbei" .. v.i]
                                        tradeTbl[i].FB = FB
                                        tradeTbl[i].itemID = GetItemID(zb:GetText())
                                        tradeTbl[i].link = zb:GetText()
                                        tinsert(tradeInfo, { b = v.b, i = v.i })
                                    end
                                    tinsert(BiaoGe[FB].tradeTbl, tradeTbl)
                                end
                            end
                        end
                    end
                end
            end
            BG.DuiZhangSet(BG.lastduizhangNum)
        end
    end

end

------------------生成下拉列表可选账单------------------
local function CreateZhangDanTitle(num)
    local zhangdan = BG.sessionDuizhang[num]
    local FBtext = ""
    if zhangdan.FB then
        for i, v in ipairs(BG.FBtable2) do
            if zhangdan.FB == v.FB then
                FBtext = L["，"] .. BG.STC_b1(v.shortName or v.localName)
                break
            end
        end
    end
    local classtext = "ffFFFFFF"
    if zhangdan.class then
        classtext = select(4, GetClassColor(zhangdan.class))
    end
    local title = zhangdan.time .. L["，"] .. "|c" .. classtext .. zhangdan.player .. RR
        .. L["，"] .. L["装备总收入"] .. BG.STC_g1(BG.FormatNumber(zhangdan.sumjine, 5)) .. FBtext
    return title
end

function BG.DuiZhangList()
    for i, v in ipairs(BG.sessionDuizhang) do
        v.sumjine = v.sunjine or v.sumjine or 0
        v.sunjine = nil
    end

    LibBG:UIDropDownMenu_Initialize(BG.DuiZhangDropDown.DropDown, function(self, level)
        BG.FrameHide(0)
        for i, v in ipairs(BG.sessionDuizhang) do
            local title = CreateZhangDanTitle(i)
            local info = LibBG:UIDropDownMenu_CreateInfo()
            info.text = title
            info.func = function()
                BG.FrameHide(0)
                BG.lastduizhangNum = i
                BG.DuiZhangSet(i)
                LibBG:UIDropDownMenu_SetText(BG.DuiZhangDropDown.DropDown, title)
            end
            if BG.lastduizhangNum == i then
                info.checked = true
            end
            LibBG:UIDropDownMenu_AddButton(info)
        end
        local info = LibBG:UIDropDownMenu_CreateInfo()
        info.text = L["无"]
        info.func = function()
            BG.FrameHide(0)
            BG.lastduizhangNum = nil
            BG.DuiZhang0()
            LibBG:UIDropDownMenu_SetText(BG.DuiZhangDropDown.DropDown, L["无"])
            BG.DuiZhangMainFrame.ButtonCopy:Disable()
        end
        if not BG.lastduizhangNum then
            info.checked = true
        end
        LibBG:UIDropDownMenu_AddButton(info)
    end)
end

------------------账单生成函数------------------
function BG.DuiZhangSet(num)
    local dz = BG.sessionDuizhang[num].zhangdan
    local FB = BG.FB1
    BG.lastduizhangNum = num
    BG.DuiZhangMainFrame.ButtonCopy:Enable()

    BG.DuiZhang0()
    --[[
        ["tradeTbl"] = {
            {
                {
                    ["maijia"] = "苍刃",
                    ["itemID"] = 24291,
                    ["jine"] = "200",
                }, -- [1]
                {
                    ["maijia"] = "苍刃",
                    ["itemID"] = 27676,
                    ["jine"] = "t",
                }, -- [2]
            }, -- [1]
        },

        ["tradeTbl"] = {
            {
                {
                    ["i"] = 1,
                    ["itemID"] = 45087,
                    ["link"] = "|cff0070dd|Hitem:45087::::::::80:::::::::|h[符文宝珠]|h|r",
                    ["FB"] = "ULD",
                    ["b"] = 15,
                }, -- [1]
                {
                    ["i"] = 3,
                    ["itemID"] = 45291,
                    ["link"] = "|cffa335ee|Hitem:45291::::::::80:::::::::|h[内燃护腕]|h|r",
                    ["FB"] = "ULD",
                    ["b"] = 1,
                }, -- [2]
            }, -- [1]
    ]]
    for _, v in ipairs(dz) do
        if v.zhuangbei then
            local item = v.zhuangbei
            local jine = v.jine
            local yes
            for b = 1, Maxb[FB] - 1 do
                for i = 1, BG.GetMaxi(FB, b) do
                    local zhuangbei = BG.DuiZhangFrame[FB]["boss" .. b]["zhuangbei" .. i]
                    local myjine = BG.DuiZhangFrame[FB]["boss" .. b]["myjine" .. i]
                    local otherjine = BG.DuiZhangFrame[FB]["boss" .. b]["otherjine" .. i]
                    local tx = BG.DuiZhangFrame[FB]["boss" .. b]["yes" .. i]
                    if zhuangbei then
                        if GetItemID(zhuangbei:GetText()) == GetItemID(item) and otherjine:GetText() == "" then
                            otherjine:SetText(jine)
                            BG.DuiZhangFrame[FB]["boss" .. b]["maijia" .. i] = v.maijia
                            for k in pairs(BG.playerClass) do
                                BG.DuiZhangFrame[FB]["boss" .. b][k .. i] = v[k]
                            end
                            yes = true
                            break
                        end
                    end
                end
                if yes then break end
            end
            -- 漏记
            if not yes then
                local b = Maxb[FB]
                for i = 1, BG.GetMaxi(FB, b) do
                    local zhuangbei = BG.DuiZhangFrame[FB]["boss" .. b]["zhuangbei" .. i]
                    local otherjine = BG.DuiZhangFrame[FB]["boss" .. b]["otherjine" .. i]
                    if zhuangbei then
                        if not GetItemID(zhuangbei:GetText()) then
                            zhuangbei:SetText(item)
                            otherjine:SetText(jine)
                            break
                        end
                    end
                end
            end
        end
    end

    if BG.sessionDuizhang[num].tradeTbl then
        for ii in ipairs(BG.sessionDuizhang[num].tradeTbl) do
            local tbl = {}
            for _, v in ipairs(BG.sessionDuizhang[num].tradeTbl[ii]) do
                local yes
                for b = 1, Maxb[FB] do
                    for i = 1, BG.GetMaxi(FB, b) do
                        local otherjine = BG.DuiZhangFrame[FB]["boss" .. b]["otherjine" .. i]
                        if otherjine and not (otherjine.hasTradeTbl or otherjine.tradeTbl) then
                            local maijia = BG.DuiZhangFrame[FB]["boss" .. b]["maijia" .. i]
                            local itemID = GetItemID(BG.DuiZhangFrame[FB]["boss" .. b]["zhuangbei" .. i]:GetText())
                            local jine = BG.DuiZhangFrame[FB]["boss" .. b]["otherjine" .. i]:GetText()
                            if jine == L["打包交易"] then jine = "t" end
                            if maijia == v.maijia and itemID == v.itemID and jine == v.jine then
                                otherjine.hasTradeTbl = true
                                tinsert(tbl, { b = b, i = i })
                                yes = true
                                break
                            end
                        end
                    end
                    if yes then break end
                end
            end
            for i, v in ipairs(tbl) do
                BG.DuiZhangFrame[FB]["boss" .. v.b]["otherjine" .. v.i].hasTradeTbl = nil
                BG.DuiZhangFrame[FB]["boss" .. v.b]["otherjine" .. v.i].tradeTbl = tbl
            end
        end
    end

    -- 设置打钩/叉叉材质
    BG.After(0, function()
        local errorItems = {}
        for b = 1, Maxb[FB] + 1 do
            for i = 1, BG.GetMaxi(FB, b) do
                local zhuangbei = BG.DuiZhangFrame[FB]["boss" .. b]["zhuangbei" .. i]
                local myjine = BG.DuiZhangFrame[FB]["boss" .. b]["myjine" .. i]
                local otherjine = BG.DuiZhangFrame[FB]["boss" .. b]["otherjine" .. i]
                local tx = BG.DuiZhangFrame[FB]["boss" .. b]["yes" .. i]
                if zhuangbei and zhuangbei ~= BG.DuiZhangFrame[FB]["boss" .. Maxb[FB] + 1]["zhuangbei2"] then
                    local mj = myjine:GetText()
                    local oj = otherjine:GetText()
                    if not tonumber(mj) or tonumber(mj) == 0 then
                        mj = ""
                    end
                    if not tonumber(oj) or tonumber(oj) == 0 then
                        oj = ""
                    end
                    if (tonumber(mj) or tonumber(oj)) and tonumber(mj) == tonumber(oj) then
                        tx:SetTexture("interface/raidframe/readycheck-ready")
                        BG.DuiZhangFrameDs[FB .. 3]["boss" .. b]["ds" .. i]:Hide()
                    elseif (tonumber(mj) or tonumber(oj)) and tonumber(mj) ~= tonumber(oj) then
                        tx:SetTexture("interface/raidframe/readycheck-notready")
                        BG.DuiZhangFrameDs[FB .. 3]["boss" .. b]["ds" .. i]:Show()
                        if b <= Maxb[FB] - 1 then
                            local itemID = GetItemID(zhuangbei:GetText())
                            if itemID then
                                tinsert(errorItems, {
                                    itemID = itemID,
                                    b = b,
                                    i = i,
                                    my = tonumber(mj) or 0,
                                    other = tonumber(oj) or 0,
                                })
                            end
                        end
                    else
                        tx:SetTexture(nil)
                        BG.DuiZhangFrameDs[FB .. 3]["boss" .. b]["ds" .. i]:Hide()
                    end
                end
            end
        end
        if next(errorItems) then
            local sameItem = {}
            for i, v in ipairs(errorItems) do
                sameItem[v.itemID] = sameItem[v.itemID] or { gz = {}, my = 0, other = 0, }
                tinsert(sameItem[v.itemID].gz, { b = v.b, i = v.i })
                sameItem[v.itemID].my = sameItem[v.itemID].my + v.my
                sameItem[v.itemID].other = sameItem[v.itemID].other + v.other
            end
            for itemID, v in pairs(sameItem) do
                if v.my == v.other then
                    for _, vv in ipairs(v.gz) do
                        local b = vv.b
                        local i = vv.i
                        local tx = BG.DuiZhangFrame[FB]["boss" .. b]["yes" .. i]
                        tx:SetTexture("interface/raidframe/readycheck-ready")
                        BG.DuiZhangFrameDs[FB .. 3]["boss" .. b]["ds" .. i]:Hide()

                        BG.DuiZhangFrame[FB]["boss" .. b]["zhuangbei" .. i].sameItem = v.gz
                        BG.DuiZhangFrame[FB]["boss" .. b]["myjine" .. i].sameItem = v.gz
                        BG.DuiZhangFrame[FB]["boss" .. b]["otherjine" .. i].sameItem = v.gz
                    end
                end
            end
        end


        -- 打包交易的进行合并对账
        --[[         if BG.sessionDuizhang[num].tradeTbl then
            BG.After(0, function()
                for b = 1, Maxb[FB] do
                    for i = 1, BG.GetMaxi(FB, b) do
                        local otherjine = BG.DuiZhangFrame[FB]["boss" .. b]["otherjine" .. i]
                        if otherjine and otherjine.tradeTbl and BG.DuiZhangFrameDs[FB .. 3]["boss" .. b]["ds" .. i]:IsVisible() then
                            local mySum = 0
                            local otherSum = 0
                            for _, v in ipairs(otherjine.tradeTbl) do
                                local b = v.b
                                local i = v.i
                                local mybutton = BG.DuiZhangFrame[FB]["boss" .. b]["myjine" .. i]
                                local otherbutton = BG.DuiZhangFrame[FB]["boss" .. b]["otherjine" .. i]
                                mySum = mySum + (tonumber(mybutton:GetText()) or 0)
                                otherSum = otherSum + (tonumber(otherbutton:GetText()) or 0)
                            end
                            if mySum == otherSum then
                                for _, v in ipairs(otherjine.tradeTbl) do
                                    local b = v.b
                                    local i = v.i
                                    BG.DuiZhangFrame[FB]["boss" .. b]["yes" .. i]:SetTexture("interface/raidframe/readycheck-ready")
                                    BG.DuiZhangFrameDs[FB .. 3]["boss" .. b]["ds" .. i]:Hide()
                                end
                            end
                        end
                    end
                end
            end)
        end ]]
    end)
end

------------------对账格子清空------------------
function BG.DuiZhang0()
    local FB = BG.FB1
    for b = 1, Maxb[FB] + 1 do
        for i = 1, BG.GetMaxi(FB, b) do
            local zhuangbei = BG.DuiZhangFrame[FB]["boss" .. b]["zhuangbei" .. i]
            local myjine = BG.DuiZhangFrame[FB]["boss" .. b]["myjine" .. i]
            local otherjine = BG.DuiZhangFrame[FB]["boss" .. b]["otherjine" .. i]
            local tx = BG.DuiZhangFrame[FB]["boss" .. b]["yes" .. i]
            local ds = BG.DuiZhangFrameDs[FB .. 3]["boss" .. b]["ds" .. i]
            if zhuangbei then
                otherjine:SetText("")
                otherjine.tradeTbl = nil
                zhuangbei.sameItem = nil
                myjine.sameItem = nil
                otherjine.sameItem = nil
                BG.DuiZhangFrame[FB]["boss" .. b]["maijia" .. i] = nil
                for k, v in pairs(BG.playerClass) do
                    BG.DuiZhangFrame[FB]["boss" .. b][k .. i] = nil
                end
                tx:SetTexture(nil)
                ds:Hide()
            end
        end
    end

    -- 漏记装备
    local b = Maxb[FB]
    for i = 1, BG.GetMaxi(FB, b) do
        local zhuangbei = BG.DuiZhangFrame[FB]["boss" .. b]["zhuangbei" .. i]
        local myjine = BG.DuiZhangFrame[FB]["boss" .. b]["myjine" .. i]
        if zhuangbei then
            zhuangbei:SetText("")
            myjine:SetText("")
        end
    end
end

local function CopyBill(num, FB)
    FB = FB or BG.FB1
    if FB ~= BG.FB1 then
        BG.ClickFBbutton(FB)
    end
    BG.MainFrame:Show()
    BG.ClickTabButton(BG.DuiZhangMainFrameTabNum)
    BG.DuiZhangSet(num)
    LibBG:UIDropDownMenu_SetText(BG.DuiZhangDropDown.DropDown, CreateZhangDanTitle(num))
    BG.DuiZhangMainFrame.ButtonCopy:Copy()
    BG.ClickTabButton(BG.FBMainFrameTabNum)
end

hooksecurefunc("SetItemRef", function(link)
    local _, BiaoGeDuiZhang, num, FB = strsplit(":", link)
    if BiaoGeDuiZhang == "BiaoGeDuiZhang" and num then
        num = tonumber(num)
        BG.MainFrame:Show()
        BG.ClickTabButton(BG.DuiZhangMainFrameTabNum)
        BG.DuiZhangSet(num)
        LibBG:UIDropDownMenu_SetText(BG.DuiZhangDropDown.DropDown, CreateZhangDanTitle(num))
        BG.PlaySound(1)
    elseif BiaoGeDuiZhang == "BiaoGeDuiZhangCopy" and num and IsAltKeyDown() then
        num = tonumber(num)
        CopyBill(num, FB)
        BG.PlaySound(2)
    end
end)
