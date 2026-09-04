return function(test)
    -- Loads the real Core/Module/Auction.lua baseline override plus the real
    -- AuctionPriceStore / AuctionPriceCatalog / AuctionPriceRuntime modules and
    -- drives the actual BG.StartAuction entry with the new explicit options
    -- contract. This proves the Alt+right-click direct-start behaviour end to end:
    -- a leader price preset with an explicit (or provable) raid source enters the
    -- existing auction chain directly at the resolved price, and every direct
    -- start still passes the reused OnClick send closure and its onPreSend gate.
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
        local nowValue = 1000
        local nextAuctionID = 0
        local sends = {}
        local messages = {}

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

        -- --- Load the real modules --------------------------------------------
        -- Store/Catalog/Codec self-register on BG.BGNext and are pure.
        local Store = dofile("Core/BGNext/AuctionPriceStore.lua")
        local Catalog = dofile("Core/BGNext/AuctionPriceCatalog.lua")
        local Codec = dofile("Core/BGNext/AuctionPriceCodec.lua")

        -- Auction.lua registers BG.StartAuction inside an Init callback; the
        -- runtime then wraps it inside its own Init callback (registered later,
        -- so it runs after the original is defined).
        local auctionChunk = assert(loadfile("Core/Module/Auction.lua"))
        auctionChunk("BGNEXT", ns)
        local runtimeChunk = assert(loadfile("Core/BGNext/AuctionPriceRuntime.lua"))
        runtimeChunk("BGNEXT", ns)
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
    end)

    for _, name in ipairs(watchedGlobals) do
        rawset(_G, name, originalValues[name])
    end
    if not ok then
        error(err, 0)
    end
end
