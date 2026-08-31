BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

local function clearArray(values)
    for index = #values, 1, -1 do values[index] = nil end
end

function M.new(options)
    options = options or {}
    assert(type(options.createFrame) == "function", "createFrame is required")

    local createFrame = options.createFrame
    local poolParent = options.poolParent
    local active = options.active or {}
    local now = options.now or (type(GetTime) == "function" and GetTime) or function() return 0 end
    local revisionInterval = tonumber(options.revisionInterval) or 0.5
    local pools = { plain = {}, flash = {} }
    local indexes = {}
    local manager = {}

    function manager:acquire(parent, flash)
        local kind = flash and "flash" or "plain"
        local pool = pools[kind]
        local frame = table.remove(pool)
        if not frame then frame = createFrame(flash == true) end
        frame.__BGNextHighlightKind = kind
        frame:SetParent(parent)
        frame:Show()
        active[#active + 1] = frame
        return frame
    end

    function manager:getLabel(frame, createLabel)
        assert(frame ~= nil and type(createLabel) == "function", "frame and createLabel are required")
        if not frame.highlightLabel then frame.highlightLabel = createLabel(frame) end
        frame.highlightLabel:Show()
        return frame.highlightLabel
    end

    function manager:releaseAll()
        for _, frame in ipairs(active) do
            if frame.flashGroup then frame.flashGroup:Stop() end
            if frame.highlightLabel then
                frame.highlightLabel:ClearAllPoints()
                frame.highlightLabel:SetText("")
                frame.highlightLabel:Hide()
            end
            frame:ClearAllPoints()
            frame:Hide()
            frame:SetParent(poolParent)
            local pool = pools[frame.__BGNextHighlightKind or "plain"]
            pool[#pool + 1] = frame
        end
        clearArray(active)
    end

    function manager:invalidate(surface)
        local index = indexes[surface]
        if index then index.dirty = true end
    end

    function manager:getMatches(surface, key, itemID, builder, validator, revisionProvider)
        local index = indexes[surface]
        local nowValue = now()
        if index and not index.dirty and index.key == key and
            type(revisionProvider) == "function" and
            nowValue - (index.checkedAt or 0) >= revisionInterval then
            index.checkedAt = nowValue
            if revisionProvider() ~= index.revision then index.dirty = true end
        end
        if not index or index.dirty or index.key ~= key then
            local entries, revision = builder()
            index = { key = key, byItem = {}, revision = revision, checkedAt = nowValue }
            for _, entry in ipairs(entries or {}) do
                if entry.itemID ~= nil then
                    local matches = index.byItem[entry.itemID]
                    if not matches then
                        matches = {}
                        index.byItem[entry.itemID] = matches
                    end
                    matches[#matches + 1] = entry
                end
            end
            indexes[surface] = index
        end

        local matches = index.byItem[itemID] or {}
        if type(validator) ~= "function" then return matches end
        local valid = {}
        for _, entry in ipairs(matches) do
            if validator(entry) then valid[#valid + 1] = entry end
        end
        return valid
    end

    return manager
end

BG.BGNext.HighlightManager = M
return M
