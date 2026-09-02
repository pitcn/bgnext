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
    for _, state in ipairs({ "normal", "hover", "selected", "disabled", "danger" }) do
        test.eq(Style.applyButton(button, state, 0.58), true, state .. " applies")
        local palette = Style.palette(state)
        test.eq(button._BGNextVisualState, state, state .. " records logical state")
        test.eq(bg.alpha, math.min(1, 0.58 + palette.alphaLift), state .. " applies bounded alpha")
        test.eq(#button.border, 4, state .. " sets a border color")
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
    test.eq(main:find("UIStyle.applyNavigationTab", 1, true) ~= nil, true,
        "module navigation delegates preview colors")
    test.eq(main:find('"selected"', 1, true) ~= nil, true,
        "module navigation declares selected state")
    test.eq(main:find('"normal"', 1, true) ~= nil, true,
        "module navigation declares inactive state")

    BG = nil
end
