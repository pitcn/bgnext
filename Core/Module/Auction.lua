if BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local LibBG         = ns.LibBG
local L             = ns.L

local Size          = ns.Size
local RGB           = ns.RGB
local GetClassRGB   = ns.GetClassRGB
local SetClassCFF   = ns.SetClassCFF
local AddTexture    = ns.AddTexture
local GetItemID     = ns.GetItemID

local Maxb          = ns.Maxb
local HopeMaxn      = ns.HopeMaxn
local HopeMaxb      = ns.HopeMaxb
local HopeMaxi      = ns.HopeMaxi

local RealmId       = GetRealmID()
local player        = BG.playerName
local IsAddOnLoaded = IsAddOnLoaded or C_AddOns.IsAddOnLoaded
local LoadAddOn     = LoadAddOn or C_AddOns.LoadAddOn

BG.Init(function()
    BiaoGe.Auction = BiaoGe.Auction or {}
    if BG.verLess2 then
        BiaoGe.Auction.money = BiaoGe.Auction.money or 1
        BiaoGe.Auction.fastMoney = BiaoGe.Auction.fastMoney or { 100, 300, 500, 1000, 2000 }
    elseif BG.IsTitan then
        BG.Once("fastMoney", 251201, function()
            BiaoGe.Auction.money = nil
            BiaoGe.Auction.fastMoney = nil
        end)
        BiaoGe.Auction.money = BiaoGe.Auction.money or 1000
        BiaoGe.Auction.fastMoney = BiaoGe.Auction.fastMoney or { 300, 500, 1000, 2000, 3000 }
        BG.Once('fastMoney', 250528, function()
            BiaoGe.Auction.fastMoney = { 100, 300, 500, 1000, 2000 }
        end)
    elseif BG.IsWLK then
        BiaoGe.Auction.money = BiaoGe.Auction.money or 1000
        BiaoGe.Auction.fastMoney = BiaoGe.Auction.fastMoney or { 1000, 2000, 3000, 5000, 10000 }
    elseif BG.IsMOP then
        BG.Once("fastMoney", 260110, function()
            BiaoGe.Auction.money = nil
            BiaoGe.Auction.fastMoney = nil
        end)
        BiaoGe.Auction.money = BiaoGe.Auction.money or 10000
        BiaoGe.Auction.fastMoney = BiaoGe.Auction.fastMoney or { 10000, 20000, 30000, 50000, 100000 }
    else
        BiaoGe.Auction.money = BiaoGe.Auction.money or 100000
        BiaoGe.Auction.fastMoney = BiaoGe.Auction.fastMoney or { 10000, 50000, 100000, 200000, 500000 }
    end

    local sending = {}
    local sendDone = {}
    local sendingCount = {}
    local notShowSendingText = {}

    local function UpdateGuildFrame(frame)
        if IsInRaid(1) then
            frame:SetWidth(1)
            frame:Hide()
        elseif IsInGuild() then
            local numTotal, numOnline, numOnlineAndMobile = GetNumGuildMembers()
            frame.text:SetFormattedText(frame.title2, (Size(frame.table) .. "/" .. numOnline))
            frame:SetWidth(frame.text:GetWidth() + 10)
            frame:Show()
        end
    end

    local function UpdateAddonFrame(frame)
        if IsInRaid(1) then
            local count = 0
            for name in pairs(frame.table) do
                name = BG.GSN(name)
                if BG.raidRosterName[name] then
                    count = count + 1
                end
            end
            frame.text:SetFormattedText(frame.title2, (count .. "/" .. GetNumGroupMembers()))
            frame:SetWidth(frame.text:GetWidth() + 10)
            frame:Show()
        else
            wipe(frame.table)
            frame:Hide()
        end
    end
    local function Guild_OnEnter(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
        GameTooltip:ClearLines()
        GameTooltip:AddLine(self.title, 0, 1, 0)
        GameTooltip:AddLine(" ")
        local ii = 0
        for i = 1, GetNumGuildMembers() do
            local name, rankName, rankIndex, level, classDisplayName, zone,
            publicNote, officerNote, isOnline, status, class, achievementPoints,
            achievementRank, isMobile, canSoR, repStanding, guid = GetGuildRosterInfo(i)
            if isOnline then
                name = BG.GSN(name)
                if ii > 40 then
                    GameTooltip:AddLine("......")
                    break
                end
                ii = ii + 1
                local line = 2
                local Ver = self.table[name] or L["无"]
                local r, g, b = GetClassColor(class)
                GameTooltip:AddDoubleLine(BG.GSN(name), Ver, r, g, b, 1, 1, 1)
                if Ver == L["无"] then
                    local alpha = 0.3
                    if _G["GameTooltipTextLeft" .. (ii + line)] then
                        _G["GameTooltipTextLeft" .. (ii + line)]:SetAlpha(alpha)
                    end
                    if _G["GameTooltipTextRight" .. (ii + line)] then
                        _G["GameTooltipTextRight" .. (ii + line)]:SetAlpha(alpha)
                    end
                end
            end
        end
        GameTooltip:Show()
    end

    local function Addon_OnEnter(self, _, tooltip)
        if not self then return end
        if tooltip then
            self.title = L["BGLite版本"] .. "(" .. RAID .. ")"
            self.table = BG.raidBiaoGeVersion
            tooltip:SetOwner(self, "ANCHOR_NONE", 0, 0)
            tooltip:ClearLines()
            if BG.ButtonIsInTop(self) then
                tooltip:SetPoint('TOP', self, 'BOTTOM', 0, -0)
            else
                tooltip:SetPoint('BOTTOM', self, 'TOP', 0, 0)
            end
        else
            tooltip = GameTooltip
            self.isOnEnter = true
            tooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
            tooltip:ClearLines()
        end
        local line = 2
        tooltip:AddLine(self.title, 0, 1, 0)
        --[[         if self.isAuciton then
            tooltip:AddLine(L["需全团安装%s，没安装的人将会看不到拍卖窗口。"]:format(BG.IsRetail and "BGLite插件" or L["拍卖WA"]), 0.5, 0.5, 0.5, true)
            if not BG.IsRetail then
                local text = ""
                if not WeakAurasOptions then
                    text = BG.STC_r1(L["（WA面板尚未初始化）"])
                elseif BG.ButtonRaidAuction.loadProgressNum and BG.ButtonRaidAuction.total then
                    text = BG.STC_y1(format(L["（WA面板正在初始化：%s/%s）"],
                        BG.ButtonRaidAuction.loadProgressNum, BG.ButtonRaidAuction.total))
                else
                    text = BG.STC_g1(L["（WA面板已初始化，可以发送了）"])
                end
                tooltip:AddLine(L["SHIFT+点击：把WA字符串通过密语发送给没有的团员。"] .. text, 1, 1, 1, true)
                line = line + 2
            else
                line = line + 1
            end
        end ]]
        tooltip:AddLine(" ")
        for i, v in ipairs(BG.SortRaidRosterInfo()) do
            local name = v.name
            local Ver = self.table[name]
            local r, g, b = 1, 1, 1
            if not Ver then
                if v.online then
                    Ver = L["无"]
                else
                    Ver = L["未知(离线)"]
                end
                if self.isAuciton then
                    if sendDone[name] then
                        Ver = L["接收完毕，但未导入"]
                    elseif sending[name] then
                        Ver = L["正在接收拍卖WA"]
                    end
                end
            elseif not self.isAuciton then
                if BG.GetVerNum(BG.ver) > BG.GetVerNum(Ver) then
                    r = .6
                    g, b = r, r
                elseif BG.GetVerNum(BG.ver) < BG.GetVerNum(Ver) then
                    r, g, b = 0, 1, 0
                end
            end
            local role = ""
            local y
            if v.rank == 2 then
                role = role .. AddTexture("interface/groupframe/ui-group-leadericon", y)
            elseif v.rank == 1 then
                role = role .. AddTexture("interface/groupframe/ui-group-assistanticon", y)
            end
            if v.isML then
                role = role .. AddTexture("interface/groupframe/ui-group-masterlooter", y)
            end
            local c1, c2, c3 = GetClassRGB(name)
            tooltip:AddDoubleLine(name .. role, Ver, c1, c2, c3, r, g, b)
            if Ver == L["无"] or Ver == L["未知(离线)"] then
                local alpha = 0.4
                if _G[tooltip:GetName() .. "TextLeft" .. (i + line)] then
                    _G[tooltip:GetName() .. "TextLeft" .. (i + line)]:SetAlpha(alpha)
                end
                if _G[tooltip:GetName() .. "TextRight" .. (i + line)] then
                    _G[tooltip:GetName() .. "TextRight" .. (i + line)]:SetAlpha(alpha)
                end
            end
        end
        tooltip:Show()
    end

    local function UpdateOnEnter(self)
        if self and self.isOnEnter then
            self:GetScript("OnEnter")(self)
        end
    end

    local cd
    local function CanSend()
        if IsAddOnLoaded("WeakAuras") then
            if not IsAddOnLoaded("WeakAurasOptions") then
                if not LoadAddOn("WeakAurasOptions") then
                    BG.SendSystemMessage(L["你没有启用WeakAurasOptions插件。"])
                    return
                end
            end
            return true
        else
            BG.SendSystemMessage(L["你没有安装WeakAuras插件。"])
        end
    end
    local function StartSend()
        if cd then return end
        for i = 1, 10 do
            local header = _G["WeakAurasLoadedHeaderButton" .. i]
            if header then
                local titleString = _G[header:GetName() .. "Text"]:GetText()
                if titleString:match("/") then
                    -- if titleString:match("Loaded/Standby") or titleString:match("已载入") then
                    local tbl = { header:GetParent():GetChildren() }
                    for i, bt in ipairs(tbl) do
                        if bt.id and WeakAuras.IsAuraLoaded(bt.id) then
                            local ver = bt.id:match("<BiaoGe>拍卖%s-v(%d+%.%d+)")
                            if ver then
                                if IsShiftKeyDown() then
                                    cd = true
                                    BG.After(2, function() cd = nil end)
                                    BG.PlaySound(2)
                                    local edit = ChatEdit_ChooseBoxForSend()
                                    edit:SetText("")
                                    ChatEdit_ActivateChat(edit)
                                    bt:Click()
                                    BG.ButtonRaidAuction.WACode = edit:GetText()
                                    edit:SetText("")
                                    edit:Hide()
                                    GameTooltip:Hide()
                                    if BG.ButtonRaidAuction.isOnEnter then
                                        BG.ButtonRaidAuction:GetScript("OnEnter")(BG.ButtonRaidAuction)
                                    end
                                    if BG.ButtonRaidAuction.WACode ~= "" then
                                        for _, v in ipairs(BG.raidRosterInfo) do
                                            if not BG.raidAuctionVersion[v.name] and v.online then
                                                SendChatMessage(BG.ButtonRaidAuction.WACode, "WHISPER", nil, v.name)
                                            end
                                        end
                                    end
                                else
                                    BG.SendSystemMessage(L["需要按下SHIFT才能发送WA。"])
                                end
                                return
                            end
                        end
                    end
                    break
                end
            end
        end
        BG.SendSystemMessage(L["在你的WA面板里未找到拍卖WA字符串，你需要先从表格左上角的\"拍卖WA\"按钮导入该字符串。"])
    end
    local function SendWACode()
        if not CanSend() then return end
        if not IsShiftKeyDown() then return end
        if not WeakAurasOptions then
            WeakAuras.OpenOptions()
            WeakAurasOptions:Hide()
            BG.ButtonRaidAuction.total = 0
            for _, _ in pairs(WeakAurasSaved.displays) do
                BG.ButtonRaidAuction.total = BG.ButtonRaidAuction.total + 1
            end
            BG.OnUpdateTime(function(self)
                BG.ButtonRaidAuction.loadProgressNum = WeakAurasOptions.loadProgressNum
                if BG.ButtonRaidAuction.isOnEnter then
                    BG.ButtonRaidAuction:GetScript("OnEnter")(BG.ButtonRaidAuction)
                end
                if not WeakAurasOptions.loadProgress:IsShown() then
                    self:SetScript("OnUpdate", nil)
                    self:Hide()
                    BG.ButtonRaidAuction.total = nil
                    BG.ButtonRaidAuction.loadProgressNum = nil
                    if BG.ButtonRaidAuction.isOnEnter then
                        BG.ButtonRaidAuction:GetScript("OnEnter")(BG.ButtonRaidAuction)
                    end
                    BG.After(0, function()
                        StartSend()
                    end)
                end
            end)
        else
            StartSend()
        end
    end

    -- 团长开始拍卖UI
    do
        BiaoGe.Auction.duration = BiaoGe.Auction.duration or 40
        BiaoGe.Auction.mod = BiaoGe.Auction.mod or "normal"
        if BiaoGe.Auction.mod == 'roll' or BiaoGe.Auction.mod == 'anonymous' then
            BiaoGe.Auction.mod = 'normal'
        end
        BiaoGe.Auction.aotoSendLate = BiaoGe.Auction.aotoSendLate or 3
        BiaoGe.Auction.gen = BiaoGe.Auction.gen or 1
        BiaoGe.Auction.resetThreshold = BiaoGe.Auction.resetThreshold or 20

        local mods = {
            normal = L["常规模式"],
            -- roll = L["Roll点"],
        }
        local gens = {
            [1] = L["第一代拍卖"],
            [2] = L["第二代拍卖"],
        }
        if not mods[BiaoGe.Auction.mod] then
            BiaoGe.Auction.mod = "normal"
        end
        local mainFrameWidth = 250
        local mainFrameHeight = 217
        local maxCount = 10
        local errorMsg = L['错误：同时拍卖的数量不能超过%s个']:format(maxCount)

        function BG.SendStartAuctionMsg(isGen2, itemID, money, duration, mod, link, resetThreshold)
            local channel, text
            if isGen2 then
                channel = BGA.aura_env.GetAddonChannelName()
                text = format("StartAuction^%s^%s^%s^%s^^%s^%s^%s",
                    GetTime(), itemID, money, duration, mod, link, resetThreshold)
            else
                channel = "BiaoGeAuction"
                text = format("StartAuction,%s,%s,%s,%s,,%s,%s",
                    GetTime(), itemID, money, duration, mod, link)
            end
            C_ChatInfo.SendAddonMessage(channel, text, "RAID")
        end

        local function OverAuctionMaxCount(i)
            local j = 0
            for _, f in pairs(BGA.Frames) do
                j = j + 1
            end
            if i + j > maxCount then
                UIErrorsFrame:AddMessage(errorMsg, 1, 0, 0)
                return true
            end
        end

        local function ClearAllFocus(f)
            local i = 1
            while f['Edit' .. i] do
                f['Edit' .. i]:ClearFocus()
                i = i + 1
            end
            LibBG:CloseDropDownMenus()
        end
        local function item_OnEnter(self)
            if BG.ButtonIsInRight(self) then
                GameTooltip:SetOwner(self, "ANCHOR_LEFT", 0, 0)
            else
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0)
            end
            GameTooltip:ClearLines()
            GameTooltip:SetHyperlink(self.link)
            self.isOnEnter = true
            if self.isIcon then
                self.owner.lastIcon = self
                if not self.isChooseTex then
                    self.isChooseTex = self:CreateTexture()
                    self.isChooseTex:SetAllPoints()
                    self.isChooseTex:SetColorTexture(1, 1, 1, .2)
                    self.isChooseTex:Hide()
                end
                self.isChooseTex:Show()
            end
        end
        local function item_OnLeave(self)
            GameTooltip_Hide()
            self.isOnEnter = nil
            if self.isIcon then
                self.owner.lastIcon = nil
                self.isChooseTex:Hide()
            end
        end
        local function Start_OnClick(self)
            if not self.noSound then
                BG.PlaySound(1)
            end
            local mod = BiaoGe.Auction.mod
            if mod == "roll" then
                if #self.items > 1 then
                    return
                end
                SendChatMessage(format(L["{rt1}Roll点开始{rt1} %s"], self.items[1].link), "RAID_WARNING")
            else
                local money = self.money or tonumber(BiaoGe.Auction.money)
                local _duration = tonumber(BiaoGe.Auction.duration)
                local duration = _duration and _duration > 0 and _duration
                if not (money and duration) then return end
                local isGen2 = BiaoGe.Auction.gen == 2
                local resetThreshold = max(tonumber(BiaoGe.Auction.resetThreshold) or 0, 10)
                local delay = 0
                if #self.items > 1 then
                    for i, v in ipairs(self.items) do
                        local itemID = v.id
                        local link = v.link
                        BG.After(delay, function()
                            BG.SendStartAuctionMsg(isGen2, itemID, money, duration, mod, link, resetThreshold)
                        end)
                        delay = delay + 1
                    end
                else
                    local count = tonumber(self:GetParent().Edit4:GetText()) or 1
                    for i = 1, count do
                        local itemID = self.items[1].id
                        local link = self.items[1].link
                        BG.After(delay, function()
                            BG.SendStartAuctionMsg(isGen2, itemID, money, duration, mod, link, resetThreshold)
                        end)
                        delay = delay + 1
                    end
                end
                if self.callback then
                    self.callback()
                end
            end
            self:GetParent():Hide()
        end
        local function resetThreshold_OnEnter(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", -5, 0)
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L["重置阈值(秒)"], 1, 1, 1, true)
            GameTooltip:AddLine(L["当剩余时间低于此阈值时有人出价，拍卖时间会自动重置回该阈值。"], 1, 0.82, 0, true)
            GameTooltip:AddLine(L["阈值不能低于10秒。"], 1, 0.82, 0, true)
            if BiaoGe.Auction.gen ~= 2 then
                GameTooltip:AddLine(L["仅第二代拍卖可以修改。"], 1, 0, 0, true)
            end
            GameTooltip:Show()
        end
        local function Start_OnEnter(self)
            if BiaoGe.Auction.mod == "roll" and #self.items > 1 then
                GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
                GameTooltip:ClearLines()
                GameTooltip:AddLine(self:GetText(), 1, 1, 1, true)
                GameTooltip:AddLine(L["不能同时发起多件装备Roll点。"], 1, 0, 0, true)
                GameTooltip:Show()
            end
        end
        local function OnTextChanged(self)
            BiaoGe.Auction[self._type] = self:GetText()
        end
        local function OnEnterPressed(self)
            if self.num == 1 then
                self:GetParent().Edit2:SetFocus()
            elseif self.num == 2 then
                Start_OnClick(self:GetParent().bt)
            else
                self:ClearFocus()
            end
        end
        local matchStr = ITEM_CLASSES_ALLOWED:gsub("%%s", "")
        function BG.GetTooltipClassText(itemID)
            BG.Tooltip_SetItemByID(itemID)
            for i = 1, BiaoGeTooltip:NumLines() do
                local str = _G["BiaoGeTooltipTextLeft" .. i]:GetText()
                if str then
                    local classStr = str:match(matchStr .. "(.+)")
                    if classStr then
                        local colorCls = ""
                        for _, className in ipairs({ strsplit(",", classStr) }) do
                            className = className:gsub("^%s+", "")
                            colorCls = colorCls .. (BG.classColorNames[className] or className) .. "  "
                        end
                        return colorCls
                    end
                end
            end
            return ""
        end

        local function UpdateFrame()
            local mainFrame = BG.StartAucitonFrame
            if BiaoGe.Auction.gen == 2 then
                mainFrame.Edit3:SetEnabled(true)
                mainFrame.Edit3:SetTextColor(1, 1, 1)
                mainFrame.Text5:SetTextColor(1, .82, 0)
            else
                mainFrame.Edit3:SetEnabled(false)
                mainFrame.Edit3:SetTextColor(0.5, 0.5, 0.5)
                mainFrame.Edit3:SetText(20)
                mainFrame.Text5:SetTextColor(0.5, 0.5, 0.5)
            end
        end

        hooksecurefunc(LibBG, "ToggleDropDownMenu", function(_, _, _, dropDown)
            local _dropDown = BG.StartAucitonFrame and BG.StartAucitonFrame.dropDown2
            if _dropDown and dropDown == _dropDown then
                if L_DropDownList1:IsVisible() then
                    Addon_OnEnter(BG.StartAucitonFrame, _, BiaoGeTooltip2)
                else
                    BiaoGeTooltip2:Hide()
                end
            end
        end)
        L_DropDownList1:HookScript('OnHide', function(self)
            BiaoGeTooltip2:Hide()
        end)

        function BG.StartAuction(link, bt, isNotAuctioned, notAlt, isRightButton, noSound, callback)
            if BiaoGe.options["autoAuctionStart"] ~= 1 and not notAlt then return end
            if not link then return end
            if not BG.IsML then return end
            local link = BG.Copy(link)
            local items = {}
            if type(link) == "table" then
                items = link
            else
                items[1] = { id = GetItemID(link), link = link }
            end
            if OverAuctionMaxCount(#items) then return end
            if BG.StartAucitonFrame then BG.StartAucitonFrame:Hide() end
            GameTooltip:Hide()
            local name, link, quality, level, _, itemType, itemSubType, _, itemEquipLoc, Texture,
            _, classID, subclassID, bindType = GetItemInfo(items[1].link)

            local mainFrame
            local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            do
                f:SetBackdrop({
                    bgFile = "Interface/ChatFrame/ChatFrameBackground",
                    edgeFile = "Interface/ChatFrame/ChatFrameBackground",
                    edgeSize = 2,
                })
                f:SetBackdropColor(0.3, 0.3, 0.3, 0.8)
                f:SetBackdropBorderColor(0, 0, 0, 1)
                f:SetSize(mainFrameWidth, mainFrameHeight)
                if bt then
                    if isNotAuctioned then
                        f:SetPoint("TOP", bt, "BOTTOM", 10, 0)
                    else
                        f:SetPoint("BOTTOM", bt, "TOP", 0, 0)
                    end
                else
                    local x, y = GetCursorPosition()
                    x, y = x / UIParent:GetEffectiveScale(), y / UIParent:GetEffectiveScale()
                    f:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x + 10, y + 10)
                end
                f:SetFrameStrata("DIALOG")
                f:SetFrameLevel(300)
                f:SetClampedToScreen(true)
                f:SetToplevel(true)
                f:EnableMouse(true)
                f:SetMovable(true)
                f:SetScript("OnMouseUp", function(self)
                    f:StopMovingOrSizing()
                    f:SetScript("OnUpdate", nil)
                end)
                f:SetScript("OnMouseDown", function(self)
                    f:StartMoving()
                    ClearAllFocus(f)

                    f.time = 0
                    f:SetScript("OnUpdate", function(self, time)
                        f.time = f.time + time
                        if f.time >= 0.2 then
                            f.time = 0
                            if f.itemFrame.isOnEnter then
                                GameTooltip:Hide()
                                f.itemFrame:GetScript("OnEnter")(f.itemFrame)
                            elseif f.lastIcon then
                                GameTooltip:Hide()
                                f.lastIcon:GetScript("OnEnter")(f.lastIcon)
                            end
                        end
                    end)
                end)
                mainFrame = f
                BG.StartAucitonFrame = mainFrame
                f.UpdateFrame = UpdateFrame

                BG.CreateCloseButton(f, 0, 0)
                f.CloseButton:SetSize(35, 35)
                f.CloseButton:SetFrameLevel(f.CloseButton:GetParent():GetFrameLevel() + 50)
            end

            -- 装备显示
            do
                local f = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
                f:SetPoint("TOPLEFT", f:GetParent(), "TOPLEFT", 2, -2)
                f:SetPoint("BOTTOMRIGHT", f:GetParent(), "TOPRIGHT", -2, -35)
                f:SetFrameLevel(f:GetParent():GetFrameLevel() + 10)
                f.itemID = items[1].id
                f.link = items[1].link
                f:SetScript("OnMouseUp", function(self)
                    mainFrame:GetScript("OnMouseUp")(mainFrame)
                end)
                f:SetScript("OnMouseDown", function(self)
                    mainFrame:GetScript("OnMouseDown")(mainFrame)
                end)
                mainFrame.itemFrame = f
                -- 黑色背景
                local s = CreateFrame("StatusBar", nil, f)
                s:SetAllPoints()
                s:SetFrameLevel(s:GetParent():GetFrameLevel() - 5)
                s:SetStatusBarTexture("Interface/ChatFrame/ChatFrameBackground")
                s:SetStatusBarColor(0, 0, 0, 0.8)

                local icons = {}
                for i, v in ipairs(items) do
                    local itemID = v.id
                    local link = v.link
                    local name, link, quality, level, _, itemType, itemSubType, _, itemEquipLoc, Texture,
                    _, classID, subclassID, bindType = GetItemInfo(link)

                    -- 图标
                    local r, g, b = GetItemQualityColor(quality)
                    local ftex = CreateFrame("Frame", nil, f, "BackdropTemplate")
                    ftex:SetBackdrop({
                        edgeFile = "Interface/ChatFrame/ChatFrameBackground",
                        edgeSize = 1.5,
                    })
                    ftex:SetBackdropBorderColor(r, g, b, 1)
                    if i == 1 then
                        ftex:SetPoint("TOPLEFT", 0, 0)
                    else
                        ftex:SetPoint("TOPLEFT", icons[i - 1], "TOPRIGHT", 3, 0)
                    end
                    ftex:SetSize(f:GetHeight() - 2, f:GetHeight() - 2)
                    ftex.itemID = itemID
                    ftex.link = link
                    tinsert(icons, ftex)

                    ftex.isIcon = true
                    ftex.owner = mainFrame
                    ftex:SetScript("OnEnter", item_OnEnter)
                    ftex:SetScript("OnLeave", item_OnLeave)
                    ftex:SetScript("OnMouseUp", function(self)
                        mainFrame:GetScript("OnMouseUp")(mainFrame)
                    end)
                    ftex:SetScript("OnMouseDown", function(self)
                        mainFrame:GetScript("OnMouseDown")(mainFrame)
                    end)

                    ftex.tex = ftex:CreateTexture(nil, "BACKGROUND")
                    ftex.tex:SetAllPoints()
                    ftex.tex:SetTexture(Texture)
                    ftex.tex:SetTexCoord(0.1, 0.9, 0.1, 0.9)
                    -- 装备等级
                    local t = ftex:CreateFontString()
                    t:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
                    t:SetPoint("BOTTOM", ftex, "BOTTOM", 0, 1)
                    t:SetText(level)
                    t:SetTextColor(r, g, b)
                    -- 装绑
                    if bindType == 2 then
                        local t = ftex:CreateFontString()
                        t:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
                        t:SetPoint("TOP", ftex, 0, -2)
                        t:SetText(L["装绑"])
                        t:SetTextColor(0, 1, 0)
                    end
                end

                if #items == 1 then
                    -- 装备名称
                    local t = f:CreateFontString()
                    t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                    t:SetPoint("TOPLEFT", icons[1], "TOPRIGHT", 2, -2)
                    t:SetWidth(f:GetWidth() - f:GetHeight() - 10)
                    t:SetText(link:gsub("%[", ""):gsub("%]", ""))
                    t:SetJustifyH("LEFT")
                    t:SetWordWrap(false)
                    local itemNameText = t
                    -- 装备类型
                    local t = f:CreateFontString()
                    t:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
                    t:SetPoint("BOTTOMLEFT", icons[1], "BOTTOMRIGHT", 2, 1)
                    t:SetHeight(12)
                    t:SetWidth(itemNameText:GetWidth())
                    local classText = BG.GetTooltipClassText(items[1].id) or ""
                    if _G[itemEquipLoc] then
                        if classID == 2 then
                            t:SetText(itemSubType .. "  " .. classText)
                        else
                            t:SetText(_G[itemEquipLoc] .. " " .. itemSubType .. "  " .. classText)
                        end
                    else
                        t:SetText(classText)
                    end
                    t:SetJustifyH("LEFT")
                end
            end

            local width = 90
            local textWidth = width + 12
            local dropDownWidth = width + 2

            -- 拍卖版本
            do
                local t = mainFrame:CreateFontString()
                t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                t:SetSize(textWidth, 20)
                t:SetPoint("TOPLEFT", mainFrame.itemFrame, "BOTTOMLEFT", 10, -2)
                t:SetJustifyH("LEFT")
                t:SetWordWrap(false)
                t:SetText(L["|cffFFD100拍卖版本|r"])
                mainFrame.Text1 = t

                local dropDown2 = LibBG:Create_UIDropDownMenu(nil, mainFrame)
                dropDown2:SetScale(0.95)
                dropDown2:SetPoint("TOPLEFT", mainFrame.Text1, "BOTTOMLEFT", -17, 2)
                LibBG:UIDropDownMenu_SetText(dropDown2, gens[BiaoGe.Auction.gen])
                dropDown2.Text:SetJustifyH("LEFT")
                LibBG:UIDropDownMenu_SetWidth(dropDown2, dropDownWidth)
                LibBG:UIDropDownMenu_SetAnchor(dropDown2, 0, 0, "BOTTOM", dropDown2, "TOP")
                mainFrame.dropDown2 = dropDown2
                BG.dropDownToggle(dropDown2)
                LibBG:UIDropDownMenu_Initialize(dropDown2, function(self, level)
                    ClearAllFocus(mainFrame)
                    if IsInRaid(1) then
                        local counts = { [1] = 0, [2] = 0 }
                        for name, ver in pairs(BG.raidAuctionVersion) do
                            name = BG.GSN(name)
                            if BG.raidRosterName[name] then
                                counts[1] = counts[1] + 1
                            end
                        end
                        for name, ver in pairs(BG.raidBiaoGeVersion) do
                            name = BG.GSN(name)
                            if BG.raidRosterName[name] and BG.raidBiaoGeNewVersion[name] then
                                counts[2] = counts[2] + 1
                            end
                        end
                        for gen, name in pairs(gens) do
                            local info = LibBG:UIDropDownMenu_CreateInfo()
                            info.text = format('%s|cff00ff00（%s/%s）|r'
                            , name, counts[gen], GetNumGroupMembers())
                            info.arg1 = gen
                            info.func = function(self, arg1, arg2)
                                BiaoGe.Auction.gen = arg1
                                LibBG:UIDropDownMenu_SetText(dropDown2, gens[BiaoGe.Auction.gen])
                                UpdateFrame()
                            end
                            info.checked = info.arg1 == BiaoGe.Auction.gen
                            if gen == 2 then
                                info.tooltipTitle = L['第二代拍卖']
                                info.tooltipText = L['需要团员的BGLite版本高于v2.0.0，否则团员无法看见拍卖框。']
                                info.tooltipOnButton = true
                            end
                            LibBG:UIDropDownMenu_AddButton(info)
                        end
                    end
                end)
            end

            -- 拍卖模式
            do
                local t = f:CreateFontString()
                t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                t:SetSize(textWidth, 20)
                t:SetJustifyH("LEFT")
                t:SetText(L["|cffFFD100拍卖模式|r"])
                t:SetPoint("LEFT", mainFrame.Text1, "RIGHT", 18, 0)
                mainFrame.Text2 = t

                local dropDown = LibBG:Create_UIDropDownMenu(nil, mainFrame)
                dropDown:SetScale(0.95)
                dropDown:SetPoint("TOPLEFT", mainFrame.Text2, "BOTTOMLEFT", -17, 2)
                LibBG:UIDropDownMenu_SetText(dropDown, mods[BiaoGe.Auction.mod])
                dropDown.Text:SetJustifyH("LEFT")
                LibBG:UIDropDownMenu_SetWidth(dropDown, dropDownWidth)
                LibBG:UIDropDownMenu_SetAnchor(dropDown, 0, 0, "BOTTOM", dropDown, "TOP")
                mainFrame.dropDown = dropDown
                BG.dropDownToggle(dropDown)
                LibBG:UIDropDownMenu_Initialize(dropDown, function(self, level)
                    ClearAllFocus(mainFrame)
                    for mod, name in pairs(mods) do
                        local info = LibBG:UIDropDownMenu_CreateInfo()
                        info.text = name
                        info.arg1 = mod
                        info.func = function(self, arg1, arg2)
                            BiaoGe.Auction.mod = arg1
                            LibBG:UIDropDownMenu_SetText(dropDown, mods[BiaoGe.Auction.mod])
                            UpdateFrame()
                        end
                        info.checked = info.arg1 == BiaoGe.Auction.mod
                        LibBG:UIDropDownMenu_AddButton(info)
                    end
                end)
            end

            -- 拍卖时长、起拍价
            do
                local t = mainFrame:CreateFontString()
                t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                t:SetSize(textWidth, 20)
                t:SetPoint("TOPLEFT", mainFrame.Text1, "BOTTOMLEFT", 0, -24)
                t:SetJustifyH("LEFT")
                t:SetWordWrap(false)
                t:SetText(L["|cffFFD100拍卖时长(秒)"])
                mainFrame.Text3 = t

                local edit = CreateFrame("EditBox", nil, mainFrame, BG.editTemplate)
                edit:SetSize(textWidth, 20)
                edit:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 3, 0)
                edit._type = "duration"
                edit.num = 1
                edit:SetText(BiaoGe.Auction[edit._type])
                edit:SetAutoFocus(false)
                edit:SetNumeric(true)
                edit:SetMaxLetters(3)
                edit:SetScript("OnTextChanged", OnTextChanged)
                edit:SetScript("OnEnterPressed", OnEnterPressed)
                mainFrame.Edit1 = edit

                local t = f:CreateFontString()
                t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                t:SetSize(textWidth, 20)
                t:SetPoint("TOPLEFT", mainFrame.Text3, "BOTTOMLEFT", 0, -20)
                t:SetJustifyH("LEFT")
                t:SetWordWrap(false)
                t:SetText(L["|cffFFD100起拍价|r"])
                mainFrame.Text4 = t

                local edit = CreateFrame("EditBox", nil, mainFrame, BG.editTemplate)
                edit:SetSize(textWidth, 20)
                edit:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 3, 0)
                edit._type = "money"
                edit.num = 2
                edit:SetText(BiaoGe.Auction[edit._type])
                edit:SetAutoFocus(false)
                edit:SetNumeric(true)
                edit:SetMaxLetters(8)
                edit:SetScript("OnTextChanged", OnTextChanged)
                edit:SetScript("OnEnterPressed", OnEnterPressed)
                mainFrame.Edit2 = edit
            end

            -- 重置阈值、拍卖数量
            do
                local t = f:CreateFontString()
                t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                t:SetSize(textWidth, 20)
                t:SetJustifyH("LEFT")
                t:SetText(L["重置阈值(秒)"])
                t:SetPoint("TOPLEFT", mainFrame.Text2, "BOTTOMLEFT", 0, -24)
                mainFrame.Text5 = t
                local edit3 = CreateFrame("EditBox", nil, mainFrame, BG.editTemplate)
                edit3:SetSize(textWidth, 20)
                edit3:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 3, 0)
                edit3._type = "resetThreshold"
                edit3:SetText(BiaoGe.Auction.resetThreshold)
                edit3:SetAutoFocus(false)
                edit3:SetNumeric(true)
                edit3:SetMaxLetters(3)
                edit3:SetScript("OnTextChanged", OnTextChanged)
                edit3:SetScript("OnEnterPressed", OnEnterPressed)
                edit3:SetScript("OnEnter", resetThreshold_OnEnter)
                edit3:SetScript("OnLeave", GameTooltip_Hide)
                mainFrame.Edit3 = edit3

                local t = f:CreateFontString()
                t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                t:SetSize(textWidth, 20)
                t:SetPoint("TOPLEFT", mainFrame.Text5, "BOTTOMLEFT", 0, -20)
                t:SetJustifyH("LEFT")
                t:SetWordWrap(false)
                t:SetText(L["|cffFFD100拍卖数量|r"])
                mainFrame.Text6 = t
                local edit = CreateFrame("EditBox", nil, mainFrame, BG.editTemplate)
                edit:SetSize(textWidth, 20)
                edit:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 3, 0)
                edit._type = "count"
                edit.num = 3
                edit:SetText(1)
                edit:SetAutoFocus(false)
                edit:SetNumeric(true)
                edit:SetMaxLetters(1)
                edit:SetScript("OnEnterPressed", OnEnterPressed)
                edit:SetScript("OnMouseWheel", function(self, delta)
                    local val = tonumber(self:GetText()) or 1
                    val = val + delta
                    if val < 1 then val = 1 end
                    if val > 9 then val = 9 end
                    self:SetText(val)
                end)
                mainFrame.Edit4 = edit
                -- 右侧 +/- 按钮（左右分布）
                local a = .13
                local coord = { a, 1 - a, a, 1 - a }
                local w, h = 18, 18
                local btnDown = CreateFrame("Button", nil, mainFrame)
                btnDown:SetSize(w, h)
                btnDown:SetPoint("RIGHT", edit, "RIGHT", 0, 0)
                btnDown:SetFrameLevel(edit:GetFrameLevel() + 2)
                btnDown:SetNormalTexture("Interface/ChatFrame/UI-ChatIcon-ScrollDown-Up")
                btnDown:GetNormalTexture():SetTexCoord(unpack(coord))
                btnDown:SetPushedTexture("Interface/ChatFrame/UI-ChatIcon-ScrollDown-Down")
                btnDown:GetPushedTexture():SetTexCoord(unpack(coord))
                btnDown:SetDisabledTexture("Interface/ChatFrame/UI-ChatIcon-ScrollDown-Disabled")
                btnDown:GetDisabledTexture():SetTexCoord(unpack(coord))
                btnDown:SetHighlightTexture("Interface/Buttons/UI-Common-MouseHilight")
                btnDown:SetScript("OnClick", function()
                    local val = tonumber(edit:GetText()) or 1
                    if val > 1 then edit:SetText(val - 1) end
                    BG.PlaySound(1)
                end)
                local btnUp = CreateFrame("Button", nil, mainFrame)
                btnUp:SetSize(w, h)
                btnUp:SetPoint("RIGHT", btnDown, "LEFT", 0, 0)
                btnUp:SetFrameLevel(edit:GetFrameLevel() + 2)
                btnUp:SetNormalTexture("Interface/ChatFrame/UI-ChatIcon-ScrollUp-Up")
                btnUp:GetNormalTexture():SetTexCoord(unpack(coord))
                btnUp:SetPushedTexture("Interface/ChatFrame/UI-ChatIcon-ScrollUp-Down")
                btnUp:GetPushedTexture():SetTexCoord(unpack(coord))
                btnUp:SetDisabledTexture("Interface/ChatFrame/UI-ChatIcon-ScrollUp-Disabled")
                btnUp:GetDisabledTexture():SetTexCoord(unpack(coord))
                btnUp:SetHighlightTexture("Interface/Buttons/UI-Common-MouseHilight")
                btnUp:SetScript("OnClick", function()
                    local val = tonumber(edit:GetText()) or 1
                    if val < 9 then edit:SetText(val + 1) end
                    BG.PlaySound(1)
                end)
                if #items > 1 then
                    mainFrame.Edit4:SetEnabled(false)
                    mainFrame.Edit4:SetTextColor(0.5, 0.5, 0.5)
                    mainFrame.Text6:SetTextColor(0.5, 0.5, 0.5)
                    btnUp:Hide()
                    btnDown:Hide()
                end
            end

            -- 开始拍卖
            do
                local bt = BG.CreateButton(mainFrame)
                bt:SetSize(width + 19, 25)
                bt:SetPoint("TOPLEFT", mainFrame, "BOTTOMLEFT", 10, BiaoGe.options["fastMoney"] == 1 and 50 or 30)
                bt:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -10, BiaoGe.options["fastMoney"] == 1 and 25 or 5)
                bt:SetText(L["开始拍卖"])
                bt.items = items
                bt.noSound = noSound
                bt.callback = callback
                mainFrame.bt = bt
                bt:SetScript("OnClick", Start_OnClick)
                bt:SetScript("OnEnter", Start_OnEnter)
                bt:SetScript("OnLeave", GameTooltip_Hide)
                -- if BiaoGe.Auction.mod ~= "roll" and isRightButton and ns.isYes and ABCD and ABCD.auction then
                --     local _duration = tonumber(BiaoGe.Auction.duration)
                --     local duration = _duration and _duration > 0 and _duration
                --     if duration then
                --         local tbl = {}
                --         for _, FB in pairs(BG.FBtable) do
                --             if FB == BG.FB1 then
                --                 tinsert(tbl, 1, FB)
                --             else
                --                 tinsert(tbl, FB)
                --             end
                --         end
                --         local itemID = BG.GetLeiTingItem(items[1].id)
                --         for _, FB in ipairs(tbl) do
                --             local money = ABCD.auction[FB].money[itemID]
                --             if money then
                --                 bt.money = money
                --                 Start_OnClick(bt)
                --                 break
                --             end
                --         end
                --     end
                -- end
            end

            -- 底部文字
            if BiaoGe.options["fastMoney"] == 1 then
                mainFrame.fastMoneyFrame = CreateFrame("Frame", nil, mainFrame)
                local tex = mainFrame.fastMoneyFrame:CreateTexture()
                tex:SetPoint("TOPLEFT", mainFrame, "BOTTOMLEFT", 2, 18)
                tex:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -2, 2)
                tex:SetColorTexture(0.2, 0.2, 0.2, 1)

                local buttons = {}
                local function CreateButton()
                    local money = BiaoGe.Auction.fastMoney[#buttons + 1]
                    local bt = CreateFrame("Button", nil, mainFrame.fastMoneyFrame)
                    bt:SetSize(50, 18)
                    if #buttons == 0 then
                        bt:SetPoint("BOTTOMLEFT", mainFrame, 0, 1)
                    else
                        bt:SetPoint("BOTTOMLEFT", buttons[#buttons], "BOTTOMRIGHT", 0, 0)
                    end
                    if BiaoGe.Auction.fastMoney[#buttons + 1] == "" then
                        bt:Hide()
                    end
                    bt.money = money
                    local t = bt:CreateFontString()
                    t:SetFont(BIAOGE_TEXT_FONT, 10, "OUTLINE")
                    t:SetWidth(bt:GetWidth())
                    t:SetPoint("CENTER")
                    t:SetText(BG.FormatNumber(money, 2))
                    t:SetTextColor(1, 0.82, 0)
                    t:SetWordWrap(false)
                    bt:SetFontString(t)
                    tinsert(buttons, bt)
                    bt:SetScript("OnClick", function(self)
                        mainFrame.Edit2:SetText(self.money)
                        BiaoGe.Auction.money = self.money
                        Start_OnClick(mainFrame.bt)
                    end)
                    bt:SetScript("OnEnter", function(self)
                        t:SetTextColor(1, 1, 1)
                        if t:GetStringWidth() > bt:GetWidth() then
                            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
                            GameTooltip:ClearLines()
                            GameTooltip:AddLine(t:GetText(), 1, 0.82, 0, true)
                            GameTooltip:Show()
                        end
                    end)
                    bt:SetScript("OnLeave", function(self)
                        t:SetTextColor(1, .82, 0)
                        GameTooltip:Hide()
                    end)
                end
                for i = 1, #BiaoGe.Auction.fastMoney do
                    CreateButton()
                end
            else
                mainFrame:SetHeight(mainFrameHeight - 20)
            end

            UpdateFrame()
        end

        -- ALT点击背包生效
        local function func(self, button)
            if not IsAltKeyDown() then return end
            local link = C_Container.GetContainerItemLink(self:GetParent():GetID(), self:GetID())
            BG.StartAuction(link, self, nil, nil, button == "RightButton")
        end
        if BG.IsRetail then
            hooksecurefunc("ContainerFrameItemButton_OnClick", func)
        else
            hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", func)
        end
    end

    -- 插件版本
    do
        BG.guildBiaoGeVersion = {}
        BG.guildClass = {}
        BG.raidBiaoGeVersion = {}
        BG.raidBiaoGeNewVersion = {}
        BG.raidAuctionVersion = {}

        -- 会员插件
        local guild = CreateFrame("Frame", nil, BG.MainFrame)
        do
            guild:SetSize(1, 20)
            guild:SetPoint("BOTTOMLEFT", 10, 2)
            guild:Hide()
            guild.title = L["BGLite版本"] .. "(" .. GUILD .. ")"
            guild.title2 = GUILD .. L["插件：%s"]
            guild.table = BG.guildBiaoGeVersion
            guild.isGuild = true
            guild:SetScript("OnEnter", Guild_OnEnter)
            guild:SetScript("OnLeave", GameTooltip_Hide)
            guild.text = guild:CreateFontString()
            guild.text:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
            guild.text:SetPoint("LEFT")
            guild.text:SetTextColor(RGB(BG.g1))
            BG.ButtonGuildVer = guild
        end

        -- 团员插件
        local addon = CreateFrame("Frame", nil, BG.MainFrame)
        do
            addon:SetSize(1, 20)
            addon:SetPoint("LEFT", BG.ButtonGuildVer, "RIGHT", 0, 0)
            addon:Hide()
            addon.title = L["BGLite版本"] .. "(" .. RAID .. ")"
            addon.title2 = L["插件：%s"]
            addon.table = BG.raidBiaoGeVersion
            addon.isAddon = true
            addon:SetScript("OnEnter", Addon_OnEnter)
            addon:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
                self.isOnEnter = false
            end)
            addon.text = addon:CreateFontString()
            addon.text:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
            addon.text:SetPoint("LEFT")
            addon.text:SetTextColor(RGB(BG.g1))
            BG.ButtonRaidVer = addon
        end

        -- 拍卖WA
        local auction = CreateFrame("Frame", nil, BG.MainFrame)
        do
            auction:SetSize(1, 20)
            auction:SetPoint("LEFT", addon, "RIGHT", 0, 0)
            auction:Hide()
            auction.title = L["自动拍卖版本"]
            auction.title2 = L["拍卖：%s"]
            auction.table = BG.raidAuctionVersion
            auction.isAuciton = true
            auction:SetScript("OnEnter", Addon_OnEnter)
            auction:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
                self.isOnEnter = false
            end)
            -- if not BG.IsRetail then
            --     auction:SetScript("OnMouseUp", function(self)
            --         SendWACode()
            --     end)
            -- end
            auction.text = auction:CreateFontString()
            auction.text:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
            auction.text:SetPoint("LEFT")
            auction.text:SetTextColor(RGB(BG.g1))
            BG.ButtonRaidAuction = auction
        end

        local lastNum = 0
        function BG.CanSend_BiaoGeVer()
            local n
            local canSend = true
            if IsInRaid(1) then
                n = GetNumGroupMembers(1)
                if lastNum >= n then
                    canSend = false
                end
            else
                canSend = false
                n = 0
            end
            lastNum = n
            return canSend
        end

        BG.RegisterEvent("GROUP_ROSTER_UPDATE", function(self, event, ...)
            local canSend = BG.CanSend_BiaoGeVer()
            BG.After(1, function()
                if IsInRaid(1) then
                    if canSend then
                        C_ChatInfo.SendAddonMessage("BiaoGe", "MyVer-" .. BG.ver, "RAID")
                    end
                else
                    UpdateAddonFrame(addon)
                    UpdateAddonFrame(auction)
                end
                if BG.StartAucitonFrame then
                    BG.StartAucitonFrame:UpdateFrame()
                end
                UpdateGuildFrame(guild)
            end)
        end)
        BG.RegisterEvent("GUILD_ROSTER_UPDATE", function(self, event, ...)
            BG.After(1, function()
                for i = 1, GetNumGuildMembers() do
                    local name, rankName, rankIndex, level, classDisplayName, zone,
                    publicNote, officerNote, isOnline, status, class, achievementPoints,
                    achievementRank, isMobile, canSoR, repStanding, guid = GetGuildRosterInfo(i)
                    if name then
                        name = BG.GSN(name)
                        if not isOnline then
                            BG.guildBiaoGeVersion[name] = nil
                            BG.guildClass[name] = nil
                        else
                            BG.guildClass[name] = class
                        end
                    end
                end
                UpdateGuildFrame(guild)
            end)
        end)
        BG.RegisterEvent("CHAT_MSG_SYSTEM", function(self, event, ...) -- 如果团队里有人退出，就删掉
            local msg = ...
            if BG.IsSecret(msg) then return end
            local leave = ERR_RAID_MEMBER_REMOVED_S:gsub("%%s", "(.+)")
            local name = strmatch(msg, leave)
            if name then
                BG.raidBiaoGeVersion[name] = nil
                BG.raidAuctionVersion[name] = nil
                UpdateAddonFrame(addon)
                UpdateAddonFrame(auction)
            end
        end)
        BG.RegisterEvent("CHAT_MSG_ADDON", function(self, event, ...)
            local prefix, msg, distType, sender = ...
            sender = BG.GSN(sender)
            if prefix == "BiaoGe" and distType == "GUILD" then
                if strfind(msg, "MyVer") then
                    local _, version = strsplit("-", msg)
                    BG.guildBiaoGeVersion[sender] = version
                    UpdateGuildFrame(guild)
                end
            elseif prefix == "BiaoGe" and distType == "RAID" then -- 插件版本
                if msg == "VersionCheck" then
                    C_ChatInfo.SendAddonMessage("BiaoGe", "MyVer-" .. BG.ver, "RAID")
                elseif strfind(msg, "MyVer") then
                    local _, version = strsplit("-", msg)
                    BG.raidBiaoGeVersion[sender] = version
                    if BG.GetVerNum(version) >= 20000 then
                        BG.raidBiaoGeNewVersion[sender] = true
                    end
                    UpdateAddonFrame(addon)
                    if BG.StartAucitonFrame then
                        BG.StartAucitonFrame:UpdateFrame()
                    end
                end
            elseif prefix == "BiaoGeAuction" and distType == "RAID" then -- 拍卖版本
                local arg1, version = strsplit(",", msg)
                if arg1 == "MyVer" then
                    BG.raidAuctionVersion[sender] = version
                    UpdateAddonFrame(auction)
                    if sendDone[sender] then
                        sendDone[sender] = nil
                        if not notShowSendingText[sender] and sendingCount[sender] <= 2 then
                            BG.SendSystemMessage(format(BG.STC_g1(L["%s已成功导入拍卖WA。"]), SetClassCFF(sender)))
                        end
                        UpdateOnEnter(BG.ButtonRaidAuction)
                        UpdateOnEnter(BG.StartAucitonFrame)
                    end
                end
            end
        end)
        BG.Init2(function()
            C_Timer.After(3, function()
                if IsInRaid(1) then
                    C_ChatInfo.SendAddonMessage("BiaoGe", "VersionCheck", "RAID")
                    C_ChatInfo.SendAddonMessage("BiaoGeAuction", "VersionCheck", "RAID")
                end
            end)
        end)
    end

    -- 移除屏蔽
    local CheckIgnore
    do
        local link = "|cffFFFF00|Hgarrmission:" .. "BiaoGeIgnore:" .. "|h[" .. L["禁用此功能"] .. "]|h|r"
        local function Send(ignoreName)
            BG.SendSystemMessage((format(L["已把%s从屏蔽名单中移除，防止你看不到对方的拍卖聊天信息。"],
                SetClassCFF(ignoreName)) .. link))
        end
        function CheckIgnore()
            if BiaoGe.options.ignore ~= 1 then return end
            for i = 1, C_FriendList.GetNumIgnores() do
                local ignoreName = C_FriendList.GetIgnoreName(i)
                if UnitInRaid(ignoreName) then
                    C_FriendList.DelIgnore(ignoreName)
                    Send(ignoreName)
                end
            end
        end

        local str = ERR_IGNORE_ADDED_S:gsub("%%s", "(.+)")
        BG.RegisterEvent("CHAT_MSG_SYSTEM", function(self, event, msg)
            if BiaoGe.options.ignore ~= 1 then return end
            if BG.IsSecret(msg) then return end
            local ignoreName = msg:match(str)
            if ignoreName and UnitInRaid(ignoreName) then
                C_FriendList.DelIgnore(ignoreName)
                BG.After(0, function()
                    Send(ignoreName)
                end)
            end
        end)

        hooksecurefunc("SetItemRef", function(link, _, button)
            local arg1, arg2, arg3, arg4 = strsplit(":", link)
            if arg2 == "BiaoGeIgnore" then
                local name = "ignore"
                BiaoGe.options[name] = 0
                BG.options["button" .. name]:SetChecked(false)
                BG.SendSystemMessage(L["已禁用自动移除屏蔽对象功能。"])
            end
        end)
    end

    -- 删除aaa插件
    if IsAddOnLoaded("aaa") then
        BG.After(10, function()
            BG.SendSystemMessage(L["请你删除aaa插件，该插件会破坏系统的通讯功能，导致其他插件功能失效。"])
        end)
    end

    -- 给拍卖WA设置关注和心愿
    local LibCustomGlow = LibStub("LibCustomGlow-1.0")
    local function ShowTooltipGlow(frame)
        local startColor = nil
        LibCustomGlow.PixelGlow_Start(
            frame,      -- 目标帧（必填）
            startColor, -- 颜色 {r,g,b,a}，默认 {0.95,0.95,0.32,1}
            10,         -- 线条数量 N，默认 8
            0.2,        -- 旋转频率（负数反转方向），默认 0.25
            nil,        -- 线条长度（默认随帧大小/线条数自适应）
            2,          -- 线条厚度，默认 2
            0,          -- X 轴偏移（相对边框）
            0,          -- Y 轴偏移（相对边框）
            true,      -- 是否显示线条下方的边框，默认 false
            nil         -- 发光标识（同一帧可加多个发光，用 key 区分）
        )
        BG.After(.5, function()
            frame:HookScript("OnEnter", function(self)
                LibCustomGlow.PixelGlow_Stop(frame)
            end)
            frame.autoFrame:HookScript("OnEnter", function(self)
                LibCustomGlow.PixelGlow_Stop(frame)
            end)
        end)
    end
    -- 已移除 SetBestPriceAuto：它读取第三方付费模块 BGV 的「最佳价格」并自动填入出价框、
    -- 自动点击出价按钮。该能力依赖付费模块，本插件不做付费模块挂载点，整函数删除。
    function BG.HookCreateAuction(f)
        local leiting
        for _, FB in ipairs(BG.GetAllFB()) do
            if BG.GetLeiTingItem(f.itemID, FB) ~= f.itemID then
                leiting = BG.GetLeiTingItem(f.itemID, FB)
                break
            end
        end
        local itemID = leiting or f.itemID
        -- 关注
        local hasGZ, hasHope
        for _, FB in ipairs(BG.GetAllFB()) do
            for b = 1, Maxb[FB] do
                for i = 1, BG.GetMaxi(FB, b) do
                    local zb = BG.Frame[FB]["boss" .. b]["zhuangbei" .. i]
                    if zb and itemID == GetItemID(zb:GetText()) and BiaoGe[FB]["boss" .. b]["guanzhu" .. i] then
                        local itemType = f.itemFrame.itemTypeText
                        itemType:SetText((itemType:GetText() or "") .. BG.STC_b1(L["<关注>"]))
                        hasGZ = true
                        break
                    end
                end
                if hasGZ then break end
            end
            if hasGZ then break end
        end
        -- 心愿
        for _, FB in ipairs(BG.GetAllFB()) do
            for n = 1, HopeMaxn[FB] do
                for b = 1, HopeMaxb[FB] do
                    for i = 1, HopeMaxi do
                        local zb = BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i]
                        if zb and itemID == GetItemID(zb:GetText()) then
                            local itemType = f.itemFrame.itemTypeText
                            itemType:SetText((itemType:GetText() or "") .. (hasGZ and " " or "") .. BG.STC_g1(L["<心愿>"]))
                            hasHope = true
                            break
                        end
                    end
                    if hasHope then break end
                end
                if hasHope then break end
            end
            if hasHope then break end
        end
        local isFold
        if hasGZ or hasHope then
            BG.After(0.5, function()
                f.autoFrame:Show()
            end)
            ShowTooltipGlow(f)
        end
        -- 过滤
        f.filter = nil
        local num = BiaoGe.FilterClassItemDB[RealmId][player].chooseID
        if num then
            local name, link, quality, level, _, _, _, _, EquipLoc, Texture, _, typeID, subclassID, bindType = GetItemInfo(f.itemID)
            if BG.FilterAll(f.itemID, typeID, EquipLoc, subclassID) then
                f.filter = true
                if not (f.player and f.player == BG.playerName) then
                    BGA.aura_env.SetFrameColor(f, 2)
                end
                if not hasGZ and not hasHope and not isFold and bindType ~= 2 and BiaoGe.options.autoAuctionFold == 1 then
                    f.notClick = true
                    f.hide:Click()
                    f.notClick = false
                end
            end
        end

        tinsert(BG.auctionLogFrame.auctioning, f.itemID)
        BG.UpdateAuctioning()
        CheckIgnore()
    end

    -- 被顶价语音提醒
    local tipTime = 10
    function BG.PlayTopPriceSound(f, player)
        if BiaoGe.options.autoAuctionAutoEndTips == 1 and f.remaining and f.player then
            if f.remaining <= tipTime and f.player == BG.playerName
                and player ~= BG.playerName then
                BG.PlaySound("auctionTopPrice")
            end
        end
    end

    -- 拍卖欢呼语
    do
        if BG.IsVanilla then
            BG.autoAuctionHappySay_minMoney = 20000
        elseif BG.IsTBC then
            BG.autoAuctionHappySay_minMoney = 50000
        elseif BG.IsWLK_80 then
            BG.autoAuctionHappySay_minMoney = 100000
        elseif BG.IsTitan then
            BG.autoAuctionHappySay_minMoney = 20000
        elseif BG.IsMOP then
            BG.autoAuctionHappySay_minMoney = 1000000
        elseif BG.IsRetail then
            BG.autoAuctionHappySay_minMoney = 5000000
        else
            BG.autoAuctionHappySay_minMoney = 100000
        end
        if not BG.IsTitan then
            local tbl = {
                [[<%s>这波操作，直接把竞拍场变成了 "金币战场"，敌方全员溃败！]],
                [[天呐！<%s>的金币像 "冰霜新星"一样冻住了所有竞争者！太强了！]],
                [[<%s>出价如 "炎爆术"般炸裂，直接秒杀全场竞拍者！]],
                [[救命！<%s>的金币大军开着 "奥术飞弹"来了，谁顶得住啊！]],
                [[这波出价，堪比 "星辰坠落"！<%s>这是要把装备砸穿地心啊！]],
                [[<%s>一喊价，就像按下了 "群体驱散"，其他出价瞬间消失！]],
                [[别人竞拍靠 "普通攻击"，<%s>竞拍直接 "开大"！这谁受得了！]],
                [[<%s>的金币如 "复活币"般珍贵，这波操作直接让装备 "起死回生"！]],
                [[哇塞！<%s>这波 "闪现"出价，直接把其他玩家甩到外太空！]],
                [[<%s>的金币像 "治疗链"一样疯狂跳，直接把竞拍值抬到天花板！]],
                [[这出价，是要发动 "末日决战"吗？<%s>太强了！]],
                [[<%s>一出手，就像 "圣骑士开无敌"，其他竞拍者完全无法抵抗！]],
                [[救命！<%s>的金币如 "恶魔之怒"般汹涌，直接把竞拍场炸翻！]],
                [[<%s>这波 "影遁"出价，其他玩家根本找不到机会反击！]],
                [[别人出价是 "普通任务"，<%s>出价是 "史诗级成就"！瑞斯拜！]],
                [[<%s>的金币像 "狂暴战"一样疯狂输出，直接把竞拍值打崩！]],
                [[这波操作，堪比 "法师偷取增益"，<%s>直接把装备buff拉满！]],
                [[<%s>一喊价，就像 "猎人开威慑"，其他出价全成了挠痒痒！]],
                [[<%s>的金币如 "盗贼伏击"般突然，直接把竞拍节奏带飞！]],
                [[哇哦！<%s>这波 "牧师渐隐术"出价，其他玩家完全跟不上节奏！]],
                [[这出价，是要发动 "萨满嗜血"吗？<%s>直接让竞拍速度翻倍！]],
                [[<%s>一出手，就像 "术士召唤末日守卫"，其他竞拍者直接吓退！]],
                [[救命！<%s>的金币如 "猎人瞄准射击"般精准，直接命中装备！]],
                [[<%s>这波 "战士冲锋"出价，直接把其他玩家撞出竞拍圈！]],
                [[别人出价是 "小怪巡逻"，<%s>出价是 "BOSS碾压"！太强了！]],
                [[<%s>的金币像 "德鲁伊变熊"一样坚挺，直接把竞拍价稳住！]],
                [[这波操作，堪比 "潜行者偷袭"，<%s>直接把装备偷走啦！]],
                [[<%s>一喊价，就像 "死亡骑士开大军"，其他出价全成了炮灰！]],
                [[<%s>的金币如 "法师暴风雪"般覆盖全场，其他玩家根本无处可逃！]],
                [[哇塞！<%s>这波 "圣骑士制裁"出价，其他竞拍者直接被沉默！]],
                [[这出价，是要发动 "猎人误导"吗？<%s>直接把装备骗到手！]],
                [[<%s>一出手，就像 "萨满开英勇"，其他玩家只能看着干瞪眼！]],
                [[救命！<%s>的金币如 "术士生命虹吸"般疯狂，直接吸干所有竞争者！]],
                [[<%s>这波 "盗贼消失"出价，其他玩家根本反应不过来！]],
                [[别人出价是 "普通攻击"，<%s>出价是 "暴击秒杀"！太狠了！]],
                [[<%s>的金币像 "牧师治疗祷言"一样慷慨，直接把装备价格抬到天际！]],
                [[这波操作，堪比 "法师奥术飞弹连发"，<%s>直接把竞拍值打穿！]],
                [[<%s>一喊价，就像 "战士破甲"，其他玩家的抵抗瞬间瓦解！]],
                [[<%s>的金币如 "德鲁伊回春术"般持续，直接把竞拍热度拉满！]],
                [[哇哦！<%s>这波 "圣骑士奉献"出价，其他竞拍者全被烧死啦！]],
                [[这出价，是要发动 "猎人假死"吗？<%s>直接让其他玩家放弃抵抗！]],
                [[<%s>一出手，就像 "萨满地震术"，其他玩家的出价全被震碎！]],
                [[救命！<%s>的金币如 "术士恐惧术"般可怕，其他玩家直接吓跑！]],
                [[<%s>这波 "盗贼闷棍"出价，其他玩家根本无法反击！]],
                [[别人出价是 "新手村练习"，<%s>出价是 "团本开荒"！太强了！]],
                [[<%s>的金币像 "法师炎爆术"一样高伤害，直接秒杀所有竞争者！]],
                [[这波操作，堪比 "潜行者毁伤"，<%s>直接把装备拆分成碎片！]],
                [[<%s>一喊价，就像 "死亡骑士冰链术"，其他玩家的出价全被冻结！]],
                [[<%s>的金币如 "猎人爆炸射击"般炸裂，直接把竞拍场炸上天！]],
                [[哇塞！<%s>这波 "圣骑士神恩术"出价，其他玩家只能望尘莫及！]],

                [[救命！<%s>这手速和魄力，是吃了“竞拍开挂套餐”吧！太强了！]],
                [[<%s>出价，寸草不生！这波直接把竞拍门槛抬到外太空！]],
                [[家人们快看！大佬<%s>的金币正在组团冲锋，势不可挡！]],
                [[这出价，是要把装备焊在身上的节奏啊！<%s>太狠了！]],
                [[<%s>这波操作，直接让竞拍变成了个人秀场，瑞斯拜！]],
                [[别人出价靠犹豫，<%s>出价靠霸气！膝盖已献上！]],
                [[哇哦！<%s>这一嗓子，整个服务器都在颤抖！]],
                [[竞拍界的“钞能力”天花板出现了！<%s>yyds！]],
                [[<%s>的金币如瀑布般倾泻，这谁顶得住啊！]],
                [[这波出价，直接给竞拍结果盖棺定论！<%s>太会了！]],
                [[救命！<%s>的金币大军已抵达战场，宣告胜利！]],
                [[<%s>一出手，就知有没有！这格局，爱了爱了！]],
                [[别人出价是试水，<%s>出价是海啸！太强了！]],
                [[<%s>这波操作，直接把竞拍玩成了“金币交响乐”！]],
                [[天呐！<%s>的金币正在疯狂上分，无人能敌！]],
                [[<%s>出价，直接“杀疯了”！这装备妥妥是你的！]],
                [[这出价，是要把其他竞拍者“卷”到地心吗？<%s>牛！]],
                [[别人竞拍靠运气，<%s>竞拍靠实力！瑞斯拜！]],
                [[<%s>的金币正在上演“速度与激情”，太刺激了！]],
                [[哇塞！<%s>这气势，直接把竞拍现场变成了“土豪专属区”！]],
                [[救命！<%s>这波操作，直接让竞拍进入“碾压局”！]],
                [[<%s>一喊价，空气都凝固了！这威慑力绝了！]],
                [[别人出价是小打小闹，<%s>出价是惊天动地！]],
                [[<%s>的金币如火箭般发射，这谁能拦得住！]],
                [[这波出价，直接给装备贴上了“<%s>专属”标签！]],
                [[天呐！<%s>的金币正在疯狂刷屏，太壕了！]],
                [[<%s>出价，直接“封神”！这操作太秀了！]],
                [[别人竞拍是过家家，<%s>竞拍是打BOSS！太强了！]],
                [[<%s>的金币正在谱写“竞拍传奇”，太牛了！]],
                [[哇哦！<%s>这一出手，直接把竞拍变成了“降维打击”！]],
                [[救命！<%s>的金币大军已势不可挡，宣告胜利！]],
                [[<%s>一喊价，全场都沸腾了！这魅力谁能抗拒！]],
                [[别人出价是毛毛雨，<%s>出价是倾盆大雨！]],
                [[<%s>的金币正在上演“王者归来”，太霸气了！]],
                [[这波出价，直接把装备“拿捏”得死死的！<%s>牛！]],
                [[天呐！<%s>的金币正在疯狂输出，太猛了！]],
                [[<%s>出价，直接“炸场”！这操作太顶了！]],
                [[别人竞拍是青铜，<%s>竞拍是王者！瑞斯拜！]],
                [[<%s>的金币正在书写“竞拍神话”，太厉害了！]],
                [[哇塞！<%s>这气势，直接把竞拍现场变成了“个人演唱会”！]],
                [[救命！<%s>这波操作，直接让竞拍进入“无敌模式”！]],
                [[<%s>一喊价，世界都安静了！这实力太震撼了！]],
                [[别人出价是小浪花，<%s>出价是惊涛骇浪！]],
                [[<%s>的金币正在发起“总攻”，胜利在望！]],
                [[这波出价，直接给装备插上了“<%s>的翅膀”！]],
                [[天呐！<%s>的金币正在疯狂收割，太绝了！]],
                [[<%s>出价，直接“起飞”！这操作太帅了！]],
                [[别人竞拍是新手村，<%s>竞拍是终极大本营！太强了！]],
                [[<%s>的金币正在创造“竞拍奇迹”，太牛啦！]],
                [[哇哦！<%s>这一出手，直接把竞拍变成了“老板的Show Time”！]],
            }

            BG.RegisterEvent("CHAT_MSG_ADDON", function(self, event, ...)
                if not (BG.IsLeader and BiaoGe.options.autoAuctionHappySay == 1) then return end
                local prefix, msg, distType, sender = ...
                local arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10
                if prefix == "BiaoGeAuction" then
                    arg1, arg2, arg3, arg4, arg5, arg6, arg7 = strsplit(",", msg)
                elseif prefix:match("BiaoGeAuction(%d+)") then
                    arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10 = strsplit("^", msg)
                end
                if not arg1 then return end
                sender = BG.GSN(sender)
                if arg1 == "SendMyMoney" and distType == "RAID" then
                    local auctionID = tonumber(arg2)
                    local money = tonumber(arg3)
                    if money and money >= BG.autoAuctionHappySay_minMoney then
                        for _, f in pairs(_G.BGA.Frames) do
                            if not f.IsEnd and not f.isPaused and f.auctionID == auctionID then
                                if random(10) > 5 then
                                    local text = tbl[random(#tbl)]
                                    if text and sender then
                                        SendChatMessage(format(text, sender), "RAID")
                                    end
                                end
                                return
                            end
                        end
                    end
                end
            end)
        end
    end

    -- 团长拍的装备询问记账
    BG.Init2(function()
        local function HasEmptyGeZi(link, FB)
            for b = 1, BG.Maxb[FB] do
                for i = 1, BG.GetMaxi and BG.GetMaxi(FB, b) or BG.Maxi do
                    local zhuangbei = BG.Frame[FB]["boss" .. b]["zhuangbei" .. i]
                    local maijia = BG.Frame[FB]["boss" .. b]["maijia" .. i]
                    local jine = BG.Frame[FB]["boss" .. b]["jine" .. i]

                    if zhuangbei and GetItemID(zhuangbei:GetText()) == GetItemID(link) and
                        maijia:GetText() == "" and jine:GetText() == "" and
                        not BiaoGe[FB]["boss" .. b]["qiankuan" .. i] then
                        return b, i, zhuangbei, maijia, jine, FB
                    end
                end
            end
        end
        local function OnClick(zhuangbei, maijia, jine, saveQianKuan, FB)
            local b, i, _, _maijia, _jine = HasEmptyGeZi(zhuangbei, FB)
            if b then
                _maijia:SetText(maijia or "")
                _maijia:SetTextColor(GetClassRGB(nil, "player"))
                _jine:SetText(jine)
                BiaoGe[FB]["boss" .. b]["maijia" .. i] = maijia
                BiaoGe[FB]["boss" .. b]["jine" .. i] = jine
                for k, v in pairs(BG.playerClass) do
                    BiaoGe[FB]["boss" .. b][k .. i] = select(v.select, v.func("player"))
                end
                if saveQianKuan then
                    BiaoGe[FB]["boss" .. b]["qiankuan" .. i] = tonumber(jine)
                    BG.Frame[FB]["boss" .. b]["qiankuan" .. i]:Show()
                end
                BG.SendSystemMessage(zhuangbei .. BG.STC_g1(L["记账成功！"]))
            else
                BG.SendSystemMessage(zhuangbei .. BG.STC_r1(L["记账失败！表格里没有匹配到合适的装备！"]))
            end
        end
        local function MoneyIsError(money)
            return money:match("[!@#$%^&*]")
        end

        local frameName = 'BiaoGe_SaveRaidLeaderBuyItem'
        for i = 1, 4 do
            StaticPopupDialogs[frameName .. i] = {
                text = L["你以|cffffff00%s金|r成功竞拍%s，需要记账进表格吗？"],
                button1 = YES,
                button2 = L["记为欠款"],
                button3 = NO,
                OnButton3 = function()
                    StaticPopup_Hide(frameName .. i)
                end,
                selectCallbackByIndex = true,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
        end

        function BG.SaveRLAuction(zhuangbei, maijia, jine, FB)
            if BG.ImMLorLeader() and zhuangbei and maijia and jine and maijia == player then
                for i = 1, 4 do
                    local _, dialog = StaticPopup_Visible(frameName .. i)
                    if not dialog then
                        StaticPopupDialogs[frameName .. i].OnButton1 = function()
                            OnClick(zhuangbei, maijia, jine, nil, FB)
                        end
                        StaticPopupDialogs[frameName .. i].OnButton2 = function()
                            OnClick(zhuangbei, maijia, jine, true, FB)
                        end
                        StaticPopup_Show(frameName .. i, jine, zhuangbei)
                        return
                    end
                end
            end
        end

        -- 已移除对第三方付费模块 BGV 状态字段的清理（该挂载点已整体移除）
    end)

    -- 已移除内嵌的竞拍 WeakAuras 导出字符串（原 22593 字节，单行）及其消费者代码块。
    -- 该字符串是第三方 WeakAuras 作者的导出产物，著作权不属于本插件作者，
    -- 随插件分发缺乏授权依据；且一段不可读的长 blob 出现在公开源码里，观感等同混淆。
    -- 三个消费者（WeakAuras.Import / edit:SetText）原本全部位于长注释块内，
    -- 即「活字面量 + 死消费者」，删除不改变任何运行行为。
end)
