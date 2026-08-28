local T = dofile("tests/testlib.lua")
local suites = {
    "tests/test_init.lua",
    "tests/test_identity.lua",
    "tests/test_conflict_guard.lua",
    "tests/test_data_lifecycle.lua",
    "tests/test_baseline_safety.lua",
    "tests/test_current_settlement.lua",
    "tests/test_current_settlement_view.lua",
    "tests/test_current_settlement_runtime.lua",
    "tests/test_current_settlement_ui.lua",
    "tests/test_release_info.lua",
    "tests/test_wishlist.lua",
    "tests/test_wishlist_ui.lua",
    "tests/test_wishlist_picker.lua",
    "tests/test_wishlist_reminder.lua",
    "tests/test_equipment_filter_profiles.lua",
    "tests/test_equipment_filter.lua",
    "tests/test_current_purchases.lua",
    "tests/test_equipment_filter_ui.lua",
    "tests/test_own_characters.lua",
    "tests/test_own_character_adapters.lua",
    "tests/test_own_character_collector.lua",
    "tests/test_own_character_readers.lua",
    "tests/test_own_character_runtime.lua",
    "tests/test_own_character_view.lua",
    "tests/test_own_character_ui.lua",
    "tests/test_role_overview_entry.lua",
    "tests/test_auction_names.lua",
    "tests/test_auction_preset_store.lua",
    "tests/test_controlled_auto_bid.lua",
    "tests/test_auction_bid_message.lua",
    "tests/test_auction_bid_ui.lua",
    "tests/test_auction_preset_runtime.lua",
}

for _, path in ipairs(suites) do
    T.run(path, dofile(path))
end

print(string.format("passed=%d failed=%d", T.passed, T.failed))
if T.failed > 0 then
    os.exit(1)
end
