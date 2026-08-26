if BG.IsBlackListPlayer then return end
local _, ns = ...

local L = ns.L

local SetClassCFF = ns.SetClassCFF
local Maxb = ns.Maxb
local AddTexture = ns.AddTexture
local GetItemID = ns.GetItemID


local channel = "BiaoGeReceive"
C_ChatInfo.RegisterAddonMessagePrefix(channel)
for i = 1, BG.addonChannelCount do
    local channelName = channel .. i
    C_ChatInfo.RegisterAddonMessagePrefix(channelName)
end

local _, class = UnitClass("player")
local r, g, b, cff = GetClassColor(class)

function BG.ReceiveUI()
    local DB = {}
    local CreateButton

    -- UI
    do
        -- 主界面
        BG.ReceiveMainFrame = CreateFrame("Frame", "BG.ReceiveFrame", UIParent, "BackdropTemplate")
        do
            BG.ReceiveMainFrame:SetBackdrop({
                bgFile = "Interface/ChatFrame/ChatFrameBackground",
                edgeFile = "Interface/ChatFrame/ChatFrameBackground",
                edgeSize = 2
            })
            BG.ReceiveMainFrame:SetBackdropColor(0, 0, 0, 0.9)
            BG.ReceiveMainFrame:SetBackdropBorderColor(r, g, b)
            BG.ReceiveMainFrame:SetPoint("CENTER")
            BG.ReceiveMainFrame:SetFrameLevel(100)
            BG.ReceiveMainFrame:SetMovable(true)
            BG.ReceiveMainFrame:SetToplevel(true)
            BG.ReceiveMainFrame:SetSize(300, 500)
            BG.ReceiveMainFrame.FB = BG.FB1
            BG.ReceiveMainFrame:SetScript("OnMouseUp", function(self)
                self:StopMovingOrSizing()
            end)
            BG.ReceiveMainFrame:SetScript("OnMouseDown", function(self)
                BG.FrameHide(0)
                self:StartMoving()
            end)
            BG.ReceiveMainFrame:SetScript("OnHide", function(self)
                StaticPopup_Hide("BiaoGe_YingYongReceiveBiaoGe")
            end)
            BG.ReceiveMainFrame:SetScript("OnShow", function(self)
                local FB = self.FB
                BG.ReceiveMainFrame:SetWidth(BG.FBWidth[FB])
                BG.ReceiveMainFrame:SetHeight(BG.FBHeight[FB] - 20)
                BG.ReceiveAuctionLogFrame:SetHeight(BG.ReceiveMainFrame:GetHeight())
                BG.ReceiveAuctionLogFrame.notText:SetShown(not next(BG.ReceiveAuctionLogFrame.buttons))
            end)
            tinsert(UISpecialFrames, "BG.ReceiveFrame")

            BG.CreateCloseButton(BG.ReceiveMainFrame)
            BG.ReceiveMainFrame.CloseButton:SetSize(40, 40)

            local TitleText = BG.ReceiveMainFrame:CreateFontString()
            TitleText:SetPoint("TOP", BG.ReceiveMainFrame, "TOP", 0, -10)
            TitleText:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
            BG.ReceiveMainFrameTitle = TitleText

            local l = BG.ReceiveMainFrame:CreateLine()
            l:SetColorTexture(r, g, b)
            l:SetStartPoint("BOTTOMLEFT", TitleText, -20, -2)
            l:SetEndPoint("BOTTOMRIGHT", TitleText, 20, -2)
            l:SetThickness(1.5)
        end

        -- 拍卖记录
        do
            BG.ReceiveAuctionLogFrame = CreateFrame("Frame", nil, BG.ReceiveMainFrame, "BackdropTemplate")
            do
                BG.ReceiveAuctionLogFrame:SetBackdrop(BG.ReceiveMainFrame:GetBackdrop())
                BG.ReceiveAuctionLogFrame:SetBackdropColor(BG.ReceiveMainFrame:GetBackdropColor())
                BG.ReceiveAuctionLogFrame:SetBackdropBorderColor(r, g, b)
                BG.ReceiveAuctionLogFrame:SetSize(220, BG.ReceiveMainFrame:GetHeight())
                BG.ReceiveAuctionLogFrame:SetPoint("TOPRIGHT", BG.ReceiveMainFrame, "TOPLEFT", 1, 0)
                BG.ReceiveAuctionLogFrame:EnableMouse(true)
                BG.ReceiveAuctionLogFrame.buttons = {}
                BG.ReceiveAuctionLogFrame:SetScript("OnMouseUp", function(self)
                    BG.ReceiveMainFrame:GetScript("OnMouseUp")(BG.ReceiveMainFrame)
                end)
                BG.ReceiveAuctionLogFrame:SetScript("OnMouseDown", function(self)
                    BG.ReceiveMainFrame:GetScript("OnMouseDown")(BG.ReceiveMainFrame)
                end)

                local t = BG.ReceiveAuctionLogFrame:CreateFontString()
                t:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
                t:SetPoint("TOP", BG.ReceiveAuctionLogFrame, "TOP", 0, -8)
                t:SetText(L["拍卖记录"])
            end

            -- 滚动框
            do
                local frame = CreateFrame("Frame", nil, BG.ReceiveAuctionLogFrame, "BackdropTemplate")
                frame:SetBackdrop({
                    edgeFile = "Interface/ChatFrame/ChatFrameBackground",
                    edgeSize = 1,
                })
                frame:SetBackdropBorderColor(.5, .5, .5, .5)
                frame:SetBackdropColor(0, 0, 0, 0.8)
                frame:SetPoint("TOPLEFT", 5, -30)
                frame:SetPoint("BOTTOMRIGHT", -5, 5)
                frame:EnableMouse(true)
                BG.ReceiveAuctionLogFrame.frame = frame

                local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
                scroll:SetPoint("TOPLEFT", 5, -5)
                scroll:SetPoint("BOTTOMRIGHT", -26, 5)
                scroll.ScrollBar.scrollStep = BG.scrollStep
                frame.scroll = scroll
                BG.CreateSrollBarBackdrop(scroll.ScrollBar)
                BG.HookScrollBarShowOrHide(scroll)
                BG.ReceiveAuctionLogFrame.scroll = scroll

                local child = CreateFrame("Frame", nil, scroll)
                child:SetAllPoints()
                child:SetWidth(scroll:GetWidth())
                child:SetHeight(scroll:GetHeight())
                scroll:SetScrollChild(child)
                BG.ReceiveAuctionLogFrame.child = child

                local _f = CreateFrame("Frame", nil, frame)
                _f:SetSize(1, 1)
                _f:SetPoint("TOPRIGHT", 0, 1)
                frame.tooltip = _f

                local t = child:CreateFontString()
                t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                t:SetPoint("TOP", 0, 0)
                t:SetTextColor(1, 0, 0)
                t:SetText(L["没有自动拍卖记录。"])
                t:SetWidth(scroll:GetWidth())
                t:Hide()
                BG.ReceiveAuctionLogFrame.notText = t
            end

            -- 列表内容
            local buttons = BG.ReceiveAuctionLogFrame.buttons
            function CreateButton(num, v)
                local bts = {}
                local width = BG.ReceiveAuctionLogFrame.child:GetWidth()
                local link = v.zhuangbei
                local itemID = GetItemID(link)
                local icon, typeID = select(5, GetItemInfoInstant(link))
                local r, g, b = GetItemQualityColor(v.quality)
                bts.link = link
                bts.itemID = itemID
                bts.num = num
                -- 主框架
                do
                    local f = CreateFrame("Frame", nil, BG.ReceiveAuctionLogFrame.child, "BackdropTemplate")
                    f:SetSize(width, 32)
                    if not next(buttons) then
                        f:SetPoint("TOPLEFT")
                    else
                        f:SetPoint("TOPLEFT", buttons[#buttons].frame, "BOTTOMLEFT", 0, 0)
                    end
                    f.link = link
                    bts.frame = f
                    f:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(BG.ReceiveAuctionLogFrame.frame.tooltip, "ANCHOR_BOTTOMRIGHT", 0, 0)
                        GameTooltip:ClearLines()
                        local itemID = GetItemInfoInstant(link)
                        if itemID then
                            GameTooltip:SetHyperlink(BG.SetSpecIDToLink(link))
                        end
                        bts.ds:Show()
                    end)
                    f:SetScript("OnLeave", function(self)
                        GameTooltip:Hide()
                        bts.ds:Hide()
                    end)

                    local tex = bts.frame:CreateTexture(nil, "BACKGROUND")
                    tex:SetAllPoints()
                    if num % 2 == 0 then
                        tex:SetColorTexture(.5, .5, .5, .15)
                    else
                        tex:SetColorTexture(0, 0, 0, .25)
                    end
                    bts.tex = tex

                    local tex = bts.frame:CreateTexture()
                    tex:SetAllPoints()
                    tex:SetColorTexture(.5, .5, .5, .5)
                    tex:Hide()
                    bts.ds = tex

                    tinsert(buttons, bts)
                end
                -- 图标和装等
                do
                    local f = CreateFrame("Frame", nil, bts.frame, "BackdropTemplate")
                    f:SetBackdrop({
                        edgeFile = "Interface/ChatFrame/ChatFrameBackground",
                        edgeSize = 1,
                    })
                    f:SetBackdropBorderColor(r, g, b)
                    f:SetSize(bts.frame:GetHeight() - 2, bts.frame:GetHeight() - 2)
                    f:SetPoint("LEFT")
                    bts.iconFrame = f
                    local tex = f:CreateTexture(nil, "BACKGROUND")
                    tex:SetAllPoints()
                    tex:SetTexture(icon)
                    tex:SetTexCoord(unpack(BG.iconTexCoord))
                    bts.icon = tex
                    f.level = f:CreateFontString()
                    f.level:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
                    f.level:SetPoint("BOTTOM", bts.icon, 0, 1)
                    f.level:SetText((typeID == 2 or typeID == 4) and v.itemlevel or nil)
                    f.level:SetTextColor(r, g, b)
                    if v.bindType == 2 then
                        local text = bts.iconFrame:CreateFontString()
                        text:SetFont(BIAOGE_TEXT_FONT, 10, "OUTLINE")
                        text:SetPoint("TOP", bts.iconFrame, 0, -1)
                        text:SetText(L["装绑"])
                        text:SetTextColor(0, 1, 0)
                    end
                end
                -- 装备
                do
                    local text = bts.frame:CreateFontString()
                    text:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
                    text:SetWidth(width - bts.icon:GetWidth())
                    text:SetPoint("TOPLEFT", bts.icon, "TOPRIGHT", 1, 0)
                    text:SetText(link:gsub("%[", ""):gsub("%]", ""))
                    text:SetJustifyH("LEFT")
                    text:SetWordWrap(false)
                    bts.item = text
                end
                -- 买家和金额
                do
                    local text = bts.frame:CreateFontString()
                    text:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
                    text:SetPoint("BOTTOMLEFT", bts.icon, "BOTTOMRIGHT", 1, 0)
                    text:SetWidth(width - bts.icon:GetWidth())
                    text.LiuPaiText = BG.STC_r1(L["<流拍>"])
                    if v.type == 1 then
                        local color = "FFFFFF"
                        if v.color then
                            local r, g, b = unpack(v.color)
                            color = ns.RGB_16(nil, r, g, b)
                        end
                        text:SetText(format("%s |cff%s%s|r", BG.FormatNumber(v.jine, 2), color, v.maijia))
                    else
                        text:SetText(text.LiuPaiText)
                    end
                    text:SetJustifyH("LEFT")
                    text:SetWordWrap(false)
                    bts.money = text
                end
            end
        end

        -- 使用该表格
        do
            local bt = BG.CreateButton(BG.ReceiveMainFrame)
            bt:SetSize(120, 25)
            bt:SetPoint("BOTTOMRIGHT", BG.ReceiveMainFrame, "BOTTOM", -10, 20)
            bt:SetText(L["使用该表格"])
            bt:SetScript("OnClick", function(self)
                BG.PlaySound(1)
                if not StaticPopupDialogs["BiaoGe_YingYongReceiveBiaoGe"] then
                    StaticPopupDialogs["BiaoGe_YingYongReceiveBiaoGe"] = {
                        text = L["确定使用该表格？\n你的当前表格将被其|cffff0000替换|r"],
                        button1 = L["是"],
                        button2 = L["否"],
                        OnCancel = function()
                        end,
                        timeout = 0,
                        whileDead = true,
                        hideOnEscape = true,
                        showAlert = true,
                    }
                end
                StaticPopupDialogs["BiaoGe_YingYongReceiveBiaoGe"].OnAccept = function()
                    local FB = DB.FB
                    BG.ClearBiaoGe("biaoge", FB)
                    BG.PairFBItem(function(item, buyer, money, b, i)
                        item:SetText(DB["boss" .. b]["zhuangbei" .. i] or "")
                        buyer:SetText(DB["boss" .. b]["maijia" .. i] or "")
                        buyer:SetCursorPosition(0)
                        if DB["boss" .. b]["color" .. i] then
                            buyer:SetTextColor(unpack(DB["boss" .. b]["color" .. i]))
                        end
                        money:SetText(DB["boss" .. b]["jine" .. i] or "")
                        local qiankuan = DB["boss" .. b]["qiankuan" .. i]
                        if qiankuan then
                            BiaoGe[FB]["boss" .. b]["qiankuan" .. i] = qiankuan
                            BG.Frame[FB]["boss" .. b]["qiankuan" .. i]:Show()
                        end
                    end, nil, true, FB)
                    if next(DB.auctionLog) then
                        BiaoGe[FB].auctionLog = {}
                        for k, v in pairs(DB.auctionLog) do
                            BiaoGe[FB].auctionLog[k] = BG.Copy(v)
                        end
                    end
                    BG.ReceiveMainFrame:Hide()
                    BG.MainFrame:Show()
                    BG.ClickTabButton(BG.FBMainFrameTabNum)
                    BG.ClickFBbutton(FB)
                    BG.PlaySound(2)
                end
                StaticPopup_Show("BiaoGe_YingYongReceiveBiaoGe")
            end)

        end

        -- 二级
        for i, FB in ipairs(BG.FBtable) do
            BG["ReceiveFrame" .. FB] = CreateFrame("Frame", "BG.ReceiveFrame" .. FB, BG.ReceiveMainFrame)
            BG["ReceiveFrame" .. FB]:Hide()
        end
    end

    -- 把分享表格文字转换为链接
    do
        local function ChangSendLink(self, event, msg, ...)
            local ver
            if strfind(msg, "^%[BiaoGe:.*%]$") then
                ver = 1
            elseif strfind(msg, "^%[!BiaoGe:.*%]$") then
                ver = 2
            end
            if not ver then return end
            msg = strtrim(msg, "[]")
            local _, text = strsplit(":", msg, 2)
            if text then
                local newmsg = "|cff00BFFF|Hgarrmission:" .. msg .. "|h[" .. text .. "]|h|r"
                if ver == 1 then
                    newmsg = newmsg .. L["|cffff0000（该链接为旧版本表格，已失效）"]
                end
                return false, newmsg, ...
            end
        end

        ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", ChangSendLink)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_YELL", ChangSendLink)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", ChangSendLink)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_OFFICER", ChangSendLink)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY", ChangSendLink)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY_LEADER", ChangSendLink)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID", ChangSendLink)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID_LEADER", ChangSendLink)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", ChangSendLink)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", ChangSendLink)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", ChangSendLink)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER", ChangSendLink)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER_INFORM", ChangSendLink)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_INSTANCE_CHAT", ChangSendLink)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_INSTANCE_CHAT_LEADER", ChangSendLink)
    end

    local cd = {}
    hooksecurefunc("SetItemRef", function(link)
        local _, prefix, text = strsplit(":", link, 3)
        if not (prefix == "!BiaoGe" and text) then return end
        local player, server, BiaoGeType, FB, title = strsplit("-", text)
        if BG.ValueInTable(BG.FBtable, FB) then
            if IsShiftKeyDown() then
                local msg = format("[%s:%s]", prefix, text)
                BG.InsertLink(msg)
            else
                if BG.SetCD(cd, 5) then
                    UIErrorsFrame:AddMessage(L["请求CD中..."], 1, 0, 0)
                    return
                end
                BG.ResetReceiveBiaoGe(FB)
                if not title then
                    title = ""
                end
                text = BiaoGeType .. "-" .. FB .. "-" .. title
                local fullName = player .. "-" .. server
                ChatThrottleLib:SendAddonMessage("NORMAL", channel, text, "WHISPER", fullName)
                BG.SendSystemMessage(format(L["已向%s发送请求%s。"], SetClassCFF(fullName), ""))
            end
        end
    end)

    -- 发送和接收表格数据
    -- 1级分隔：^^ 基本信息 表格内容 拍卖记录
    -- 2级分割：&&
    -- 3级分割：¦
    local receiveStart = {}
    local receiveCodes = {}
    local receiveStart2 = {}
    local receiveCodes2 = {}
    function BG.ResetReceiveBiaoGe(FB)
        BG.ReceiveMainFrame:Hide()
        wipe(DB)
        DB.auctionLog = {}
        for b = 1, Maxb[FB] + 2 do
            DB["boss" .. b] = {}
            for i = 1, BG.GetMaxi(FB, b) do
                if BG.ReceiveFrame[FB]["boss" .. b]["zhuangbei" .. i] then
                    BG.ReceiveFrame[FB]["boss" .. b]["zhuangbei" .. i]:SetText("")
                    BG.ReceiveFrame[FB]["boss" .. b]["maijia" .. i]:SetText("")
                    BG.ReceiveFrame[FB]["boss" .. b]["maijia" .. i]:SetTextColor(1, 1, 1)
                    BG.ReceiveFrame[FB]["boss" .. b]["jine" .. i]:SetText("")
                    BG.ReceiveFrame[FB]["boss" .. b]["qiankuan" .. i]:Hide()

                    DB["boss" .. b]["zhuangbei" .. i] = ""
                    DB["boss" .. b]["maijia" .. i] = ""
                    DB["boss" .. b]["color" .. i] = { 1, 1, 1 }
                    DB["boss" .. b]["jine" .. i] = ""
                    DB["boss" .. b]["qiankuan" .. i] = nil
                end
            end
        end
        for i = #BG.ReceiveAuctionLogFrame.buttons, 1, -1 do
            BG.ReceiveAuctionLogFrame.buttons[i].frame:Hide()
            tremove(BG.ReceiveAuctionLogFrame.buttons, i)
        end
        BG.ReceiveAuctionLogFrame.notText:Hide()
    end

    local function GetColorStr(tbl)
        local c1, c2, c3 = "", "", ""
        if type(tbl) == "table" then
            c1, c2, c3 = unpack(tbl)
            c1 = format("%.2f", c1)
            c2 = format("%.2f", c2)
            c3 = format("%.2f", c3)
        end
        return c1, c2, c3
    end
    local function BuildCode(db, FB, DT, title)
        if not (FB and DT and title) then return end
        local str = format("%s&&%s&&%s^^", FB, DT, title)
        local FBstr = ""
        for b = 1, Maxb[FB] + 2 do
            for i = 1, BG.GetMaxi(FB, b) do
                local item = db["boss" .. b]["zhuangbei" .. i] or ""
                local buyer = db["boss" .. b]["maijia" .. i] or ""
                local money = db["boss" .. b]["jine" .. i] or ""
                local qk = db["boss" .. b]["qiankuan" .. i] or ""
                local c1, c2, c3 = GetColorStr(db["boss" .. b]["color" .. i])
                if item ~= "" or buyer ~= "" or money ~= "" or qk ~= "" then
                    FBstr = FBstr .. format("%s¦%s¦%s¦%s¦%s¦%s¦%s¦%s¦%s&&",
                        b, i, item, buyer, money,
                        qk, c1, c2, c3)
                end
            end
        end
        str = str .. FBstr .. "^^"
        local logStr = ""
        if db.auctionLog then
            for i, log in ipairs(db.auctionLog) do
                local c1, c2, c3 = GetColorStr(log.color)
                logStr = logStr .. format("%s¦%s¦%s¦%s¦%s¦%s¦%s¦%s¦%s¦%s&&",
                    log.type or "",
                    log.zhuangbei or "",
                    log.itemlevel or "",
                    log.quality or "",
                    log.bindType or "",
                    log.maijia or "",
                    log.jine or "",
                    c1, c2, c3)
            end
        end
        str = str .. logStr .. "^^"
        str = C_EncodingUtil.CompressString(str)
        return ns.Encode(str)
    end
    local function ReceiveFinish(sender, codes)
        local code = table.concat(codes)
        code = code:match("^!BIAOGE!(.+)!END!$")
        if not code then return end
        local str
        if ns.IsBase64(code) then
            str = C_EncodingUtil.DecompressString(ns.Decode(code))
        else
            return
        end
        local info, biaoge, log = BG.Split("^^", str)
        local FB, DT, title = BG.Split("&&", info)
        DT = tonumber(DT)
        if FB and DT and title then
            BG.CreateFBUI(FB, "Receive")
            DB.FB = FB
            DB.DT = DT
            DB.title = title
            for _, bossStr in ipairs({ BG.Split("&&", biaoge) }) do
                if bossStr and bossStr ~= "" then
                    local b, i, item, buyer, money,
                    qk, c1, c2, c3 = BG.Split("¦", bossStr)
                    b = tonumber(b)
                    i = tonumber(i)
                    qk = tonumber(qk)
                    c1 = tonumber(c1)
                    c2 = tonumber(c2)
                    c3 = tonumber(c3)
                    if b and i and DB["boss" .. b] then
                        DB["boss" .. b]["zhuangbei" .. i] = item
                        DB["boss" .. b]["maijia" .. i] = buyer
                        DB["boss" .. b]["jine" .. i] = money
                        DB["boss" .. b]["qiankuan" .. i] = qk
                        if c1 and c2 and c3 then
                            DB["boss" .. b]["color" .. i] = { c1, c2, c3 }
                        end
                    end
                end
            end
            for _, bossStr in ipairs({ BG.Split("&&", log) }) do
                if bossStr and bossStr ~= "" then
                    local type, zhuangbei, itemlevel, quality, bindType,
                    maijia, jine, c1, c2, c3 = BG.Split("¦", bossStr)
                    type = tonumber(type)
                    itemlevel = tonumber(itemlevel)
                    quality = tonumber(quality)
                    bindType = tonumber(bindType)
                    c1 = tonumber(c1)
                    c2 = tonumber(c2)
                    c3 = tonumber(c3)
                    if type and zhuangbei and itemlevel and quality and bindType and maijia and jine and class then
                        local color = { 1, 1, 1 }
                        if c1 and c2 and c3 then
                            color = { c1, c2, c3 }
                        end
                        tinsert(DB.auctionLog, {
                            type = type,
                            zhuangbei = zhuangbei,
                            itemlevel = itemlevel,
                            quality = quality,
                            bindType = bindType,
                            maijia = maijia,
                            jine = jine,
                            color = color,
                        })
                    end
                end
            end

            for b = 1, Maxb[FB] + 2 do
                for i = 1, BG.GetMaxi(FB, b) do
                    if BG.ReceiveFrame[FB]["boss" .. b]["zhuangbei" .. i] then
                        BG.ReceiveFrame[FB]["boss" .. b]["zhuangbei" .. i]:SetText(DB["boss" .. b]["zhuangbei" .. i] or "")
                        BG.ReceiveFrame[FB]["boss" .. b]["maijia" .. i]:SetText(DB["boss" .. b]["maijia" .. i] or "")
                        BG.ReceiveFrame[FB]["boss" .. b]["maijia" .. i]:SetCursorPosition(0)
                        if DB["boss" .. b]["color" .. i] then
                            BG.ReceiveFrame[FB]["boss" .. b]["maijia" .. i]:SetTextColor(unpack(DB["boss" .. b]["color" .. i]))
                        end
                        BG.ReceiveFrame[FB]["boss" .. b]["jine" .. i]:SetText(DB["boss" .. b]["jine" .. i] or "")
                        local qiankuan = DB["boss" .. b]["qiankuan" .. i]
                        if qiankuan then
                            BG.ReceiveFrame[FB]["boss" .. b]["qiankuan" .. i]:Show()
                            BG.ReceiveFrame[FB]["boss" .. b]["qiankuan" .. i].qiankuan = qiankuan
                        end
                    end
                end
            end
            for i, log in ipairs(DB.auctionLog) do
                CreateButton(i, log)
            end

            BG.MainFrame:Hide()
            BG.ReceiveMainFrame.FB = FB
            BG.ReceiveMainFrame:Show()

            for i, FB in ipairs(BG.FBtable) do
                BG["ReceiveFrame" .. FB]:Hide()
            end
            BG["ReceiveFrame" .. FB]:Show()

            BG.ReceiveMainFrameTitle:SetText(title)
            BG.SendSystemMessage(format(L["|cff00ff00已成功接收%s的表格。"], SetClassCFF(sender)))
        end
    end

    -- 接收数据
    BG.RegisterEvent("CHAT_MSG_ADDON", function(self, event, ...)
        local prefix, msg, distType, sender = ...
        if distType == "WHISPER" then
            if prefix == channel then
                if msg:match("^!BIAOGE!") then
                    receiveStart[sender] = true
                    wipe(receiveCodes)
                end
                if receiveStart[sender] then
                    tinsert(receiveCodes, msg)
                    if msg:match("!END!$") then
                        receiveStart[sender] = nil
                        ReceiveFinish(sender, receiveCodes)
                    end
                end
            elseif prefix:match(channel .. '(%d+)') then
                if msg:match("^!BIAOGE!") then
                    receiveStart2[sender] = true
                    wipe(receiveCodes2)
                end
                if receiveStart2[sender] then
                    tinsert(receiveCodes2, msg)
                    if msg:match("!END!$") then
                        ReceiveFinish(sender, receiveCodes2)
                        BG.After(2, function()
                            receiveStart2[sender] = nil
                            receiveStart[sender] = nil
                        end)
                    end
                end
                receiveStart[sender] = nil
            end
        end
    end)
end
