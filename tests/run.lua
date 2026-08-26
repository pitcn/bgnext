local T = dofile("tests/testlib.lua")
local suites = {
    "tests/test_init.lua",
    "tests/test_identity.lua",
    "tests/test_conflict_guard.lua",
    "tests/test_data_lifecycle.lua",
    "tests/test_baseline_safety.lua",
    "tests/test_current_settlement.lua",
    "tests/test_release_info.lua",
    "tests/test_wishlist.lua",
    "tests/test_wishlist_ui.lua",
    "tests/test_wishlist_reminder.lua",
    "tests/test_equipment_filter_profiles.lua",
    "tests/test_equipment_filter.lua",
}

for _, path in ipairs(suites) do
    T.run(path, dofile(path))
end

print(string.format("passed=%d failed=%d", T.passed, T.failed))
if T.failed > 0 then
    os.exit(1)
end
