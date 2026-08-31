BG = BG or {}
BG.BGNext = BG.BGNext or {}

local TooltipDebtCache = assert(BG.BGNext.TooltipDebtCache,
    "BGNext TooltipDebtCache must load before TooltipDebtRuntime")

local M = {}
local Runtime = {}
Runtime.__index = Runtime

function M.new(options)
    local self = setmetatable({
        options = options,
        watched = setmetatable({}, { __mode = "k" }),
    }, Runtime)
    self.cache = TooltipDebtCache.new(function(raidId)
        return self:build(raidId)
    end)
    return self
end

function Runtime:invalidate()
    self.cache:invalidate()
end

function Runtime:watch(raidId, buyer, money, bossIndex, rowIndex)
    for _, edit in ipairs({ buyer, money }) do
        if edit and not self.watched[edit] then
            self.watched[edit] = true
            self.options.hookEdit(edit, function() self:invalidate() end)
        end
    end

    local debtButton = self.options.getDebtButton(raidId, bossIndex, rowIndex)
    if debtButton and not self.watched[debtButton] then
        self.watched[debtButton] = true
        self.options.hookMethod(debtButton, "Show", function() self:invalidate() end)
        self.options.hookMethod(debtButton, "Hide", function() self:invalidate() end)
    end
end

function Runtime:build(raidId)
    local fines, debts = {}, {}
    if not self.options.isReady(raidId) then return fines, debts end

    local maxBoss = self.options.maxBoss(raidId)
    self.options.pairItems(raidId, function(_, buyer, money, bossIndex, rowIndex)
        self:watch(raidId, buyer, money, bossIndex, rowIndex)
        local name = buyer:GetText()
        if name ~= "" then
            fines[name] = fines[name] or 0
            debts[name] = debts[name] or 0
            if bossIndex == maxBoss then
                fines[name] = fines[name] + (tonumber(money:GetText()) or 0)
            end
            debts[name] = debts[name]
                + (tonumber(self.options.getDebt(raidId, bossIndex, rowIndex)) or 0)
        end
    end)
    return fines, debts
end

function Runtime:get(context)
    return self.cache:get(context)
end

BG.BGNext.TooltipDebtRuntime = M
return M
