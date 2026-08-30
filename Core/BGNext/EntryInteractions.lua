-- BGNext unified entry interactions.
--
-- A small pure module that projects minimap buttons and menu items into one
-- testable contract. It holds no window, storage or communication state:
-- RoleOverviewEntry remains the sole owner of preview and pinned windows, and
-- the LibDataBroker module only adapts user input to guarded public entry
-- methods. It never reads another player and never sends a message.

local AddonName, ns = ...

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

-- Maps a minimap mouse button to one intent string.
function M.minimapAction(button)
    if button == "LeftButton" then return "toggle-main" end
    if button == "RightButton" then return "menu" end
    if button == "MiddleButton" then return "toggle-role" end
    return nil
end

-- Builds the right-click menu model. Main is always first and settings always
-- last; the role overview sits between them only when this client can actually
-- open it. Each window item derives open/close from its live visibility.
function M.menuModel(state)
    state = type(state) == "table" and state or {}
    local items = {}
    items[#items + 1] = { id = "main", verb = state.mainShown and "close" or "open" }
    if state.roleAvailable == true then
        items[#items + 1] = { id = "role", verb = state.roleShown and "close" or "open" }
    end
    items[#items + 1] = { id = "settings" }
    return items
end

BG.BGNext.EntryInteractions = M
return M
