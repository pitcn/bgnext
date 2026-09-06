return function(test)
    local file = assert(io.open("Core/Module/AuctionLog.lua", "rb"))
    local source = file:read("*a")
    file:close()

    local tradeBody = assert(source:match("function BG%.IsAutoCreateBill%(%)(.-)\n%s*end"),
        "BG.IsAutoCreateBill implementation not found")
    local auctionBody = assert(source:match("function BG%.ShouldCreateBillFromAuction%(%)(.-)\n%s*end"),
        "BG.ShouldCreateBillFromAuction implementation not found")
    test.eq(source:find("if BG.ShouldCreateBillFromAuction() then", 1, true) ~= nil, true,
        "auction completion uses the dedicated bill-fill policy")
    test.eq(source:find("local waitForLeaderPurchaseChoice = BG.ImMLorLeader() and SamePlayer(maijia, player)", 1, true) ~= nil, true,
        "leader self-purchases keep the existing paid-or-debt choice")
    test.eq(source:find("if not waitForLeaderPurchaseChoice then", 1, true) ~= nil, true,
        "other successful auctions fill immediately without racing the leader self-purchase dialog")
    test.eq(source:find("BG.FillBillFromAuctionResult(FB, a)", 1, true) ~= nil, true,
        "leader and master-looter auction completion fills only the completed result")
    test.eq(source:find("function BG.FillBillFromAuctionResult", 1, true) ~= nil, true,
        "targeted auction-result bill filler is present")
    local tradeFile = assert(io.open("Core/Module/Trade.lua", "rb"))
    local tradeSource = tradeFile:read("*a")
    tradeFile:close()
    test.eq(tradeSource:find("BG.ShouldCreateBillFromAuction", 1, true), nil,
        "trade accounting remains isolated from auction-result filling")
    local compile = loadstring or load
    local isAutoCreateBill = assert(compile("return function()" .. tradeBody .. "\nend"))()
    local shouldCreateBillFromAuction = assert(compile("return function()" .. auctionBody .. "\nend"))()

    local oldBiaoGe, oldBG = BiaoGe, BG
    local ok, err = pcall(function()
        BiaoGe = { options = { autoCreateBill = 1 } }
        BG = { IsML = true }
        test.eq(shouldCreateBillFromAuction(), true,
            "checked auction result filling remains active for the raid leader/master looter")
        test.eq(isAutoCreateBill(), false,
            "leader trade accounting remains active")

        BG.IsML = nil
        test.eq(shouldCreateBillFromAuction(), true,
            "checked auction result filling remains active for ordinary raid members")
        test.eq(isAutoCreateBill(), true,
            "ordinary member trade accounting remains suppressed to prevent duplicate entries")

        BiaoGe.options.autoCreateBill = 0
        BG.IsML = true
        test.eq(shouldCreateBillFromAuction(), false,
            "unchecked auction result filling remains disabled")
        test.eq(isAutoCreateBill(), false,
            "unchecked ordinary auto-create policy remains disabled")
    end)
    BiaoGe, BG = oldBiaoGe, oldBG
    if not ok then error(err, 0) end

    local helperStart = assert(source:find("            function BG.FillBillFromAuctionResult", 1, true))
    local helperEnd = assert(source:find("\n            function BG.IsAutoCreateBill", helperStart, true))
    local helperSource = source:sub(helperStart, helperEnd - 1)
    local helperFactory = assert(compile([[
        return function(env)
            local Maxb, GetItemID, BillBuyer, GetClassColor =
                env.Maxb, env.GetItemID, env.BillBuyer, env.GetClassColor
    ]] .. helperSource .. [[
            return BG.FillBillFromAuctionResult
        end
    ]]))()

    local function editBox(text)
        return {
            text = text or "",
            GetText = function(self) return self.text end,
            SetText = function(self, value) self.text = value end,
            SetTextColor = function() end,
        }
    end
    local manualBuyer, manualAmount = editBox("手填玩家"), editBox("999")
    local emptyBuyer, emptyAmount = editBox(""), editBox("")
    local nextBuyer, nextAmount = editBox(""), editBox("")
    local firstItem, secondItem, thirdItem = editBox("item:123"), editBox("item:123"), editBox("item:123")
    oldBiaoGe, oldBG = BiaoGe, BG
    ok, err = pcall(function()
        BiaoGe = { TEST = { boss1 = {} } }
        BG = {
            playerClass = { class = true },
            Frame = { TEST = { boss1 = {
                zhuangbei1 = firstItem, maijia1 = manualBuyer, jine1 = manualAmount,
                zhuangbei2 = secondItem, maijia2 = emptyBuyer, jine2 = emptyAmount,
                zhuangbei3 = thirdItem, maijia3 = nextBuyer, jine3 = nextAmount,
            } } },
            GetMaxi = function() return 3 end,
        }
        local fill = helperFactory({
            Maxb = { TEST = 2 },
            GetItemID = function(value) return tonumber(tostring(value):match("item:(%d+)")) end,
            GetClassColor = function() return 1, 1, 1 end,
            BillBuyer = {
                color = function() return 1, 1, 1 end,
                set = function(box, buyer) box:SetText(buyer) end,
            },
        })
        test.eq(fill("TEST", { type = 1, zhuangbei = "item:123", maijia = "成交玩家", jine = 500, class = "MAGE" }), true,
            "targeted auction fill finds the next empty matching row")
        test.eq(manualBuyer:GetText(), "手填玩家", "targeted auction fill preserves an existing buyer")
        test.eq(manualAmount:GetText(), "999", "targeted auction fill preserves an existing amount")
        test.eq(emptyBuyer:GetText(), "成交玩家", "targeted auction fill writes the completed buyer")
        test.eq(emptyAmount:GetText(), 500, "targeted auction fill writes the completed amount")
        test.eq(BiaoGe.TEST.boss1.class2, "MAGE", "targeted auction fill stores player metadata")
        test.eq(fill("TEST", { type = 1, zhuangbei = "item:123", maijia = "第二位买家", jine = 600 }), true,
            "a second sale of the same item finds the next empty row")
        test.eq(nextBuyer:GetText(), "第二位买家", "duplicate items retain independent buyers")
        test.eq(nextAmount:GetText(), 600, "duplicate items retain independent amounts")
    end)
    BiaoGe, BG = oldBiaoGe, oldBG
    if not ok then error(err, 0) end

    -- Exercise the public auction-completion entry point with the item-cache
    -- boundary completing synchronously. A successful auction must be visible
    -- in the bill before the handler returns; it must not depend on a later
    -- timer that can observe a changed raid/table state.
    local completionStart = assert(source:find("        function BG.AuctionWAEnd", 1, true))
    local completionEnd = assert(source:find("\n        end\n    end\n\n    -- 拍卖成功的聊天信息", completionStart, true))
    local completionSource = source:sub(completionStart, completionEnd + #"\n        end" - 1)
    local completionFactory = assert(compile([[
        return function(env)
            local BG, BiaoGe, Item = env.BG, env.BiaoGe, env.Item
            local GetItemID, GetItemInfo = env.GetItemID, env.GetItemInfo
            local tinsert, tremove, time = table.insert, table.remove, env.time
            local player, realmName, PlayerIdentity = env.player, env.realmName, nil
            local function SamePlayer(left, right) return left == right end
            local function DeleteAuctioning() end
            local function MoneyIsError() return false end
            local function GetFB() return "TEST" end
    ]] .. completionSource .. [[
            return BG.AuctionWAEnd
        end
    ]]))()

    local billBuyer, billAmount = "", ""
    local savedAfterFill = false
    local saveCalls = 0
    local delayed = {}
    local flowBG = {
        auctionLogFrame = { auctioning = {} },
        Copy = function(value) return value end,
        playerClass = {},
        ImML = function() return true end,
        UpdateAuctionLogFrame = function() end,
        GN = function() return nil end,
        tradelastAuctionFrame = { frame = { IsVisible = function() return false end } },
        ImMLorLeader = function() return true end,
        SaveRLAuction = function()
            saveCalls = saveCalls + 1
            savedAfterFill = billBuyer == "成交玩家" and billAmount == "500"
        end,
        ShouldCreateBillFromAuction = function() return true end,
        IsML = true,
        FillBillFromAuctionResult = function(_, result)
            billBuyer, billAmount = result.maijia, result.jine
            return true
        end,
        CreateBillByAuctionLog = function() error("full bill rebuild is not required") end,
        After = function(_, callback) delayed[#delayed + 1] = callback end,
    }
    local flowBiaoGe = { TEST = {} }
    local completeAuction = completionFactory({
        BG = flowBG,
        BiaoGe = flowBiaoGe,
        Item = { CreateFromItemID = function()
            return { ContinueOnItemLoad = function(_, callback) callback() end }
        end },
        GetItemID = function() return 123 end,
        GetItemInfo = function() return "item", "item:123", 4, 245, nil, nil, nil, nil, nil, nil, nil, nil, nil, 1 end,
        time = function() return 1 end,
        player = "团长",
        realmName = "测试服",
    })
    completeAuction(1, "item:123", "成交玩家", 500, {})
    test.eq(billBuyer, "成交玩家", "auction completion writes the buyer before returning")
    test.eq(billAmount, "500", "auction completion writes the amount before returning")
    test.eq(savedAfterFill, true, "primary bill write completes before optional leader accounting")
    test.eq(saveCalls, 1, "auction completion invokes leader accounting after the primary write")
    test.eq(#delayed, 0, "auction completion does not defer the primary bill write")

    billBuyer, billAmount, savedAfterFill = "", "", false
    completeAuction(1, "item:123", "团长", 600, {})
    test.eq(billBuyer, "", "leader self-purchase waits for the paid-or-debt choice")
    test.eq(billAmount, "", "leader self-purchase does not prefill an amount before the choice")
    test.eq(saveCalls, 2, "leader self-purchase invokes the paid-or-debt accounting path")
    test.eq(#delayed, 0, "leader self-purchase does not schedule a competing bill write")

    billBuyer, billAmount = "", ""
    flowBG.ImMLorLeader = function() return false end
    completeAuction(1, "item:123", "团长", 700, {})
    test.eq(billBuyer, "团长", "stale cached leader state cannot suppress a self-buyer result")
    test.eq(billAmount, "700", "stale cached leader state cannot leave the amount empty")

    billBuyer, billAmount = "", ""
    flowBG.IsML = nil
    completeAuction(1, "item:123", "普通团员", 800, {})
    test.eq(billBuyer, "普通团员", "ordinary members use the targeted result writer")
    test.eq(billAmount, "800", "ordinary members do not depend on a full bill rebuild")
    test.eq(#delayed, 0, "ordinary-member bill writes are not deferred")
end
