BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

local function identity()
    return BG.BGNext and BG.BGNext.PlayerIdentity or nil
end

-- Writes a buyer cell. The visible text is the display name (short on non-retail
-- and for same-realm retail players), while the canonical full identity is kept
-- transiently on the edit box so the OnTextChanged handler can store it for
-- comparison. The marker is cleared after SetText (which fires OnTextChanged
-- synchronously), so a later manual edit stores the typed text instead.
function M.set(editBox, buyer, r, g, b)
    if not editBox then return end
    local id = identity()
    local realm = BG.realmName or nil
    local family = id and id.familyFromGlobals(BG) or nil
    local canonical = id and id.canonical(buyer, realm) or nil
    local display = id and id.display(buyer, realm, family) or buyer
    if not display then
        display = buyer or ""
    end
    editBox.bgnextCanonical = canonical
    editBox:SetTextColor(r or 1, g or 1, b or 1)
    editBox:SetText(display)
    editBox.bgnextCanonical = nil
    if editBox.SetCursorPosition then
        editBox:SetCursorPosition(0)
    end
end

-- Reads the canonical identity for a buyer cell. Returns the transient canonical
-- written by set() when present, otherwise the current visible text (a manual
-- entry). Returns nil for an empty field.
function M.canonical(editBox)
    if not editBox then return nil end
    if type(editBox.bgnextCanonical) == "string" and editBox.bgnextCanonical ~= "" then
        return editBox.bgnextCanonical
    end
    local text = editBox.GetText and editBox:GetText() or nil
    if type(text) == "string" and text ~= "" then return text end
    return nil
end

BG.BGNext.BillBuyer = M

return M
