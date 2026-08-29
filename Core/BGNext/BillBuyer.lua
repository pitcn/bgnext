BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

function M.set(editBox, buyer, r, g, b)
    if not editBox then return end
    editBox:SetTextColor(r or 1, g or 1, b or 1)
    editBox:SetText(buyer or "")
    if editBox.SetCursorPosition then
        editBox:SetCursorPosition(0)
    end
end

BG.BGNext.BillBuyer = M

return M
