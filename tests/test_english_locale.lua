local function read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local function trackedBGNextFiles()
    local pipe = assert(io.popen('git ls-files "Core/BGNext/*.lua"'))
    local files = {}
    for path in pipe:lines() do
        files[#files + 1] = path
    end
    assert(pipe:close())
    return files
end

local function staticLocaleKeys(source)
    local keys = {}
    for key in source:gmatch('L%["([^"\r\n]+)"%]') do keys[key] = true end
    for key in source:gmatch("L%['([^'\r\n]+)'%]") do keys[key] = true end
    return keys
end

local function englishAssignments(source)
    local values = {}
    for key, value in source:gmatch('L%["([^"\r\n]+)"%]%s*=%s*"([^"\r\n]*)"') do
        values[key] = value
    end
    for key, value in source:gmatch("L%['([^'\r\n]+)'%]%s*=%s*'([^'\r\n]*)'") do
        values[key] = value
    end
    return values
end

local function formatSignature(value)
    local signature = {}
    value = value:gsub("%%%%", "")
    for token in value:gmatch("%%[%d%.$%-%+ #*]*[cdeEfgGiouXxqs]") do
        signature[#signature + 1] = token
    end
    return table.concat(signature, ",")
end

local function loadLocale(locale)
    local oldGetLocale, oldGetBuildInfo = GetLocale, GetBuildInfo
    GetLocale = function() return locale end
    GetBuildInfo = function() return nil, nil, nil, 11508 end
    local ns = {}
    assert(loadfile("Locales/zhCN.lua"))("BGNext", ns)
    assert(loadfile("Locales/zhTW.lua"))("BGNext", ns)
    assert(loadfile("Locales/enUS.lua"))("BGNext", ns)
    GetLocale, GetBuildInfo = oldGetLocale, oldGetBuildInfo
    return ns
end

return function(test)
    local required = {}
    for _, path in ipairs(trackedBGNextFiles()) do
        for key in pairs(staticLocaleKeys(read(path))) do required[key] = true end
    end

    local englishSource = read("Locales/enUS.lua")
    local english = englishAssignments(englishSource)
    local traditional = englishAssignments(read("Locales/zhTW.lua"))
    local missing = {}
    local missingTraditional = {}
    for key in pairs(required) do
        if english[key] == nil then missing[#missing + 1] = key end
        if traditional[key] == nil then missingTraditional[#missingTraditional + 1] = key end
    end
    table.sort(missing)
    table.sort(missingTraditional)
    test.eq(#missing, 0, "every BGNext-owned static locale key has an English translation: " .. table.concat(missing, " | "))
    test.eq(#missingTraditional, 0,
        "every BGNext-owned static locale key has a Traditional Chinese translation: " .. table.concat(missingTraditional, " | "))

    for key in pairs(required) do
        local value = assert(english[key], "missing English value for " .. key)
        test.eq(value:find("[\228-\233][\128-\191][\128-\191]") == nil, true,
            "English translation contains CJK text: " .. key .. " = " .. value)
        test.eq(formatSignature(value), formatSignature(key), "format placeholders match for " .. key)
    end
    for key, value in pairs(english) do
        test.eq(formatSignature(value), formatSignature(key), "English placeholder signature matches for " .. key)
    end

    local expectedEnglish = {
        ["你可以在该模式，调整拍卖UI的位置，预览UI缩放和层级效果。只能在非团队状态下使用。"] =
            "Use this mode outside a group to reposition the auction UI and preview its scale and frame level.",
        ["调整自动拍卖UI的大小。"] = "Adjust the automatic auction UI size.",
        ["调整装备记录通知和交易通知的位置。"] = "Adjust the position of loot-record and trade notifications.",
        ["快捷命令：/BGM"] = "Shortcut: /BGM",
        ["调整表格UI的大小。"] = "Adjust the table UI size.",
        ["调整背景材质透明度。"] = "Adjust the background opacity.",
        ["调整该字体的大小。"] = "Adjust this font size.",
        ["输入金额和欠款时自动加两个0，减少记账操作，提高记账效率。"] =
            "Automatically append two zeros to amounts and debts for faster bookkeeping.",
        ["快捷命令：/BGO"] = "Shortcut: /BGO",
    }
    for key, value in pairs(expectedEnglish) do
        test.eq(english[key], value, "active English UI copy is reviewed: " .. key)
    end

    test.eq(englishSource:find("BGNext v0%.2%.3", 1, false), nil, "English guide is not pinned to an obsolete version")
    test.eq(english["添加装备"], "Add Equipment", "active Add Equipment label remains English")

    local zhCN = loadLocale("zhCN")
    local zhTW = loadLocale("zhTW")
    local enUS = loadLocale("enUS")
    local enGB = loadLocale("enGB")
    local deDE = loadLocale("deDE")
    for _, localized in ipairs({ zhCN, zhTW, enUS, enGB, deDE }) do
        for key, value in pairs(localized.L) do
            test.eq(type(value), "string", "loaded UI translation must be text: " .. key)
        end
        test.eq(type(localized.L["存储与隐私"]), "string", "storage tab receives text, never a boolean")
        local guide = table.concat(localized.instructionsText, "\n")
        test.eq(guide:find(localized.L["备选"], 1, true) ~= nil, true,
            "guide explains the starting wishlist priority in every locale")
        local previousBG = BG
        BG = { BGNext = {} }
        dofile("Core/BGNext/Identity.lua")
        local releaseInfo = assert(loadfile("Core/BGNext/ReleaseInfo.lua"))("BGNext", localized)
        test.eq(releaseInfo.changelog[1], localized.L["紧急修复团长或物品分配者拍卖成功后，主表不自动填写买家和成交金额的问题。"],
            "in-game release notes use the selected locale")
        BG = previousBG
    end
    test.eq(zhCN.L["开始对账"], "开始对账", "Simplified Chinese clients use zhCN")
    test.eq(zhTW.L["开始对账"], "開始對賬", "Traditional Chinese clients use zhTW")
    test.eq(enUS.L["开始对账"], "Start Reconciliation", "enUS clients use English")
    test.eq(enGB.L["开始对账"], "Start Reconciliation", "enGB clients fall back to English")
    test.eq(deDE.L["开始对账"], "Start Reconciliation", "all non-Chinese clients fall back to English")
end
