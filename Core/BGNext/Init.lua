BG = BG or {}
BG.BGNext = BG.BGNext or {}
BG.BGNext.schemaVersion = 1

-- A hidden EditBox can keep keyboard focus after its parent window closes.
-- Keep the release primitive tiny and frame-only so UI modules can share the
-- same safe lifecycle cleanup without changing bindings, persistence or input.
function BG.BGNext.releaseEditFocus(...)
    for index = 1, select("#", ...) do
        local edit = select(index, ...)
        local kind = type(edit)
        if (kind == "table" or kind == "userdata") and type(edit.ClearFocus) == "function" then
            edit:ClearFocus()
        end
    end
end

return BG.BGNext
