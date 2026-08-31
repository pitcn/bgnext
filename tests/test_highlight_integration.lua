return function(test)
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local toc = read("BGLite.toc")
    local managerAt = toc:find("Core\\BGNext\\HighlightManager.lua", 1, true)
    local engineAt = toc:find("Core\\function2.lua", 1, true)
    test.eq(managerAt ~= nil and engineAt ~= nil and managerAt < engineAt, true,
        "highlight manager loads before the shared UI engine")

    local engine = read("Core/function2.lua")
    test.eq(engine:find("HighlightManager.new", 1, true) ~= nil, true,
        "shared highlight engine constructs the tested manager")
    test.eq(engine:find('highlightManager:getMatches("bag"', 1, true) ~= nil, true,
        "bag highlighting uses the item index")
    test.eq(engine:find('highlightManager:getMatches("table"', 1, true) ~= nil, true,
        "table highlighting uses the item index")
    test.eq(engine:find("local function BagLayoutRevision()", 1, true) ~= nil, true,
        "bag indexes detect dynamically replaced child buttons")
    test.eq(engine:find("BuildBagHighlightIndex, IsVisibleHighlightEntry, BagLayoutRevision", 1, true) ~= nil, true,
        "bag layout validation is connected to indexed lookup")
    test.eq(engine:find("local function TableLayoutRevision()", 1, true) ~= nil, true,
        "table indexes detect dynamically replaced cells")
    test.eq(engine:find("BuildTableHighlightIndex, IsVisibleHighlightEntry, TableLayoutRevision", 1, true) ~= nil, true,
        "table layout validation is connected to indexed lookup")
    test.eq(engine:find("function BG.InvalidateHighlightBagIndex()", 1, true) ~= nil, true,
        "bag index exposes an invalidation hook")
    test.eq(engine:find("function BG.InvalidateHighlightTableIndex()", 1, true) ~= nil, true,
        "table index exposes an invalidation hook")
    test.eq(engine:find("function BG.GetHighlightFrameLabel(frame)", 1, true) ~= nil, true,
        "loaded callers can reuse one label per pooled highlight frame")
    local highlightStart = assert(engine:find("表格/背包高亮对应装备", 1, true))
    local highlightEnd = assert(engine:find("创建按钮模板1", highlightStart, true))
    local highlightBlock = engine:sub(highlightStart, highlightEnd - 1)
    test.eq(highlightBlock:find("SetParent(nil)", 1, true), nil,
        "released highlight frames are never detached with SetParent nil")

    local hooks = read("Core/Module/hooks.lua")
    local onEnterAt = assert(hooks:find("local function OnEnter(self, button)", 1, true))
    local disabledAt = assert(hooks:find('BiaoGe.options["HighOnterItem"] ~= 1', onEnterAt, true))
    local linkReadAt = assert(hooks:find("C_Container.GetContainerItemLink", onEnterAt, true))
    test.eq(disabledAt < linkReadAt, true,
        "disabled bag highlighting returns before reading the item link")
    local onUpdateAt = assert(hooks:find("local function OnUpdate(self, t)", 1, true))
    local delayedGuardAt = assert(hooks:find('BiaoGe.options["HighOnterItem"] ~= 1', onUpdateAt, true))
    local showAt = assert(hooks:find('BG.Show_AllHighlight(link, "bag")', onUpdateAt, true))
    test.eq(delayedGuardAt < showAt, true,
        "the delayed callback rechecks the setting before scanning")

    local auctionLog = read("Core/Module/AuctionLog.lua")
    test.eq(auctionLog:find("BG.GetHighlightFrameLabel(frame)", 1, true) ~= nil, true,
        "auction-log duplicate count reuses the pooled frame label")
    local tableUI = read("Core/FBUI/FBUIfunction.lua")
    test.eq(tableUI:find("BG.GetHighlightFrameLabel(frame)", 1, true) ~= nil, true,
        "table duplicate count reuses the pooled frame label")
    test.eq(tableUI:find("BG.GetHighlightFrameLabel(f)", 1, true) ~= nil, true,
        "table trade marker reuses the pooled frame label")
end
