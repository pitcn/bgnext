return function(test)
    BG = { BGNext = {} }
    BG.BGNext.LeaderToolsStore = dofile("Core/BGNext/LeaderToolsStore.lua")
    BG.BGNext.LeaderToolsRuntime = {
        currentSettlementSummary = function() return {} end,
    }
    BG.BGNext.LeaderToolsLayout = dofile("Core/BGNext/LeaderToolsLayout.lua")
    local ui = dofile("Core/BGNext/LeaderToolsUI.lua")
    test.eq(ui.buildWindow(), nil, "UI is harmless outside the game")
    test.eq(ui.installEntry(nil), nil, "entry install needs a real main frame")
    test.eq(ui.toggle(), false, "all opt-in tools disabled means no window")
    for _, method in ipairs({ "setTab", "refreshFeatureState" }) do
        test.eq(type(ui[method]), "function", method .. " is public for feature refresh")
    end
    local frame = { SetScale = function(self, value) self.scale = value end }
    local parent = { GetWidth = function() return 680 end, GetHeight = function() return 470 end }
    local scale = ui.fitToScreen(frame, parent)
    test.eq(scale < 1, true, "window shrinks to fit a narrow UI parent")
    test.eq(frame.scale, scale, "computed scale is applied to the real frame boundary")

    local file = assert(io.open("Core/BGNext/LeaderToolsUI.lua", "rb"))
    local source = file:read("*a")
    file:close()
    test.eq(source:find('frame:SetSize(Layout.WIDTH, Layout.HEIGHT)', 1, true) ~= nil, true,
        "real window consumes the shared logical canvas")
    test.eq(source:find('"UIPanelScrollFrameTemplate"', 1, true) ~= nil, true,
        "auction rows use a native scroll frame")
    test.eq(source:find('panel.body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, geometry.bodyBottom)', 1, true) ~= nil, true,
        "template editor reserves its footer actions")
    test.eq(source:find('panel.text:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, geometry.textBottom)', 1, true) ~= nil, true,
        "settlement text reserves its confirmation footer")
    test.eq(source:find('frame:SetScript("OnHide", function(self)', 1, true) ~= nil, true,
        "closing leader tools has an explicit focus-release lifecycle")
    test.eq(source:find('panels.templates.name', 1, true) ~= nil, true,
        "closing leader tools releases the expense-template name editor")
    test.eq(source:find('panels.history.search', 1, true) ~= nil, true,
        "closing leader tools releases the history filter editor")
end
