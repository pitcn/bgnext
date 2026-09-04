return function(test)
    -- Integration test for the leader price-preset direct start. It loads the
    -- REAL wrapper chain end to end:
    --   baseline Core/Module/Auction.lua (defines BG.StartAuction)
    --   Core/BGNext/AuctionPriceRuntime.lua (inner wrapper: prefills + snapshot)
    --   Core/BGNext/AuctionQueueRuntime.lua (outer wrapper: arms the shared gate)
    -- plus the shared Core/BGNext/AuctionPreSend.lua gate and the real WoW entry
    -- callers. Firing the Init callbacks in registration order proves the wrapper
    -- install order (queue outermost, price inner, baseline innermost) and that an
    -- Alt+right-click direct start only clicks after the outer wrapper has armed
    -- the gate. In addition to the hand-invoked BG.StartAuction scenarios, three
    -- real callers are driven: the backpack container click hook, the auction-msg
    -- chat hyperlink handler, and the table equipment-list mouse-down handler.
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
        "InCombatLockdown",
    }
    -- WoW stat/item globals that function2.lua reads at load time, plus the extra
    -- globals the real chat and table callers need. These are saved and restored
    -- so the shared interpreter never leaks them into later suites.
    for _, name in ipairs({
        "ITEM_SOCKET_BONUS", "ITEM_MOD_FERAL_ATTACK_POWER", "ITEM_LIMIT_CATEGORY_MULTIPLE",
        "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_INTELLECT_SHORT",
        "ITEM_MOD_SPIRIT_SHORT", "ITEM_MOD_MANA_REGENERATION", "STAT_CATEGORY_DEFENSE",
        "STAT_PARRY", "STAT_DODGE", "ITEM_MOD_BLOCK_RATING_SHORT", "ITEM_MOD_BLOCK_VALUE_SHORT",
        "ITEM_MOD_ATTACK_POWER_SHORT", "HIT_LCD", "ITEM_MOD_HIT_RATING_SHORT",
        "STAT_CRITICAL_STRIKE", "ITEM_MOD_CRIT_RATING_SHORT", "STAT_HASTE",
        "ITEM_MOD_HASTE_RATING_SHORT", "STAT_EXPERTISE", "ITEM_MOD_ARMOR_PENETRATION_RATING",
        "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_MASTERY_RATING_SHORT", "STAT_MASTERY",
        "ITEM_MOD_VERSATILITY", "RESILIENCE",
        "strsub", "GetServerTime", "GetItemInfoInstant", "GetRaidDifficultyID", "UnitClass",
        "IsShiftKeyDown", "IsControlKeyDown", "SetCursor", "date", "GetClassColor",
        "GetItemStats", "Item", "C_Item", "GetGameTime", "CreateColor",
    }) do
        watchedGlobals[#watchedGlobals + 1] = name
    end
    local originalValues = {}
    for _, name in ipairs(watchedGlobals) do
        originalValues[name] = rawget(_G, name)
    end
    local function setGlobal(name, value)
        rawset(_G, name, value)
    end

    local ok, err = pcall(function()
        local initCallbacks = {}
        local afters = {}
        local hookedFuncs = {}
        local nowValue = 1000
        local nextAuctionID = 0
        local sends = {}
        local messages = {}

        -- --- Fake frame factory ------------------------------------------------

        local useUserdataFrames = false
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
            function frame:SetGradient() end
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
            function frame:GetHighlightTexture()
                if not self.highlightTexture then self.highlightTexture = makeFrame() end
                return self.highlightTexture
            end
            function frame:SetHitRectInsets() end
            function frame:SetAutoFocus() end
            function frame:SetNumeric() end
            function frame:SetMaxLetters() end
            function frame:SetTextInsets() end
            function frame:SetCursorPosition() end
            function frame:ClearFocus() end
            function frame:SetFocus() end
            function frame:SetChecked() end
            function frame:GetID() return 0 end
            function frame:GetStringWidth() return 60 end
            function frame:GetEffectiveScale() return 1 end
            function frame:GetParent() return self.parent end
            function frame:SetSpacing() end
            function frame:SetFading() end
            function frame:SetMaxLines() end
            function frame:SetHyperlinksEnabled() end
            function frame:AtBottom() return true end
            function frame:AddMessage() end
            function frame:ScrollToTop() end
            function frame:ScrollToBottom() end
            function frame:ScrollUp() end
            function frame:ScrollDown() end
            function frame:UpdateButtonItem() end
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
            function frame:CreateAnimationGroup()
                local function anim()
                    return {
                        SetChildKey = function() end,
                        SetOrder = function() end,
                        SetDuration = function() end,
                        SetFromAlpha = function() end,
                        SetToAlpha = function() end,
                    }
                end
                return {
                    CreateAnimation = function(_, _animType) return anim() end,
                    Play = function() end,
                    SetLooping = function() end,
                }
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
            if useUserdataFrames then
                local proxy = newproxy(true)
                local mt = getmetatable(proxy)
                mt.__index = frame
                mt.__newindex = frame
                return proxy
            end
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
            Init2 = function(fn) end,
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
            b1 = "b1",
            MainFrame = makeFrame(),
            raidRosterInfo = { { name = "Alice" }, { name = "Bob" } },
            Tooltip_SetItemByID = function() end,
            FormatNumber = function(n) return tostring(n) end,
            SortRaidRosterInfo = function() return {} end,
            GetVerNum = function() return 0 end,
            GSN = function(s) return s end,
            STC_g1 = function(s) return s end,
            STC_b1 = function(s) return s end,
            STC_w1 = function(s) return s end,
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
            -- function2.lua / AuctionMSG.lua load-time and table caller helpers.
            SetButtonAtlas = function() end,
            GameTooltip_Hide = function() end,
            diffIDTbl = { ULD = { [3] = "normal" } },
            difficultyTable = {},
            onEnterAlpha = 0.4,
            AddHText = function() return true end,
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
            local id = tostring(link):match("item:(%d+)") or tostring(link)
            local itemLink = "item:" .. id
            return "测试装备", itemLink, 4, 80, nil, "装备", "武器", nil, "INVTYPE_WEAPON",
                "Interface/Icons/inv_weapon_1", nil, 2, 0, 2
        end)
        setGlobal("GetItemQualityColor", function() return 1, 0.5, 0 end)
        setGlobal("GetCursorPosition", function() return 100, 100 end)
        setGlobal("IsInRaid", function() return true end)
        setGlobal("IsAddOnLoaded", function() return false end)
        setGlobal("LoadAddOn", function() end)
        setGlobal("BiaoGe", { options = { autoAuctionStart = 1, fastMoney = 1 }, Auction = { money = 500 }, ULD = { boss1 = {} } })
        setGlobal("Locale", "zhCN")
        setGlobal("strlen", string.len)
        setGlobal("strfind", string.find)
        setGlobal("strsub", string.sub)
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
        setGlobal("BiaoGeTooltip", {
            SetOwner = function() end,
            ClearLines = function() end,
            SetHyperlink = function() end,
            SetItemByID = function() end,
            NumLines = function() return 0 end,
        })
        for i = 1, 10 do
            setGlobal("BiaoGeTooltipTextLeft" .. i, { GetText = function() return "" end })
            setGlobal("BiaoGeTooltipTextRight" .. i, { GetText = function() return "" end })
        end
        setGlobal("WARDROBE_SETS", "WARDROBE_SETS")
        setGlobal("GameTooltip_Hide", function() end)
        setGlobal("UIErrorsFrame", { AddMessage = function() end })
        setGlobal("ITEM_CLASSES_ALLOWED", "item classes: %s")
        setGlobal("ERR_IGNORE_ADDED_S", "You are no longer ignoring %s")
        setGlobal("SlashCmdList", {})
        setGlobal("StaticPopupDialogs", {})
        setGlobal("StaticPopup_Hide", function() end)
        setGlobal("StaticPopup_Show", function() end)
        setGlobal("StaticPopup_Visible", function() return nil end)
        setGlobal("hooksecurefunc", function(name, func) hookedFuncs[#hookedFuncs + 1] = { name = name, func = func } end)
        setGlobal("LibStub", function()
            return { PixelGlow_Start = function() end, PixelGlow_Stop = function() end }
        end)
        setGlobal("UnitInRaid", function() return false end)
        setGlobal("IsAltKeyDown", function() return false end)
        setGlobal("IsShiftKeyDown", function() return false end)
        setGlobal("IsControlKeyDown", function() return false end)
        setGlobal("UpdateFrame", function() end)
        setGlobal("ClearAllFocus", function() end)
        setGlobal("YES", "YES")
        setGlobal("NO", "NO")
        setGlobal("GetServerTime", function() return nowValue end)
        setGlobal("GetItemInfoInstant", function() return nil end)
        setGlobal("GetRaidDifficultyID", function() return 3 end)
        setGlobal("UnitClass", function() return "WARRIOR", "WARRIOR" end)
        setGlobal("SetCursor", function() end)
        setGlobal("date", function() return "" end)
        setGlobal("GetClassColor", function() return 1, 1, 1, 1 end)
        setGlobal("GetItemStats", function() return nil end)
        setGlobal("GetGameTime", function() return 0, 0 end)
        setGlobal("CreateColor", function() return { r = 0, g = 0, b = 0, a = 1 } end)
        setGlobal("Item", { CreateFromItemID = function() return { ContinueOnItemLoad = function(_, cb) cb() end } end })

        -- WoW stat/item globals read by function2.lua at load time.
        for _, name in ipairs({
            "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_INTELLECT_SHORT",
            "ITEM_MOD_SPIRIT_SHORT", "ITEM_MOD_MANA_REGENERATION", "STAT_CATEGORY_DEFENSE",
            "STAT_PARRY", "STAT_DODGE", "ITEM_MOD_BLOCK_RATING_SHORT", "ITEM_MOD_BLOCK_VALUE_SHORT",
            "ITEM_MOD_ATTACK_POWER_SHORT", "HIT_LCD", "ITEM_MOD_HIT_RATING_SHORT",
            "STAT_CRITICAL_STRIKE", "ITEM_MOD_CRIT_RATING_SHORT", "STAT_HASTE",
            "ITEM_MOD_HASTE_RATING_SHORT", "STAT_EXPERTISE", "ITEM_MOD_ARMOR_PENETRATION_RATING",
            "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_MASTERY_RATING_SHORT", "STAT_MASTERY",
            "ITEM_MOD_VERSATILITY", "RESILIENCE",
        }) do
            setGlobal(name, "%s")
        end
        setGlobal("ITEM_SOCKET_BONUS", "镶孔奖励：%s")
        setGlobal("ITEM_MOD_FERAL_ATTACK_POWER", "攻击强度提高%s点")
        setGlobal("ITEM_LIMIT_CATEGORY_MULTIPLE", "最多%d件%s")

        local fallbackL = setmetatable({}, { __index = function(_, key) return tostring(key) end })
        local ns = {
            LibBG = {},
            L = fallbackL,
            RGB = function() return 1, 1, 1 end,
            GetClassRGB = function() return 1, 1, 1 end,
            SetClassCFF = function(s) return s end,
            AddTexture = function() return "" end,
            GetItemID = function(link) return tonumber(tostring(link):match("item:(%d+)")) or 1001 end,
            Maxb = { ULD = 2 },
            HopeMaxn = 0,
            HopeMaxb = 0,
            HopeMaxi = 0,
            RN = function() return "" end,
            GetText_T = function(s) return tostring(s) end,
            BossNum = function() return 1 end,
        }

        -- --- Load the real modules (load order = TOC order) -------------------
        -- Store/Catalog/Codec/PreSend/ItemPrimaryStats/HighlightManager are pure
        -- and self-register on BG.BGNext.
        local Store = dofile("Core/BGNext/AuctionPriceStore.lua")
        local Catalog = dofile("Core/BGNext/AuctionPriceCatalog.lua")
        local Codec = dofile("Core/BGNext/AuctionPriceCodec.lua")
        dofile("Core/BGNext/AuctionPreSend.lua")
        dofile("Core/BGNext/ItemPrimaryStats.lua")
        dofile("Core/BGNext/HighlightManager.lua")

        -- Auction.lua registers BG.StartAuction inside an Init callback; the
        -- wrappers then wrap it inside their own Init callbacks (registered later,
        -- so they run after the original is defined). AuctionQueueRuntime is the
        -- outermost layer.
        assert(loadfile("Core/Module/Auction.lua"))("BGNEXT", ns)
        assert(loadfile("Core/BGNext/AuctionPriceRuntime.lua"))("BGNEXT", ns)
        dofile("Core/BGNext/AuctionQueue.lua")
        assert(loadfile("Core/BGNext/AuctionQueueRuntime.lua"))("BGNEXT", ns)

        -- Real chat caller (AuctionMSG) and table caller (function2) register
        -- their handlers in an Init callback / at load time respectively.
        assert(loadfile("Core/Module/AuctionMSG.lua"))("BGNEXT", ns)
        assert(loadfile("Core/function2.lua"))("BGNEXT", ns)

        -- Firing in registration order: Auction.lua first, then the Price wrapper,
        -- then the Queue wrapper, then the chat frame.
        for _, fn in ipairs(initCallbacks) do fn() end

        -- Replace the transport with a recording version (same signature) and
        -- capture the local reason messages the direct start may emit.
        BG.SendStartAuctionMsg = function(itemID, money, duration, link)
            nextAuctionID = nextAuctionID + 1
            sends[#sends + 1] = { auctionID = nextAuctionID, itemID = itemID, money = money }
            return nextAuctionID
        end
        BG.SendSystemMessage = function(msg) messages[#messages + 1] = msg end

        local function flushZeroTimers()
            local zero, rest = {}, {}
            for _, t in ipairs(afters) do
                if t.delay == 0 then zero[#zero + 1] = t else rest[#rest + 1] = t end
            end
            afters = rest
            for _, t in ipairs(zero) do t.fn() end
        end

        -- --- Raid / loot / scheme fixtures ------------------------------------

        BG.FBtable = { "ULD", "ICC", "MC" }
        BG.FB1 = "ULD"
        BG.realmID = 1
        BG.Loot = {
            ULD = { normal = { boss1 = { 1001, 2001 } } },
            ICC = { normal = { boss1 = { 1001, 3001 } } },
            MC  = { normal = { boss1 = { 4001 } } },
        }
        local root = {}
        BG.BGNext.DB = root
        Store.ensureLeaderRaid(root, "wrath", "ULD", 1000)
        Store.setLeaderItemPrice(root, "wrath", "ULD", "p1", 1001, 500)
        Store.ensureLeaderRaid(root, "wrath", "ICC", 2000)
        Store.ensureLeaderRaid(root, "wrath", "MC", 0)

        local function resetAuction()
            sends = {}
            nextAuctionID = 0
            messages = {}
            BG.StartAucitonFrame = nil
            BG.IsML = true
            BG.ImMLorLeader = function() return true end
            BGA.Frames = {}
            InCombatLockdown = nil
            setGlobal("IsAltKeyDown", function() return false end)
            setGlobal("IsShiftKeyDown", function() return false end)
            setGlobal("C_Container", { GetContainerItemLink = function() end })
        end

        -- Runs the real entry as an Alt+right-click direct start (isRightButton
        -- true, explicit options) and flushes the zero-delay send timers.
        local function runDirect(link, options)
            BG.StartAuction(link, nil, nil, nil, true, nil, nil, options)
            flushZeroTimers()
            return { sends = sends, frame = BG.StartAucitonFrame, messages = messages }
        end

        -- --- (1) The core bug: an explicit table source proves the raid for a
        -- cross-raid-duplicate item, so the direct start proceeds at the override.

        resetAuction()
        local s = runDirect("item:1001", { source = "table", raidId = "ULD" })
        test.eq(#s.sends, 1, "duplicate item with explicit table source starts directly")
        test.eq(s.sends[1].money, 500, "single-item override price wins")
        test.eq(s.sends[1].itemID, 1001, "the correct item is sent")
        test.eq(s.frame.shown, false, "direct start hides the dialog")

        -- WoW UI objects may be userdata while still exposing Frame methods and
        -- writable custom fields. The direct-start wrapper must use the object
        -- contract instead of rejecting the frame solely because type() is not
        -- "table"; otherwise the price is prefilled but the reused start button
        -- is never clicked (the live #86 symptom).
        resetAuction()
        useUserdataFrames = true
        s = runDirect("item:1001", { source = "table", raidId = "ULD" })
        useUserdataFrames = false
        test.eq(#s.sends, 1, "userdata-shaped WoW frames still direct-start")
        test.eq(s.sends[1].money, 500, "userdata-shaped frame keeps the approved price")

        -- --- (2) A loot source proves the current raid without an explicit raidId.

        resetAuction()
        s = runDirect("item:1001", { source = "loot" })
        test.eq(#s.sends, 1, "loot source proves the current raid for a duplicate item")
        test.eq(s.sends[1].money, 500, "loot source still resolves the override price")

        -- --- (3) Base price when the item has no single-item override.

        resetAuction()
        s = runDirect("item:2001", { source = "table", raidId = "ULD" })
        test.eq(#s.sends, 1, "unique item with explicit table source starts directly")
        test.eq(s.sends[1].money, 1000, "base price is used when no override exists")

        -- --- (4) A zero base price is still a valid direct start.

        resetAuction()
        s = runDirect("item:4001", { source = "table", raidId = "MC" })
        test.eq(#s.sends, 1, "a zero base price still starts directly")
        test.eq(s.sends[1].money, 0, "zero gold is sent as zero")

        -- --- (5) An active preset imported from the legacy price string.

        resetAuction()
        local importRoot = {}
        BG.BGNext.DB = importRoot
        local legacy = Codec.parse("ULD:encoded", "leader", { [1001] = true }, {
            clientFamily = "wrath",
            defaultBasePrice = 1000,
            isBase64 = function(text) return text == "encoded" end,
            decodeBase64 = function() return "1001-750-," end,
        })
        test.eq(legacy.ok, true, "legacy price string parses")
        test.eq(Codec.applyLeader(importRoot, legacy, { mode = "replace-all" }), true, "legacy import applies")
        s = runDirect("item:1001", { source = "table", raidId = "ULD" })
        test.eq(#s.sends, 1, "imported active preset starts directly")
        test.eq(s.sends[1].money, 750, "imported preset price is honored")
        BG.BGNext.DB = root

        -- --- (6) Backpack cannot guess a duplicated item's raid: keep window.

        resetAuction()
        s = runDirect("item:1001", { source = "backpack" })
        test.eq(#s.sends, 0, "backpack refuses to guess a duplicated item's raid")
        test.eq(s.frame.shown, true, "backpack keeps the confirm window")
        test.eq(#s.messages, 1, "backpack shows a short local reason")

        -- --- (7) Backpack still direct-starts a catalog-unique current-raid item.

        resetAuction()
        s = runDirect("item:2001", { source = "backpack" })
        test.eq(#s.sends, 1, "backpack direct-starts a unique current-raid item")
        test.eq(s.sends[1].money, 1000, "catalog-unique item uses the base price")

        -- --- (8..10) The authoritative gate rejects permission/combat/active-auction.

        resetAuction()
        BG.IsML = false
        BG.ImMLorLeader = function() return false end
        s = runDirect("item:1001", { source = "table", raidId = "ULD" })
        test.eq(#s.sends, 0, "permission loss blocks the direct start")
        test.eq(s.frame == nil, true, "no dialog opens without permission")

        resetAuction()
        InCombatLockdown = function() return true end
        s = runDirect("item:1001", { source = "table", raidId = "ULD" })
        test.eq(#s.sends, 0, "combat blocks the direct start")
        test.eq(s.frame.shown, true, "combat keeps the dialog open")

        resetAuction()
        BGA.Frames = { [1] = { IsEnd = false } }
        s = runDirect("item:1001", { source = "table", raidId = "ULD" })
        test.eq(#s.sends, 0, "an active auction blocks the direct start")
        test.eq(s.frame.shown, true, "an active auction keeps the dialog open")

        -- --- (11) An explicit raid that is not active is refused, not guessed.

        resetAuction()
        s = runDirect("item:1001", { source = "table", raidId = "NAXX" })
        test.eq(#s.sends, 0, "an inactive explicit raid is refused")
        test.eq(s.frame.shown, true, "an inactive explicit raid keeps the dialog open")

        -- --- (12) Every real entry caller now passes the explicit source contract.

        local function fileContains(path, needle)
            local f = assert(io.open(path, "rb"))
            local src = f:read("*a")
            f:close()
            return src:find(needle, 1, true) ~= nil
        end
        test.eq(fileContains("Core/function2.lua", '{ source = "table", raidId = FB }'), true, "table caller passes explicit source")
        test.eq(fileContains("Core/FBUI/FBUIfunction.lua", '{ source = "table", raidId = FB }'), true, "FBUI caller passes explicit source")
        test.eq(fileContains("Core/BiaoGe.lua", '{ source = "chat" }'), true, "chat caller passes source")
        test.eq(fileContains("Core/Module/AuctionMSG.lua", '{ source = "chat" }'), true, "auction-msg caller passes source")
        test.eq(fileContains("Core/Module/Auction.lua", '{ source = "backpack" }'), true, "backpack caller passes source")
        test.eq(fileContains("Core/Module/Loot.lua", '{ source = "loot", raidId = BG.FB1 }'), true, "loot caller passes current raid")
        test.eq(fileContains("Core/Module/AuctionLog.lua", '{ source = "auctionlog", raidId = BG.FB1 }'), true, "auctionlog caller passes current raid")

        -- --- Real caller: backpack container click hook -----------------------

        resetAuction()
        local backpackHook
        for _, entry in ipairs(hookedFuncs) do
            if entry.name == "ContainerFrameItemButton_OnModifiedClick" then
                backpackHook = entry.func
                break
            end
        end
        test.eq(type(backpackHook), "function", "backpack container click hook is registered")
        setGlobal("IsAltKeyDown", function() return true end)
        setGlobal("C_Container", { GetContainerItemLink = function() return "item:2001" end })
        local backpackParent = makeFrame()
        local backpackButton = makeFrame()
        backpackButton.parent = backpackParent
        backpackHook(backpackButton, "RightButton")
        flushZeroTimers()
        test.eq(#sends, 1, "real backpack Alt+right-click direct-starts a unique item")
        test.eq(sends[1].money, 1000, "backpack unique item uses the base price")

        -- --- Real caller: auction-msg chat hyperlink handler ------------------

        resetAuction()
        local msgFrame = BG.FrameAuctionMSG
        test.eq(type(msgFrame), "table", "auction message frame is built")
        local click = msgFrame:GetScript("OnHyperlinkClick")
        test.eq(type(click), "function", "chat hyperlink handler is registered")
        setGlobal("IsAltKeyDown", function() return true end)
        setGlobal("IsShiftKeyDown", function() return false end)
        click(msgFrame, "item:2001", "item:2001", "RightButton")
        flushZeroTimers()
        test.eq(#sends, 1, "real chat Alt+right-click direct-starts a unique item")
        test.eq(sends[1].money, 1000, "chat unique item uses the base price")

        -- --- Real caller: table equipment-list mouse-down handler -------------

        resetAuction()
        setGlobal("IsAltKeyDown", function() return true end)
        setGlobal("IsShiftKeyDown", function() return false end)
        local slot = makeFrame()
        slot.FB = "ULD"
        slot.bossnum = 1
        slot.hopenandu = nil
        slot.i = 1
        BG.SetListzhuangbei(slot)
        local tableButton = BG.ZhuangbeiList and BG.ZhuangbeiList["button1"]
        test.eq(type(tableButton), "table", "table equipment list creates a button")
        test.eq(tableButton.link, "item:1001", "table button resolves its item link")
        local onMouseDown = tableButton:GetScript("OnMouseDown")
        test.eq(type(onMouseDown), "function", "table button registers a real mouse handler")
        onMouseDown(tableButton, "RightButton")
        flushZeroTimers()
        test.eq(#sends, 1, "real table Alt+right-click direct-starts a duplicate item with explicit raid")
        test.eq(sends[1].money, 500, "table caller honors the single-item override")
    end)

    for _, name in ipairs(watchedGlobals) do
        rawset(_G, name, originalValues[name])
    end
    if not ok then
        error(err, 0)
    end
end
