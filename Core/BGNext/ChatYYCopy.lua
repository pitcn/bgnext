BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}
local runtimeInstalled = false
local POPUP_NAME = "BGNextCopyYYNumber"

local CHAT_EVENTS = {
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_BN_WHISPER_INFORM",
}

local function link(number)
    return "|cff00BFFF|Hgarrmission:bgnextyycopy:" .. number .. "|h[" .. number .. "]|h|r"
end

local function skipSpaces(text, position)
    while text:sub(position, position):match("%s") do
        position = position + 1
    end
    return position
end

local function digitStart(text, yyEnd)
    local position = yyEnd + 1
    if text:sub(position, position + #"频道" - 1) == "频道" then
        return skipSpaces(text, position + #"频道")
    end
    if text:sub(position, position + #"号" - 1) == "号" then
        return skipSpaces(text, position + #"号")
    end
    if text:sub(position, position + #"：" - 1) == "：" then
        return skipSpaces(text, position + #"：")
    end
    if text:sub(position, position) == ":" then
        return skipSpaces(text, position + 1)
    end
    if text:sub(position, position):match("%d") then
        return position
    end
end

local function transformPlain(text)
    local output = {}
    local cursor = 1
    while cursor <= #text do
        local yyStart, yyEnd = text:find("[Yy][Yy]", cursor)
        if not yyStart then
            output[#output + 1] = text:sub(cursor)
            break
        end

        local numberStart = digitStart(text, yyEnd)
        local numberEnd = numberStart and numberStart - 1 or nil
        while numberEnd and text:sub(numberEnd + 1, numberEnd + 1):match("%d") do
            numberEnd = numberEnd + 1
        end
        local number = numberEnd and text:sub(numberStart, numberEnd) or ""
        local previousByte = text:sub(yyStart - 1, yyStart - 1)
        local nextByte = numberEnd and text:sub(numberEnd + 1, numberEnd + 1) or ""
        local valid = #number >= 3 and #number <= 12
            and not previousByte:match("[A-Za-z]")
            and not nextByte:match("[A-Za-z]")

        if valid then
            output[#output + 1] = text:sub(cursor, numberStart - 1)
            output[#output + 1] = link(number)
            cursor = numberEnd + 1
        else
            output[#output + 1] = text:sub(cursor, yyEnd)
            cursor = yyEnd + 1
        end
    end
    return table.concat(output)
end

local function transformMarkup(message)
    local output = {}
    local cursor = 1
    while cursor <= #message do
        local hyperlinkStart = message:find("|H", cursor, true)
        local textureStart = message:find("|T", cursor, true)
        local escapeStart
        local isHyperlink
        if hyperlinkStart and (not textureStart or hyperlinkStart < textureStart) then
            escapeStart = hyperlinkStart
            isHyperlink = true
        else
            escapeStart = textureStart
            isHyperlink = false
        end

        if not escapeStart then
            output[#output + 1] = transformPlain(message:sub(cursor))
            break
        end
        output[#output + 1] = transformPlain(message:sub(cursor, escapeStart - 1))

        local escapeEnd
        if isHyperlink then
            local labelStart = message:find("|h", escapeStart + 2, true)
            escapeEnd = labelStart and message:find("|h", labelStart + 2, true) or nil
        else
            escapeEnd = message:find("|t", escapeStart + 2, true)
        end
        if not escapeEnd then return message end

        output[#output + 1] = message:sub(escapeStart, escapeEnd + 1)
        cursor = escapeEnd + 2
    end
    return table.concat(output)
end

function M.transform(message)
    if type(message) ~= "string" then return message end
    if type(issecretvalue) == "function" and issecretvalue(message) then return message end
    return transformMarkup(message)
end

function M.decodeLink(value)
    if type(value) ~= "string" then return nil end
    local number = value:match("^garrmission:bgnextyycopy:(%d+)$")
    if not number or #number < 3 or #number > 12 then return nil end
    return number
end

function M.showCopyPopup(number)
    if type(number) ~= "string" or not number:match("^%d+$") or #number < 3 or #number > 12 then
        return false
    end
    if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then
        return false
    end

    if not StaticPopupDialogs[POPUP_NAME] then
        StaticPopupDialogs[POPUP_NAME] = {
            text = "按下 Ctrl+C 复制 YY 号码",
            button1 = OKAY,
            hasEditBox = 1,
            editBoxWidth = 220,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            OnShow = function(self, value)
                local edit = self.EditBox or self.editBox
                edit:SetText(value)
                edit:HighlightText()
                edit:SetFocus()
            end,
            OnHide = function(self)
                local edit = self.EditBox or self.editBox
                edit:SetText("")
            end,
            EditBoxOnEscapePressed = function(self)
                self:GetParent():Hide()
            end,
        }
    end
    StaticPopup_Show(POPUP_NAME, nil, nil, number)
    return true
end

function M.install(dependencies)
    if runtimeInstalled then return false end
    dependencies = dependencies or {}

    local addFilter = dependencies.addFilter or ChatFrame_AddMessageEventFilter
    local showCopyPopup = dependencies.showCopyPopup or M.showCopyPopup
    local hookSetItemRef = dependencies.hookSetItemRef
    if not hookSetItemRef and type(hooksecurefunc) == "function" and type(SetItemRef) == "function" then
        hookSetItemRef = function(callback)
            hooksecurefunc("SetItemRef", callback)
        end
    end
    if type(addFilter) ~= "function" or type(showCopyPopup) ~= "function"
        or type(hookSetItemRef) ~= "function" then
        return false
    end

    local function filter(_, _, message, ...)
        local transformed = M.transform(message)
        if transformed == message then return nil end
        return false, transformed, ...
    end
    for _, event in ipairs(CHAT_EVENTS) do
        addFilter(event, filter)
    end
    hookSetItemRef(function(value, _, button)
        if button ~= "LeftButton" then return end
        local number = M.decodeLink(value)
        if number then showCopyPopup(number) end
    end)

    runtimeInstalled = true
    return true
end

BG.BGNext.ChatYYCopy = M
M.install()
return M
