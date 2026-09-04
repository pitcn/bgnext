return function(test)
    -- Loads the real Core/Module/Auction.lua baseline override and drives the
    -- actual private Start_OnClick through its three activation paths (button
    -- click, Edit2 Enter, quick-price), verifying the optional onPreSend veto and
    -- the causal onAuctionSent(auctionID, ...) callback that the queue runtime
    -- attaches to. This proves the baseline hook itself is wired, not just the
    -- runtime's use of it.
    local watchedGlobals = {
        "BG", "C_Timer", "C_ChatInfo", "C_AddOns", "C_FriendList", "C_Container",
        "CreateFont", "CreateFrame", "BIAOGE_TEXT_FONT", "GetRealmName",
        "GetNormalizedRealmName", "GetRealmID", "GetTime", "GetItemInfo",
        "GetItemQualityColor", "GetCursorPosition", "IsInRaid", "IsAddOnLoaded",
        "LoadAddOn", "BiaoGe", "Locale", "strlen", "strfind", "format", "strsplit",
        "tinsert", "tremove", "BGA", "UIParent", "SendChatMessage", "GetNumGroupMembers",
        "GetRaidRosterInfo", "GameTooltip", "BiaoGeTooltip", "GameTooltip_Hide",
        "UIErrorsFrame", "ITEM_CLASSES_ALLOWED", "ERR_IGNORE_ADDED_S",
        "SlashCmdList", "StaticPopupDialogs", "StaticPopup_Hide", "StaticPopup_Show",
        "StaticPopup_Visible", "hooksecurefunc", "LibStub", "UnitInRaid", "IsAltKeyDown",
        "UpdateFrame", "ClearAllFocus", "wipe", "unpack", "random", "YES", "NO",
    }
    local originalValues = {}
    for _, name in ipairs(watchedGlobals) do
        originalValues[name] = rawget(_G, name)
    end
    local function setGlobal(name, value)
        rawset(_G, name, value)
    end

    local ok, err = pcall(function()
        local initCallbacks = {}
        local init2Callbacks = {}
        local afters = {}
        local nowValue = 1000
        local nextAuctionID = 0
        local sends = {}

        -- --- Fake frame factory ------------------------------------------------

        local function makeFrame()
            local frame = {
                points = {}, scripts = {}, children = {}, hooks = {},
                text = "", shown = true, enabled = true,
                width = 0, height = 0, min = 0, max = 1000, value = 0, alpha = 1,
                fontString = nil, normalTexture = nil, pushedTexture = nil,
                disabledTexture = nil, parent = nil,
            }
            function frame:SetPoint() end
            function frame:SetAllPoints() end
            function frame:ClearAllPoints() self.points = {} end
            function frame:SetSize(width, height) self.width, self.height = width, height end
            function frame:SetWidth(width) self.width = width end
            function frame:SetHeight(height) self.height = height end
            function frame:GetWidth() return self.width end
            function frame:GetHeight() return self.height end
            function frame:SetScript(name, handler) self.scripts[name] = handler end
            function frame:GetScript(name) return self.scripts[name] end
            function frame:HookScript(name, handler)
                self.hooks[name] = self.hooks[name] or {}
                self.hooks[name][#self.hooks[name] + 1] = handler
            end
            function frame:SetText(value) self.text = tostring(value) end
            function frame:GetText() return self.text end
            function frame:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) end
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
            function frame:SetEnabled(value) self.enabled = value and true or false end
            function frame:IsEnabled() return self.enabled end
            function frame:EnableMouse() end
            function frame:SetFrameLevel() end
            function frame:GetFrameLevel() return 0 end
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
            function frame:SetFontString(value) self.fontString = value end
            function frame:SetAlpha(value) self.alpha = value end
            function frame:GetAlpha() return self.alpha end
            function frame:SetBackdrop() end
            function frame:SetBackdropColor() end
            function frame:SetBackdropBorderColor() end
            function frame:SetValue(value) self.value = value end
            function frame:GetMinMaxValues() return self.min, self.max end
            function frame:SetMinMaxValues(min, max) self.min, self.max = min, max end
            function frame:SetStatusBarColor() end
            function frame:SetStatusBarTexture() end
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
            function frame:SetAutoFocus() end
            function frame:SetNumeric() end
            function frame:SetMaxLetters() end
            function frame:ClearFocus() end
            function frame:SetChecked() end
            function frame:GetID() return 0 end
            function frame:GetStringWidth() return 60 end
            function frame:GetEffectiveScale() return 1 end
            function frame:GetParent() return self.parent end
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
            function frame:GetNormalTexture()
                if not self.normalTexture then self.normalTexture = makeFrame() end
                return self.normalTexture
            end
            function frame:SetNormalTexture() end
            function frame:GetPushedTexture()
                if not self.pushedTexture then self.pushedTexture = makeFrame() end
                return self.pushedTexture
            end
            function frame:SetPushedTexture() end
            function frame:GetDisabledTexture()
                if not self.disabledTexture then self.disabledTexture = makeFrame() end
                return self.disabledTexture
            end
            function frame:SetDisabledTexture() end
            return frame
        end

        setGlobal("CreateFrame", function(frameType, name, parent, template)
            local f = makeFrame()
            f.parent = parent
            if type(parent) == "table" and type(parent.children) == "table" then
                parent.children[#parent.children + 1] = f
            end
            return f
        end)

        -- --- BG and WoW stubs -------------------------------------------------

        local Readiness = {
            READY = 1, ADDON_ONLY = 2, OFFLINE = 3,
            footerView = function() return { mode = "solo", ready = 0, total = 0 } end,
            requestDelay = function() return nil end,
            takeRequest = function() return false end,
            status = function() return nil end,
            prune = function() end,
        }
        BG = {
            BGNext = {
                PlayerIdentity = { same = function() return false end },
                AuctionReadiness = Readiness,
                AuctionSender = {
                    canonical = function(name) return name end,
                    shouldRespondVersion = function() return false end,
                    isRaidSender = function() return false end,
                    parseBid = function() return nil end,
                },
                WishlistReminder = { notify = function() end },
            },
            playerName = "玩家甲",
            ver = "2.0.0",
            IsWLK = true,
            IsML = true,
            ImML = function() return true end,
            ImMLorLeader = function() return true end,
            Once = function() end,
            Init = function(fn) initCallbacks[#initCallbacks + 1] = fn end,
            Init2 = function(fn) init2Callbacks[#init2Callbacks + 1] = fn end,
            RegisterEvent = function() end,
            After = function(delay, fn) afters[#afters + 1] = { delay = delay, fn = fn } end,
            SendSystemMessage = function() end,
            Copy = function(x) return x end,
            CreateButton = function(parent) local b = makeFrame(); b.parent = parent; return b end,
            CreateCloseButton = function(f, x, y)
                local b = makeFrame(); b.parent = f; f.CloseButton = b; return b
            end,
            editTemplate = "template",
            g1 = { 1, 1, 1 },
            MainFrame = makeFrame(),
            raidRosterInfo = { { name = "Alice" }, { name = "Bob" } },
            Tooltip_SetItemByID = function() end,
            FormatNumber = function(n) return tostring(n) end,
            SortRaidRosterInfo = function() return {} end,
            GetVerNum = function() return 0 end,
            GSN = function(s) return s end,
            STC_g1 = function(s) return s end,
            STC_b1 = function(s) return s end,
            STC_r1 = function(s) return s end,
            GetAllFB = function() return {} end,
            GetLeiTingItem = function() return nil end,
            Frame = {},
            GetMaxi = function() return 0 end,
            UpdateAuctionFilter = function(f, cb) end,
            auctionLogFrame = { auctioning = {} },
            UpdateAuctioning = function() end,
            IsHope = function() return false end,
            PlaySound = function() end,
            IsLeader = false,
            IsVanilla = false,
            IsTBC = false,
            IsWLK_80 = false,
            IsTitan = false,
            IsMOP = false,
            IsRetail = false,
            verLess2 = false,
        }

        setGlobal("C_Timer", { After = function() end })
        setGlobal("C_ChatInfo", { SendAddonMessage = function() end })
        setGlobal("C_AddOns", { IsAddOnLoaded = function() return false end, LoadAddOn = function() end })
        setGlobal("C_FriendList", { GetNumIgnores = function() return 0 end, GetIgnoreName = function() end, DelIgnore = function() end })
        setGlobal("C_Container", { GetContainerItemLink = function() end })
        setGlobal("CreateFont", function() return makeFrame() end)
        setGlobal("BIAOGE_TEXT_FONT", "Fonts\\FRIZQT__.TTF")
        setGlobal("GetRealmName", function() return "MyRealm" end)
        setGlobal("GetNormalizedRealmName", function() return "MyRealm" end)
        setGlobal("GetRealmID", function() return 1 end)
        setGlobal("GetTime", function() return nowValue end)
        setGlobal("GetItemInfo", function(link)
            return "测试装备", link, 4, 80, nil, "装备", "武器", nil, "INVTYPE_WEAPON",
                "Interface/Icons/inv_weapon_1", nil, 2, 0, 2
        end)
        setGlobal("GetItemQualityColor", function() return 1, 0.5, 0 end)
        setGlobal("GetCursorPosition", function() return 100, 100 end)
        setGlobal("IsInRaid", function() return true end)
        setGlobal("IsAddOnLoaded", function() return false end)
        setGlobal("LoadAddOn", function() end)
        setGlobal("BiaoGe", { options = { autoAuctionStart = 1, fastMoney = 1 }, Auction = { money = 500 } })
        setGlobal("Locale", "zhCN")
        setGlobal("strlen", string.len)
        setGlobal("strfind", string.find)
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
        setGlobal("wipe", function(t) for k in pairs(t) do t[k] = nil end; return t end)
        setGlobal("unpack", unpack)
        setGlobal("random", math.random)
        setGlobal("BGA", { Frames = {} })
        setGlobal("UIParent", makeFrame())
        setGlobal("SendChatMessage", function() end)
        setGlobal("GetNumGroupMembers", function() return 0 end)
        setGlobal("GetRaidRosterInfo", function() end)
        setGlobal("GameTooltip", {
            SetOwner = function() end, ClearLines = function() end, AddLine = function() end,
            AddDoubleLine = function() end, Show = function() end, Hide = function() end,
            SetHyperlink = function() end,
        })
        setGlobal("BiaoGeTooltip", { NumLines = function() return 0 end })
        setGlobal("GameTooltip_Hide", function() end)
        setGlobal("UIErrorsFrame", { AddMessage = function() end })
        setGlobal("ITEM_CLASSES_ALLOWED", "item classes: %s")
        setGlobal("ERR_IGNORE_ADDED_S", "You are no longer ignoring %s")
        setGlobal("SlashCmdList", {})
        setGlobal("StaticPopupDialogs", {})
        setGlobal("StaticPopup_Hide", function() end)
        setGlobal("StaticPopup_Show", function() end)
        setGlobal("StaticPopup_Visible", function() return nil end)
        setGlobal("hooksecurefunc", function() end)
        setGlobal("LibStub", function()
            return { PixelGlow_Start = function() end, PixelGlow_Stop = function() end }
        end)
        setGlobal("UnitInRaid", function() return false end)
        setGlobal("IsAltKeyDown", function() return false end)
        setGlobal("UpdateFrame", function() end)
        setGlobal("ClearAllFocus", function() end)
        setGlobal("YES", "YES")
        setGlobal("NO", "NO")

        local fallbackL = setmetatable({}, { __index = function(_, key) return tostring(key) end })
        local ns = {
            LibBG = {},
            L = fallbackL,
            RGB = function() return 1, 1, 1 end,
            GetClassRGB = function() return 1, 1, 1 end,
            SetClassCFF = function(s) return s end,
            AddTexture = function() return "" end,
            GetItemID = function(link) return tonumber(tostring(link):match("item:(%d+)")) or 1001 end,
            Maxb = {},
            HopeMaxn = 0,
            HopeMaxb = 0,
            HopeMaxi = 0,
        }

        -- --- Load and initialise the real module ------------------------------

        local chunk = assert(loadfile("Core/Module/Auction.lua"))
        chunk("BGNEXT", ns)
        for _, fn in ipairs(initCallbacks) do fn() end

        -- Replace the transport with a recording version (still the same signature
        -- and return contract) so the send closure's returned auctionID is observable.
        BG.SendStartAuctionMsg = function(itemID, money, duration, link)
            nextAuctionID = nextAuctionID + 1
            sends[#sends + 1] = { auctionID = nextAuctionID, itemID = itemID, money = money }
            return nextAuctionID
        end

        local function flushZeroTimers()
            local zero, rest = {}, {}
            for _, t in ipairs(afters) do
                if t.delay == 0 then zero[#zero + 1] = t else rest[#rest + 1] = t end
            end
            afters = rest
            for _, t in ipairs(zero) do t.fn() end
        end

        local function newFrame()
            BG.StartAuction("item:1001", nil, nil, true)
            local f = BG.StartAucitonFrame
            f.bt.money = 500
            return f
        end

        local function fastButtons(f)
            local buttons = {}
            if type(f.fastMoneyFrame) == "table" and type(f.fastMoneyFrame.children) == "table" then
                for _, child in ipairs(f.fastMoneyFrame.children) do
                    if type(child.money) == "number" then buttons[#buttons + 1] = child end
                end
            end
            return buttons
        end

        -- --- (1) onPreSend veto blocks every path with no side effects ---------

        local paths = {
            { name = "button", run = function(f) f.bt.scripts.OnClick(f.bt) end },
            { name = "enter", run = function(f) f.Edit2.scripts.OnEnterPressed(f.Edit2) end },
            { name = "fast", run = function(f) fastButtons(f)[1].scripts.OnClick(fastButtons(f)[1]) end },
        }
        for _, path in ipairs(paths) do
            local preSendCount = 0
            local f = newFrame()
            f.bt.onPreSend = function()
                preSendCount = preSendCount + 1
                return false
            end
            path.run(f)
            test.eq(preSendCount, 1, path.name .. " path invokes the authoritative onPreSend")
            test.eq(f.shown, true, path.name .. " veto leaves the dialog open")
        end
        test.eq(#sends, 0, "a vetoed path schedules no send")

        -- --- (2) onAuctionSent receives the exact returned auctionID -------------

        local captured = {}
        local f = newFrame()
        f.bt.onPreSend = function() return true end
        f.bt.onAuctionSent = function(auctionID, itemID, money, link)
            captured[#captured + 1] = { auctionID = auctionID, itemID = itemID, money = money }
        end
        f.bt.scripts.OnClick(f.bt)
        flushZeroTimers()
        test.eq(#sends, 1, "an allowed path sends once")
        test.eq(#captured, 1, "the send closure invokes onAuctionSent once")
        test.eq(captured[1].auctionID, sends[1].auctionID, "onAuctionSent receives the exact returned auctionID")
        test.eq(captured[1].itemID, 1001, "onAuctionSent receives the itemID")
        test.eq(captured[1].money, 500, "onAuctionSent receives the bound money")

        -- --- (3) a foreign same-item send never invokes onAuctionSent -------------

        captured = {}
        local g = newFrame()
        g.bt.onPreSend = function() return true end
        g.bt.onAuctionSent = function(auctionID, itemID, money, link)
            captured[#captured + 1] = { auctionID = auctionID, itemID = itemID, money = money }
        end
        g.bt.scripts.OnClick(g.bt) -- schedules the queue's own BG.After(0) send
        local foreignID = BG.SendStartAuctionMsg(1001, 777, 40, "item:1001") -- unrelated sender
        test.eq(#captured, 0, "a foreign send never invokes the button callback")
        flushZeroTimers()
        test.eq(#captured, 1, "only the own scheduled send invokes the callback")
        test.eq(captured[1].auctionID ~= foreignID, true, "the own auctionID is distinct from the foreign one")
        test.eq(captured[1].auctionID, sends[#sends].auctionID, "the callback carries the own send's auctionID")
    end)

    for _, name in ipairs(watchedGlobals) do
        rawset(_G, name, originalValues[name])
    end
    if not ok then
        error(err, 0)
    end
end
