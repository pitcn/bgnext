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
    test.eq(source:find("if BG.IsML then", 1, true) ~= nil, true,
        "leader and master-looter auction completion has a dedicated safe path")
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
    local firstItem, secondItem = editBox("item:123"), editBox("item:123")
    oldBiaoGe, oldBG = BiaoGe, BG
    ok, err = pcall(function()
        BiaoGe = { TEST = { boss1 = {} } }
        BG = {
            playerClass = { class = true },
            Frame = { TEST = { boss1 = {
                zhuangbei1 = firstItem, maijia1 = manualBuyer, jine1 = manualAmount,
                zhuangbei2 = secondItem, maijia2 = emptyBuyer, jine2 = emptyAmount,
            } } },
            GetMaxi = function() return 2 end,
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
    end)
    BiaoGe, BG = oldBiaoGe, oldBG
    if not ok then error(err, 0) end
end
