return function(test)
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local text = file:read("*a"); file:close(); return text
    end
    local db = read("Core/DB/DB.lua")
    local configs = {}
    -- Execute the real Titan layout declarations, without unrelated login APIs.
    local block = assert(db:match("if BG%.IsTitan then(.-)\n        end"))
    local env = setmetatable({ mainFrameWidth = 1275, mainFrameWidth2 = 1685,
        AddDB = function(id, width, height, columns, maxb, starts, diff, diffIDs, rows, fold, pay)
            configs[id] = { width = width, height = height, columns = columns, maxb = maxb,
                starts = starts, rows = rows, fold = fold, pay = pay }
        end }, { __index = _G })
    setfenv(assert(loadstring(block)), env)()
    local c = configs.ULDtitan
    test.eq(c.columns, 4, "P6 has four display columns")
    test.eq(c.width, 1685, "expanded table uses existing wide frame")
    test.eq(c.rows[15], 56, "misc has capacity for a full raid")
    test.eq(c.fold, 33, "misc folds into 32 and 24 rows to leave room for summary")
    test.eq(c.maxb, 16, "boss/misc/fine identities remain stable")
    test.eq(c.starts[4], 15, "fine/expense/summary move to fourth column")
    -- Existing big-raid widgets use 20px normal rows, 20.1px scroll rows,
    -- 15px first-scroll gap and 13px subsequent gaps. Reserve footer space.
    local rightBottom = 78 + (c.rows[15] - c.fold + 1) * 20
        + 15 + c.rows[16] * 20.1 + 13 + c.pay * 20.1 + 13 + 5 * 20.1
    test.eq(rightBottom <= c.height - 30, true, "final column fits including wages and footer")
    local previous = { 4,4,4,4,5,4,5,5,5,5,5,5,6,6 }
    local required = { 5,4,5,5,6,4,5,5,6,5,6,6,6,6 }
    for b = 1, 14 do
        test.eq(c.rows[b] >= previous[b], true, "never hides an existing boss row")
        test.eq(c.rows[b], required[b], "independent boss capacity requirement")
    end
    test.eq(configs.SWtitan.columns, 3, "P5 layout stays unchanged")
    test.eq(configs.SWtitan.rows[14], 18, "P5 misc capacity stays unchanged")

    -- Clear the actual existing bill keys, including the last new row.
    local data, frame, compare = {}, {}, {}
    local function widget(text)
        return { text = text or "", SetText = function(self, v) self.text = v end,
            GetText = function(self) return self.text end, Hide = function() end }
    end
    for i = 1, 56 do
        for _, key in ipairs({ "zhuangbei", "maijia", "jine", "qiankuan", "guanzhu", "loot", "itemLevel", "bindOnEquip" }) do
            data[key .. i] = key == "jine" and "10" or "existing"
            frame[key .. i] = widget(data[key .. i])
        end
        compare["zhuangbei" .. i], compare["myjine" .. i] = widget("existing"), widget("10")
    end
    local bg = { Maxi = 40, Frame = { ULDtitan = { boss15 = frame } },
        DuiZhangFrame = { ULDtitan = { boss15 = compare } }, playerClass = {},
        GetMaxi = function(_, b) return c.rows[b] or 0 end }
    local e = setmetatable({ BG = bg, BiaoGe = { options = {}, ULDtitan = { boss15 = data } },
        Maxb = { ULDtitan = 16 } }, { __index = _G })
    for b = 1, 16 do
        bg.Frame.ULDtitan["boss" .. b] = bg.Frame.ULDtitan["boss" .. b] or {}
    end
    local ui = read("Core/FBUI/FBUIfunction.lua")
    local incomeStart = assert(ui:find("function BG.GetTotalIncome", 1, true))
    local incomeEnd = assert(ui:find("function BG.GetTotalExpenditure", incomeStart, true))
    setfenv(assert(loadstring(ui:sub(incomeStart, incomeEnd - 1))), e)()
    test.eq(bg.GetTotalIncome("ULDtitan"), 560, "income includes rows 51 through 56")

    -- Execute the real equipment-widget positioning and saved-value restore
    -- prefix. Unrelated mouse handlers are outside this layout regression.
    local widgetStart = assert(ui:find("function BG.FBZhuangBeiUI", 1, true))
    local widgetEnd = assert(ui:find("    bt.guanzhu =", widgetStart, true))
    local anchor = {}
    local layout = { Frame = { ULDtitan = { boss14 = {}, boss15 = {} } },
        zaxiang = { ULDtitan = { i = c.fold } },
        SetEditStickyFocus = function() end, IsBigFB = function() return true end }
    local saved = { boss14 = { zhuangbei6 = "old boss item" }, boss15 = data }
    local le = setmetatable({ BG = layout, BiaoGe = { ULDtitan = saved },
        Maxb = { ULDtitan = 16 }, rightAnchor = anchor,
        BossNum = function(_, b, t) return c.starts[t] + b end,
        CreateFrame = function()
            local w = widget()
            w.SetPoint = function(self, ...) self.point = { ... } end
            w.CreateTexture = function() return { SetPoint = function() end, SetSize = function() end } end
            for _, method in ipairs({ "SetSize", "SetFrameLevel", "SetAutoFocus", "SetCursorPosition" }) do
                w[method] = function() end
            end
            return w
        end }, { __index = _G })
    local prefix = "local p = { preWidget0 = rightAnchor }; local preWidget; local framedown = rightAnchor; local frameright = rightAnchor;\n"
    setfenv(assert(loadstring(prefix .. ui:sub(widgetStart, widgetEnd - 1) .. "\nend")), le)()
    layout.FBZhuangBeiUI("ULDtitan", 3, 1, 2, 6, 6)
    test.eq(layout.Frame.ULDtitan.boss14.zhuangbei6:GetText(), "old boss item", "existing last boss row restores")
    for i = 1, c.rows[15] do
        layout.FBZhuangBeiUI("ULDtitan", 3, 2, 2, i, c.rows[15])
        test.eq(layout.Frame.ULDtitan.boss15["zhuangbei" .. i]:GetText(), "existing", "saved misc rows restore")
    end
    local foldPoint = layout.Frame.ULDtitan.boss15.zhuangbei33.point
    test.eq(foldPoint[2], anchor, "second misc half anchors to the next column")
    test.eq(foldPoint[4], 170, "fold uses existing column offset")
    test.eq(saved.boss14.zhuangbei6, "old boss item", "layout construction preserves old data")
    test.eq(saved.boss15.zhuangbei56, "existing", "layout construction preserves new data")

    local source = read("Core/Module/ClearBiaoGe.lua")
    local a = assert(source:find("    function BG.ClearBiaoGeByIndex", 1, true))
    local z = assert(source:find("    -- Automatic new-lockout cleanup", a, true))
    setfenv(assert(loadstring(source:sub(a, z - 1))), e)()
    bg.ClearBiaoGeByIndex("ULDtitan", 15)
    for i = 1, 56 do
        test.eq(data["zhuangbei" .. i], nil, "all misc item rows are cleared")
        test.eq(data["jine" .. i], nil, "all misc amount rows are cleared")
        test.eq(data["loot" .. i], nil, "all misc loot facts are cleared")
        test.eq(frame["zhuangbei" .. i]:GetText(), "", "new rows clear from visible bill")
    end
end
