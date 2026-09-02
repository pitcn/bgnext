BG = BG or {}
BG.BGNext = BG.BGNext or {}

local UITheme = BG.BGNext.UITheme
local M = {}
local registeredButtons = setmetatable({}, { __mode = "k" })

local palettes = {
    normal = {
        id = "normal", fill = "0C2033", border = "24445E", text = "F5B230", alphaLift = 0.14,
    },
    hover = {
        id = "hover", fill = "10314A", border = "2A7896", text = "E8F1F8", alphaLift = 0.32,
    },
    selected = {
        id = "selected", fill = "073044", border = "00E6FF", text = "E8F1F8", alphaLift = 0.30,
    },
    disabled = {
        id = "disabled", fill = "07182A", border = "24445E", text = "8EA6BA", alphaLift = -0.16,
    },
    danger = {
        id = "danger", fill = "2A1018", border = "8F3347", text = "FF8098", alphaLift = 0.20,
    },
}

local function hexRGB(hex)
    return tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255
end

local function boundedAlpha(alpha, lift)
    alpha = UITheme.clampAlpha(alpha)
    return math.max(0, math.min(1, alpha + (lift or 0)))
end

local function fontOf(button)
    if button and type(button.GetFontString) == "function" then
        local ok, font = pcall(button.GetFontString, button)
        if ok then return font end
    end
end

function M.palette(state)
    return palettes[state] or palettes.normal
end

function M.isPreviewEnabled(root)
    return type(root) == "table" and type(root.settings) == "table"
        and root.settings.uiTheme == "preview"
end

function M.applyButton(button, state, alpha)
    if not button or not button.bg then return false end
    local palette = M.palette(state)
    local fillR, fillG, fillB = hexRGB(palette.fill)
    local borderR, borderG, borderB = hexRGB(palette.border)
    local textR, textG, textB = hexRGB(palette.text)
    local ok = pcall(function()
        if type(button.bg.SetColorTexture) == "function" then
            button.bg:SetColorTexture(fillR, fillG, fillB, 1)
        end
        if type(button.bg.SetAlpha) == "function" then
            button.bg:SetAlpha(boundedAlpha(alpha, palette.alphaLift))
        end
        if type(button.SetBackdropBorderColor) == "function" then
            button:SetBackdropBorderColor(borderR, borderG, borderB, 0.95)
        end
        local font = fontOf(button)
        if font and type(font.SetTextColor) == "function" then
            font:SetTextColor(textR, textG, textB, 1)
        end
        button._BGNextVisualState = palette.id
    end)
    return ok
end

function M.setButtonState(button, state, alpha)
    return M.applyButton(button, state, alpha)
end

function M.registerButton(button)
    if not button then return end
    registeredButtons[button] = true
    button._BGNextVisualState = button._BGNextVisualState or "normal"
end

local function makeColor(r, g, b, a)
    if type(CreateColor) == "function" then return CreateColor(r, g, b, a) end
    return { r = r, g = g, b = b, a = a }
end

local function applyClassicButton(button, alpha)
    if not button or not button.bg then return end
    local enabled = true
    if type(button.IsEnabled) == "function" then
        local ok, value = pcall(button.IsEnabled, button)
        if ok then enabled = value end
    end
    if type(button.bg.SetGradient) == "function" then
        if enabled then
            button.bg:SetGradient("VERTICAL", makeColor(0, 0, 0, 0.7), makeColor(0.3, 0.3, 0.3, 0.7))
        else
            button.bg:SetGradient("VERTICAL", makeColor(0, 0, 0, 0.3), makeColor(0.5, 0.5, 0.5, 0.7))
        end
    elseif type(button.bg.SetColorTexture) == "function" then
        button.bg:SetColorTexture(0.01, 0.01, 0.01, 1)
        if type(button.bg.SetAlpha) == "function" then button.bg:SetAlpha(UITheme.clampAlpha(alpha)) end
    end
    if type(button.SetBackdropBorderColor) == "function" then
        button:SetBackdropBorderColor(0, 0, 0, 1)
    end
    local font = fontOf(button)
    if font and type(font.SetTextColor) == "function" then
        if enabled then font:SetTextColor(1, 0.82, 0, 1) else font:SetTextColor(0.5, 0.5, 0.5, 1) end
    end
end

function M.refreshButtons(themeId, alpha)
    for button in pairs(registeredButtons) do
        if themeId == "preview" then
            M.applyButton(button, button._BGNextVisualState or "normal", alpha)
        else
            applyClassicButton(button, alpha)
        end
    end
end

function M.applyNavigationTab(tab, state, alpha)
    return M.applyButton(tab, state, alpha)
end

function M.applySurface(frame, variant, alpha)
    if not frame or type(frame.SetBackdrop) ~= "function" then return false end
    local colors = UITheme.tokens.preview.colors
    local fill = variant == "raised" and colors.raised or colors.surface
    local r, g, b = hexRGB(fill)
    local br, bg, bb = hexRGB(colors.border)
    local ok = pcall(function()
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        if type(frame.SetBackdropColor) == "function" then
            frame:SetBackdropColor(r, g, b, boundedAlpha(alpha, 0))
        end
        if type(frame.SetBackdropBorderColor) == "function" then
            frame:SetBackdropBorderColor(br, bg, bb, 0.72)
        end
    end)
    return ok
end

function M.objectBudget()
    return 4
end

BG.BGNext.UIStyle = M
return M
