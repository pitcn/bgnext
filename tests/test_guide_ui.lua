return function(test)
    BG = { BGNext = {} }
    BG.BGNext.FeatureCatalog = dofile("Core/BGNext/FeatureCatalog.lua")
    BG.BGNext.FeatureSettings = dofile("Core/BGNext/FeatureSettings.lua")
    local guide = dofile("Core/BGNext/GuideUI.lua")

    local root = { settings = {} }
    local sections = guide.sections(root, "titan")
    test.eq(sections[1].id, "quick_start", "quick start is first")
    test.eq(sections[2].id, "personal", "catalog groups follow quick start")
    test.eq(#sections, 5, "guide contains quick start plus four groups")

    local text = {}
    for _, section in ipairs(sections) do
        for _, line in ipairs(section.lines) do text[#text + 1] = line end
    end
    text = table.concat(text, "\n")
    for _, token in ipairs({ "/bgn", "/bgnext", "/bgo", "/bgm", "/bgnqueue", "/bgnq",
        "Ctrl+右键", "Alt+右键", "Shift+右键", "滚轮" }) do
        test.eq(text:find(token, 1, true) ~= nil, true, token .. " appears in the guide")
    end
    test.eq(text:find("完整模式", 1, true) ~= nil, true, "full mode is explained")
    test.eq(text:find("基础模式", 1, true) ~= nil, true, "basic mode is explained")
    test.eq(text:find("不可撤销", 1, true) ~= nil, true, "destructive interaction is warned")

    BG.BGNext.FeatureSettings.setEnabled(root, "wishlist", false)
    local disabledText = {}
    for _, section in ipairs(guide.sections(root, "titan")) do
        for _, line in ipairs(section.lines) do disabledText[#disabledText + 1] = line end
    end
    test.eq(table.concat(disabledText, "\n"):find("已关闭", 1, true) ~= nil, true,
        "disabled features are annotated")
    test.eq(guide.toggle(), false, "toggle is harmless without WoW frame helpers")
end
