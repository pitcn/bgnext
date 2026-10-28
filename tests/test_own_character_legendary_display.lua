return function(test)
    local objects, callbacks, cached = {}, {}, {}
    local env = setmetatable({ BG = { BGNext = {} } }, { __index = _G })
    local function widget(kind)
        local value = { kind = kind, shown = true }
        function value:SetText(text) self.text = text end
        function value:GetStringWidth() return #(self.text or "") * 7 end
        function value:SetPoint(...) self.point = { ... } end
        function value:SetFont(_, size) self.fontSize = size end
        function value:Hide() self.shown = false end
        function value:Show() self.shown = true end
        function value:IsShown() return self.shown end
        function value:GetFrameLevel() return 1 end
        function value:CreateFontString() return widget("text") end
        function value:CreateTexture() return widget("texture") end
        setmetatable(value, { __index = function() return function() end end })
        objects[#objects + 1] = value
        return value
    end
    env.CreateFrame = function() return widget("button") end
    env.GetItemIcon = function() return 134400 end
    env.GetItemInfo = function(id)
        return "Legendary", "item:" .. id, 5, cached[id]
    end
    env.Item = { CreateFromItemID = function(self, id)
        test.eq(self, env.Item, "Blizzard item constructor receives its mixin receiver")
        return { ContinueOnItemLoad = function(_, callback)
            callbacks[#callbacks + 1] = callback
        end }
    end }
    local function load(path)
        local chunk = assert(loadfile(path)); setfenv(chunk, env); return chunk()
    end
    load("Core/BGNext/OwnCharactersAdapters.lua")
    local catalog = load("Core/BGNext/OwnCharactersCatalog.lua")
    local view = load("Core/BGNext/OwnCharactersView.lua")
    local ui = load("Core/BGNext/OwnCharactersUI.lua")
    local target = widget("frame")
    ui.SetFrame(target)
    local snapshot = {
        realmId = 1, player = "Test", level = 80,
        items = { ["legendary:255103"] = 1, ["upgrade:265340"] = 33 },
        equipment = { [16] = { itemId = 1234, itemLevel = 226 } },
    }
    local function draw()
        ui.Draw(ui.layout(view.project({ family = "titan", catalog = catalog.forFamily("titan"),
            snapshots = { snapshot }, currentRealmId = 1, now = 1000 })))
    end
    local function overlays()
        local result = {}
        for _, object in ipairs(objects) do
            if object.kind == "text" and object.shown and object.fontSize == 10 then
                result[#result + 1] = object
            end
        end
        return result
    end
    cached[255103] = 326
    draw()
    local labels = overlays()
    test.eq(#labels, 3, "weapon level, legendary level and upgrade quantity are all visible")
    test.eq(labels[1].text, "226", "equipped weapon retains its observed level")
    test.eq(labels[2].text, "326", "owned legendary shows its own level without hovering")
    test.eq(labels[3].text, "33", "upgrade material still shows quantity rather than item level")
    test.eq(snapshot.items["legendary:255103"], 1, "drawing does not change the owned-item snapshot")
    cached[255103] = nil
    draw()
    labels = overlays()
    test.eq(labels[2].text, "?", "uncached legendary level is unknown, never its quantity")
    test.eq(#callbacks, 1, "uncached legendary schedules a local item-data callback")
    cached[255103] = 326
    callbacks[1]()
    test.eq(labels[2].text, "326", "loaded metadata updates the visible overlay without hovering")
    cached[255103] = nil
    draw()
    local oldCallback = callbacks[2]
    cached[255103] = 340
    draw()
    cached[255103] = 326
    oldCallback()
    test.eq(overlays()[2].text, "340", "stale callbacks cannot overwrite reused overlay labels")
    cached[255103] = nil
    draw()
    target:Hide()
    cached[255103] = 350
    callbacks[#callbacks]()
    test.eq(overlays()[2].text, "?", "closing the overview prevents late UI updates")
    target:Show()
    env.C_Item = { GetItemInfo = env.GetItemInfo }
    env.GetItemInfo = false
    draw()
    test.eq(overlays()[2].text, "350", "the namespaced item API also provides the overlay")
    env.C_Item.GetItemInfo = function() error("item cache unavailable") end
    env.Item = false
    draw()
    test.eq(overlays()[2].text, "?", "unavailable item APIs leave an unknown level without breaking the view")
    for _, invalid in ipairs({ 0, -1, math.huge, 0/0, "326" }) do
        env.C_Item.GetItemInfo = function() return "Item", nil, 5, invalid end
        draw()
        test.eq(overlays()[2].text, "?", "invalid item metadata never becomes a fabricated level")
    end
    test.eq(overlays()[1].text, "226", "unavailable cache never erases observed equipment levels")
    test.eq(overlays()[3].text, "33", "unavailable cache never erases upgrade quantities")
end
