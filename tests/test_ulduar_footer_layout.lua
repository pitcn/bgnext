return function(test)
    local function read(path)
        local f = assert(io.open(path, "rb"))
        local s = f:read("*a"); f:close(); return s
    end
    local db = read("Core/DB/DB.lua")
    local configs = {}
    local declarations = assert(db:match("if BG%.IsTitan then(.-)\n        end"))
    local configEnv = setmetatable({ mainFrameWidth = 1275, mainFrameWidth2 = 1685,
        AddDB = function(id, width, height, columns, maxb, starts, _, _, rows, fold, pay)
            rows[#rows + 1], rows[#rows + 2] = pay or 8, 5
            configs[id] = { width = width, height = height, columns = columns,
                maxb = maxb, starts = starts, rows = rows, fold = fold }
        end }, { __index = _G })
    setfenv(assert(loadstring(declarations)), configEnv)()

    -- Execute real constructors and anchors against virtual WoW UI regions.
    -- Coordinates use a downward Y axis; scripts/chat actions never run.
    local function build(id, foldOverride, fontHeight, wcl)
        local c = configs[id]
        local fold = foldOverride or c.fold
        local function region(parent)
            local r = { parent = parent, width = 0, height = 0, text = "" }
            function r:SetSize(w, h) self.width, self.height = w, h end
            function r:SetWidth(w) self.width = w end
            function r:SetHeight(h) self.height = h end
            function r:SetText(s) self.text = s end
            function r:GetText() return self.text end
            function r:SetFont() self.height = fontHeight end
            function r:CreateFontString() return region(self) end
            function r:CreateTexture() return region(self) end
            function r:SetScrollChild(child) child.parent = self end
            function r:SetPoint(point, relative, relativePoint, x, y)
                if type(relativePoint) == "number" then
                    x, y, relativePoint = relativePoint, x, point
                end
                self.anchor = { point, relative, relativePoint, x or 0, y or 0 }
            end
            function r:rect()
                local a = rawget(self, "anchor")
                if not a then
                    local x, y = 0, 0
                    if rawget(self, "parent") then x, y = self.parent:rect() end
                    return x, y, self.width, self.height
                end
                local x, y, w, h = a[2]:rect()
                local function offset(point, width, height)
                    return point:find("RIGHT") and width or (point:find("LEFT") and 0 or width / 2),
                        point:find("BOTTOM") and height or (point:find("TOP") and 0 or height / 2)
                end
                local rx, ry = offset(a[3], w, h)
                local sx, sy = offset(a[1], self.width, self.height)
                return x + rx + a[4] - sx, y + ry - a[5] - sy, self.width, self.height
            end
            return setmetatable(r, { __index = function() return function() end end })
        end
        local root = region(); root:SetSize(c.width, c.height)
        local bg = { MainFrame = root, FBMainFrame = root, Frame = { p = {}, [id] = {} },
            BossNumtbl = { [id] = c.starts }, zaxiang = { [id] = { i = fold } },
            fakuanIsFirst = {}, Maxi = 40, zhuangbeiWidth = 140, zhuangbeiWidth2 = 240,
            maijiaWidth = 90, jineWidth = 90, DuiZhangProxy = true, hasWCL = wcl,
            BGNext = { BillBuyer = { set = function(w, text) w:SetText(text) end } },
            SetEditStickyFocus = function() end, SetMixin = function() end,
            IsBigFB = function() return true end,
            CreateSrollBarBackdrop = function() end, HookScrollBarShowOrHide = function() end,
            FBDiSeUI = function() end, BossNameUI = function() end,
            FBZhiChuZongLanGongZiUI = function() end, TongBaoButtons = {} }
        local saved = {}
        for b = 1, c.maxb + 2 do
            saved["boss" .. b], bg.Frame[id]["boss" .. b] = {}, {}
        end
        saved.boss14.zhuangbei6 = "existing boss item"
        saved.boss15.zhuangbei56 = "existing misc item"
        saved.boss17.maijia20 = "existing expense buyer"
        local ns = { Maxt = { [id] = c.columns }, Maxb = { [id] = c.maxb } }
        local e = setmetatable({ BG = bg, BiaoGe = { [id] = saved }, ns = ns,
            Maxb = ns.Maxb, Maxt = ns.Maxt, Maxi = { [id] = c.rows },
            L = setmetatable({}, { __index = function(_, key) return key end }),
            RGB = function() return 1, 1, 1 end, tinsert = table.insert,
            CreateFrame = function(_, _, parent)
                local r = region(parent); r.ScrollBar = region(r); return r
            end }, { __index = _G })
        local functions = read("Core/function1.lua")
        local a = assert(functions:find("local function BossNum", 1, true))
        local z = assert(functions:find("\n------------------", a, true))
        setfenv(assert(loadstring(functions:sub(a, z - 1))), e)()
        e.BossNum = ns.BossNum
        a = assert(db:find("function BG.GetMaxi", 1, true))
        z = assert(db:find("\n        end", a, true))
        setfenv(assert(loadstring(db:sub(a, z) .. "        end")), e)()
        local ui = read("Core/FBUI/FBUIfunction.lua")
        local function section(start, stop)
            local first = assert(ui:find(start, 1, true))
            local last = assert(ui:find(stop, first, true))
            return ui:sub(first, last - 1)
        end
        local pieces = {
            "local p = BG.Frame.p; local preWidget; local framedown; local frameright;",
            section("function BG.FBTitleUI", "\n------------------"),
            section("function BG.FBZhuangBeiUI", "    bt.guanzhu =") .. "\nend",
            section("function BG.FBMaiJiaUI", "    bt:SetScript") .. "\nend",
            section("function BG.FBJinEUI", "    local QKButton") .. "\nend",
        }
        setfenv(assert(loadstring(table.concat(pieces, "\n"))), e)()
        setfenv(assert(loadfile("Core/FBUI/CreateFBUI.lua")), e)("BGNext", ns)
        bg.CreateFBUI(id, "FB")
        bg.CreateButton = function(parent) return region(parent) end
        local announcements = read("Core/TongBao/ZhangDan.lua")
        a = assert(announcements:find("function BG.ZhangDanUI", 1, true))
        z = assert(announcements:find("    bt:SetScript", a, true))
        setfenv(assert(loadstring(announcements:sub(a, z - 1) .. "\nreturn bt\nend")), e)()
        local button = bg.ZhangDanUI()
        return bg, c, button, saved
    end

    local function overlaps(a, b, scale)
        local ax, ay, aw, ah = a:rect()
        local bx, by, bw, bh = b:rect()
        return ax * scale < (bx + bw) * scale and bx * scale < (ax + aw) * scale
            and ay * scale < (by + bh) * scale and by * scale < (ay + ah) * scale
    end
    local old, _, oldButton = build("ULDtitan", 33, 18, false)
    test.eq(overlaps(old.FrameULDtitan.scrollFrame18.owner, oldButton, 1), true,
        "0.8.11 reproduces salary viewport blocking the announcement button")

    for _, fontHeight in ipairs({ 15, 18 }) do
        for _, wcl in ipairs({ false, true }) do
            local bg, c, button, saved = build("ULDtitan", nil, fontHeight, wcl)
            local previous = build("ULDtitan", 33, fontHeight, wcl)
            for b = 16, 18 do
                local _, previousTop = previous.FrameULDtitan["scrollFrame" .. b].owner:rect()
                local _, currentTop = bg.FrameULDtitan["scrollFrame" .. b].owner:rect()
                test.eq(math.abs(previousTop - currentTop - 40) < 0.001, true,
                    "fine, expense and summary/salary sections move up 40px")
                for _, scale in ipairs({ 0.5, 0.75, 1 }) do
                    test.eq(overlaps(bg.FrameULDtitan["scrollFrame" .. b].owner, button, scale), false,
                        "settlement viewports leave announcement button clickable")
                end
                local _, top, _, height = bg.FrameULDtitan["scrollFrame" .. b].owner:rect()
                local _, buttonTop = button:rect()
                test.eq(top + height <= buttonTop - 12, true, "settlement leaves a 12px footer gap")
            end
            local _, _, _, miscHeight = bg.Frame.ULDtitan.boss15.zhuangbei56:rect()
            test.eq(miscHeight, 20, "last misc entry is still generated")
            test.eq(saved.boss14.zhuangbei6, "existing boss item", "boss data stays unchanged")
            test.eq(bg.Frame.ULDtitan.boss15.zhuangbei56:GetText(), "existing misc item", "last misc value restores")
            test.eq(saved.boss17.maijia20, "existing expense buyer", "expense data stays unchanged")
            test.eq(bg.GetMaxi("ULDtitan", 16), 40, "all fine entries remain accessible through scrolling")
            test.eq(bg.GetMaxi("ULDtitan", 17), 20, "all expense entries remain accessible through scrolling")
            for b = 1, 15 do
                for i = 1, c.rows[b] do
                    test.eq(overlaps(bg.Frame.ULDtitan["boss" .. b]["zhuangbei" .. i], button, 1), false,
                        "redistributed equipment rows do not block announcement")
                end
            end
        end
    end
    local other, _, otherButton = build("SWtitan", nil, 18, false)
    test.eq(overlaps(other.FrameSWtitan.scrollFrame17.owner, otherButton, 1), false,
        "existing Sunwell settlement remains clear of announcement")
end
