local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

return function(test)
    local builder = readAll("tools/build-release.ps1")

    test.eq(builder:find("BGLite.toc", 1, true) ~= nil, true,
        "the package is rooted in the runtime manifest")
    test.eq(builder:find("Script|Include", 1, true) ~= nil, true,
        "nested XML runtime dependencies are discovered")
    for _, path in ipairs({
        "Core/Module/History.lua",
        "Core/Module/TradeHistory.lua",
        "Core/Module/MailHistory.lua",
        "Core/Module/Receive.lua",
        "Core/FBUI/ReceiveUIfunction.lua",
    }) do
        test.eq(builder:find(path, 1, true) ~= nil, true,
            path .. " is explicitly denied from release packages")
    end
    test.eq(builder:find("Get-ChildItem -LiteralPath $repositoryRoot -Recurse", 1, true), nil,
        "the builder never packages the whole repository")
    test.eq(builder:find("Get-FileHash -Algorithm SHA256", 1, true) ~= nil, true,
        "the builder emits a checksum for the release archive")
end
