local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

return function(test)
    local builder = readAll("tools/build-release.ps1")
    local workflow = readAll(".github/workflows/release-package.yml")
    local toc = readAll("BGLite.toc")
    local init = readAll("Core/DB/Init.lua")
    local main = readAll("Core/BiaoGe.lua")
    local helpers = readAll("Core/function1.lua")
    local database = readAll("Core/DB/DB.lua")
    local minimap = readAll("Core/Module/minimap.lua")

    test.eq(builder:find("BGLite.toc", 1, true) ~= nil, true,
        "the package is rooted in the runtime manifest")
    test.eq(builder:find('$addonRoot = Join-Path $stagingRoot "BGNext"', 1, true) ~= nil, true,
        "the release archive installs into a BGNext directory")
    test.eq(builder:find('$releaseTocName = "BGNext.toc"', 1, true) ~= nil, true,
        "the release archive exposes a TOC matching the BGNext directory")
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
    test.eq(builder:find("X-BGNext-Version", 1, true) ~= nil, true,
        "the default archive name uses the BGNext release version")
    test.eq(builder:find("Join-Path $repositoryRoot \"addon_version.txt\"") == nil, true,
        "the upstream channel build number is not used as the BGNext release version")
    test.eq(workflow:find('.FullName.Replace("\\", "/")', 1, true) ~= nil, true,
        "the release audit normalizes Windows ZIP entry separators")
    local baselineGate = assert(workflow:find("tools/verify-baseline.ps1", 1, true),
        "the release job must verify the baseline before packaging")
    local buildStep = assert(workflow:find("tools/build-release.ps1", 1, true),
        "the release job must build the runtime archive")
    test.eq(baselineGate < buildStep, true,
        "baseline integrity is verified before a distributable archive is built")
    test.eq(workflow:find("fetch-depth: 0", 1, true) ~= nil, true,
        "the release checkout includes the pinned baseline commit")
    test.eq(workflow:find("lua5.1 tests/run.lua", 1, true) ~= nil, true,
        "the release workflow runs the Lua suite itself")
    test.eq(workflow:find("needs: lua-tests", 1, true) ~= nil, true,
        "the package cannot build or upload before Lua tests pass")

    test.eq(init:find('addonName ~= "BGLite"', 1, true), nil,
        "ADDON_LOADED follows the actual packaged addon name")
    for path, content in pairs({
        ["BGLite.toc"] = toc,
        ["Core/BiaoGe.lua"] = main,
        ["Core/function1.lua"] = helpers,
        ["Core/DB/DB.lua"] = database,
        ["Core/Module/minimap.lua"] = minimap,
    }) do
        test.eq(content:find("Interface\\AddOns\\BGLite", 1, true), nil,
            path .. " does not resolve release assets through the old folder name")
        test.eq(content:find("Interface\\\\AddOns\\\\BGLite", 1, true), nil,
            path .. " does not resolve escaped release assets through the old folder name")
    end
end
