local AddonName, ns = ...

-- Keep the item information cache warm for Titan raid drops.  This is the
-- non-UI portion of the original item library; it deliberately owns no
-- wish-list state or controls.
local requested = {}

local function RequestItem(itemID)
    if not itemID or requested[itemID] then return end
    requested[itemID] = true
    BG.OnItemLoad(itemID):ContinueOnItemLoad(function()
        -- Requesting the item data is sufficient. Loot.lua will read its
        -- quality, type and icon when CHAT_MSG_LOOT is received.
    end)
end

local function RequestList(list)
    if not list then return end
    for _, itemID in pairs(list) do
        RequestItem(itemID)
    end
end

local function PreloadTitanLoot()
    for _, FB in pairs(BG.FBtable) do
        if FB:find("titan") then
            for _, difficulty in pairs(BG.difficultyTable[FB] or {}) do
                local loot = BG.Loot[FB] and BG.Loot[FB][difficulty]
                if loot then
                    for key, list in pairs(loot) do
                        if key:find("boss") then
                            RequestList(list)
                        end
                    end
                    if loot.Quest then
                        for _, list in pairs(loot.Quest) do
                            RequestList(list)
                        end
                    end
                end
            end
            local exchangeItems = BG.Loot[FB] and BG.Loot[FB].ExchangeItems
            if exchangeItems then
                for itemID, list in pairs(exchangeItems) do
                    RequestItem(itemID)
                    RequestList(list)
                end
            end
        end
    end
end

BG.Init2(function()
    BG.After(0.5, PreloadTitanLoot)
end)
