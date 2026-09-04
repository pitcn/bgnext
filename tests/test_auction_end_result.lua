return function(test)
    -- Drives the real AuctionWA.lua countdown end callback with a minimal WoW API
    -- surface and asserts the final buyer/price becomes visible for a collapsed
    -- card, bidding stays disabled, and the card is released after a bounded
    -- display window instead of being kept forever.
    local watchedGlobals = {
        "BG", "C_Timer", "C_ChatInfo", "SOUNDKIT", "CreateFont",
        "BIAOGE_TEXT_FONT", "GetRealmName", "GetTime", "GetTimePreciseSec",
        "GetUnitName", "IsInRaid", "BiaoGe", "Locale", "strlen", "format",
        "BGA", "UIParent", "SendChatMessage",
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

        BG = { BGNext = {}, Init = function(callback) callback() end,
            AuctionWAEnd = function(...) auctionEndCalls[#auctionEndCalls + 1] = { ... } end }
        setGlobal("C_Timer", {
            After = function(delay, callback)
                afters[#afters + 1] = { delay = delay, callback = callback }
            end,
        })
        setGlobal("C_ChatInfo", { RegisterAddonMessagePrefix = function() end })
        setGlobal("SOUNDKIT", { GS_TITLE_OPTION_OK = 1 })
        setGlobal("CreateFont", function() return makeFrame() end)
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
        setGlobal("UIParent", makeFrame())
        setGlobal("SendChatMessage", function(message, channel, language, target)
            sentChat[#sentChat + 1] = { message = message, channel = channel, target = target }
        end)

        local fallbackL = setmetatable({}, { __index = function(_, key) return tostring(key) end })
        local chunk = assert(loadfile("Core/Module/AuctionWA.lua"))
        chunk("BGNEXT", { LibBG = {}, L = fallbackL })
        local wa = BGA.aura_env
        BGA.AuctionMainFrame = makeFrame()

        local function newBidFrame(num, player, isSmall)
            local f = makeFrame()
            f.num = num
            f.IsSmallWindow = isSmall
            f.IsEnd = false
            f.isPaused = false
            f.isGen2 = false
            f.start = false
            f.money = 5000
            f.player = player
            f.colorplayer = player
            f.link = "[测试装备]"
            f.auctionID = 100 + num
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
            if isSmall then
                f.topMoneyFrame:Hide()
                f.itemFrame2:Hide()
            end
            BGA.Frames[num] = f
            return f
        end

        local function driveEnd(f, duration)
            wa.Auctioning(f, duration)
            nowValue = nowValue + duration + 1
            f.bar.scripts.OnUpdate(f.bar, 0.1)
        end

        -- (1) Collapsed card with a winner reveals the buyer and the price, keeps
        -- bidding disabled, and arms a bounded result display.
        local f1 = newBidFrame(1, "买家乙", true)
        local f1Timer = f1.autoTimer
        driveEnd(f1, 20)
        test.eq(f1.IsEnd, true, "the end callback marks the auction ended")
        test.eq(f1.IsSmallWindow, false, "a collapsed card expands to show the result")
        test.eq(f1.topMoneyFrame.shown, true, "the buyer area becomes visible")
        test.eq(f1.currentMoneyText.text:find("成交价", 1, true) ~= nil, true, "price label is visible")
        test.eq(f1.currentMoneyText.text:find("5000", 1, true) ~= nil, true, "transaction amount is visible")
        test.eq(f1.topMoneyText.text:find("买家乙", 1, true) ~= nil, true, "the winner name is visible")
        test.eq(f1.myMoneyEdit.shown, false, "the bid edit box stays hidden")
        test.eq(f1.cancelButton.shown, false, "the cancel button stays hidden")
        test.eq(f1.hide:IsEnabled(), false, "the collapse/expand button is disabled")
        test.eq(f1.autoTextButton.shown, false, "the auto-bid toggle is not re-shown")
        test.eq(f1Timer.cancelled, true, "the auto-bid ticker is cancelled at end")
        test.eq(f1.autoTimer, nil, "the auto-bid ticker handle is cleared")
        test.eq(afters[1].delay, 15, "the result uses the bounded display time, not one second")
        test.eq(f1.bar.scripts.OnUpdate, nil, "the countdown stops after the end transition")

        -- (2) An already-expanded card is a regression guard: it still shows the
        -- result without re-enabling bidding.
        local f2 = newBidFrame(2, "买家丙", false)
        driveEnd(f2, 20)
        test.eq(f2.IsEnd, true, "expanded card ends")
        test.eq(f2.topMoneyFrame.shown, true, "expanded card keeps the buyer area")
        test.eq(f2.currentMoneyText.text:find("成交价", 1, true) ~= nil, true, "expanded price label")
        test.eq(f2.topMoneyText.text:find("买家丙", 1, true) ~= nil, true, "expanded winner name")
        test.eq(f2.autoTextButton.shown, false, "expanded card hides the auto-bid toggle too")
        test.eq(f2.hide:IsEnabled(), false, "expanded card disable button is disabled")

        -- (3) The player winning is labelled "you", not a fabricated name.
        local f3 = newBidFrame(3, "玩家甲", true)
        driveEnd(f3, 20)
        test.eq(f3.topMoneyText.text:find("你", 1, true) ~= nil, true, "own win shows 你")

        -- (4) A no-bid auction shows 流拍 and never fabricates a buyer.
        local f4 = newBidFrame(4, nil, true)
        driveEnd(f4, 20)
        test.eq(f4.IsEnd, true, "no-bid auction ends")
        test.eq(f4.currentMoneyText.text:find("流拍", 1, true) ~= nil, true, "no-bid shows 流拍")
        test.eq(f4.topMoneyText.text, "", "no-bid never fabricates a buyer")
        test.eq(f4.topMoneyFrame.shown, true, "no-bid card still expands to show the status")

        -- (5) Cancelling clears any stale bidder and shows the cancelled status.
        local f5 = newBidFrame(5, "买家丁", false)
        f5.topMoneyText:SetText("出价最高者：买家丁")
        wa.EndAuction(f5, "cancel")
        test.eq(f5.IsEnd, true, "cancel marks the card ended")
        test.eq(f5.currentMoneyText.text:find("拍卖取消", 1, true) ~= nil, true, "cancel shows the cancelled status")
        test.eq(f5.topMoneyText.text, "", "cancel clears any stale bidder")
        test.eq(f5.hide:IsEnabled(), false, "cancel disables the toggle button")

        -- (6) A long winner name is preserved in full.
        local longName = "这是一个非常长的买家名字超过二十个字来测试边界情况甲乙丙丁戊"
        local f6 = newBidFrame(6, longName, true)
        driveEnd(f6, 20)
        test.eq(f6.topMoneyText.text:find(longName, 1, true) ~= nil, true, "long winner name is not truncated away")

        -- (7) Two simultaneous auctions end independently.
        local f7 = newBidFrame(7, "买家戊", true)
        local f8 = newBidFrame(8, "买家己", true)
        driveEnd(f7, 30)
        driveEnd(f8, 20)
        test.eq(f7.topMoneyText.text:find("买家戊", 1, true) ~= nil, true, "first auction keeps its winner")
        test.eq(f8.topMoneyText.text:find("买家己", 1, true) ~= nil, true, "second auction keeps its winner")
        test.eq(f7.topMoneyText.text:find("买家己", 1, true), nil, "winners do not cross-contaminate")

        -- (8) The bounded display releases the card instead of keeping it forever.
        local nAfter = #afters
        afters[1].callback()
        test.eq(f1.scripts.OnUpdate ~= nil, true, "the fade handler is armed after the display window")
        f1.scripts.OnUpdate(f1, 2)
        test.eq(f1.shown, false, "the card is hidden after the bounded display")
        test.eq(BGA.Frames[1], nil, "the card is released from the frame registry")

        -- (9) The existing protocol/ledger callback is preserved, not reworked.
        test.eq(#auctionEndCalls >= 1, true, "the ledger end callback still fires")
        test.eq(auctionEndCalls[1][1], 1, "success still reports kind 1")
        test.eq(sentChat[1] == nil, true, "no extra chat is introduced outside the raid-leader path")

        -- (10) A forced end expansion rearranges siblings exactly once (bounded,
        -- no periodic layout) so simultaneous folded cards do not overlap.
        local arrangeCount = 0
        local origUpdateAllFrames = wa.UpdateAllFrames
        wa.UpdateAllFrames = function()
            arrangeCount = arrangeCount + 1
            return origUpdateAllFrames()
        end
        local fCollapsed = newBidFrame(20, "买家壬", true)
        wa.EndAuction(fCollapsed, "success")
        test.eq(arrangeCount, 1, "forced end expansion rearranges siblings exactly once")
        wa.UpdateAllFrames = origUpdateAllFrames

        -- (11) Cancelling also detaches the countdown OnUpdate immediately (the
        -- network cancel path has no natural-expiry cleanup to rely on).
        local fCancel = newBidFrame(21, "买家癸", false)
        wa.Auctioning(fCancel, 20)
        wa.EndAuction(fCancel, "cancel")
        test.eq(fCancel.bar.scripts.OnUpdate, nil, "cancel detaches the countdown OnUpdate")
    end)

    for _, name in ipairs(watchedGlobals) do
        rawset(_G, name, originalValues[name])
    end
    if not ok then
        error(err, 0)
    end
end
