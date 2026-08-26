return function(test)
    BG = { BGNext = {} }
    local info = dofile("Core/BGNext/ReleaseInfo.lua")

    test.eq(info.projectName, "BGNext", "project name")
    test.eq(info.author, "国服社区共创", "community author")
    test.eq(info.official, false, "independent project")
    test.eq(type(info.changelog), "table", "local changelog")
    test.eq(type(info.credits.upstream), "table", "upstream credits")

    local about = dofile("Core/BGNext/About.lua")
    test.eq(about.buildText("about", info):find("非官方", 1, true) ~= nil, true, "independent status disclosed")
    test.eq(about.buildText("changelog", info):find(info.changelog[1], 1, true) ~= nil, true, "changelog rendered")
    test.eq(about.buildText("credits", info):find(info.credits.upstream[1], 1, true) ~= nil, true, "credits rendered")

    local tocFile = assert(io.open("BGLite.toc", "rb"))
    local toc = tocFile:read("*a")
    tocFile:close()
    test.eq(toc:find("## Author: 国服社区共创", 1, true) ~= nil, true, "community author metadata")
    test.eq(toc:find("## X-Upstream-Author: CQZS (Lite)", 1, true) ~= nil, true, "upstream author metadata")
end
