local T = dofile("tests/testlib.lua")
local suites = {
    "tests/test_init.lua",
    "tests/test_identity.lua",
    "tests/test_conflict_guard.lua",
    "tests/test_data_lifecycle.lua",
    "tests/test_baseline_safety.lua",
    "tests/test_release_builder.lua",
    "tests/test_current_settlement.lua",
    "tests/test_current_settlement_view.lua",
    "tests/test_current_settlement_runtime.lua",
    "tests/test_current_settlement_ui.lua",
    "tests/test_release_info.lua",
    "tests/test_wishlist.lua",
    "tests/test_wishlist_ui.lua",
    "tests/test_retail_loot_status.lua",
    "tests/test_wishlist_picker.lua",
    "tests/test_wishlist_reminder.lua",
    "tests/test_equipment_filter_profiles.lua",
    "tests/test_item_primary_stats.lua",
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
    "tests/test_entry_interactions.lua",
    "tests/test_entry_menu_lifecycle.lua",
    "tests/test_entry_menu_runtime.lua",
    "tests/test_player_identity.lua",
    "tests/test_trade_auction_state.lua",
    "tests/test_bill_buyer.lua",
    "tests/test_auction_sender.lua",
    "tests/test_ledger_capture.lua",
    "tests/test_ledger_runtime_privacy.lua",
    "tests/test_chat_yy_copy.lua",
    "tests/test_main_frame_scale.lua",
}

for _, path in ipairs(suites) do
    T.run(path, dofile(path))
end

print(string.format("passed=%d failed=%d", T.passed, T.failed))
if T.failed > 0 then
    os.exit(1)
end
