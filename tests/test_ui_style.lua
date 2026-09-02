return function(test)
    BG = { BGNext = {} }
    BG.BGNext.UITheme = dofile("Core/BGNext/UITheme.lua")
    local Style = dofile("Core/BGNext/UIStyle.lua")

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local selected = Style.palette("selected")
    test.eq(selected.fill, "073044", "selected fill")
    test.eq(selected.border, "00E6FF", "selected cyan border")
    test.eq(selected.text, "E8F1F8", "selected primary text")
    test.eq(Style.palette("future").id, "normal", "unknown state is normal")
    test.eq(Style.objectBudget(), 4, "price decoration budget is bounded")
    test.eq(Style.textColor("brand"), "00E6FF", "brand text is cyan")
    test.eq(Style.textColor("primary"), "E8F1F8", "primary text is neutral")
    test.eq(Style.textColor("secondary"), "A6B8C8", "secondary text stays readable over the game world")
    test.eq(Style.BOSS_LABEL_FONT_SIZE, 15, "boss labels keep the readable baseline size")
    test.eq(Style.textColor("danger"), "FF8098", "danger text is restrained pink")
    test.eq(Style.textColor("unknown"), "E8F1F8", "unknown text role is primary")
    test.eq(Style.palette("listNormal").borderAlpha < Style.palette("normal").borderAlpha, true,
        "ordinary list rows have a quieter border")
    test.eq(Style.palette("listSelected").border, "00E6FF", "selected list row keeps brand cyan")

    local function fakeButton(enabled)
        local font = { color = {} }
        function font:SetTextColor(r, g, b, a) self.color = { r, g, b, a } end
        local bg = { color = {}, alpha = 1 }
        function bg:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
        function bg:SetAlpha(alpha) self.alpha = alpha end
        local button = { bg = bg, enabled = enabled ~= false, border = {} }
        function button:SetBackdropBorderColor(r, g, b, a) self.border = { r, g, b, a } end
        function button:GetFontString() return font end
        function button:IsEnabled() return self.enabled end
        return button, bg, font
    end

    local button, bg, font = fakeButton(true)
    for _, state in ipairs({ "normal", "hover", "selected", "disabled", "danger", "listNormal", "listSelected" }) do
        test.eq(Style.applyButton(button, state, 0.58), true, state .. " applies")
        local palette = Style.palette(state)
        test.eq(button._BGNextVisualState, state, state .. " records logical state")
        test.eq(bg.alpha, math.min(1, 0.58 + palette.alphaLift), state .. " applies bounded alpha")
        test.eq(button.border[4], palette.borderAlpha, state .. " sets the intended border emphasis")
        test.eq(#font.color, 4, state .. " sets a text color")
    end

    test.eq(Style.setButtonState(button, "selected", 0.58), true, "setButtonState applies")
    local firstColor = table.concat(bg.color, ",") .. ":" .. table.concat(button.border, ",")
    test.eq(Style.setButtonState(button, "selected", 0.58), true, "repeat selected applies")
    test.eq(table.concat(bg.color, ",") .. ":" .. table.concat(button.border, ","), firstColor,
        "repeat selected is idempotent")

    test.eq(Style.isPreviewEnabled({ settings = { uiTheme = "preview" } }), true,
        "preview preference is recognized")
    test.eq(Style.isPreviewEnabled({ settings = { uiTheme = "classic" } }), false,
        "classic preference is recognized")

    local label = { color = {} }
    function label:SetTextColor(r, g, b, a) self.color = { r, g, b, a } end
    Style.registerText(label, "secondary", "00FF00")
    Style.refreshButtons("preview", 0.58)
    test.eq(label.color[3] > label.color[1], true, "preview refresh applies semantic text")
    Style.refreshButtons("classic", 0.58)
    test.eq(label.color[1], 0, "classic refresh restores text red")
    test.eq(label.color[2], 1, "classic refresh restores text green")
    test.eq(label.color[3], 0, "classic refresh restores text blue")

    local previewFont, classicFont = {}, {}
    local utility = {}
    function utility:SetNormalFontObject(value) self.normalFont = value end
    Style.registerUtilityButton(utility, previewFont, classicFont)
    Style.refreshButtons("preview", 0.58)
    test.eq(utility.normalFont, previewFont, "preview refresh applies utility font")
    Style.refreshButtons("classic", 0.58)
    test.eq(utility.normalFont, classicFont, "classic refresh restores utility font")

    local source = read("Core/BGNext/UIStyle.lua")
    for _, token in ipairs({
        "SetPoint", "SetSize", "SetWidth", "SetHeight", "SetParent",
        "SetScript", "HookScript", "OnUpdate", "C_Timer",
        "SendAddonMessage", "SendChatMessage", "BiaoGe.BGNext.settings =",
    }) do
        test.eq(source:find(token, 1, true), nil, "style source forbids " .. token)
    end

    local helpers = read("Core/function2.lua")
    local main = read("Core/BiaoGe.lua")
    test.eq(helpers:find("UIStyle.registerButton(bt)", 1, true) ~= nil, true,
        "shared button factory registers buttons")
    test.eq(helpers:find('UIStyle.setButtonState(bt, "hover"', 1, true) ~= nil, true,
        "shared button hover uses BGNext state")
    test.eq(helpers:find("bt._BGNextVisualState", 1, true) ~= nil, true,
        "shared button leave restores its logical state")
    test.eq(helpers:find("bt.bg:SetGradient", 1, true) ~= nil, true,
        "shared button keeps classic gradient fallback")
    test.eq(helpers:find('t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")', 1, true) ~= nil, true,
        "ordinary shared buttons use the readable 15px size")
    test.eq(main:find("UIStyle.applyNavigationTab", 1, true) ~= nil, true,
        "module navigation delegates preview colors")
    test.eq(main:find('"selected"', 1, true) ~= nil, true,
        "module navigation declares selected state")
    test.eq(main:find('"normal"', 1, true) ~= nil, true,
        "module navigation declares inactive state")
    test.eq(main:find('UIStyle.applyText(t, "secondary")', 1, true) ~= nil, true,
        "top utility text uses the modern secondary hierarchy")
    test.eq(main:find('UIStyle.applyText(t, "primary")', 1, true) ~= nil, true,
        "top utility hover uses primary text")
    test.eq(main:find("UIStyle.registerUtilityButton", 1, true) ~= nil, true,
        "top utility buttons participate in live theme refresh")

    local ledger = read("Core/FBUI/FBUIfunction.lua")
    test.eq(ledger:find("UIStyle.applyText", 1, true) ~= nil, true,
        "ledger boss labels delegate preview semantic colour")
    test.eq(ledger:find("bossLabelRole", 1, true) ~= nil, true,
        "ledger boss labels classify structural roles")
    test.eq(ledger:find("UIStyle.BOSS_LABEL_FONT_SIZE", 1, true) ~= nil, true,
        "ledger boss labels use the shared readable font size")

    BG = nil
end
