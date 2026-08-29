return function(test)
    BG = nil
    dofile("Core/BGNext/Init.lua")
    test.eq(type(BG.BGNext), "table", "BG.BGNext namespace")
    test.eq(BG.BGNext.schemaVersion, 1, "schema version")
end
