return function(test)
    BG = { BGNext = {} }
    BG.BGNext.UITheme = dofile("Core/BGNext/UITheme.lua")
    BG.BGNext.LegacyLedgerSkin = dofile("Core/BGNext/LegacyLedgerSkin.lua")
    local Settings = dofile("Core/BGNext/UIThemeSettings.lua")

    local function read(path)
        local f = assert(io.open(path, "rb"))
        local s = f:read("*a")
        f:close()
        return s
    end

    -- read: missing and invalid preferences resolve to classic without writing.
    test.eq(Settings.read({ settings = {} }), "classic", "empty settings read classic")
    test.eq(Settings.read({ settings = { uiTheme = "future" } }), "classic", "invalid theme reads classic")
    test.eq(Settings.read(nil), "classic", "missing root reads classic")

    local noAdd = { settings = {} }
    Settings.read(noAdd)
    test.eq(noAdd.settings.uiTheme, nil, "read does not add uiTheme")

    local invalid = { settings = { uiTheme = "future" } }
    Settings.read(invalid)
    test.eq(invalid.settings.uiTheme, "future", "read does not rewrite invalid value")

    -- choose: persists only after a successful apply.
    local called = 0
    local root = { settings = {} }
    test.eq(Settings.choose(root, "preview", function(id)
        called = called + 1
        return true
    end), true, "choose preview succeeds")
    test.eq(root.settings.uiTheme, "preview", "preview persisted only after success")
    test.eq(called, 1, "apply called exactly once on success")

    root.settings.uiTheme = "classic"
    test.eq(Settings.choose(root, "preview", function(id) return false, "boom" end), false, "failed choose returns false")
    test.eq(root.settings.uiTheme, "classic", "failed apply leaves prior value unchanged")

    called = 0
    test.eq(Settings.choose(root, "future", function(id) called = called + 1; return true end), false, "invalid theme rejected")
    test.eq(called, 0, "invalid theme does not call apply")

    -- buildPanel returns harmlessly when prerequisites are missing.
    test.eq(Settings.buildPanel(), nil, "buildPanel returns nil without prerequisites")

    -- Source safety: never assign options.alpha, never reload, never mutate ledger geometry.
    local source = read("Core/BGNext/UIThemeSettings.lua")
    test.eq(source:find("options%.alpha%s*="), nil, "settings source never assigns options.alpha")
    test.eq(source:find("ReloadUI", 1, true), nil, "settings source has no ReloadUI")
    for _, token in ipairs({
        "ClearAllPoints", "SetWidth", "SetHeight", "SetParent",
        "SetFrameLevel", "SetFrameStrata",
    }) do
        test.eq(source:find(token, 1, true), nil, "settings source forbids ledger geometry " .. token)
    end

    -- TOC loads the settings module after Core\Options.lua.
    local toc = read("BGLite.toc")
    local optionsPos = toc:find("Core\\Options.lua", 1, true)
    local settingsPos = toc:find("Core\\BGNext\\UIThemeSettings.lua", 1, true)
    test.eq(settingsPos ~= nil, true, "TOC loads settings module")
    test.eq(optionsPos and settingsPos and optionsPos < settingsPos, true, "settings loads after options")
end
