return function(test)
    -- Loads the real AuctionWA.lua and AuctionWAEvent.lua modules and drives the
    -- actual CancelAuction event path (BGA.Event's CHAT_MSG_ADDON handler) rather
    -- than source-searching. Covers authorization, exactly-once ledger callback,
    -- matching only the targeted auctionID, immediate countdown stop, and the
    -- bounded 15-second release.
    local watchedGlobals = {
        "BG", "C_Timer", "C_ChatInfo", "SOUNDKIT", "CreateFont", "CreateFrame",
        "BIAOGE_TEXT_FONT", "GetRealmName", "GetTime", "GetTimePreciseSec",
        "GetUnitName", "IsInRaid", "BiaoGe", "Locale", "strlen", "format",
        "strsplit", "tinsert", "tremove", "BGA", "UIParent", "SendChatMessage",
    }
    local originalValues = {}
    for _, name in ipairs(watchedGlobals) do
        originalValues[name] = rawget(_G, name)
    end
    local function setGlobal(name, value)
        rawset(_G, name, value)
    end

    local ok, err = pcall(function()
        local nowValue = 1000
        local afters = {}
        local sentChat = {}
        local auctionEndCalls = {}

        local function makeFrame()
            local frame = {
                points = {}, scripts = {}, children = {},
                text = "", shown = true, enabled = true,
                width = 0, height = 0, min = 0, max = 1000, value = 0, alpha = 1,
            }
            function frame:SetPoint(point, relative, relativePoint) end
            function frame:SetAllPoints() end
            function frame:ClearAllPoints() self.points = {} end
            function frame:SetSize(width, height) self.width, self.height = width, height end
            function frame:SetWidth(width) self.width = width end
            function frame:SetHeight(height) self.height = height end
            function frame:GetWidth() return self.width end
            function frame:GetHeight() return self.height end
            function frame:SetScript(name, handler) self.scripts[name] = handler end
            function frame:GetScript(name) return self.scripts[name] end
            function frame:SetText(value) self.text = value end
            function frame:GetText() return self.text end
            function frame:SetTextColor() end
            function frame:SetFont() end
            function frame:SetJustifyH() end
            function frame:SetJustifyV() end
            function frame:SetWordWrap() end
            function frame:SetColorTexture() end
            function frame:SetTexture() end
            function frame:SetTexCoord() end
            function frame:SetVertexColor() end
            function frame:SetShown(value) self.shown = value and true or false end
            function frame:Show() self.shown = true end
            function frame:Hide() self.shown = false end
            function frame:IsShown() return self.shown end
            function frame:IsVisible() return self.shown end
            function frame:Enable() self.enabled = true end
            function frame:Disable() self.enabled = false end
            function frame:IsEnabled() return self.enabled end
            function frame:EnableMouse() end
            function frame:SetFrameLevel() end
            function frame:SetFrameStrata() end
            function frame:SetClampedToScreen() end
            function frame:SetToplevel() end
            function frame:SetMovable() end
            function frame:SetScale() end
            function frame:RegisterForClicks() end
            function frame:RegisterEvent() end
            function frame:UnregisterEvent() end
            function frame:SetNormalFontObject() end
            function frame:SetHighlightFontObject() end
            function frame:SetDisabledFontObject() end
            function frame:GetFontString()
                if not self.fontString then
                    self.fontString = makeFrame()
                    self.fontString.width = 60
                end
                return self.fontString
            end
            function frame:SetAlpha(value) self.alpha = value end
            function frame:GetAlpha() return self.alpha end
            function frame:SetBackdrop() end
            function frame:SetBackdropColor() end
            function frame:SetBackdropBorderColor() end
            function frame:SetValue(value) self.value = value end
            function frame:GetMinMaxValues() return self.min, self.max end
            function frame:SetMinMaxValues(min, max) self.min, self.max = min, max end
            function frame:SetStatusBarColor() end
            function frame:StopMovingOrSizing() end
            function frame:StartMoving() end
            function frame:SetCursor() end
            function frame:GetCenter() return 0 end
            function frame:GetTop() return 0 end
            function frame:GetBottom() return 0 end
            function frame:GetRight() return 0 end
            function frame:GetLeft() return 0 end
            function frame:GetPoint() return "TOP" end
            function frame:SetHighlightTexture() end
            function frame:SetHitRectInsets() end
            function frame:CreateFontString()
                local label = makeFrame()
                self.children[#self.children + 1] = label
                return label
            end
            function frame:CreateTexture()
                local texture = makeFrame()
                self.children[#self.children + 1] = texture
                return texture
            end
            return frame
        end

        BG = {
            BGNext = { AuctionSender = {
                isController = function(sender)
                    return sender == "主拾取者"
                end,
            } },
            Init = function(callback) callback() end,
            AuctionWAEnd = function(...) auctionEndCalls[#auctionEndCalls + 1] = { ... } end,
        }
        setGlobal("C_Timer", { After = function(delay, callback)
            afters[#afters + 1] = { delay = delay, callback = callback }
        end })
        setGlobal("C_ChatInfo", { RegisterAddonMessagePrefix = function() end, SendAddonMessage = function() end })
        setGlobal("SOUNDKIT", { GS_TITLE_OPTION_OK = 1 })
        setGlobal("CreateFont", function() return makeFrame() end)
        setGlobal("CreateFrame", function() return makeFrame() end)
        setGlobal("BIAOGE_TEXT_FONT", "Fonts\\FRIZQT__.TTF")
        setGlobal("GetRealmName", function() return "MyRealm" end)
        setGlobal("GetTime", function() return nowValue end)
        setGlobal("GetTimePreciseSec", nil)
        setGlobal("GetUnitName", function(unit)
            if unit == "player" then return "玩家甲" end
        end)
        setGlobal("IsInRaid", function() return false end)
        setGlobal("BiaoGe", { options = {} })
        setGlobal("Locale", "zhCN")
        setGlobal("strlen", string.len)
        setGlobal("format", string.format)
        setGlobal("strsplit", function(delim, subject, maxPieces)
            maxPieces = maxPieces or 0
            subject = subject or ""
            delim = delim or ","
            local parts = {}
            local startIdx = 1
            local idx = 1
            while true do
                if maxPieces > 0 and idx >= maxPieces then break end
                local pos = string.find(subject, delim, startIdx, true)
                if not pos then break end
                parts[idx] = string.sub(subject, startIdx, pos - 1)
                idx = idx + 1
                startIdx = pos + #delim
            end
            parts[idx] = string.sub(subject, startIdx)
            return unpack(parts, 1, maxPieces > 0 and maxPieces or idx)
        end)
        setGlobal("tinsert", table.insert)
        setGlobal("tremove", table.remove)
        setGlobal("UIParent", makeFrame())
        setGlobal("SendChatMessage", function(message, channel, language, target)
            sentChat[#sentChat + 1] = { message = message, channel = channel, target = target }
        end)

        local fallbackL = setmetatable({}, { __index = function(_, key) return tostring(key) end })

        local waChunk = assert(loadfile("Core/Module/AuctionWA.lua"))
        waChunk("BGNEXT", { LibBG = {}, L = fallbackL })
        local eventChunk = assert(loadfile("Core/Module/AuctionWAEvent.lua"))
        eventChunk("BGNEXT", { LibBG = {}, L = fallbackL })

        local wa = BGA.aura_env
        local handler = BGA.Event:GetScript("OnEvent")
        test.eq(handler ~= nil, true, "the real event handler is registered on BGA.Event")

        local function newBidFrame(num, auctionID, player)
            local f = makeFrame()
            f.num = num
            f.auctionID = auctionID
            f.IsSmallWindow = true
            f.IsEnd = false
            f.isPaused = false
            f.isGen2 = false
            f.start = false
            f.money = 5000
            f.player = player
            f.colorplayer = player
            f.link = "[测试装备]"
            f.itemID = num
            f.hide = makeFrame()
            f.topMoneyFrame = makeFrame()
            f.topMoneyText = makeFrame()
            f.currentMoneyFrame = makeFrame()
            f.currentMoneyText = makeFrame()
            f.itemFrame = makeFrame()
            f.itemFrame.iconFrame = makeFrame()
            f.itemFrame.iconFrame.color = { 1, 1, 1, 1 }
            f.itemFrame.itemNameText = makeFrame()
            f.itemFrame.bg = makeFrame()
            f.itemFrame2 = makeFrame()
            f.bar = makeFrame()
            f.remainingTime = makeFrame()
            f.myMoneyEdit = makeFrame()
            f.cancelButton = makeFrame()
            f.puaseButton = makeFrame()
            f.autoTextButton = makeFrame()
            f.logTextButton = makeFrame()
            f.autoSendDelayFrame = makeFrame()
            f.autoTimer = { cancelled = false, Cancel = function(self) self.cancelled = true end }
            f.topMoneyFrame:Hide()
            f.itemFrame2:Hide()
            BGA.Frames[num] = f
            return f
        end

        local function fireCancel(auctionID, sender)
            handler(BGA.Event, "CHAT_MSG_ADDON", wa.AddonChannel, "CancelAuction," .. auctionID, "RAID", sender)
        end

        local function nLedger3()
            local count = 0
            for _, call in ipairs(auctionEndCalls) do
                if call[1] == 3 then count = count + 1 end
            end
            return count
        end

        -- (1) Authorized cancel ends the matching auction, reports exactly one
        -- ledger callback with the preserved (3, link, player, money, nil, id)
        -- shape, and does not add any chat outside the raid-leader path.
        local f1 = newBidFrame(1, 1001, "买家乙")
        wa.Auctioning(f1, 20)
        fireCancel(1001, "主拾取者")
        test.eq(f1.IsEnd, true, "authorized cancel ends the matching auction")
        test.eq(f1.bar.scripts.OnUpdate, nil, "authorized cancel immediately stops the countdown")
        test.eq(nLedger3(), 1, "authorized cancel reports exactly one ledger callback")
        test.eq(auctionEndCalls[#auctionEndCalls][2], f1.link, "cancel ledger keeps the item link")
        test.eq(auctionEndCalls[#auctionEndCalls][6], 1001, "cancel ledger keeps the auction id")
        test.eq(#sentChat, 0, "no chat is emitted outside the raid-leader path")

        -- (2) Unauthorized cancel is ignored: no end, no ledger, no countdown stop.
        local f2 = newBidFrame(2, 1002, "买家丙")
        wa.Auctioning(f2, 20)
        local ledgerBefore = #auctionEndCalls
        fireCancel(1002, "路人甲")
        test.eq(f2.IsEnd, false, "unauthorized cancel does not end the auction")
        test.eq(#auctionEndCalls, ledgerBefore, "unauthorized cancel adds no ledger callback")
        test.eq(f2.bar.scripts.OnUpdate ~= nil, true, "unauthorized cancel does not stop the countdown")

        -- (3) A duplicate authorized cancel does not double-book the ledger.
        local f3 = newBidFrame(3, 1003, "买家丁")
        wa.Auctioning(f3, 20)
        fireCancel(1003, "主拾取者")
        fireCancel(1003, "主拾取者")
        test.eq(nLedger3(), 2, "second cancel on the ended frame is a no-op, not a double-book")

        -- (4) Among simultaneous auctions only the matching auctionID ends.
        local f4 = newBidFrame(4, 1004, "买家戊")
        local f5 = newBidFrame(5, 1005, "买家己")
        wa.Auctioning(f4, 20)
        wa.Auctioning(f5, 20)
        fireCancel(1004, "主拾取者")
        test.eq(f4.IsEnd, true, "the targeted auction is cancelled")
        test.eq(f5.IsEnd, false, "the sibling auction is left running")
        test.eq(f5.bar.scripts.OnUpdate ~= nil, true, "the sibling countdown keeps running")

        -- (5) The bounded 15-second release is armed and releases the card.
        local nBefore = #afters
        local f6 = newBidFrame(6, 1006, "买家庚")
        wa.Auctioning(f6, 20)
        fireCancel(1006, "主拾取者")
        local release = afters[nBefore + 1]
        test.eq(release ~= nil, true, "cancel arms a bounded release")
        test.eq(release.delay, 15, "the release uses the 15-second bounded display window")
        release.callback()
        test.eq(f6.scripts.OnUpdate ~= nil, true, "the fade handler is armed after the display window")
        f6.scripts.OnUpdate(f6, 2)
        test.eq(f6.shown, false, "the card is hidden after the bounded display")
        test.eq(BGA.Frames[f6.num], nil, "the card is released from the frame registry")
    end)

    for _, name in ipairs(watchedGlobals) do
        rawset(_G, name, originalValues[name])
    end
    if not ok then
        error(err, 0)
    end
end
