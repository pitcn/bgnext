return function(test)
    BG = { BGNext = {} }
    dofile("Core/BGNext/Wishlist.lua")
    local ui = dofile("Core/BGNext/WishlistUI.lua")

    -- Minimal mock of the shared picker frame and the bill-slot helper that
    -- creates it. This exercises the real picker lifecycle code, not its source.
    local created = {}
    local function makeSlot(id)
        local slot = { id = id, focused = true }
        function slot:ClearFocus() self.focused = false end
        function slot:HasFocus() return self.focused end
        return slot
    end
    local function makePicker(slot)
        local picker = { owner = slot, shown = true }
        function picker:IsShown() return self.shown end
        function picker:Hide() self.shown = false end
        created[#created + 1] = picker
        return picker
    end
    BG.SetListzhuangbei = function(slot)
        BG.FrameZhuangbeiList = makePicker(slot)
    end

    local slotA, slotB = makeSlot("A"), makeSlot("B")

    -- 1. focusing an unselected slot opens that slot's picker.
    ui.openPicker(slotA)
    test.eq(BG.FrameZhuangbeiList.owner, slotA, "picker opens for the focused slot")
    test.eq(BG.FrameZhuangbeiList:IsShown(), true, "picker is shown")

    -- 2. switching to another slot hides the old picker and keeps only the new one.
    local first = BG.FrameZhuangbeiList
    ui.openPicker(slotB)
    test.eq(first:IsShown(), false, "the previous picker is hidden")
    test.eq(BG.FrameZhuangbeiList.owner, slotB, "the new picker owns the new slot")
    test.eq(BG.FrameZhuangbeiList:IsShown(), true, "the new picker is shown")

    -- 3. clicking the same slot collapses it, then reopens on the next click.
    ui.togglePicker(slotB)
    test.eq(BG.FrameZhuangbeiList:IsShown(), false, "clicking the open slot collapses it")
    ui.togglePicker(slotB)
    test.eq(BG.FrameZhuangbeiList:IsShown(), true, "clicking again reopens it")

    -- 4. toggling to another slot keeps at most one picker.
    ui.togglePicker(slotA)
    test.eq(BG.FrameZhuangbeiList.owner, slotA, "toggle moves the picker to the other slot")
    test.eq(BG.FrameZhuangbeiList:IsShown(), true, "only the new picker is shown")

    -- 5. closing hides the picker and clears the owning slot's focus.
    slotA.focused = true
    ui.closePicker()
    test.eq(BG.FrameZhuangbeiList:IsShown(), false, "closing hides the picker")
    test.eq(slotA.focused, false, "closing clears the owning slot's focus")

    -- 6. the slot handlers are wired through the lifecycle, not directly to the
    --    shared frame helper, so toggle and single-owner behaviour cannot regress.
    local source = assert(io.open("Core/BGNext/WishlistUI.lua", "rb")):read("*a")
    test.eq(source:find("M.openPicker(self)", 1, true) ~= nil, true,
        "focus gain opens through the picker lifecycle")
    test.eq(source:find("M.togglePicker(self)", 1, true) ~= nil, true,
        "same-slot click toggles through the picker lifecycle")
    test.eq(source:find("SetScript(\"OnHide\", M.closePicker)", 1, true) ~= nil, true,
        "hiding the wishlist page closes the picker")
end
