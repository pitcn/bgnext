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

    local function classColor(class)
        if class == "MAGE" then return 0.25, 0.78, 0.92 end
    end
    local r, g, b = BG.BGNext.BillBuyer.color({ class = "MAGE", color = { 1, 1, 1 } }, classColor)
    test.eq(r, 0.25, "stored class metadata repairs a stale white auction color")
    test.eq(g, 0.78, "class-derived green channel is used")
    test.eq(b, 0.92, "class-derived blue channel is used")
    r, g, b = BG.BGNext.BillBuyer.color({ color = { 0.2, 0.4, 0.8 } }, classColor)
    test.eq(r, 0.2, "a valid stored color is retained when class metadata is unavailable")

    -- Display-only shortening with the canonical identity kept for comparison.
    BG.BGNext.PlayerIdentity = dofile("Core/BGNext/PlayerIdentity.lua")
    BG.realmName = "时光"
    BG.IsRetail = nil

    local editBox2 = { color = { 1, 1, 1 } }
    function editBox2:SetTextColor(r, g, b) self.color = { r, g, b } end
    function editBox2:GetTextColor() return self.color[1], self.color[2], self.color[3] end
    function editBox2:SetText(value)
        self.text = value
        self.savedCanonical = self.bgnextCanonical
    end
    function editBox2:GetText() return self.text end
    function editBox2:SetCursorPosition(value) self.cursor = value end

    BG.BGNext.BillBuyer.set(editBox2, "Reader-时光", 0.2, 0.4, 0.8)
    test.eq(editBox2.text, "Reader", "non-retail buyer cell shows the short name")
    test.eq(editBox2.savedCanonical, "Reader-时光", "canonical full identity is kept for comparison")

    BG.IsRetail = true
    BG.BGNext.BillBuyer.set(editBox2, "Reader-OtherRealm", 0.2, 0.4, 0.8)
    test.eq(editBox2.text, "Reader-OtherRealm", "retail cross-realm buyer keeps the realm suffix")
    test.eq(editBox2.savedCanonical, "Reader-OtherRealm", "cross-realm canonical identity is preserved")

    BG.BGNext.BillBuyer.set(editBox2, "Reader-时光", 0.2, 0.4, 0.8)
    test.eq(editBox2.text, "Reader", "retail same-realm buyer is shortened")
    test.eq(editBox2.savedCanonical, "Reader-时光", "same-realm canonical identity is preserved")

    BG.BGNext.BillBuyer.set(editBox2, "Reader", 0.2, 0.4, 0.8)
    test.eq(editBox2.text, "Reader", "a bare buyer name stays short")
    test.eq(editBox2.savedCanonical, "Reader-时光", "a bare name gains the local realm in canonical form")

    BG.BGNext.BillBuyer.set(editBox2, "Reader", nil, nil, nil)
    test.eq(editBox2.color[1], 1, "unknown class keeps the default white color")
    test.eq(editBox2.color[2], 1, "unknown class green channel stays default")
    test.eq(editBox2.color[3], 1, "unknown class blue channel stays default")

    editBox2.bgnextCanonical = nil
    editBox2.text = "Manual"
    test.eq(BG.BGNext.BillBuyer.canonical(editBox2), "Manual",
        "read API falls back to the typed text after the transient marker clears")
    editBox2.bgnextCanonical = "Reader-时光"
    test.eq(BG.BGNext.BillBuyer.canonical(editBox2), "Reader-时光",
        "read API prefers the transient canonical over visible text")

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
