local test = require("tests.testlib")

return function()
    BG = { BGNext = {} }
    dofile("Core/BGNext/BillBuyer.lua")

    local savedColor
    local editBox = { color = { 1, 1, 1 } }
    function editBox:SetTextColor(r, g, b) self.color = { r, g, b } end
    function editBox:GetTextColor() return self.color[1], self.color[2], self.color[3] end
    function editBox:SetText(value)
        self.text = value
        savedColor = { self:GetTextColor() }
    end
    function editBox:SetCursorPosition(value) self.cursor = value end

    BG.BGNext.BillBuyer.set(editBox, "测试玩家", 0.2, 0.4, 0.8)
    test.eq(editBox.text, "测试玩家", "buyer name is written")
    test.eq(savedColor[1], 0.2, "class color is active when OnTextChanged persists the buyer")
    test.eq(savedColor[2], 0.4, "green class channel is persisted")
    test.eq(savedColor[3], 0.8, "blue class channel is persisted")
    test.eq(editBox.cursor, 0, "buyer field scrolls back to the start")

    BG.BGNext.BillBuyer.set(editBox, nil)
    test.eq(editBox.text, "", "nil buyer clears the field")
    test.eq(savedColor[1], 1, "missing class color falls back to white")

    for _, path in ipairs({
        "Core/Module/Auction.lua",
        "Core/Module/Trade.lua",
        "Core/Module/QuickAccounting.lua",
        "Core/Module/AuctionLog.lua",
        "Core/Module/DuiZhang.lua",
        "Core/function2.lua",
    }) do
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        test.eq(source:find("BillBuyer.set", 1, true) ~= nil, true,
            path .. " uses the persistent buyer-color helper")
    end
end
