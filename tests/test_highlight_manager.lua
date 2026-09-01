return function(test)
    BG = { BGNext = {} }
    local module = dofile("Core/BGNext/HighlightManager.lua")

    local created = { plain = 0, flash = 0 }
    local labelsCreated = 0
    local frames = {}
    local poolParent = { name = "pool" }
    local function newFrame(flash)
        local kind = flash and "flash" or "plain"
        created[kind] = created[kind] + 1
        local frame = {
            kind = kind,
            shown = false,
            clearCount = 0,
            parent = nil,
        }
        if flash then
            frame.flashGroup = {
                playCount = 0,
                stopCount = 0,
                Play = function(self) self.playCount = self.playCount + 1 end,
                Stop = function(self) self.stopCount = self.stopCount + 1 end,
            }
        end
        function frame:SetParent(parent) self.parent = parent end
        function frame:Show() self.shown = true end
        function frame:Hide() self.shown = false end
        function frame:ClearAllPoints() self.clearCount = self.clearCount + 1 end
        frames[#frames + 1] = frame
        return frame
    end

    local active = {}
    local manager = module.new({
        createFrame = newFrame,
        poolParent = poolParent,
        active = active,
    })
    local parent = { name = "target" }

    for _ = 1, 1000 do
        for _ = 1, 3 do
            local frame = manager:acquire(parent, true)
            frame.flashGroup:Play()
        end
        for _ = 1, 2 do
            local frame = manager:acquire(parent, false)
            manager:getLabel(frame, function()
                labelsCreated = labelsCreated + 1
                local label = { shown = true, clearCount = 0, text = "count" }
                function label:Show() self.shown = true end
                function label:Hide() self.shown = false end
                function label:ClearAllPoints() self.clearCount = self.clearCount + 1 end
                function label:SetText(text) self.text = text end
                return label
            end)
        end
        manager:releaseAll()
    end

    test.eq(created.flash, 3, "1000 cycles create only the peak flash frame count")
    test.eq(created.plain, 2, "1000 cycles create only the peak plain frame count")
    test.eq(labelsCreated, 2, "1000 cycles create only one reusable label per pooled frame")
    test.eq(#active, 0, "release empties the active frame list")
    for _, frame in ipairs(frames) do
        test.eq(frame.shown, false, "released frame is hidden")
        test.eq(frame.parent, poolParent, "released frame returns to the private pool parent")
        test.eq(frame.clearCount, 1000, "released frame clears stale anchors on every cycle")
        if frame.flashGroup then
            test.eq(frame.flashGroup.stopCount, 1000, "released flash animation is stopped")
        elseif frame.highlightLabel then
            test.eq(frame.highlightLabel.shown, false, "released highlight label is hidden")
            test.eq(frame.highlightLabel.clearCount, 1000, "released highlight label clears stale anchors")
            test.eq(frame.highlightLabel.text, "", "released highlight label clears stale text")
        end
    end

    local buildCount = 0
    local visible = { visible = true }
    local alsoVisible = { visible = true }
    local hidden = { visible = false }
    local function build()
        buildCount = buildCount + 1
        return {
            { itemID = 100, target = visible },
            { itemID = 100, target = alsoVisible },
            { itemID = 100, target = hidden },
            { itemID = 200, target = visible },
        }
    end
    local function isVisible(entry) return entry.target.visible end

    for _ = 1, 1000 do
        local matches = manager:getMatches("table", "raid-a", 100, build, isVisible)
        test.eq(#matches, 2, "cached index returns every visible matching entry")
        test.eq(matches[1].target, visible, "cached index excludes stale hidden targets")
        test.eq(matches[2].target, alsoVisible, "cached index retains the second visible match")
    end
    test.eq(buildCount, 1, "1000 unchanged lookups build the table index once")

    manager:invalidate("table")
    manager:getMatches("table", "raid-a", 100, build, isVisible)
    test.eq(buildCount, 2, "explicit invalidation rebuilds the index")

    manager:getMatches("table", "raid-b", 100, build, isVisible)
    test.eq(buildCount, 3, "view-key changes rebuild the index")

    manager:invalidate("bag")
    manager:getMatches("bag", "open", 200, build, isVisible)
    test.eq(buildCount, 4, "a separate bag surface has an independent index")

    local now = 0
    local revision = "layout-1"
    local firstButton = { visible = true }
    local replacementButton = { visible = true }
    local currentEntries = { { itemID = 300, target = firstButton } }
    local dynamicBuildCount = 0
    local dynamicManager = module.new({
        createFrame = newFrame,
        poolParent = poolParent,
        now = function() return now end,
        revisionInterval = 0.5,
    })
    local function buildDynamic()
        dynamicBuildCount = dynamicBuildCount + 1
        return currentEntries, revision
    end
    local function currentRevision() return revision end

    local initial = dynamicManager:getMatches("bag", "same-root", 300,
        buildDynamic, isVisible, currentRevision)
    test.eq(initial[1].target, firstButton, "initial dynamic layout uses the first button")

    currentEntries = { { itemID = 300, target = replacementButton } }
    revision = "layout-2"
    now = 0.25
    local throttled = dynamicManager:getMatches("bag", "same-root", 300,
        buildDynamic, isVisible, currentRevision)
    test.eq(throttled[1].target, firstButton, "layout identity checks are throttled between mouse moves")

    now = 0.5
    local refreshed = dynamicManager:getMatches("bag", "same-root", 300,
        buildDynamic, isVisible, currentRevision)
    test.eq(refreshed[1].target, replacementButton,
        "changed button identity rebuilds the index after the bounded interval")
    test.eq(dynamicBuildCount, 2, "dynamic layout replacement triggers one bounded rebuild")
end
