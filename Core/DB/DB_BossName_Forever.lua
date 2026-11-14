if not BG.IsForever then return end
local _, ns = ...
local L = ns.L

for _, raid in ipairs(BG.ForeverRaids) do
    local names = {}
    for _, name in ipairs(raid.bosses) do names[#names + 1] = name end
    names[#names + 1] = L["杂\n\n项"]
    names[#names + 1] = L["罚\n\n款"]
    names[#names + 1] = L["支\n\n出"]
    names[#names + 1] = L["总\n览"]
    BG.Boss[raid.id] = {}
    for b, name in ipairs(names) do
        local formatted, count = BG.FormatBossName(name)
        BG.Boss[raid.id]["boss" .. b] = {
            name = formatted, name2 = name:gsub("\n", ""), nCount = count,
            color = b == #names and "EE82EE" or b == #names - 1 and "00FF00" or "00BFFF",
        }
    end
end
