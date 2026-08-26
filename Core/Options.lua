if BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local LibBG         = ns.LibBG
local L             = ns.L

local RR            = ns.RR
local NN            = ns.NN
local RN            = ns.RN
local Size          = ns.Size
local RGB           = ns.RGB
local RGB_16        = ns.RGB_16
local GetClassRGB   = ns.GetClassRGB
local SetClassCFF   = ns.SetClassCFF
local GetText_T     = ns.GetText_T
local AddTexture    = ns.AddTexture
local GetItemID     = ns.GetItemID
local Maxb          = ns.Maxb

local player        = BG.playerName
local realmID       = GetRealmID()

local pt            = print

local O             = {}
ns.O                = O

local IsAddOnLoaded = IsAddOnLoaded or C_AddOns.IsAddOnLoaded

function BG.AddOption(frame, addOn, position)
    local category, layout = Settings.RegisterCanvasLayoutCategory(frame, frame.name, frame.name)
    BG.optionsID = category:GetID()
    Settings.RegisterAddOnCategory(category)
    return category
end

function BG.OpenOption()
    Settings.OpenToCategory(BG.optionsID)
end

BG.optionsName = "BGLite-金团表格纯净版"
BG.Init(function()
    local main = CreateFrame("Frame", nil, UIParent)
    do
        main:Hide()
        main.name = BG.optionsName
        BG.AddOption(main)
        local t = main:CreateFontString()
        t:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
t:SetText("|cff" .. "00BFFF" .. "BGLite-金团表格纯净版" .. "|r")
        t:SetPoint("TOPLEFT", main, 15, 0)
        local top = t
        local t = main:CreateFontString()
        t:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
        t:SetText(L["|cff808080（带*的设置需要重载才能生效）|r"])
        t:SetPoint("BOTTOMLEFT", top, "BOTTOMRIGHT", 5, 0)
        -- 重载
        local rlButton = BG.CreateButton(main)
        rlButton:SetSize(80, 20)
        rlButton:SetPoint("TOPRIGHT", -5, 0)
        rlButton:SetText(L["重载界面"])
        rlButton:SetScript("OnClick", function(self)
            ReloadUI()
        end)
        rlButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
            GameTooltip:ClearLines()
            GameTooltip:AddLine(self:GetText(), 1, 1, 1, true)
            GameTooltip:AddLine(L["不能即时生效的设置在重载后生效。"], 1, .82, 0, true)
            GameTooltip:Show()
        end)
        rlButton:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
        -- 重置配置
        local bt = BG.CreateButton(main)
        bt:SetSize(80, 20)
        bt:SetPoint("RIGHT", rlButton, "LEFT", -10, 0)
        bt:SetText(L["重置配置"])
        bt:SetScript("OnClick", function(self)
            if not StaticPopupDialogs["BiaoGe_ResetOptions"] then
                StaticPopupDialogs["BiaoGe_ResetOptions"] = {
                    text = "重置BGLite插件中你的所有配置文件。",
                    button1 = L["是"],
                    button2 = L["否"],
                    OnAccept = function()
                        BiaoGe = nil
                        ReloadUI()
                    end,
                    OnCancel = function()
                    end,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                    showAlert = true,
                }
            end
            StaticPopup_Show("BiaoGe_ResetOptions")
        end)
        bt:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
            GameTooltip:ClearLines()
            GameTooltip:AddLine(self:GetText(), 1, 1, 1, true)
            GameTooltip:AddLine("重置BGLite插件中你的所有配置文件。", 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        bt:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
    end
    -- 背景框
    do
        local f = CreateFrame("Frame", nil, main, "BackdropTemplate")
        f:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 16,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        f:SetBackdropColor(0, 0, 0, 0.4)
        f:SetPoint("TOPLEFT", SettingsPanel.Container, 5, -60)
        f:SetPoint("BOTTOMRIGHT", SettingsPanel.Container, -5, 0)
        BG.optionsBackground = f
        -- 点空白处取消光标
        SettingsPanel.Container:HookScript("OnMouseDown", function(self, enter)
            local f = GetCurrentKeyBoardFocus()
            if f then
                f:ClearFocus()
            end
        end)
    end

    -- 子选项
    local Frames = {}
    local biaoge, autoAuction, roleOverview, boss, map, others, config
    do
        local last

        function BG.OptionsCreateTab(name, text) -- "Options_biaoge",L["表格"]
            local bt = CreateFrame("Button", "BG.Button" .. name, main)
            bt:SetHeight(25)
            bt:SetNormalFontObject(BG.FontBlue15)
            bt:SetDisabledFontObject(BG.FontWhite18)
            bt:SetHighlightFontObject(BG.FontWhite15)
            local tex = bt:CreateTexture(nil, "ARTWORK") -- 高亮材质
            tex:SetTexture("interface/paperdollinfoframe/ui-character-tab-highlight")
            bt:SetHighlightTexture(tex)
            if not last then
                bt:SetPoint("TOPLEFT", 15, -35)
            else
                bt:SetPoint("LEFT", last, "RIGHT", 0, 0)
            end
            bt:SetText(text)
            local t = bt:GetFontString()
            bt:SetWidth(t:GetStringWidth() + 20)
            BG["Button" .. name] = bt
            last = bt
            bt:SetScript("OnClick", function(self)
                BG.HideTab(Frames, BG["Frame" .. name])
                BiaoGe.options.lastFrame = "Frame" .. name
                BG.PlaySound(1)
            end)

            local f = CreateFrame("Frame", nil, bt)
            tinsert(Frames, f)
            f:Hide()
            BG["Frame" .. name] = f
            local frame = CreateFrame("Frame", nil, f)
            frame:SetSize(1, 1)
            local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
            scroll:SetPoint("TOPLEFT", SettingsPanel.Container, 15, -70)
            scroll:SetPoint("BOTTOMRIGHT", SettingsPanel.Container, -35, 10)
            scroll.ScrollBar.scrollStep = BG.scrollStep
            BG.CreateSrollBarBackdrop(scroll.ScrollBar)
            BG.HookScrollBarShowOrHide(scroll)
            scroll:SetScrollChild(frame)
            frame.scroll = scroll

            return frame
        end

        biaoge = BG.OptionsCreateTab("Options_biaoge", L["表格"])
        autoAuction = BG.OptionsCreateTab("Options_autoAuction", L["自动拍卖"])
        -- Lite: 恢复「其他功能」页（2026-08-24 按 BiaoGe v2.3.5 还原，仅保留有模块支撑的配置项）
        others = BG.OptionsCreateTab("Options_others", L["其他功能"])

        BG.Init2(function()
            if BiaoGe.options.lastFrame and BG[BiaoGe.options.lastFrame] then
                BG[BiaoGe.options.lastFrame]:Show()
                BG[BiaoGe.options.lastFrame]:GetParent():SetEnabled(false)
            else
                BG.FrameOptions_biaoge:Show()
                BG.FrameOptions_biaoge:GetParent():SetEnabled(false)
            end
        end)
    end

    -- 模板
    do
        -- 滑块
        do
            local function updateSliderEditBox(self)
                local slider = self.__owner
                local minValue, maxValue = slider:GetMinMaxValues()
                local text = tonumber(self:GetText())
                if not text then return end
                text = min(maxValue, text)
                text = max(minValue, text)
                slider:SetValue(text)
                self:SetText(text)
                BiaoGe.options[slider.name] = text
                self:ClearFocus()
                BG.PlaySound(1)
            end
            local function OnValueChanged(self, value)
                self.edit:ClearFocus()
                value = tonumber(value)
                BiaoGe.options[self.name] = value
                self.edit:SetText(value)
            end
            local function OnClick(self, enter)
                local slider = self.__owner
                if enter == "RightButton" then
                    if BG.options[slider.name .. "reset"] then
                        local value = BG.options[slider.name .. "reset"]
                        BiaoGe.options[slider.name] = value
                        slider:SetValue(value)
                        slider.edit:SetText(value)
                        BG.PlaySound(1)
                    end
                end
            end
            local function OnEnter(self)
                local slider = self.__owner
                if slider.ontext then
                    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 5)
                    GameTooltip:ClearLines()
                    if type(slider.ontext) == "table" then
                        for i, text in ipairs(slider.ontext) do
                            if i == 1 then
                                GameTooltip:AddLine(text, 1, 1, 1, true)
                            else
                                GameTooltip:AddLine(text, 1, 0.82, 0, true)
                            end
                            GameTooltip:Show()
                        end
                    else
                        GameTooltip:SetText(slider.ontext)
                    end
                end
            end
            local function OnLeave(self)
                GameTooltip:Hide()
            end
            function O.CreateSlider(name, text, parent, minValue, maxValue, step, x, y, ontext, width)
                local savedValue = tonumber(BiaoGe.options[name]) or minValue
                local value = min(maxValue, savedValue)
                value = max(minValue, value)
                BiaoGe.options[name] = value

                local template
                if BG.IsWLK_80 then
                    template = "TextToSpeechSliderTemplate"
                else
                    template = "OptionsSliderTemplate"
                end

                local slider = CreateFrame("Slider", nil, parent, template)
                slider:SetPoint("TOPLEFT", parent, x, y)
                slider:SetWidth(width or 180)
                slider:SetMinMaxValues(minValue, maxValue)
                slider:SetValueStep(step)
                slider:SetObeyStepOnDrag(true)
                slider:SetHitRectInsets(0, 0, 0, 0)
                slider:SetValue(BiaoGe.options[name])
                slider.name = name
                slider.ontext = ontext
                slider:SetScript("OnValueChanged", OnValueChanged)
                if BG.IsTBC then
                    slider.bar = CreateFrame("Frame", nil, slider, "BackdropTemplate")
                    slider.bar:SetBackdrop({
                        bgFile = "Interface/ChatFrame/ChatFrameBackground",
                        edgeFile = "Interface/ChatFrame/ChatFrameBackground",
                        edgeSize = 1,
                    })
                    slider.bar:SetBackdropColor(1, 1, 1, .1)
                    -- slider.bar:SetBackdropColor(.5, .5, .5, .3)
                    slider.bar:SetBackdropBorderColor(0, 0, 0, 1)
                    slider.bar:SetSize(slider:GetWidth(), slider:GetHeight() - 8)
                    slider.bar:SetPoint("CENTER")
                    slider.bar:SetFrameLevel(slider:GetFrameLevel())
                end

                slider.Low:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
                slider.Low:SetText(minValue)
                slider.Low:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 10, -2)
                slider.High:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
                slider.High:SetText(maxValue)
                slider.High:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", -10, -2)
                slider.Text:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
                slider.Text:ClearAllPoints()
                slider.Text:SetPoint("CENTER", 0, 25)
                slider.Text:SetText(text)
                slider.Text:SetTextColor(1, .8, 0)
                slider.Text:SetSize(slider:GetWidth(), 40)

                slider.edit = CreateFrame("EditBox", nil, slider, BG.editTemplate)
                slider.edit:SetSize(50, 20)
                slider.edit:SetPoint("TOP", slider, "BOTTOM")
                slider.edit:SetJustifyH("CENTER")
                slider.edit:SetAutoFocus(false)
                slider.edit:SetText(BiaoGe.options[name])
                slider.edit:SetCursorPosition(0)
                slider.edit.__owner = slider
                slider.edit:SetScript("OnEnterPressed", updateSliderEditBox)
                slider.edit:SetScript("OnEditFocusLost", updateSliderEditBox)

                slider.button = CreateFrame("Button", nil, slider)
                slider.button:SetAllPoints(slider.Text)
                slider.button:RegisterForClicks("RightButtonUp")
                slider.button.__owner = slider
                slider.button:SetScript("OnClick", OnClick)
                slider.button:SetScript("OnEnter", OnEnter)
                slider.button:SetScript("OnLeave", OnLeave)

                return slider
            end
        end
        -- 多选按钮
        do
            local function OnClick(self)
                if self:GetChecked() then
                    BiaoGe.options[self.name] = 1
                else
                    BiaoGe.options[self.name] = 0
                end
                if self.child then
                    for _, f in pairs(self.child) do
                        f:SetShown(self:GetChecked())
                    end
                end
                if self.callback then
                    local func, arg1, arg2, arg3, arg4, arg5 = unpack(self.callback)
                    func(arg1, arg2, arg3, arg4, arg5)
                end
                BG.PlaySound(1)
            end
            local function OnEnter(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
                GameTooltip:ClearLines()
                if type(self.ontext) == "table" then
                    for i, text in ipairs(self.ontext) do
                        if i == 1 then
                            GameTooltip:AddLine(text, 1, 1, 1, true)
                        else
                            GameTooltip:AddLine(text, 1, 0.82, 0, true)
                        end
                        GameTooltip:Show()
                    end
                else
                    GameTooltip:SetText(self.ontext)
                end
            end
            local function OnLeave(self)
                GameTooltip:Hide()
            end
            local function OnShow(self)
                self:SetChecked(BiaoGe.options[self.name] == 1)
            end
            function O.CreateCheckButton(name, text, parent, x, y, ontext, long, callback)
                local bt = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
                bt:SetSize(30, 30)
                bt:SetPoint("TOPLEFT", parent, x, y)
                bt.Text:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                bt.Text:SetText(text)
                bt.Text:SetWordWrap(false)
                bt.Text:SetWidth(min(bt.Text:GetStringWidth() + 20, (type(long) == 'number' and long) or (long and 500 or 160)))
                bt:SetHitRectInsets(0, -bt.Text:GetWidth(), 0, 0)
                bt.name = name
                bt.ontext = ontext
                bt.callback = callback
                BG.options["button" .. name] = bt
                bt:SetChecked(BiaoGe.options[name] == 1)
                bt:SetScript("OnClick", OnClick)
                bt:SetScript("OnEnter", OnEnter)
                bt:SetScript("OnLeave", OnLeave)
                bt:SetScript("OnShow", OnShow)
                return bt
            end
        end
        -- 线
        do
            function O.CreateLine(parent, y, height)
                local l = parent:CreateLine()
                l:SetColorTexture(RGB("808080", 1))
                l:SetStartPoint("TOPLEFT", 5, y)
                l:SetEndPoint("TOPLEFT", SettingsPanel.Container:GetWidth() - 20, y)
                l:SetThickness(height or 1.5)
                return l
            end
        end
        -- 快捷键
        do
            function O.CreateBindKey(parent, x, y, wdith, bindKey, name)
                local bt = BG.CreateButton(parent)
                bt:SetSize(wdith or 150, 25)
                bt:SetPoint("TOPLEFT", x, y)
                bt.bindKey = bindKey
                bt:SetScript("OnClick", function(self)
                    local category
                    for i, v in pairs(SettingsPanel:GetAllCategories()) do
                        if v.name == SETTINGS_KEYBINDINGS_LABEL then
                            category = v
                            break
                        end
                    end
                    if category then
                        SettingsPanel:SelectCategory(category)
                        SettingsPanel.Container.SettingsList.ScrollBox:ScrollToEnd()
                        for _, f in pairs({ SettingsPanel.Container.SettingsList.ScrollBox.ScrollTarget:GetChildren() }) do
                            if f.Button and f.Button.Text and f.Button.Text:GetText() == AddonName then
                                local initializer = f:GetElementData()
                                local data = initializer.data
                                data.expanded = nil;
                                f.Button:Click()
                            end
                        end
                        BG.After(0, function()
                            SettingsPanel.Container.SettingsList.ScrollBox:ScrollToEnd()
                        end)
                    end
                end)
                bt:SetScript("OnShow", function(self)
                    local key1, key2 = GetBindingKey(self.bindKey)
                    if key1 or key2 then
                        bt:SetText(key1 or key2)
                    else
                        bt:SetText(L["无"])
                    end
                end)
                local t = bt:CreateFontString()
                t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                t:SetPoint("BOTTOM", bt, "TOP", 0, 5)
                t:SetText(name)
            end
        end
    end

    local function SetParent(self, key)
        if BiaoGe.options[key] ~= 1 then
            self:Hide()
        end
        local parent = BG.options["button" .. key]
        parent.child = parent.child or {}
        tinsert(parent.child, self)
        if not parent.hookDisable then
            parent.hookDisable = true
            hooksecurefunc(parent, "Disable", function()
                if parent.Text then
                    parent.Text:SetTextColor(.5, .5, .5)
                end
                for i, child in ipairs(parent.child) do
                    child:Hide()
                end
            end)
        end
    end
    --------------------------------------------------------------------------------------------------------------------------------------------------------
    --------------------------------------------------------------------------------------------------------------------------------------------------------
    -- 表格设置
    do
        local height = 0
        local h = 30
        -- UI缩放
        do
            local name = "scale"
            BG.options[name .. "reset"] = 1
            if not BiaoGe.options[name] then
                if BiaoGe.Scale then
                    BiaoGe.options[name] = BiaoGe.Scale
                else
                    BiaoGe.options[name] = BG.options[name .. "reset"]
                end
            end
            BG.MainFrame:SetScale(BiaoGe.options[name])
            BG.ReceiveMainFrame:SetScale(tonumber(BiaoGe.options[name]) * 0.95)

            local ontext = {
                L["表格UI缩放"] .. L["|cff808080（右键还原设置）|r"],
                L["调整表格UI的大小。"],
                -- " ",
                -- L[""],
            }
            local f = O.CreateSlider(name, "|cffFFFFFF" .. L["表格UI缩放"] .. "|r", biaoge, 0.5, 1.5, 0.01, 15, height - h, ontext)
            BG.options["button" .. name] = f

            f:SetScript("OnValueChanged", function(self, value)
                f.edit:ClearFocus()
                value = tonumber(string.format("%.2f", value))
                BiaoGe.options[name] = value
                f.edit:SetText(value)
                BG.MainFrame:SetScale(value)
                BG.ReceiveMainFrame:SetScale(tonumber(value) * 0.95)
            end)
            f.button:SetScript("OnClick", function(self, enter)
                if enter == "RightButton" then
                    if BG.options[name .. "reset"] then
                        local value = BG.options[name .. "reset"]
                        BiaoGe.options[name] = value
                        f:SetValue(value)
                        f.edit:SetText(value)
                        BG.MainFrame:SetScale(value)
                        BG.ReceiveMainFrame:SetScale(tonumber(value) * 0.95)
                        BG.PlaySound(1)
                    end
                end
            end)
        end
        -- 背景材质透明度
        do
            local name = "alpha"
            BG.options[name .. "reset"] = 0.8
            if not BiaoGe.options[name] then
                if BiaoGe.Alpha then
                    BiaoGe.options[name] = BiaoGe.Alpha
                else
                    BiaoGe.options[name] = BG.options[name .. "reset"]
                end
            end
            if type(BiaoGe.options[name]) ~= "number" then
                BiaoGe.options[name] = BG.options[name .. "reset"]
            end

            local ontext = {
                L["背景材质透明度"] .. L["|cff808080（右键还原设置）|r"],
                L["调整背景材质透明度。"],
                -- " ",
                -- L[""],
            }
            local f = O.CreateSlider(name, "|cffFFFFFF" .. L["背景材质透明度"] .. "|r", biaoge, 0, 1, 0.05, 220, height - h, ontext)
            BG.options["button" .. name] = f

            local function UpdateAlpha(alpha)
                BG.MainFrame.Bg:SetAlpha(alpha)
                BG.auctionLogFrame:SetBackdropColor(0, 0, 0, alpha)
                if BG.itemGuoQiFrame then
                    BG.itemGuoQiFrame:SetBackdropColor(0, 0, 0, alpha)
                end
                for _, v in ipairs(BG.tabButtons) do
                    v.button.bg:SetAlpha(alpha)
                end
            end

            f:SetScript("OnValueChanged", function(self, value)
                f.edit:ClearFocus()
                value = tonumber(string.format("%.2f", value))
                BiaoGe.options[name] = value
                f.edit:SetText(value)
                UpdateAlpha(value)
            end)
            f.button:SetScript("OnClick", function(self, enter)
                if enter == "RightButton" then
                    if BG.options[name .. "reset"] then
                        local value = BG.options[name .. "reset"]
                        BiaoGe.options[name] = value
                        f:SetValue(value)
                        f.edit:SetText(value)
                        UpdateAlpha(value)
                        BG.PlaySound(1)
                    end
                end
            end)
        end
        -- 背景材质
        do
            local name = "bg"
            BG.options[name .. "reset"] = "0.01,0.01,0.01,0.8"
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            if BiaoGe.options[name] == "0,0,0,0.8" then
                BiaoGe.options[name] = "0.01,0.01,0.01,0.8"
            end
            BG.Once("options", 250610, function()
                if BiaoGe.options[name] == "Interface/FrameGeneral/UI-Background-Rock" then
                    BiaoGe.options[name] = "0.01,0.01,0.01,0.8"
                    BiaoGe.options["alpha"] = .8
                end
            end)

            local table = {
                { tex = "Interface/FrameGeneral/UI-Background-Rock", name = L["岩石"], alpha = 1 },
                { tex = "Interface/FrameGeneral/UI-Background-Marble", name = L["大理石"], alpha = 1 },
                { tex = "0.01,0.01,0.01,0.8", name = L["黑夜"], },
                { tex = "0,0,0,0", name = L["皇帝的新衣"], },
            }

            local function SetTex(v, setAlpha)
                if strfind(v, "/") or strfind(v, "\\") or not strfind(v, ",") then
                    BG.MainFrame.Bg:SetTexture(v, "REPEAT", "REPEAT")
                    BG.MainFrame.Bg:SetHorizTile(true)
                    BG.MainFrame.Bg:SetVertTile(true)

                    if setAlpha then
                        local a = 1
                        for index, value in ipairs(table) do
                            if v == value.tex then
                                a = value.alpha or 1
                            end
                        end
                        BiaoGe.options["alpha"] = a
                        BG.options["buttonalpha"]:SetValue(BiaoGe.options["alpha"])
                        BG.options["buttonalpha"].edit:SetText(BiaoGe.options["alpha"])
                        BG.MainFrame.Bg:SetAlpha(BiaoGe.options["alpha"])
                    end
                else
                    local r, g, b, a = strsplit(",", v)
                    if not a then a = 0.8 end
                    a = tonumber(a)
                    BG.MainFrame.Bg:SetColorTexture(r, g, b)

                    if setAlpha then
                        BiaoGe.options["alpha"] = a
                        BG.options["buttonalpha"]:SetValue(BiaoGe.options["alpha"])
                        BG.options["buttonalpha"].edit:SetText(BiaoGe.options["alpha"])
                        BG.MainFrame.Bg:SetAlpha(tonumber(BiaoGe.options["alpha"]))
                    end
                end
            end
            local function Settext(text)
                for i, v in ipairs(table) do
                    if v.tex == text then
                        return v.name
                    end
                end
                return ""
            end

            BG.MainFrame.Bg:SetAlpha(BiaoGe.options["alpha"])
            SetTex(BiaoGe.options[name])

            local dropDown = LibBG:Create_UIDropDownMenu(nil, biaoge)
            dropDown:SetPoint("TOPLEFT", 430, height - h)
            LibBG:UIDropDownMenu_SetWidth(dropDown, 120)
            LibBG:UIDropDownMenu_SetText(dropDown, Settext(BiaoGe.options[name]))
            LibBG:UIDropDownMenu_SetAnchor(dropDown, 0, 0, "TOP", dropDown, "BOTTOM")
            BG.dropDownToggle(dropDown)
            BG.options["button" .. name] = dropDown

            local t = dropDown:CreateFontString()
            t:SetPoint("BOTTOM", dropDown, "TOP", 0, 8)
            t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
            t:SetTextColor(1, 1, 1)
            t:SetText(L["背景材质"])

            LibBG:UIDropDownMenu_Initialize(dropDown, function(self, level)
                for i, v in ipairs(table) do
                    local info = LibBG:UIDropDownMenu_CreateInfo()
                    info.text = v.name
                    info.func = function()
                        BiaoGe.options[name] = v.tex
                        SetTex(v.tex, "alpha")
                        LibBG:UIDropDownMenu_SetText(dropDown, v.name)
                    end
                    if v.tex == BiaoGe.options[name] then
                        info.checked = true
                    end
                    LibBG:UIDropDownMenu_AddButton(info)
                end
            end)
        end
        h = h + 60

        O.CreateLine(biaoge, height - h)

        h = h + 40
        -- 快捷键
        do
            O.CreateBindKey(biaoge, 15, -h, nil, "BIAOGE", L["表格快捷键"])
        end
        -- 输入框字号
        do
            local name = "editFontSize"
            BG.options[name .. "reset"] = 14
            local ontext = {
                L["输入框字号"] .. L["|cff808080（右键还原设置）|r"],
                L["BGLite插件大量使用输入框，该选项可以修改其字体大小。"],
            }
            local f = O.CreateSlider(name, "|cffFFFFFF" .. L["输入框字号（需重载）"] .. "|r", biaoge, 10, 20, 1, 220, height - h, ontext)
            BG.options["button" .. name] = f
        end
        -- 字体
        if BG.fontList then
            local name = "font"

            local dropDown = LibBG:Create_UIDropDownMenu(nil, biaoge)
            dropDown:SetPoint("TOPLEFT", 430, height - h)
            LibBG:UIDropDownMenu_SetWidth(dropDown, 120)
            LibBG:UIDropDownMenu_SetText(dropDown, BiaoGe[name])
            LibBG:UIDropDownMenu_SetAnchor(dropDown, 0, 0, "TOP", dropDown, "BOTTOM")
            BG.dropDownToggle(dropDown)
            BG.options["button" .. name] = dropDown

            local t = dropDown:CreateFontString()
            t:SetPoint("BOTTOM", dropDown, "TOP", 0, 8)
            t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
            t:SetTextColor(1, 1, 1)
            t:SetText(L["字体（需重载）"])

            LibBG:UIDropDownMenu_Initialize(dropDown, function(self, level)
                for i, font in ipairs(BG.fontList) do
                    local info = LibBG:UIDropDownMenu_CreateInfo()
                    info.text = font
                    info.arg1 = font
                    info.func = function()
                        BiaoGe[name] = font
                        LibBG:UIDropDownMenu_SetText(dropDown, font)
                    end
                    info.checked = font:lower() == BiaoGe[name]:lower()
                    LibBG:UIDropDownMenu_AddButton(info)
                end
            end)

            local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            f:SetBackdrop({
                bgFile = "Interface/ChatFrame/ChatFrameBackground",
                edgeFile = "Interface/ChatFrame/ChatFrameBackground",
                edgeSize = 1,
            })
            f:SetBackdropColor(0, 0, 0, 0.5)
            f:SetBackdropBorderColor(0, 0, 0, 1)
            f:SetSize(20, 40)
            f.t = f:CreateFontString()
            f.t:SetPoint("CENTER")
            f.t:SetTextColor(1, 1, 1)
            f.t:SetJustifyH("LEFT")
            function f:Update(button, font)
                f:SetParent(button)
                f:ClearAllPoints()
                f:SetPoint("BOTTOMLEFT", button, "TOPRIGHT", 0, 0)
                f.t:SetFont(format("Fonts\\%s", font), 15, "OUTLINE")
                f.t:SetText(font .. L["字体预览\n\nBGLite插件\n1234567890"])
                f:SetWidth(f.t:GetStringWidth() + 10)
                f:SetHeight(f.t:GetStringHeight() + 10)
                f:Show()
            end

            for i = 1, L_UIDROPDOWNMENU_MAXBUTTONS do
                local button = _G["L_DropDownList1Button" .. i]
                button:HookScript("OnEnter", function()
                    if L_DropDownList1.dropdown ~= dropDown then return end
                    if button.arg1 then
                        f:Update(button, button.arg1)
                    end
                end)
                button:HookScript("OnLeave", function()
                    if L_DropDownList1.dropdown ~= dropDown then return end
                    button.isOnEnter = false
                    f:Hide()
                end)
            end
        end
        h = h + 60

        O.CreateLine(biaoge, height - h)

        h = h + 15
        -- 悬浮框
        do
            local name = "mainIcon"
            BG.options[name .. "reset"] = 0
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["显示悬浮框"],
            }
            local f = O.CreateCheckButton(name, AddTexture('QUEST') .. BG.STC_g1(L["显示悬浮框"]), biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            f:HookScript("OnClick", function(self)
                BG.MainIcon:SetShown(self:GetChecked())
            end)
        end
        -- 悬浮框缩放
        do
            local name = "mainIconScale"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            if not tonumber(BiaoGe.options[name]) then
                BiaoGe.options[name] = BG.options[name .. "reset"]
            end
            local ontext = {
                L["悬浮框缩放"] .. L["|cff808080（右键还原设置）|r"],
                L["调整悬浮框UI的大小。"],
            }
            local f = O.CreateSlider(name, "|cffFFFFFF" .. L["悬浮框缩放"] .. "|r", biaoge, 0.5, 1.5, 0.01, 220, height - h - 25, ontext)
            BG.options["button" .. name] = f
            SetParent(f, "mainIcon")

            f:SetScript("OnValueChanged", function(self, value)
                f.edit:ClearFocus()
                value = tonumber(string.format("%.2f", value))
                BiaoGe.options[name] = value
                f.edit:SetText(value)
                BG.MainIcon:SetScale(value)
            end)
            f.button:SetScript("OnClick", function(self, enter)
                if enter == "RightButton" then
                    if BG.options[name .. "reset"] then
                        local value = BG.options[name .. "reset"]
                        BiaoGe.options[name] = value
                        f:SetValue(value)
                        f.edit:SetText(value)
                        BG.MainIcon:SetScale(value)
                        BG.PlaySound(1)
                    end
                end
            end)
        end
        -- 框架层级
        do
            local name = "mainIconFrameLevel"
            BG.options[name .. "reset"] = "HIGH"
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]

            local dropDown = LibBG:Create_UIDropDownMenu(nil, biaoge)
            dropDown:SetPoint("TOPLEFT", 430, height - h - 25)
            LibBG:UIDropDownMenu_SetWidth(dropDown, 120)
            LibBG:UIDropDownMenu_SetText(dropDown, BiaoGe.options[name])
            LibBG:UIDropDownMenu_SetAnchor(dropDown, 0, 0, "TOP", dropDown, "BOTTOM")
            BG.dropDownToggle(dropDown)
            BG.options["button" .. name] = dropDown
            SetParent(dropDown, "mainIcon")

            local t = dropDown:CreateFontString()
            t:SetPoint("BOTTOM", dropDown, "TOP", 0, 8)
            t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
            t:SetTextColor(1, 1, 1)
            t:SetText(L["悬浮框层级"])

            LibBG:UIDropDownMenu_Initialize(dropDown, function(self, level)
                local info = LibBG:UIDropDownMenu_CreateInfo()
                for _, text in ipairs({ "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP", }) do
                    info.text = text
                    info.func = function()
                        BiaoGe.options[name] = text
                        LibBG:UIDropDownMenu_SetText(dropDown, BiaoGe.options[name])
                        if BG.MainIcon then
                            BG.MainIcon:SetFrameStrata(BiaoGe.options[name])
                        end
                    end
                    info.checked = BiaoGe.options[name] == text
                    LibBG:UIDropDownMenu_AddButton(info)
                end
            end)
        end
        h = h + 30
        h = h + 50

        O.CreateLine(biaoge, height - h)

        h = h + 15
        -- 自动记录装备
        do
            local name = "autoLoot"
            BG.options[name .. "reset"] = 1
            if not BiaoGe.options[name] then
                if BiaoGe.AutoLoot then
                    BiaoGe.options[name] = BiaoGe.AutoLoot
                else
                    BiaoGe.options[name] = BG.options[name .. "reset"]
                end
            end
            local ontext = {
                L["自动记录装备"],
                L["在团本里拾取装备时，会自动记录进表格。"],
                " ",
                L["不同的副本，要求的最低品质会不同。大团本一般从紫装开始记录，小团本一般从蓝装开始记录。小怪的掉落会记录到杂项里。"],
            }
            local f = O.CreateCheckButton(name, BG.STC_g1(L["自动记录装备"]), biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            f:HookScript("OnClick", function()
                local name1 = "lootTime"
                local name2 = "lootFontSize"
                local name3 = "autolootNotice"
                local name4 = "autolootRemind"
                if f:GetChecked() then
                    BG.options["button" .. name1]:Show()
                    BG.options["button" .. name2]:Show()
                    BG.options["button" .. name3]:Show()
                    BG.options["button" .. name4]:Show()
                else
                    BG.options["button" .. name1]:Hide()
                    BG.options["button" .. name2]:Hide()
                    BG.options["button" .. name3]:Hide()
                    BG.options["button" .. name4]:Hide()
                end
            end)
        end
        -- 装备记录通知显示时长
        do
            local name = "lootTime"
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["装备记录通知时长"] .. L["|cff808080（右键还原设置）|r"],
                L["自动记录装备后会在屏幕上方通知记录结果。"],
                -- " ",
                -- L[""],
            }
            local f = O.CreateSlider(name, "|cffFFFFFF" .. L["装备记录通知时长(秒)"] .. "*" .. "|r", biaoge, 1, 30, 1, 220, height - h - 25, ontext)
            BG.options["button" .. name] = f
            local name = "autoLoot"
            if BiaoGe.options[name] ~= 1 then
                f:Hide()
            end
        end
        -- 装备记录通知字体大小
        do
            local name = "lootFontSize"
            BG.options[name .. "reset"] = 20
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["装备记录通知字号"] .. L["|cff808080（右键还原设置）|r"],
                L["调整该字体的大小。"],
                -- " ",
                -- L[""],
            }
            local f = O.CreateSlider(name, "|cffFFFFFF" .. L["装备记录通知字号"] .. "|r", biaoge, 10, 30, 1, 425, height - h - 25, ontext)
            BG.options["button" .. name] = f
            f:HookScript("OnValueChanged", function(self, value)
                BG.FrameLootMsg:SetFont(BIAOGE_TEXT_FONT, value, "OUTLINE")
            end)
            local name = "autoLoot"
            if BiaoGe.options[name] ~= 1 then
                f:Hide()
            end
        end
        h = h + 30
        -- 记录装备通知
        do
            local name = "autolootNotice"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["装备记录通知"],
                L["自动记录装备后会在屏幕上方显示记录了什么装备、记录在哪个BOSS槽位。"],
                -- " ",
                -- L[""],
            }
            local f = O.CreateCheckButton(name, L["装备记录通知"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            local name = "autoLoot"
            if BiaoGe.options[name] ~= 1 then
                f:Hide()
            end
        end
        h = h + 30
        -- 未拾取提醒
        do
            local name = "autolootRemind"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["装备未拾取提醒"],
                L["击杀BOSS超过30秒装备还没拾取，且你是物品分配者时，屏幕中间红字提醒。"],
                -- " ",
                -- L[""],
            }
            local f = O.CreateCheckButton(name, L["装备未拾取提醒"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            local name = "autoLoot"
            if BiaoGe.options[name] ~= 1 then
                f:Hide()
            end
        end
        h = h + 40

        O.CreateLine(biaoge, height - h)
        h = h + 15
        -- 交易自动记账
        do
            local name = "autoTrade"
            BG.options[name .. "reset"] = 1
            if not BiaoGe.options[name] then
                if BiaoGe.AutoTrade then
                    BiaoGe.options[name] = BiaoGe.AutoTrade
                else
                    BiaoGe.options[name] = BG.options[name .. "reset"]
                end
            end
            local ontext = {
                L["交易自动记账"],
                L["需要配合自动记录装备，因为如果表格里没有该交易的装备，则记账失败。"],
                " ",
                L["如果一次交易两件装备以上，则只会记第一件装备。"],
            }
            local f = O.CreateCheckButton(name, BG.STC_g1(L["交易自动记账"]), biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
        end
        -- 交易通知显示时长
        do
            local name = "tradeTime"
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["交易通知时长"] .. L["|cff808080（右键还原设置）|r"],
                L["通知显示多久。"],
                -- " ",
                -- L[""],
            }
            local f = O.CreateSlider(name, "|cffFFFFFF" .. L["交易通知时长(秒)"] .. "*" .. "|r", biaoge, 1, 10, 1, 220, height - h - 25, ontext)
            BG.options["button" .. name] = f
            SetParent(f, "autoTrade")
            BG.After(0, function()
                SetParent(f, "tradeNotice")
            end)
        end
        -- 交易通知字体大小
        do
            local name = "tradeFontSize"
            BG.options[name .. "reset"] = 20
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["交易通知字号"] .. L["|cff808080（右键还原设置）|r"],
                L["调整该字体的大小。"],
                -- " ",
                -- L[""],
            }
            local f = O.CreateSlider(name, "|cffFFFFFF" .. L["交易通知字号"] .. "|r", biaoge, 10, 30, 1, 425, height - h - 25, ontext)
            BG.options["button" .. name] = f
            f:HookScript("OnValueChanged", function(self, value)
                BG.FrameTradeMsg:SetFont(BIAOGE_TEXT_FONT, value, "OUTLINE")
            end)
            SetParent(f, "autoTrade")
            BG.After(0, function()
                SetParent(f, "tradeNotice")
            end)
        end
        h = h + 30
        -- 交易通知
        do
            local name = "tradeNotice"
            BG.options[name .. "reset"] = 1
            if not BiaoGe.options[name] then
                if BiaoGe.AutoTrade then
                    BiaoGe.options[name] = BiaoGe.AutoTrade
                else
                    BiaoGe.options[name] = BG.options[name .. "reset"]
                end
            end
            local ontext = {
                L["交易通知"],
                L["交易完成后会在屏幕中央通知本次记账结果。"],
                -- " ",
                -- L[""],
            }
            local f = O.CreateCheckButton(name, L["交易通知"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            f:HookScript("OnClick", function()
                local name1 = "tradeTime"
                local name2 = "tradeFontSize"
                if f:GetChecked() then
                    BG.options["button" .. name1]:Show()
                    BG.options["button" .. name2]:Show()
                else
                    BG.options["button" .. name1]:Hide()
                    BG.options["button" .. name2]:Hide()
                end
            end)
            SetParent(f, "autoTrade")
        end
        h = h + 30
        -- 交易增强
        do
            local name = "tradePreview"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["在交易界面增加以下功能"],
                " ",
                L["记账效果预览框："],
                L["可以预览这次的记账效果。"],
                " ",
                L["最近拍卖/对方已拍："],
                L["如果你是物品分配者，会显示最近拍卖且可交易的装备，点击一下就能把装备放到交易里。"],
                " ",
                L["工资与补贴："],
                L["增加复制工资与补贴的按钮。"],
                " ",
                L["对方欠款记录："],
                L["如果对方曾有欠款，则会在交易框下方显示其欠款记录，点击可以清除欠款。"],
                " ",
                L["重复交易工资提醒："],
                L["如果2分钟内你曾与同一个人交易过相同的金币，会有红字提醒。"],
                " ",
                L["交易金额超上限提醒："],
                format(L["交易时，如果交易金额超过游戏上限（%s金），则会红字提醒。"], BG.tradeGoldTop.topNum),
                " ",
                L["交易后台提醒："],
                L["交易时，如果魔兽世界在后台运行，任务栏图标会闪烁提醒。"],
            }
            local f = O.CreateCheckButton(name, L["交易增强"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            SetParent(f, "autoTrade")
        end
        h = h + 30
        -- 团长是否正在交易
        do
            local name = "isTrading"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["团长是否正在交易"],
                L["在团长的团队框架显示其是否正在交易。"],
                L["支持NDui、ElvUI、Cell、原生框架。"],
            }
            local f = O.CreateCheckButton(name, L["团长是否正在交易"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            SetParent(f, "autoTrade")
        end
        h = h + 30
        -- 禁止NDui插件交易自动打开背包
        do
            local name = "NDuiOpenBag"
            BG.options[name .. "reset"] = 0
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["禁止NDui插件交易时自动打开背包"],
            }
            local f = O.CreateCheckButton(name, AddTexture("QUEST") .. L["禁止NDui插件交易时自动打开背包"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            SetParent(f, "autoTrade")
            local function Set(self)
                if C_AddOns.IsAddOnLoaded("NDui") then
                    local B = unpack(NDui)
                    local module = B:GetModule("Bags")
                    if module and type(module.OpenBags) == "function" then
                        if self:GetChecked() then
                            B:UnregisterEvent("TRADE_SHOW", module.OpenBags)
                        else
                            B:RegisterEvent("TRADE_SHOW", module.OpenBags)
                        end
                    end
                end
            end
            f:HookScript("OnClick", Set)
            BG.Init2(function()
                Set(f)
            end)
        end
        h = h + 40

        O.CreateLine(biaoge, height - h)
        h = h + 15
        -- 高亮拍卖装备
        do
            local name = "auctionHigh"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["高亮拍卖装备"],
                L["当团长或物品分配者贴出装备开始拍卖时，会自动高亮表格里相应的装备。"],
                -- " ",
                -- L[""],
            }
            local f = O.CreateCheckButton(name, BG.STC_g1(L["高亮拍卖装备"]), biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            f:HookScript("OnClick", function()
                local name = "auctionHighTime"
                if f:GetChecked() then
                    BG.options["button" .. name]:Show()
                else
                    BG.options["button" .. name]:Hide()
                end
            end)
        end
        -- 高亮拍卖装备时长
        do
            local name = "auctionHighTime"
            BG.options[name .. "reset"] = 20
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["高亮拍卖装备时长"] .. L["|cff808080（右键还原设置）|r"],
                L["高亮拍卖装备多久。"],
                -- " ",
                -- L[""],
            }
            local f = O.CreateSlider(name, "|cffFFFFFF" .. L["高亮拍卖装备时长(秒)"] .. "|r", biaoge, 1, 60, 1, 220, height - h - 25, ontext)
            BG.options["button" .. name] = f
            local name = "auctionHigh"
            if BiaoGe.options[name] ~= 1 then
                f:Hide()
            end
        end
        h = h + 30
        -- 高亮对应装备
        do
            local name = "HighOnterItem"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["高亮对应装备"],
                L["当鼠标悬停在表格装备时，高亮背包里对应的装备。"],
                " ",
                L["当鼠标悬停在背包装备时，高亮表格里对应的装备。"],
                " ",
                L["当鼠标悬停在聊天框装备时，高亮表格和背包里对应的装备。"],
                " ",
                L["（背包系统支持原生背包、NDui背包、ElvUI背包、大脚背包、Bagnon）"],
            }
            local f = O.CreateCheckButton(name, L["高亮对应装备"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
        end
        h = h + 50

        O.CreateLine(biaoge, height - h)
        h = h + 15
        -- 拍卖聊天记录框
        do
            local name = "auctionChat"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["拍卖聊天记录框"],
                L["自动记录全团跟拍卖有关的聊天。"],
                " ",
                L["当你点击买家或金额时会显示拍卖聊天记录。"],
            }
            local f = O.CreateCheckButton(name, BG.STC_g1(L["拍卖聊天记录框"]), biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            f:HookScript("OnClick", function()
                local name = "auctionChatHoldNew"
                if f:GetChecked() then
                    BG.options["button" .. name]:Show()
                else
                    BG.options["button" .. name]:Hide()
                end
            end)
        end
        h = h + 30
        -- 拍卖聊天记录总是保持在最新位置
        do
            local name = "auctionChatHoldNew"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["拍卖聊天记录总是保持在最新位置"],
                L["每次打开拍卖聊天记录框时，自动回到最新的聊天位置。"],
            }
            local f = O.CreateCheckButton(name, L["拍卖聊天记录总是保持在最新位置"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            local name = "auctionChat"
            if BiaoGe.options[name] ~= 1 then
                f:Hide()
            end
        end
        h = h + 40

        O.CreateLine(biaoge, height - h)
        h = h + 15
        -- 拍卖倒数
        do
            local name = "countDown"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["拍卖自动倒数"],
                L["该功能只有团长或物品分配者可用。"],
                " ",
                L["使用方法：右键聊天框装备时开始倒数。"],
            }
            local f = O.CreateCheckButton(name, BG.STC_g1(L["拍卖自动倒数"]), biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            f:HookScript("OnClick", function()
                local name1 = "countDownDuration"
                local name2 = "countDownSendChannel"
                local name3 = "countDownStop"
                if f:GetChecked() then
                    BG.options["button" .. name1]:Show()
                    BG.options["button" .. name2]:Show()
                    BG.options["button" .. name3]:Show()
                else
                    BG.options["button" .. name1]:Hide()
                    BG.options["button" .. name2]:Hide()
                    BG.options["button" .. name3]:Hide()
                end
            end)
        end
        -- 拍卖倒数时长
        do
            local name = "countDownDuration"
            BG.options[name .. "reset"] = 5
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["拍卖倒数时长"] .. L["|cff808080（右键还原设置）|r"],
                format(L["拍卖装备倒数多久，默认是%s秒。"], BG.options[name .. "reset"]),
                -- " ",
                -- L[""],
            }
            local f = O.CreateSlider(name, "|cffFFFFFF" .. L["拍卖倒数时长(秒)"] .. "|r", biaoge, 1, 20, 1, 220, height - h - 25, ontext)
            BG.options["button" .. name] = f
            if BiaoGe.options["countDown"] ~= 1 then
                f:Hide()
            end
        end
        h = h + 30
        -- 倒数自动暂停
        do
            local name = "countDownStop"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["倒数自动暂停"],
                L["正在自动倒数时，如果有人出价（在团队频道打出纯数字时），则自动暂停倒数。"],
            }
            local f = O.CreateCheckButton(name, L["倒数自动暂停"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            if BiaoGe.options["countDown"] ~= 1 then
                f:Hide()
            end
        end
        h = h + 30
        -- 拍卖倒数通报频道
        do
            local name = "countDownSendChannel"
            BG.options[name .. "reset"] = "RAID"
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]

            local function RaidText(channel)
                local text
                if channel == "RAID_WARNING" then
                    text = L["通报至团队通知频道"]
                elseif channel == "RAID" then
                    text = L["通报至团队频道"]
                end
                return text
            end

            local dropDown = LibBG:Create_UIDropDownMenu(nil, biaoge)
            dropDown:SetPoint("TOPLEFT", 0, height - h - 2)
            LibBG:UIDropDownMenu_SetWidth(dropDown, 170)
            LibBG:UIDropDownMenu_SetText(dropDown, RaidText(BiaoGe.options[name]))
            LibBG:UIDropDownMenu_SetAnchor(dropDown, 0, 0, "TOP", dropDown, "BOTTOM")
            BG.dropDownToggle(dropDown)
            BG.options["button" .. name] = dropDown

            LibBG:UIDropDownMenu_Initialize(dropDown, function(self, level)
                local info = LibBG:UIDropDownMenu_CreateInfo()
                info.text = L["通报至团队通知频道"]
                info.func = function()
                    BiaoGe.options[name] = "RAID_WARNING"
                    LibBG:UIDropDownMenu_SetText(dropDown, RaidText(BiaoGe.options[name]))
                end
                if BiaoGe.options[name] == "RAID_WARNING" then
                    info.checked = true
                end
                LibBG:UIDropDownMenu_AddButton(info)
                local info = LibBG:UIDropDownMenu_CreateInfo()
                info.text = L["通报至团队频道"]
                info.func = function()
                    BiaoGe.options[name] = "RAID"
                    LibBG:UIDropDownMenu_SetText(dropDown, RaidText(BiaoGe.options[name]))
                end
                if BiaoGe.options[name] == "RAID" then
                    info.checked = true
                end
                LibBG:UIDropDownMenu_AddButton(info)
            end)

            if BiaoGe.options["countDown"] ~= 1 then
                dropDown:Hide()
            end
        end
        h = h + 50

        O.CreateLine(biaoge, height - h)
        h = h + 15
        -- 快速记账
        do
            local name = "fastCount"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["快速记账"],
                L["这是一种不用打开表格界面就可以完成记账的方式。"],
                " ",
                L["该功能只有普通团员可用（非团长和物品分配者）。"],
                " ",
                L["使用方法：右键聊天框装备时打开。"],
            }
            local f = O.CreateCheckButton(name, BG.STC_g1(L["快速记账"]), biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            f:HookScript("OnClick", function()
                local name1 = "fastCountMsg"
                local name2 = "fastCountPreview"
                if f:GetChecked() then
                    BG.options["button" .. name1]:Show()
                    BG.options["button" .. name2]:Show()
                else
                    BG.options["button" .. name1]:Hide()
                    BG.options["button" .. name2]:Hide()
                end
            end)
        end
        h = h + 30
        -- 记账通知
        do
            local name = "fastCountMsg"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["记账通知"],
                L["快速记账完成后会在屏幕中央通知本次记账结果。"],
            }
            local f = O.CreateCheckButton(name, L["记账通知"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            local name = "fastCount"
            if BiaoGe.options[name] ~= 1 then
                f:Hide()
            end
        end
        h = h + 30
        -- 记账效果预览框
        do
            local name = "fastCountPreview"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["记账效果预览框"],
                L["快速记账的时候，可以预览这次的记账效果。"],
            }
            local f = O.CreateCheckButton(name, L["记账效果预览框"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            local name = "fastCount"
            if BiaoGe.options[name] ~= 1 then
                f:Hide()
            end
        end
        h = h + 40

        O.CreateLine(biaoge, height - h)
        h = h + 15
        -- 装备过期提醒
        do
            local name = "guoqiRemind"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["装备过期提醒"],
                L["当装备剩余可交易时间低于一定时（默认是低于30分钟），会有语音+文字提醒。每次提醒的最低间隔是5分钟，避免提醒过于频繁。"],
                " ",
                L["该功能只有你是团长或物品分配者时起作用。"],
            }
            local f = O.CreateCheckButton(name, BG.STC_g1(L["装备过期提醒"]), biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            f:HookScript("OnClick", function()
                local name1 = "guoqiRemindMinTime"
                if f:GetChecked() then
                    BG.options["button" .. name1]:Show()
                else
                    BG.options["button" .. name1]:Hide()
                end
            end)
        end
        -- 剩余多少分钟时提醒
        do
            local name = "guoqiRemindMinTime"
            BG.options[name .. "reset"] = 30
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["剩余时间低于多少时提醒"] .. L["|cff808080（右键还原设置）|r"],
                L["当装备剩余可交易时间低于该时间时，会提醒，默认是30分钟。"],
                -- " ",
                -- L[""],
            }
            local f = O.CreateSlider(name, "|cffFFFFFF" .. L["剩余时间低于多少时提醒(分)"] .. "|r", biaoge, 1, 120, 1, 220, height - h - 25, ontext)
            BG.options["button" .. name] = f
            if BiaoGe.options["guoqiRemind"] ~= 1 then
                f:Hide()
            end
        end
        h = h + 80

        O.CreateLine(biaoge, height - h)
        h = h + 15
        -- 进本自动清空表格
        do
            local name = "autoQingKong"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["进本自动清空表格"],
                L["当你进入一个新CD团本时，表格会自动清空。"],
                -- " ",
                -- L[""],
            }
            local f = O.CreateCheckButton(name, L["进本自动清空表格"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            -- 删除旧设置
            if BiaoGe.options["showQingKong"] then
                BiaoGe.options["showQingKong"] = nil
            end
        end
        h = h + 30
        -- 清空表格时保留支出补贴名称
        do
            local name = "retainExpenses"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["清空表格时保留支出补贴名称"],
                L["只保留补贴名称（例如XX补贴）。支出金额正常清空。"],
                " ",
                L["这样就不用每次都重复填写补贴名称。"],
                " ",
                L["只有补贴名称，但没有补贴金额的，在通报账单时不会被通报。"],
            }
            local f = O.CreateCheckButton(name, L["清空表格时保留支出补贴名称"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            f:HookScript("OnClick", function()
                local name = "retainExpensesMoney"
                if f:GetChecked() then
                    BG.options["button" .. name]:Show()
                else
                    BG.options["button" .. name]:Hide()
                end
            end)
        end
        h = h + 30
        -- 清空表格时保留支出金额
        do
            local name = "retainExpensesMoney"
            BG.options[name .. "reset"] = 0
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["清空表格时保留支出金额"],
                L["如果你们团每次支出的金额都是固定的，可以勾选此项。"],
            }
            local f = O.CreateCheckButton(name, L["清空表格时保留支出金额"], biaoge, 40, height - h, ontext)
            BG.options["button" .. name] = f
            if BiaoGe.options["retainExpenses"] ~= 1 then
                f:Hide()
            end
        end
        -- 清空表格时根据副本难度设置分钱人数
        if BG.IsTitan then
            h = h + 30
            do
                local edit

                local name = "QingKongPeople"
                BG.options[name .. "reset"] = 1
                BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
                local ontext = {
                    L["清空表格时自定义分钱人数"],
                    L["表格会按照你设定的人数修改分钱人数。"],
                    -- " ",
                    -- L[""],
                }
                local f = O.CreateCheckButton(name, L["清空表格时自定义分钱人数"], biaoge, 15, height - h, ontext)
                BG.options["button" .. name] = f
                f:HookScript("OnClick", function()
                    if f:GetChecked() then
                        edit:Show()
                    else
                        edit:Hide()
                    end
                end)

                local name2 = "MaxPlayers_Titan"
                BiaoGe.options[name2] = BiaoGe.options[name2] or 25
                edit = CreateFrame("EditBox", nil, f, BG.editTemplate)
                edit:SetSize(50, 20)
                edit:SetPoint("LEFT", f.Text, "RIGHT", 15, 0)
                edit:SetAutoFocus(false)
                edit:SetMaxBytes(8)
                if BiaoGe.options[name] ~= 1 then edit:Hide() end
                BG.SetEditBaseClass(edit)
                edit:SetScript("OnTextChanged", function(self)
                    BiaoGe.options[name2] = tonumber(self:GetText()) or 25
                end)
                edit:SetScript("OnShow", function(self)
                    self:SetText(BiaoGe.options[name2] or 25)
                end)
            end
        elseif not BG.onlyOneHard and not BG.IsRetail then
            h = h + 30
            -- 清空表格时根据副本难度设置分钱人数
            do
                local name = "QingKongPeople"
                BG.options[name .. "reset"] = 1
                if not BiaoGe.options[name] then
                    BiaoGe.options[name] = BG.options[name .. "reset"]
                end
                local ontext = {
                    L["清空表格时根据副本难度设置分钱人数"],
                    L["10人团本默认分钱人数为10人，25人团本默认分钱人数为25人。"],
                    -- " ",
                    -- L[""],
                }
                local f = O.CreateCheckButton(name, L["清空表格时根据副本难度设置分钱人数"], biaoge, 15, height - h, ontext)
                BG.options["button" .. name] = f
                f:HookScript("OnClick", function()
                    local name = "MaxPlayers"
                    if f:GetChecked() then
                        BG.options["button" .. name]:Show()
                    else
                        BG.options["button" .. name]:Hide()
                    end
                end)
            end
            h = h + 30
            -- 分钱人数
            do
                local name = "MaxPlayers"
                local f = CreateFrame("Frame", nil, BG.options.buttonQingKongPeople)
                BG.options["button" .. name] = f
                local name = "QingKongPeople"
                if BiaoGe.options[name] ~= 1 then
                    f:Hide()
                end

                local text = f:CreateFontString()
                text:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                text:SetPoint("TOPLEFT", BG.options.buttonQingKongPeople, "BOTTOMRIGHT", 0, -5)
                text:SetText(L["|cffFFFFFF10人团本分钱人数：|r"])

                local edit = CreateFrame("EditBox", nil, f, BG.editTemplate)
                edit:SetSize(50, 20)
                edit:SetPoint("LEFT", text, "RIGHT", 5, 0)
                edit:SetJustifyH("CENTER")
                edit:SetText(BiaoGe.options["10MaxPlayers"] or "10")
                edit:SetAutoFocus(false)
                BG.SetEditBaseClass(edit)
                edit:SetScript("OnTextChanged", function(self)
                    BiaoGe.options["10MaxPlayers"] = tonumber(self:GetText()) or 10
                end)

                local text = f:CreateFontString()
                text:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                text:SetPoint("LEFT", edit, "RIGHT", 40, 0)
                text:SetText(L["|cffFFFFFF25人团本分钱人数：|r"])

                local edit = CreateFrame("EditBox", nil, f, BG.editTemplate)
                edit:SetSize(50, 20)
                edit:SetPoint("LEFT", text, "RIGHT", 5, 0)
                edit:SetJustifyH("CENTER")
                edit:SetText(BiaoGe.options["25MaxPlayers"] or "25")
                edit:SetAutoFocus(false)
                BG.SetEditBaseClass(edit)
                edit:SetScript("OnTextChanged", function(self)
                    BiaoGe.options["25MaxPlayers"] = tonumber(self:GetText()) or 25
                end)
            end
        end
        h = h + 45

        O.CreateLine(biaoge, height - h)
        h = h + 15
        -- 按键交互声音
        do
            local name = "buttonSound"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["按键交互声音"],
                L["点击按钮时的声音。"],
                -- " ",
                -- L[""],
            }
            local f = O.CreateCheckButton(name, L["按键交互声音"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
        end
        h = h + 30
        -- 语音提醒
        do
            local name = "tipsSound"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["语音提醒"],
                L["在某些情况下，会有语音提醒，比如：装备快过期、拍卖啦、心愿达成、炼金转化已就绪等等。"],
            }
            local f = O.CreateCheckButton(name, L["语音提醒"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            f:HookScript("OnClick", function()
                local name = "Sound"
                if f:GetChecked() then
                    BG.options["button" .. name]:Show()
                else
                    BG.options["button" .. name]:Hide()
                end
            end)
        end
        -- 语音包
        do
            local name = "Sound"

            BG.Once("sound", 250527, function()
                BiaoGe.options.Sound = "AI"
            end)

            BiaoGe.options.Sound = BiaoGe.options.Sound or "AI"

            local function GetName()
                for i, v in ipairs(BG.soundAuthor) do
                    if v.ID == BiaoGe.options.Sound then
                        return v.ID
                    end
                end
            end

            local dropDown = LibBG:Create_UIDropDownMenu(nil, biaoge)
            dropDown:SetPoint("TOPLEFT", 220, height - h + 10)
            LibBG:UIDropDownMenu_SetWidth(dropDown, 120)
            LibBG:UIDropDownMenu_SetAnchor(dropDown, 0, 0, "TOP", dropDown, "BOTTOM")
            BG.dropDownToggle(dropDown)
            BG.options["button" .. name] = dropDown

            local f = CreateFrame("Frame", nil, dropDown, "BackdropTemplate")
            f:SetPoint("BOTTOM", dropDown, "TOP", 0, 8)
            local t = f:CreateFontString()
            t:SetPoint("CENTER")
            t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
            t:SetTextColor(1, 1, 1)
            t:SetText(L["语音包"])
            f:SetSize(t:GetWidth(), t:GetHeight())

            LibBG:UIDropDownMenu_Initialize(dropDown, function(self, level)
                for _, v in ipairs(BG.soundAuthor) do
                    local info = LibBG:UIDropDownMenu_CreateInfo()
                    info.text = v.ID
                    info.func = function()
                        BiaoGe.options[name] = v.ID
                        LibBG:UIDropDownMenu_SetText(dropDown, v.ID)
                    end
                    if v.ID == BiaoGe.options[name] then
                        info.checked = true
                    end
                    LibBG:UIDropDownMenu_AddButton(info)
                end
            end)

            hooksecurefunc(LibBG, "ToggleDropDownMenu", function(_, _, _, dropDown)
                if dropDown == BG.options["button" .. name] then
                    for i = 1, _G['L_DropDownList1'].numButtons do
                        local button = _G["L_DropDownList1Button" .. i]
                        if not button.playSound then
                            local bt = CreateFrame("Button", nil, button)
                            bt:SetSize(20, 20)
                            bt:SetPoint("RIGHT", -2, 0)
                            bt:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ArmoryChat")
                            bt:GetNormalTexture():SetVertexColor(0, 1, 0)
                            bt.num = i
                            bt:Hide()
                            button.playSound = bt
                            bt:SetScript("OnClick", function(self)
                                local index = random(#BG.soundTbl2)
                                PlaySoundFile(BG["sound_" .. BG.soundTbl2[index].ID .. BG.soundAuthor[self.num].ID] .. ".mp3", "Master")
                                PlaySoundFile(BG["sound_" .. BG.soundTbl2[index].ID .. BG.soundAuthor[self.num].ID] .. ".ogg", "Master")
                            end)
                            bt:SetScript("OnEnter", function(self)
                                LibBG:UIDropDownMenu_StopCounting(self:GetParent():GetParent())
                                button.Highlight:Show()
                                bt:GetNormalTexture():SetVertexColor(1, 1, 1)
                            end)
                            bt:SetScript("OnLeave", function(self)
                                LibBG:UIDropDownMenu_StartCounting(self:GetParent():GetParent())
                                button.Highlight:Hide()
                                GameTooltip:Hide()
                                bt:GetNormalTexture():SetVertexColor(0, 1, 0)
                            end)
                        end
                        button.playSound.num = i
                        button.playSound:Show()
                    end
                else
                    for i = 1, L_UIDROPDOWNMENU_MAXBUTTONS do
                        local button = _G["L_DropDownList1Button" .. i]
                        if button.playSound then
                            button.playSound:Hide()
                        end
                    end
                end
            end)

            if BiaoGe.options["tipsSound"] ~= 1 then
                dropDown:Hide()
            end

            BG.Init2(function()
                LibBG:UIDropDownMenu_SetText(dropDown, GetName())
            end)

            -- 已移除「查看教程」按钮与「我想成为语音包作者」说明文字。
            -- 该按钮原本把一个第三方文档平台（腾讯文档）的 URL 填入聊天输入框，
            -- 链接内容不受本插件控制、可随时被改成任意内容，故整块删除。
        end
        h = h + 40

        O.CreateLine(biaoge, height - h)
        h = h + 15
        -- 金额自动加零
        do
            local name = "autoAdd0"
            BG.options[name .. "reset"] = 0
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["金额自动加零"],
                L["输入金额和欠款时自动加两个0，减少记账操作，提高记账效率。"],
                -- " ",
                -- L[""],
            }
            local f = O.CreateCheckButton(name, L["金额自动加零"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
        end

        -- 对账单保存时长(小时)
        do
            local name = "duiZhangTime"
            local ontext = {
                L["对账单保存时长"] .. L["|cff808080（右键还原设置）|r"],
                L["对账单保存多久后自动删除。"],
                -- " ",
                -- L[""],
            }
            local f = O.CreateSlider(name, "|cffFFFFFF" .. L["对账单保存时长(小时)"] .. "|r", biaoge, 1, 168, 1, 220, height - h - 25, ontext)
            BG.options["button" .. name] = f
        end
        h = h + 30

        -- 「自动获取在线人数」选项已随 Core/Module/InfoBar.lua 整模块删除而移除：
        -- 该功能的按钮与实现（BG.ButtonOnLineCount / BG.GetChannelMemberCount）都在 InfoBar 内，
        -- 且原本被 if BG.IsTW then 包裹（BG.IsTW 的条件是 GetCurrentRegion() ~= 5，即非国服），
        -- 国服客户端上本就不生效。留着选项会在设置面板出现一个控制不存在功能的开关。

        -- 支出百分比自动计算
        do
            local name = "zhichuPercent"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]

            local ontext = {
                L["支出百分比计算"],
                L["如果支出项目有百分比符号，则按照百分比自动计算该支出金额。"],
                " ",
                L[ [[比如支出项目为：TN10%，则该支出金额会自动更新为：总收入*10%]] ],
            }
            local f = O.CreateCheckButton(name, L["支出百分比计算"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            f:HookScript("OnClick", function()
                for _, FB in pairs(BG.FBtable) do
                    local b = Maxb[FB] + 1
                    for i = 1, BG.GetMaxi(FB, b) do
                        local zhuangbei = BG.Frame[FB]["boss" .. b]["zhuangbei" .. i]
                        local jine = BG.Frame[FB]["boss" .. b]["jine" .. i]
                        if zhuangbei then
                            BG.UpdateZhiChuPercent(zhuangbei, jine)
                        end
                    end
                end
            end)
        end
        h = h + 30

        -- 数字小键盘
        do
            local name = "NumFrame"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]

            local ontext = {
                L["数字小键盘"],
                L["在可以输入数字的地方，自动显示一个数字小键盘。用鼠标就能完成数字的输入。"],
            }
            local f = O.CreateCheckButton(name, L["数字小键盘"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
        end
        h = h + 30

        -- 显示模型
        do
            local name = "model"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            if BiaoGe.options["model"] ~= 1 then
                for i, model in ipairs(BG.bossModels) do
                    model:Hide()
                end
            end

            local ontext = {
                L["显示BOSS模型"],
                L["在表格里显示BOSS的模型。"],
                -- " ",
                -- L[""],
            }
            local f = O.CreateCheckButton(name, L["显示BOSS模型"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            f:HookScript("OnClick", function()
                if f:GetChecked() then
                    for i, model in ipairs(BG.bossModels) do
                        model:Show()
                    end
                else
                    for i, model in ipairs(BG.bossModels) do
                        model:Hide()
                    end
                end
            end)
        end
        h = h + 30

        -- 自动删除屏蔽团员
        do
            local name = "ignore"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]

            local ontext = {
                L["自动移除屏蔽对象"],
                L["使用自动拍卖时，如果某个团员在你的屏蔽列表里，则自动把它移出该列表。"],
                " ",
                L["这是为了防止你看不到对方的拍卖聊天信息和自动拍卖出价消息。"],
            }
            local f = O.CreateCheckButton(name, L["自动移除屏蔽对象"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
        end
        h = h + 30

        -- 鼠标提示对方的欠款和罚款
        do
            local name = "mouseFK"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]

            local ontext = {
                L["鼠标提示对方的欠款和罚款"],
                L["鼠标悬浮在一个玩家时，显示他的欠款和罚款。"],
            }
            local f = O.CreateCheckButton(name, L["鼠标提示对方的欠款和罚款"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
        end
        h = h + 30

        -- 小地图图标
        do
            local name = "miniMap"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["小地图图标"],
                L["显示小地图图标。"],
                -- " ",
                -- L[""],
            }
            local f = O.CreateCheckButton(name, L["小地图图标"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
            f:HookScript("OnClick", function()
                local icon = LibStub("LibDBIcon-1.0", true)
                if icon then
                    if f:GetChecked() then
                        icon:Show(AddonName)
                    else
                        icon:Hide(AddonName)
                    end
                end
            end)
        end
        h = h + 30

        -- 插件过期提醒
        do
            local name = "addonsOutTime"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]

            local ontext = {
                L["插件过期提醒"],
                L["当插件有可用更新时，红字提醒。"],
            }
            local f = O.CreateCheckButton(name, L["插件过期提醒"], biaoge, 15, height - h, ontext)
            BG.options["button" .. name] = f
        end
    end

    -- 自动拍卖
    do
        local height = 0
        local h = 30
        -- UI缩放
        do
            local name = "autoAuctionScale"
            BG.options[name .. "reset"] = 0.9
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            if not tonumber(BiaoGe.options[name]) then
                BiaoGe.options[name] = BG.options[name .. "reset"]
            end
            local ontext = {
                L["自动拍卖UI缩放"] .. L["|cff808080（右键还原设置）|r"],
                L["调整自动拍卖UI的大小。"],
                -- " ",
                -- L[""],
            }
            local f = O.CreateSlider(name, "|cffFFFFFF" .. L["自动拍卖UI缩放"] .. "|r", autoAuction, 0.5, 1.5, 0.01, 15, height - h, ontext)
            BG.options["button" .. name] = f

            f:SetScript("OnValueChanged", function(self, value)
                f.edit:ClearFocus()
                value = tonumber(string.format("%.2f", value))
                BiaoGe.options[name] = value
                f.edit:SetText(value)
                BGA.AuctionMainFrame:SetScale(value)
            end)
            f.button:SetScript("OnClick", function(self, enter)
                if enter == "RightButton" then
                    if BG.options[name .. "reset"] then
                        local value = BG.options[name .. "reset"]
                        BiaoGe.options[name] = value
                        f:SetValue(value)
                        f.edit:SetText(value)
                        BGA.AuctionMainFrame:SetScale(value)
                        BG.PlaySound(1)
                    end
                end
            end)
        end

        -- UI层级
        do
            local name = "autoAuctionFrameLevel"
            BG.options[name .. "reset"] = "HIGH"
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]

            local dropDown = LibBG:Create_UIDropDownMenu(nil, autoAuction)
            dropDown:SetPoint("TOPLEFT", 220, height - h - 2)
            LibBG:UIDropDownMenu_SetWidth(dropDown, 120)
            LibBG:UIDropDownMenu_SetText(dropDown, BiaoGe.options[name])
            LibBG:UIDropDownMenu_SetAnchor(dropDown, 0, 0, "TOP", dropDown, "BOTTOM")
            BG.dropDownToggle(dropDown)
            BG.options["button" .. name] = dropDown

            local t = dropDown:CreateFontString()
            t:SetPoint("BOTTOM", dropDown, "TOP", 0, 8)
            t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
            t:SetTextColor(1, 1, 1)
            t:SetText(L["UI层级"])

            LibBG:UIDropDownMenu_Initialize(dropDown, function(self, level)
                local info = LibBG:UIDropDownMenu_CreateInfo()
                for _, text in ipairs({ "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP", }) do
                    info.text = text
                    info.func = function()
                        BiaoGe.options[name] = text
                        LibBG:UIDropDownMenu_SetText(dropDown, BiaoGe.options[name])
                        if BGA.AuctionMainFrame then
                            BGA.AuctionMainFrame:SetFrameStrata(BiaoGe.options[name])
                        end
                    end
                    info.checked = BiaoGe.options[name] == text
                    LibBG:UIDropDownMenu_AddButton(info)
                end
            end)
        end

        -- 调试模式
        do
            local mainFrame = BGA.AuctionMainFrame

            local bt = BG.CreateButton(autoAuction)
            bt:SetSize(120, 25)
            bt:SetPoint("TOPLEFT", autoAuction, 420, height - h - 2)
            bt:RegisterForClicks("AnyUp")
            bt:SetScript("OnClick", function(self)
                if IsInRaid(1) then
                    BG.SendSystemMessage(L["只能在非团队状态使用调试模式。"])
                    return
                end
                BG.PlaySound(1)
                if mainFrame.testFrame and mainFrame.testFrame:IsVisible() then
                    mainFrame.testFrame:Hide()
                else
                    if not mainFrame.testFrame then
                        local f = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
                        f:SetBackdrop({
                            bgFile = "Interface/ChatFrame/ChatFrameBackground",
                            edgeFile = "Interface/ChatFrame/ChatFrameBackground",
                            edgeSize = 1,
                        })
                        f:SetBackdropColor(0, 0, 0, 0.8)
                        f:SetBackdropBorderColor(0, 1, 0, 1)
                        f:SetAllPoints()
                        f:SetFrameLevel(mainFrame:GetFrameLevel() - 1)
                        mainFrame.testFrame = f

                        local t = f:CreateFontString()
                        t:SetFont(BIAOGE_TEXT_FONT, 20, "OUTLINE")
                        t:SetPoint("CENTER", f, "CENTER", 0, 0)
                        t:SetTextColor(1, 0.82, 0)
                        t:SetText(L["这是拍卖框架\n你可以通过拖动来改变位置。"])

                        f:SetScript("OnMouseUp", function(self)
                            mainFrame:StopMovingOrSizing()
                            BiaoGe.point.Auction = { mainFrame:GetPoint(1) }
                        end)
                        f:SetScript("OnMouseDown", function(self)
                            mainFrame:StartMoving()
                        end)
                    end
                    mainFrame.testFrame:Show()
                end
                bt:Update()
            end)
            bt:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
                GameTooltip:ClearLines()
                GameTooltip:AddLine(L["调试模式"], 1, 1, 1, true)
                GameTooltip:AddLine(L["你可以在该模式，调整拍卖UI的位置，预览UI缩放和层级效果。只能在非团队状态下使用。"], 1, 0.82, 0, true)
                GameTooltip:Show()
            end)
            bt:SetScript("OnLeave", GameTooltip_Hide)
            bt:SetScript("OnShow", function(self)
                bt:Update()
            end)
            bt:SetScript("OnHide", function(self)
                if mainFrame.testFrame then
                    mainFrame.testFrame:Hide()
                end
                bt:Update()
            end)

            function bt:Update()
                if mainFrame.testFrame and mainFrame.testFrame:IsVisible() then
                    bt:SetText(L["退出调试模式"])
                else
                    bt:SetText(L["进入调试模式"])
                end
            end

            BG.RegisterEvent("GROUP_ROSTER_UPDATE", function()
                BG.After(.5, function()
                    if IsInRaid(1) then
                        if mainFrame.testFrame then
                            mainFrame.testFrame:Hide()
                        end
                    end
                end)
            end)
        end

        h = h + 50

        O.CreateLine(autoAuction, height - h)
        h = h + 20

        -- 团长拍卖面板
        do
            local gens = {
                [1] = L["第一代拍卖"],
                [2] = L["第二代拍卖"],
            }
            local mods = {
                normal = L["常规模式"],
            }

            -- 控制第一代/第二代切换时启用/禁用关联控件
            local modDropDown, modText, resetText, resetEdit
            local function UpdateGen2State()
                local isGen2 = BiaoGe.Auction.gen == 2
                if modDropDown then
                    -- 重建下拉菜单以更新 info.disabled 状态
                    if modDropDown.open then
                        LibBG:CloseDropDownMenus()
                    end
                end
                if resetText then
                    resetText:SetTextColor(isGen2 and 1 or 0.5, isGen2 and 1 or 0.5, isGen2 and 1 or 0.5)
                end
                if resetEdit then
                    if isGen2 then
                        resetEdit:Enable()
                        resetEdit:SetTextColor(1, 1, 1)
                        resetEdit:SetText(BiaoGe.Auction.resetThreshold)
                    else
                        resetEdit:Disable()
                        resetEdit:SetTextColor(0.5, 0.5, 0.5)
                        resetEdit:SetText(20)
                    end
                end
            end

            -- 拍卖版本
            do
                local key = "gen"

                local t = autoAuction:CreateFontString()
                t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                t:SetPoint("TOPLEFT", autoAuction, "TOPLEFT", 15, -h)
                t:SetTextColor(1, 1, 1)
                t:SetText(L["拍卖版本："])

                local dropDown = LibBG:Create_UIDropDownMenu(nil, autoAuction)
                dropDown:SetPoint("LEFT", t, "RIGHT", -10, -2)
                LibBG:UIDropDownMenu_SetWidth(dropDown, 120)
                LibBG:UIDropDownMenu_SetText(dropDown, gens[BiaoGe.Auction[key]])
                LibBG:UIDropDownMenu_SetAnchor(dropDown, 0, 0, "TOP", dropDown, "BOTTOM")
                BG.dropDownToggle(dropDown)

                LibBG:UIDropDownMenu_Initialize(dropDown, function(self, level)
                    for gen, genName in pairs(gens) do
                        local info = LibBG:UIDropDownMenu_CreateInfo()
                        info.text = genName
                        info.arg1 = gen
                        info.func = function()
                            BiaoGe.Auction[key] = gen
                            LibBG:UIDropDownMenu_SetText(dropDown, gens[BiaoGe.Auction[key]])
                            UpdateGen2State()
                        end
                        info.checked = gen == BiaoGe.Auction[key]
                        if gen == 2 then
                            info.tooltipTitle = L['第二代拍卖']
                            info.tooltipText = L['需要团员的BGLite版本高于v2.0.0，否则团员无法看见拍卖框。']
                            info.tooltipOnButton = true
                        end
                        LibBG:UIDropDownMenu_AddButton(info)
                    end
                end)
                dropDown:SetScript('OnShow', function()
                    LibBG:UIDropDownMenu_SetText(dropDown, gens[BiaoGe.Auction[key]])
                    UpdateGen2State()
                end)
            end

            -- 拍卖模式
            do
                local key = "mod"

                local t = autoAuction:CreateFontString()
                t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                t:SetPoint("TOPLEFT", autoAuction, "TOPLEFT", 300, -h)
                t:SetTextColor(1, 1, 1)
                t:SetText(L["拍卖模式："])
                modText = t

                local dropDown = LibBG:Create_UIDropDownMenu(nil, autoAuction)
                dropDown:SetPoint("LEFT", t, "RIGHT", -10, -2)
                LibBG:UIDropDownMenu_SetWidth(dropDown, 120)
                LibBG:UIDropDownMenu_SetText(dropDown, mods[BiaoGe.Auction[key]])
                LibBG:UIDropDownMenu_SetAnchor(dropDown, 0, 0, "TOP", dropDown, "BOTTOM")
                BG.dropDownToggle(dropDown)
                modDropDown = dropDown

                LibBG:UIDropDownMenu_Initialize(dropDown, function(self, level)
                    for modKey, modName in pairs(mods) do
                        local info = LibBG:UIDropDownMenu_CreateInfo()
                        info.text = modName
                        info.arg1 = modKey
                        info.func = function()
                            BiaoGe.Auction[key] = modKey
                            LibBG:UIDropDownMenu_SetText(dropDown, mods[BiaoGe.Auction[key]])
                        end
                        info.checked = modKey == BiaoGe.Auction[key]
                        LibBG:UIDropDownMenu_AddButton(info)
                    end
                end)

                dropDown:SetScript('OnShow', function()
                    LibBG:UIDropDownMenu_SetText(dropDown, mods[BiaoGe.Auction[key]])
                    UpdateGen2State()
                end)
            end
            h = h + 30

            -- 拍卖时长
            do
                local name = "duration"
                local t = autoAuction:CreateFontString()
                t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                t:SetPoint("TOPLEFT", autoAuction, "TOPLEFT", 15, -h)
                t:SetTextColor(1, 1, 1)
                t:SetText(L["拍卖时长："])

                local edit = CreateFrame("EditBox", nil, autoAuction, BG.editTemplate)
                edit:SetSize(60, 20)
                edit:SetPoint("LEFT", t, "RIGHT", 10, 0)
                edit:SetAutoFocus(false)
                edit:SetNumeric(true)
                edit:SetMaxLetters(3)
                BG.SetEditBaseClass(edit, true)
                edit:SetScript("OnTextChanged", function(self)
                    BiaoGe.Auction[name] = self:GetText()
                end)
                edit:SetScript("OnShow", function(self)
                    edit:SetText(BiaoGe.Auction[name])
                end)
            end

            -- 重置阈值
            do
                local name = "resetThreshold"
                local t = autoAuction:CreateFontString()
                t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                t:SetPoint("TOPLEFT", autoAuction, "TOPLEFT", 190, -h)
                t:SetTextColor(1, 1, 1)
                t:SetText(L["重置阈值："])
                resetText = t

                local edit = CreateFrame("EditBox", nil, autoAuction, BG.editTemplate)
                edit:SetSize(60, 20)
                edit:SetPoint("LEFT", t, "RIGHT", 10, 0)
                edit:SetAutoFocus(false)
                edit:SetNumeric(true)
                edit:SetMaxLetters(3)
                BG.SetEditBaseClass(edit, true)
                edit:SetScript("OnTextChanged", function(self)
                    BiaoGe.Auction[name] = self:GetText()
                end)
                edit:SetScript("OnShow", function(self)
                    edit:SetText(BiaoGe.Auction[name])
                end)
                resetEdit = edit
            end

            -- 起拍价
            do
                local name = "money"
                local t = autoAuction:CreateFontString()
                t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                t:SetPoint("TOPLEFT", autoAuction, "TOPLEFT", 380, -h)
                t:SetTextColor(1, 1, 1)
                t:SetText(L["起拍价："])

                local edit = CreateFrame("EditBox", nil, autoAuction, BG.editTemplate)
                edit:SetSize(100, 20)
                edit:SetPoint("LEFT", t, "RIGHT", 10, 0)
                edit:SetAutoFocus(false)
                edit:SetNumeric(true)
                edit:SetMaxLetters(8)
                BG.SetEditBaseClass(edit, true)
                edit:SetScript("OnTextChanged", function(self)
                    BiaoGe.Auction[name] = self:GetText()
                end)
                edit:SetScript("OnShow", function(self)
                    edit:SetText(BiaoGe.Auction[name])
                end)
            end

            -- 初始状态
            UpdateGen2State()
        end
        h = h + 35
        O.CreateLine(autoAuction, height - h)
        h = h + 15
        -- 快速开拍
        do
            local buttons = {}

            local name = "fastMoney"
            BG.options[name .. "reset"] = 1
            BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
            local ontext = {
                L["快速开拍"],
                L["在团长拍卖面板里，增加多个价格按钮，点击后直接按该价格开始拍卖。"],
            }
            local f = O.CreateCheckButton(name, L["快速开拍"], autoAuction, 15, height - h, ontext, true)
            BG.options["button" .. name] = f
            f:HookScript("OnClick", function(self)
                if self:GetChecked() then
                    buttons[1]:Show()
                else
                    buttons[1]:Hide()
                end
            end)

            local function CreateEdit(i)
                local edit = CreateFrame("EditBox", nil, f, BG.editTemplate)
                edit:SetSize(80, 20)
                if i == 1 then
                    edit:SetPoint("TOPLEFT", f, "BOTTOMRIGHT", 5, 0)
                    if BiaoGe.options[name] ~= 1 then edit:Hide() end
                else
                    edit:SetParent(buttons[1])
                    edit:SetPoint("LEFT", buttons[i - 1], "RIGHT", 10, 0)
                end
                edit:SetAutoFocus(false)
                edit:SetNumeric(true)
                edit:SetMaxBytes(8)
                edit.i = i
                tinsert(buttons, edit)
                BG.SetEditBaseClass(edit)
                edit:SetScript("OnTextChanged", function(self)
                    BiaoGe.Auction.fastMoney[i] = tonumber(self:GetText()) or ""
                end)
                edit:SetScript("OnShow", function(self)
                    self:SetText(BiaoGe.Auction.fastMoney[i] or "")
                end)
                edit:HookScript("OnTabPressed", function(self)
                    if buttons[i + 1] then
                        buttons[i + 1]:SetFocus()
                    end
                end)
            end
            for i = 1, #BiaoGe.Auction.fastMoney do
                CreateEdit(i)
            end
        end
        h = h + 30
        h = h + 30
        -- 数据驱动：两列布局创建选项
        do
            local MAX_LEFT_ROWS = 9 -- 左列最大行数，可自行调整
            local RIGHT_COL_X = 320 -- 右列起始X坐标
            local ROW_H = 30        -- 每行高度
            local h_start = h       -- 记录起始h值

            -- ontext 数据表
            local ontextDB = {
                autoAuctionStart         = { L["使用组合键打开拍卖面板"], L["团长或物品分配者ALT+点击背包/表格/聊天框装备，来打开拍卖面板。"] },
                autoAuctionPut           = { L["交易时自动摆放装备"], L["交易时，如果你是物品分配者，会自动把对方所拍装备摆放到交易框。"] },
                autoAuctionMoney         = { L["交易时显示应收或应付金额"], L["交易时，根据对方或你所拍装备显示应收或应付金额。"] },
                autoAuctionQianKuan      = { L["交易时自动记录欠款"], L["交易时，会自动记录欠款。"] },
                autoAuctionSetMoney      = { L["复制应付金额"], L["在交易界面增加一个复制应付金额的按钮。"] },
                autoShowTradeCopyMoney   = { L["自动弹出复制应付金额窗口"], L["交易时，无需点击按钮，复制应付金额的窗口会自动弹出。"] },
                autoAuctionSureClick     = { L["自动点击交易按钮"], L["当交易金额等于应收/应付金额时，自动点击交易按钮。但屏幕中间的二次确认框还是需要你手动确认。"] },
                autoAuctionLogLink       = { L["拍卖成功的聊天消息后面增加[出价记录]"], L["鼠标悬停在[出价记录]时会显示该装备的出价记录。"] },
                autoAuctionHappySay      = { L["竞拍欢呼语"],
        format(L["在竞价过程中，如果有人出价超过%s，有%s概率团长在团队频道发送一段随机的欢呼语，以活跃拍卖氛围。"], BG.autoAuctionHappySay_minMoney or 0, "50%"),
                    " ",
                    L["需要你是团长时才会生效。"],
                },
                autoAuctionAutoEndTips   = { L["拍卖语音提醒"],
                    L["自动出价结束后，语音提醒你，防止你错过装备。"], " ",
                    L["没有使用自动出价时，如果拍卖剩余时间低于10秒时被顶价，语音提醒你\"小心偷家\"。"],
                },
                autoCreateBill           = { L["自动生成表格账单"], L["当一个装备拍卖成功时，会根据拍卖记录，自动填写表格里该装备所对应的买家和金额。"], " ",
                    L["启用该功能时，交易记账会被自动禁用，以免记账冲突。"], " ",
                    L["注意：如果你是团长或物品分配者，该功能不会生效。团长或物品分配者仍会使用更为可靠的交易记账。"] },
                autoAuctionFold          = { L["被过滤的装备自动折叠"], L["启用装备过滤时，如果拍卖的装备不合适你，自动折叠。"] },
                autoAuctionUp            = { L["拍卖竞价窗口自动往上吸附"], L["当靠前的窗口消失时，后面的窗口会自动往上吸附。"] },
                aotoSendLate             = { L["自动出价的延迟时间随机"], L["启用自动出价时，当别人出价后，默认是自己会延迟0.5秒后才自动出价。"], " ",
                    format(L["现在可以修改这个延迟时间，并在一定范围内随机（%s秒-X秒）。X最低为%s秒，最高为%s秒。"], 1, 1, 5) },
                auctionMoveByShift       = { L["锁定拍卖竞价窗口"], L["拍卖竞价窗口默认不可拖动，需要按住SHIFT键才能拖动。"] },
            }

            -- 选项配置表
            local auctionCheckButtons = {
                { name = "autoAuctionStart", default = 1, },
                { name = "autoAuctionPut", default = 1, },
                { name = "autoAuctionMoney", default = 1, },
                { name = "autoAuctionQianKuan", default = 1, x = 40, parent = "autoAuctionMoney" },
                { name = "autoAuctionSetMoney", default = 1, x = 40, parent = "autoAuctionMoney" },
                {
                    name = "autoShowTradeCopyMoney",
                    default = 1,
                    x = 40,
                    parent = "autoAuctionMoney",
                    init = function(f)
                        f:HookScript("OnShow", function(self)
                            f:SetChecked(BiaoGe.options.autoShowTradeCopyMoney == 1)
                        end)
                        BG.Once("autoShowTradeCopyMoney", 260218, function()
                            BiaoGe.options.autoShowTradeCopyMoney = 1
                        end)
                    end
                },
                { name = "autoAuctionSureClick", default = 0, x = 40, parent = "autoAuctionMoney" },
                { name = "autoAuctionLogLink", default = 1, },
                { name = "autoAuctionHappySay", default = 1, condition = function() return not BG.IsTitan end },
                { name = "autoAuctionAutoEndTips", default = 1, },
                { name = "autoCreateBill", default = 1, callback = { BG.UpdateAutoCreateBillButton } },
                { name = "autoAuctionFold", default = 0, isnew = true },
                { name = "autoAuctionUp", default = 0, },
                {
                    name = "aotoSendLate",
                    default = 0,
                    textwidth = 200,
                    init = function(f)
                        f:HookScript("OnClick", function(self)
                            if self:GetChecked() then f.editBox:Show() else f.editBox:Hide() end
                        end)
                        local edit = CreateFrame("EditBox", nil, f, BG.editTemplate)
                        edit:SetSize(50, 20)
                        edit:SetPoint("LEFT", f.Text, "RIGHT", 0, 0)
                        edit:SetAutoFocus(false)
                        edit:SetMaxBytes(8)
                        edit:SetNumeric(true)
                        if BiaoGe.options.aotoSendLate ~= 1 then edit:Hide() end
                        BG.SetEditBaseClass(edit)
                        edit:SetScript("OnTextChanged", function(self)
                            BiaoGe.Auction.aotoSendLate = tonumber(self:GetText()) or ""
                        end)
                        edit:SetScript("OnShow", function(self)
                            self:SetText(BiaoGe.Auction.aotoSendLate or "")
                        end)
                        f.editBox = edit
                    end
                },
                { name = "auctionMoveByShift", default = 0, isnew = true },
            }

            -- 检查条件是否满足
            local function isConditionMet(opt)
                return opt.condition == nil or opt.condition()
            end

            -- 计算子项数量
            local function countChildren(parentName)
                local count = 0
                for _, opt in ipairs(auctionCheckButtons) do
                    if opt.parent == parentName and isConditionMet(opt) then
                        count = count + 1
                    end
                end
                return count
            end

            -- 列分配
            local leftCount, rightCount = 0, 0
            local i = 1
            while i <= #auctionCheckButtons do
                local opt = auctionCheckButtons[i]
                if not isConditionMet(opt) then
                    i = i + 1
                elseif opt.parent then
                    i = i + 1 -- 子项由父项循环一并处理
                else
                    local groupSize = 1 + countChildren(opt.name)
                    if leftCount + groupSize <= MAX_LEFT_ROWS then
                        for j = 0, groupSize - 1 do
                            local item = auctionCheckButtons[i + j]
                            item._col, item._row = 1, leftCount + j
                        end
                        leftCount = leftCount + groupSize
                    else
                        for j = 0, groupSize - 1 do
                            local item = auctionCheckButtons[i + j]
                            item._col, item._row = 2, rightCount + j
                        end
                        rightCount = rightCount + groupSize
                    end
                    i = i + groupSize
                end
            end

            -- 将分配信息复制到子项
            for idx, opt in ipairs(auctionCheckButtons) do
                if opt.parent and not opt._col then
                    local parentOpt
                    for _, p in ipairs(auctionCheckButtons) do
                        if p.name == opt.parent then
                            parentOpt = p; break
                        end
                    end
                    if parentOpt and parentOpt._col then
                        opt._col = parentOpt._col
                        -- 行号需要重新计算：找到该列中该父项后的偏移
                        local offset = 0
                        for j = idx - 1, 1, -1 do
                            local prev = auctionCheckButtons[j]
                            if prev._col == parentOpt._col and prev.parent == opt.parent then
                                offset = offset + 1
                            end
                            if prev.name == opt.parent then break end
                        end
                        opt._row = parentOpt._row + offset + 1
                    end
                end
            end

            -- 两列之间竖线分隔
            do
                local lineX = RIGHT_COL_X - 20
                local lineH = math.max(leftCount, rightCount) * ROW_H
                local l = autoAuction:CreateLine()
                l:SetColorTexture(RGB("808080", 0.6))
                l:SetStartPoint("TOPLEFT", lineX, height - h_start)
                l:SetEndPoint("TOPLEFT", lineX, height - h_start - lineH)
                l:SetThickness(1.5)
            end

            -- 创建选项
            for _, opt in ipairs(auctionCheckButtons) do
                if isConditionMet(opt) then
                    local name = opt.name
                    BG.options[name .. "reset"] = opt.default or 1
                    BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]

                    local colX = (opt._col == 1) and 15 or RIGHT_COL_X
                    local rowY = height - h_start - opt._row * ROW_H

                    -- 计算 ontext（都从 ontextDB 获取）
                    local ontext = ontextDB[name]

                    -- 按钮文本：从 ontextDB 获取标题
                    local buttonText = ontextDB[name][1]
                    if opt.isnew then
                        buttonText = AddTexture("QUEST") .. buttonText
                    end

                    local f = O.CreateCheckButton(name, buttonText, autoAuction, colX + ((opt.x or 15) - 15), rowY, ontext, opt.textwidth or 240, opt.callback)
                    BG.options["button" .. name] = f

                    if opt.parent then
                        SetParent(f, opt.parent)
                    end

                    if opt.init then
                        opt.init(f)
                    end
                end
            end

            -- 更新总高度（取两列中较高的一列）
            h = h_start + math.max(leftCount, rightCount) * ROW_H
        end
    end

    -- 其他功能（2026-08-24 按 BiaoGe v2.3.5 还原：保留分区标题 + 仅保留有模块支撑的配置项）
    -- 未还原（对应模块已删、0 消费者）：查询记录 searchList / 一键指定 zhidingFB / 一键举报 report / 贸易局 commerceAuthorityTooltip / 血月 xueyueAuto / 商品总览 enableShopping
    do
        local width = 15
        local height = -10
        local height_jiange = 22
        local line_height = 4
        local h = 0

        -- 原生功能
        do
            local text = others:CreateFontString()
            text:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
            text:SetPoint("TOPLEFT", width, height)
            text:SetText(BG.STC_g1(L["原生功能"]))
            height = height - height_jiange

            O.CreateLine(others, height + line_height)

            -- 退队/入队玩家上色
            do
                local name = "joinorleavePlayercolor"
                BG.options[name .. "reset"] = 1
                if not BiaoGe.options[name] then
                    BiaoGe.options[name] = BG.options[name .. "reset"]
                end
                local ontext = {
                    L["退队/入队玩家上色"],
                    L["在退队/入队的系统消息里，给该玩家名字加上职业色并设置为链接。"],
                }
                local f = O.CreateCheckButton(name, L["退队/入队玩家上色"], others, 15, height - h, ontext, true)
                BG.options["button" .. name] = f
            end
            -- 一键自动分配
            h = h + 30
            do
                local name = "allLootToMe"
                BG.options[name .. "reset"] = 1
                if not BiaoGe.options[name] then
                    BiaoGe.options[name] = BG.options[name .. "reset"]
                end
                local ontext = {
                    L["队长模式一键分配"],
                    L["队长分配模式时，在战利品界面增加一键分配按钮。"],
                    " ",
                    L["点击按钮后会把全部可交易的物品分配给自己（橙片、任务物品等不会自动分配）。"],
                }

                local f = O.CreateCheckButton(name, L["队长模式一键分配"], others, 15, height - h, ontext, true)
                BG.options["button" .. name] = f

                h = h + 30
                local name = "autoAllLootToMe"
                BG.options[name .. "reset"] = 0
                BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
                local ontext
                ontext = {
                    L["自动点击一键分配"],
                    L["当你打开战利品界面时，自动点击一键分配按钮（等于自动把符合条件的装备全部分配给你，省去你每次点击按钮的动作）。"],
                    " ",
                    L["按下ALT/SHIFT/CTRL时不会自动一键分配。"],
                }
                local f = O.CreateCheckButton(name, L["自动点击一键分配"], others, 40, height - h, ontext, true)
                BG.options["button" .. name] = f
                SetParent(f, "allLootToMe")

                if BG.IsTitan then
                    h = h + 30
                    local name = "autoSetLootNum"
                    BG.options[name .. "reset"] = 1
                    BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
                    local ontext
                    ontext = {
                        L["部分Boss自动切换分配品质"],
                        L["比如进入祖格的疯狂之缘时，自动把分配品质切换为绿色。"],
                    }
                    local f = O.CreateCheckButton(name, L["部分Boss自动切换分配品质"], others, 40, height - h, ontext, true)
                    BG.options["button" .. name] = f
                    SetParent(f, "allLootToMe")
                end
            end

            -- 牌子拾取增强
            if not BG.verLess2 then
                h = h + 30
                local name = "showCurrencyCount"
                BG.options[name .. "reset"] = 1
                if not BiaoGe.options[name] then
                    BiaoGe.options[name] = BG.options[name .. "reset"]
                end
                local ontext = {
                    L["牌子拾取增强"],
                    L["拾取牌子时，增加显示该牌子的现有数量。"],
                    " ",
                    L["拾取牌子时，如果已经达到该牌子的数量上限，播放语音提醒。"],
                    " ",
                    L["在部分物品的提示文本中，增加显示该牌子的数量。比如在熊猫人之怒的正义奖章里，提示正义点数现有数量。"],
                }
                local f = O.CreateCheckButton(name, L["牌子拾取增强"], others, 15, height - h, ontext, true)
                BG.options["button" .. name] = f
            end
            -- 屏蔽发送受限的系统消息
            do
                h = h + 30
                local name = "ERR_CHAT_THROTTLED"
                BG.options[name .. "reset"] = 1
                BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
                local ontext = {
                    L["屏蔽发送受限的系统消息"],
                    L["自动屏蔽该系统消息\"可发送的信息数量受限，请稍候再发送下一条信息。\"。"],
                }
                local f = O.CreateCheckButton(name, L["屏蔽发送受限的系统消息"], others, 15, height - h, ontext, true)
                BG.options["button" .. name] = f
            end
            -- 启用批量邮寄工资
            do
                h = h + 30
                local name = "enableSendMail"
                BG.options[name .. "reset"] = 1
                BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
                local ontext = {
                    L["启用批量邮寄工资"] .. L["（需重载）"],
                }
                local f = O.CreateCheckButton(name, AddTexture('QUEST') .. L["启用批量邮寄工资"] .. L["（需重载）"], others, 15, height - h, ontext, true)
                BG.options["button" .. name] = f
            end
            h = h + 45
        end

        -- 交易记录
        do
            local text = others:CreateFontString()
            text:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
            text:SetPoint("TOPLEFT", width, height - h)
            text:SetText(BG.STC_g1(L["交易记录"]))
            h = h + height_jiange

            O.CreateLine(others, height - h + line_height)
            h = h + 5

            -- 交易成功时语音提醒
            do
                local name = "tradeSuccessSound"
                BG.options[name .. "reset"] = 0
                BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
                local ontext = {
                    L["交易成功时语音提醒"],
                }
                O.CreateCheckButton(name, L["交易成功时语音提醒"], others, 15, height - h, ontext, true)
            end

            h = h + 30

            -- 交易失败时语音提醒
            do
                local name = "tradeFalseSound"
                BG.options[name .. "reset"] = 0
                BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
                local ontext = {
                    L["交易失败时语音提醒"],
                }
                O.CreateCheckButton(name, L["交易失败时语音提醒"], others, 15, height - h, ontext, true)
            end

            h = h + 30

            -- 交易通报
            do
                local name = "tradeMSG"
                BG.options[name .. "reset"] = 0
                BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
                local ontext = {
                    L["交易通报"],
                    L["交易后把结果通报至指定频道。"],
                }
                O.CreateCheckButton(name, L["交易通报"], others, 15, height - h, ontext, true)
            end

            -- 通报频道
            do
                local name = "tradeMSG_channel"
                BG.options[name .. "reset"] = "WHISPER"
                BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
                if BiaoGe.options[name] ~= "WHISPER" and BiaoGe.options[name] ~= "RAID" then
                    BiaoGe.options[name] = BG.options[name .. "reset"]
                end
                local channelTbl = {
                    WHISPER = L["密语"],
                    RAID = RAID,
                }
                local dropDown = LibBG:Create_UIDropDownMenu(nil, others)
                dropDown:SetPoint("TOPLEFT", others, 100, height - h + 1)
                LibBG:UIDropDownMenu_SetWidth(dropDown, 120)
                LibBG:UIDropDownMenu_SetAnchor(dropDown, 0, 0, "TOP", dropDown, "BOTTOM")
                BG.dropDownToggle(dropDown)
                BG.options["button" .. name] = dropDown
                SetParent(dropDown, "tradeMSG")

                local function SetText(key)
                    for k, text in pairs(channelTbl) do
                        if k == key then
                            return L["通报至："] .. text
                        end
                    end
                end
                LibBG:UIDropDownMenu_SetText(dropDown, SetText(BiaoGe.options[name]))

                LibBG:UIDropDownMenu_Initialize(dropDown, function(self, level)
                    for key, text in pairs(channelTbl) do
                        local info = LibBG:UIDropDownMenu_CreateInfo()
                        info.text = L["通报至："] .. text
                        info.func = function()
                            BG.PlaySound(1)
                            BiaoGe.options[name] = key
                            LibBG:UIDropDownMenu_SetText(dropDown, SetText(key))
                        end
                        info.checked = BiaoGe.options[name] == key
                        LibBG:UIDropDownMenu_AddButton(info)
                    end
                end)
            end

            h = h + 30

            -- 交易成功时通报
            do
                local name = "tradeMSG_success"
                BG.options[name .. "reset"] = 1
                BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
                local ontext = {
                    L["交易成功时通报"],
                }
                local f = O.CreateCheckButton(name, L["交易成功时通报"], others, 40, height - h, ontext, true)
                SetParent(f, "tradeMSG")
            end

            h = h + 30

            -- 交易失败时通报
            do
                local name = "tradeMSG_false"
                BG.options[name .. "reset"] = 0
                BiaoGe.options[name] = BiaoGe.options[name] or BG.options[name .. "reset"]
                local ontext = {
                    L["交易失败时通报"],
                }
                local f = O.CreateCheckButton(name, L["交易失败时通报"], others, 40, height - h, ontext, true)
                SetParent(f, "tradeMSG")
            end
            h = h + 45
        end
    end

    end)

-- debug
-- BG.Init2(function(self, event, ...)
--     BG.OpenOption()
-- end)
