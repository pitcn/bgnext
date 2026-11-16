-- A deliberately small reference equipment selection, not a complete or
-- verified Forever drop table. No probabilities, stats, third-party code,
-- private table layouts or assets are imported. See the provenance notes.
if not BG.IsForever then return end

BG.Loot.encounterID = BG.Loot.encounterID or {}
-- Exact DungeonEncounter rows in the local 1.60.1.70938 client. Optional
-- bosses without an encounter row deliberately have an empty event list.
BG.Loot.encounterID.UBRSforever = {
    { 3062 }, {}, {}, {}, {}, { 3063 }, { 3068 }, { 3069 }, { 3070 },
}
BG.Loot.encounterID.ONYforever = { { 1084 } }

for _, raid in ipairs(BG.ForeverRaids) do
    for b = 1, #raid.bosses + 1 do
        BG.Loot[raid.id].N["boss" .. b] = {}
    end
end

local loot = BG.Loot.UBRSforever.N
-- Equipment only. Quests, recipes and uncertain additions stay out of this
-- initial reference pool. Boss order is BGNext's own ledger order.
loot.boss1 = { 12905, 12926, 12927, 12929, 16672 }
loot.boss2 = { 12589, 12603, 12606, 12609, 16695 }
loot.boss3 = { 12604, 12605, 12930 }
loot.boss4 = { 13498, 13502, 18047, 18048 }
loot.boss5 = { 12952, 12953, 12960, 16669, 22225 }
loot.boss6 = { 12583, 12587, 12588, 12590, 12935, 12936, 12939, 12940, 16733, 18102, 18103, 18104, 22247 }
loot.boss7 = { 12963, 12964, 12965, 12966, 12967, 12968, 12969, 16729, 22311 }
loot.boss8 = { 12592, 12602, 13098, 13141, 13142, 16666, 16674, 16688, 16690, 16700, 16706, 16721, 16726, 16730, 22253, 22267, 22268, 22269 }
loot.boss9 = { 22302, 22335, 22336, 22337, 22339, 22340, 22342, 22343 }
