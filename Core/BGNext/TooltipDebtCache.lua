BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}
local Cache = {}
Cache.__index = Cache

local function empty()
    return {}, {}
end

function M.new(builder)
    return setmetatable({
        builder = builder,
        active = false,
        dirty = true,
        raidId = nil,
        fines = {},
        debts = {},
    }, Cache)
end

function Cache:invalidate()
    self.dirty = true
end

function Cache:clear()
    if not self.active then return end
    self.fines, self.debts = empty()
    self.raidId = nil
    self.dirty = true
    self.active = false
end

function Cache:get(context)
    if not context.enabled or not context.inRaid then
        self:clear()
        return self.fines, self.debts
    end

    self.active = true
    if self.dirty or self.raidId ~= context.raidId then
        local fines, debts = self.builder(context.raidId)
        self.fines = type(fines) == "table" and fines or {}
        self.debts = type(debts) == "table" and debts or {}
        self.raidId = context.raidId
        self.dirty = false
    end
    return self.fines, self.debts
end

BG.BGNext.TooltipDebtCache = M
return M
