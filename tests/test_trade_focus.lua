return function(test)
    local file = assert(io.open("Core/Module/Trade.lua", "rb"))
    local source = file:read("*a")
    file:close()

    local debtStart = assert(source:find("-- 交易欠款输入框", 1, true))
    local debtEnd = assert(source:find("-- 金币超上限", debtStart, true))
    local debtSource = source:sub(debtStart, debtEnd - 1)
    test.eq(debtSource:find('TradeFrame:HookScript("OnHide"', 1, true) ~= nil, true,
        "closing the native trade window has a debt-input focus-release hook")
    test.eq(debtSource:find("edit:ClearFocus()", 1, true) ~= nil, true,
        "trade success, cancel and close all release the debt input through OnHide")
end
