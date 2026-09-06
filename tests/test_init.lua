return function(test)
    BG = nil
    dofile("Core/BGNext/Init.lua")
    test.eq(type(BG.BGNext), "table", "BG.BGNext namespace")
    test.eq(BG.BGNext.schemaVersion, 1, "schema version")
    local cleared = 0
    BG.BGNext.releaseEditFocus(
        { ClearFocus = function() cleared = cleared + 1 end },
        nil,
        { ClearFocus = false },
        { ClearFocus = function() cleared = cleared + 1 end }
    )
    test.eq(cleared, 2, "focus release safely clears every supplied editable frame")
end
