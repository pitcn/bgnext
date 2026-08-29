return function(test)
    local M = dofile("Core/BGNext/ChatYYCopy.lua")

    test.eq(
        M.transform("来YY：123456"),
        "来YY：|cff00BFFF|Hgarrmission:bgnextyycopy:123456|h[123456]|h|r",
        "explicit YY number becomes a copy link"
    )

    local copy123 = "|cff00BFFF|Hgarrmission:bgnextyycopy:123|h[123]|h|r"
    local accepted = {
        { "YY123", "YY" .. copy123 },
        { "YY: 123", "YY: " .. copy123 },
        { "YY： 123", "YY： " .. copy123 },
        { "YY号 123", "YY号 " .. copy123 },
        { "YY频道 123", "YY频道 " .. copy123 },
        { "yy：123", "yy：" .. copy123 },
    }
    for _, case in ipairs(accepted) do
        test.eq(M.transform(case[1]), case[2], "accepted YY form: " .. case[1])
    end

    local minNumber = "123"
    local maxNumber = "123456789012"
    test.eq(M.transform("YY" .. minNumber), "YY" .. copy123, "three digits are accepted")
    test.eq(
        M.transform("YY" .. maxNumber),
        "YY|cff00BFFF|Hgarrmission:bgnextyycopy:" .. maxNumber .. "|h[" .. maxNumber .. "]|h|r",
        "twelve digits are accepted"
    )

    local rejected = {
        "YY12",
        "YY1234567890123",
        "YY123abc",
        "BYY123",
        "yyds123",
        "出价16000G",
        "装等566",
        "时间20:30",
    }
    for _, message in ipairs(rejected) do
        test.eq(M.transform(message), message, "ambiguous text remains plain: " .. message)
    end

    test.eq(
        M.transform("YY123，备用YY号 456"),
        "YY" .. copy123 .. "，备用YY号 "
            .. "|cff00BFFF|Hgarrmission:bgnextyycopy:456|h[456]|h|r",
        "multiple explicit YY numbers are linked independently"
    )

    test.eq(
        M.transform("|cffff0000YY123|r"),
        "|cffff0000YY" .. copy123 .. "|r",
        "colour controls are preserved"
    )
    local existingLink = "装备|Hitem:123|h[YY123]|h结束"
    test.eq(M.transform(existingLink), existingLink, "existing hyperlinks are not rewritten")
    local texture = "图标|TYY123:16|t结束"
    test.eq(M.transform(texture), texture, "texture escapes are not rewritten")
    local malformedLink = "损坏|Hitem:123|hYY123"
    test.eq(M.transform(malformedLink), malformedLink, "malformed hyperlinks fail closed")
    local malformedTexture = "损坏|TYY123:16"
    test.eq(M.transform(malformedTexture), malformedTexture, "malformed textures fail closed")

    local oldIsSecretValue = issecretvalue
    issecretvalue = function(value) return value == "YY999" end
    test.eq(M.transform("YY999"), "YY999", "protected chat text fails closed")
    issecretvalue = oldIsSecretValue

    test.eq(M.decodeLink("garrmission:bgnextyycopy:123456"), "123456", "valid link decodes")
    test.eq(M.decodeLink("garrmission:bgnextyycopy:12"), nil, "short link is rejected")
    test.eq(M.decodeLink("garrmission:bgnextyycopy:1234567890123"), nil, "long link is rejected")
    test.eq(M.decodeLink("garrmission:bgnextyycopy:123abc"), nil, "mixed link is rejected")
    test.eq(M.decodeLink("item:123456"), nil, "unrelated link is rejected")

    local filters = {}
    local clickHandler
    local copied
    local installed = M.install({
        addFilter = function(event, callback)
            filters[event] = callback
        end,
        hookSetItemRef = function(callback)
            clickHandler = callback
        end,
        showCopyPopup = function(number)
            copied = number
        end,
    })
    test.eq(installed, true, "runtime installs with available APIs")
    test.eq(type(filters.CHAT_MSG_CHANNEL), "function", "public channels are filtered")
    test.eq(type(filters.CHAT_MSG_RAID), "function", "raid chat is filtered")
    test.eq(type(filters.CHAT_MSG_WHISPER), "function", "game whispers are filtered")
    test.eq(type(filters.CHAT_MSG_WHISPER_INFORM), "function", "outgoing game whispers are filtered")
    test.eq(type(filters.CHAT_MSG_BN_WHISPER), "function", "Battle.net whispers are filtered")
    test.eq(type(filters.CHAT_MSG_BN_WHISPER_INFORM), "function", "outgoing Battle.net whispers are filtered")
    test.eq(filters.CHAT_MSG_SYSTEM, nil, "system messages are not filtered")
    test.eq(type(clickHandler), "function", "custom link click is installed")

    local filtered, transformed, sender = filters.CHAT_MSG_CHANNEL(nil, nil, "YY123", "Sender")
    test.eq(filtered, false, "changed chat remains visible")
    test.eq(transformed, "YY" .. copy123, "chat filter uses the pure transformer")
    test.eq(sender, "Sender", "chat metadata passes through without storage")
    test.eq(filters.CHAT_MSG_CHANNEL(nil, nil, "出价123"), nil, "unchanged chat uses the default path")

    clickHandler("garrmission:bgnextyycopy:123", nil, "LeftButton")
    test.eq(copied, "123", "left click sends digits only to the copy popup")
    copied = nil
    clickHandler("garrmission:bgnextyycopy:456", nil, "RightButton")
    test.eq(copied, nil, "right click has no action")
    test.eq(M.install({ addFilter = function() end }), false, "installation is idempotent")

    local oldDialogs, oldShow, oldOkay = StaticPopupDialogs, StaticPopup_Show, OKAY
    local popupValue
    StaticPopupDialogs = {}
    OKAY = "OK"
    StaticPopup_Show = function(name, _, _, value)
        local edit = {
            SetText = function(self, text) self.text = text end,
            HighlightText = function() end,
            SetFocus = function() end,
        }
        StaticPopupDialogs[name].OnShow({ EditBox = edit }, value)
        popupValue = edit.text
    end
    test.eq(M.showCopyPopup("789"), true, "valid number opens the copy popup")
    test.eq(popupValue, "789", "copy popup contains digits without quotes")
    test.eq(M.showCopyPopup("78x"), false, "copy popup rejects non-digits")
    StaticPopupDialogs, StaticPopup_Show, OKAY = oldDialogs, oldShow, oldOkay

    local tocFile = assert(io.open("BGLite.toc", "rb"))
    local toc = tocFile:read("*a")
    tocFile:close()
    local initAt = assert(toc:find("Core\\BGNext\\Init.lua", 1, true))
    local moduleAt = assert(toc:find("Core\\BGNext\\ChatYYCopy.lua", 1, true))
    test.eq(moduleAt > initAt, true, "chat YY copy loads after BGNext initialization")

    local sourceFile = assert(io.open("Core/BGNext/ChatYYCopy.lua", "rb"))
    local source = sourceFile:read("*a")
    sourceFile:close()
    local prohibited = {
        "SendChatMessage",
        "SendAddonMessage",
        "C_ChatInfo.SendAddonMessage",
        "BiaoGe.BGNext",
        "SavedVariables",
        "http",
        "io.open",
    }
    for _, token in ipairs(prohibited) do
        test.eq(source:find(token, 1, true), nil, "runtime omits prohibited capability: " .. token)
    end
end
