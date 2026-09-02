local _, ns = ...

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local L = ns and ns.L or setmetatable({}, {
    __index = function(_, key) return key end,
})

local M = {}
local FIELDS = { "History", "HistoryList", "tradeHistory", "mailHistory" }

-- Detection deliberately checks four known top-level keys only. The legacy
-- values are never enumerated, displayed, migrated, copied, or reused.
function M.detect(saved)
    if type(saved) ~= "table" then
        return false, 0
    end
    local count = 0
    for index = 1, #FIELDS do
        if saved[FIELDS[index]] ~= nil then
            count = count + 1
        end
    end
    return count > 0, count
end

-- Destructive cleanup is available only after an explicit confirmation from
-- the settings UI and removes only the fixed legacy-history whitelist.
function M.clear(saved, confirmed)
    if confirmed ~= true then
        return false, "confirmation-required"
    end
    if type(saved) ~= "table" then
        return false, "invalid-saved-variables"
    end
    local count = 0
    for index = 1, #FIELDS do
        local field = FIELDS[index]
        if saved[field] ~= nil then
            saved[field] = nil
            count = count + 1
        end
    end
    return true, count
end

local function buildPanel()
    if type(BG.OptionsCreateTab) ~= "function" or type(BG.CreateButton) ~= "function" then
        return
    end

    local panel = BG.OptionsCreateTab("Options_storagePrivacy", L["存储与隐私"])
    if type(panel) ~= "table" then return end

    local heading = panel:CreateFontString(nil, "OVERLAY")
    heading:SetPoint("TOPLEFT", panel, "TOPLEFT", 15, 0)
    heading:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
    heading:SetTextColor(1, 1, 1)
    heading:SetText(L["旧历史数据清理"])

    local description = panel:CreateFontString(nil, "OVERLAY")
    description:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -12)
    description:SetWidth(720)
    description:SetJustifyH("LEFT")
    description:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    description:SetTextColor(0.82, 0.82, 0.82)
    description:SetText(L["BGNext 不会读取或迁移旧版历史表格、交易记录和邮件记录。若旧数据仍保存在本地，可在这里手动清理以减少常驻内存。"])

    local status = panel:CreateFontString(nil, "OVERLAY")
    status:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -18)
    status:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")

    local button = BG.CreateButton(panel)
    button:SetSize(220, 26)
    button:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -14)
    button:SetText(L["清理 BGNext 中的旧历史数据"])

    local note = panel:CreateFontString(nil, "OVERLAY")
    note:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -12)
    note:SetWidth(720)
    note:SetJustifyH("LEFT")
    note:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    note:SetTextColor(1, 0.82, 0)
    note:SetText(L["此操作不可恢复。建议先退出游戏并备份 WTF 文件夹；当前账单、设置、心愿清单、当前团结算和角色总览不会被删除。"])

    local function refresh()
        local present, count = M.detect(BiaoGe)
        if present then
            status:SetText(string.format(L["检测到 %d 项旧历史数据。"], count))
            status:SetTextColor(1, 0.82, 0)
            button:Enable()
        else
            status:SetText(L["未检测到旧历史数据。"])
            status:SetTextColor(0.35, 0.85, 0.55)
            button:Disable()
        end
    end

    button:SetScript("OnClick", function()
        local dialogKey = "BGNEXT_CLEAR_LEGACY_HISTORY"
        if not StaticPopupDialogs[dialogKey] then
            StaticPopupDialogs[dialogKey] = {
                text = L["确定清理 BGNext 中的旧历史数据吗？\n\n此操作不可恢复。建议先退出游戏并备份 WTF 文件夹。只会删除旧版历史表格、交易记录和邮件记录。"],
                button1 = L["确认清理"],
                button2 = L["取消"],
                OnAccept = function()
                    M.clear(BiaoGe, true)
                    if type(collectgarbage) == "function" then
                        collectgarbage("collect")
                    end
                    refresh()
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                showAlert = true,
            }
        end
        StaticPopup_Show(dialogKey)
    end)

    panel:HookScript("OnShow", refresh)
    refresh()
end

M.buildPanel = buildPanel

if type(BG.Init) == "function" then
    BG.Init(buildPanel)
end

BG.BGNext.LegacyHistoryCleanup = M
return M
