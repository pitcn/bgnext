-- BGNext Forever declarations. Game identifiers only; see docs/design/2026-11-13-forever-raids.md.
if not BG.IsForever then return end
local _, ns = ...
local L = ns.L
BG.ForeverRaids = {
    { id = "UBRSforever", mapID = 229, phase = "P0", players = 10, requiresRaid = true,
      name = L["黑石塔上层"], rows = { 4, 3, 3, 3, 3, 4, 3, 4, 3 }, bosses = {
        L["烈焰卫士艾博希尔"],
        L["索拉卡·火冠"],
        L["杰德"],
        L["古拉鲁克"],
        L["盖斯"],
        L["大酋长雷德·黑手"],
        L["比斯巨兽"],
        L["达基萨斯将军"],
        L["瓦塔拉克公爵"],
    } },
    { id = "BDforever", mapID = 3052, phase = "P1", players = 10,
      name = L["深穴"], bosses = {
        L["寒嚎"],
        L["长者纠爪"],
        L["恐网者卡利斯"],
        L["悲伤之井"],
        L["阿梅斯拉克斯"],
        L["德利纳尔·歌木"],
        L["拉弗斯与达莉莎"],
        L["索尼娅·暗影之谷"],
    } },
    { id = "HSforever", mapID = 2981, phase = "P1", players = 20,
      name = L["海加尔峰"], bosses = {
        L["班达拉尔"],
        L["腐朽古树"],
        L["迷时军团"],
        L["希尔维斯翠丝·暮歌"],
        L["老暮暗潜伏者"],
        L["深渊者加拉里斯"],
        L["鬼影缠身的卡斯里斯"],
        L["阿娜拉·寒风"],
        L["长者敏德雷尔"],
        L["追踪者静风"],
        L["荆棘议会"],
        L["缚梦者尼苏斯"],
        L["荒野之王"],
    } },
    { id = "ONYforever", mapID = 249, phase = "P1", players = 40,
      name = L["奥妮克希亚的巢穴"], bosses = {
        L["奥妮克希亚"],
    } },
}

local raids = BG.ForeverRaids
function BG.ForeverRaidActive(fb, inRaid)
    for _, raid in ipairs(raids) do
        if raid.id == fb and raid.requiresRaid then
            return inRaid == true
        end
    end
    return true
end

-- SavedVariables becomes available before ADDON_LOADED. Keep any occupied
-- bill row visible rather than truncating a ledger when adopting compact rows.
BG.Init(function()
    local raid = BG.ForeverRaids[1]
    local saved = type(BiaoGe) == "table" and BiaoGe[raid.id]
    local slots = ns.Maxi and ns.Maxi[raid.id]
    if type(saved) ~= "table" or not slots then return end
    local fields = { zhuangbei = true, maijia = true, jine = true, qiankuan = true,
        loot = true, itemLevel = true, bindOnEquip = true, guanzhu = true }
    for b = 1, #raid.bosses do
        local boss = saved["boss" .. b]
        if type(boss) == "table" then
            for key, value in pairs(boss) do
                local field, row
                if type(key) == "string" then field, row = key:match("^(%a+)(%d+)$") end
                row = tonumber(row)
                if fields[field] and row and row <= BG.Maxi and row > slots[b]
                    and value ~= nil and value ~= "" and value ~= false then
                    slots[b] = row
                    BG.FBHeight[raid.id] = 960
                end
            end
        end
    end
end)
