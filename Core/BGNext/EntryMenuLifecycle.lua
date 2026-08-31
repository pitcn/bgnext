BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}
local Lifecycle = {}
Lifecycle.__index = Lifecycle

function M.new(dismissDelay)
    return setmetatable({
        dismissDelay = dismissDelay,
        elapsedOutside = 0,
        opened = false,
    }, Lifecycle)
end

function Lifecycle:open()
    self.elapsedOutside = 0
    self.opened = true
end

function Lifecycle:close()
    self.elapsedOutside = 0
    self.opened = false
end

function Lifecycle:update(elapsed, ownerVisible, pointerInside)
    if not self.opened or not ownerVisible then
        self:close()
        return false
    end

    if pointerInside then
        self.elapsedOutside = 0
        return false
    end

    self.elapsedOutside = self.elapsedOutside + elapsed
    if self.elapsedOutside >= self.dismissDelay then
        self:close()
        return true
    end
    return false
end

BG.BGNext.EntryMenuLifecycle = M
return M
