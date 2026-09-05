return function(test)
    BG = { BGNext = {} }
    BG.BGNext.LeaderToolsStore = dofile("Core/BGNext/LeaderToolsStore.lua")
    BG.BGNext.LeaderToolsRuntime = {
        currentSettlementSummary = function() return {} end,
    }
    local ui = dofile("Core/BGNext/LeaderToolsUI.lua")
    test.eq(ui.buildWindow(), nil, "UI is harmless outside the game")
    test.eq(ui.installEntry(nil), nil, "entry install needs a real main frame")
    test.eq(ui.toggle(), false, "all opt-in tools disabled means no window")
    for _, method in ipairs({ "setTab", "refreshFeatureState" }) do
        test.eq(type(ui[method]), "function", method .. " is public for feature refresh")
    end
end
