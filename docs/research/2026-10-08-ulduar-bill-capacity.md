# Titan P6 Ulduar bill capacity

## Scope and reference evidence

The maintainer requested Ulduar capacity comparable to the restored local BGLite package. Read-only inspection of the package reporting version 2.10.8 found four display columns, 52 miscellaneous entries, and raid-wide aggregation of the current fragment item 270187. The local per-file inventory is retained outside Git at `.local/bglite-restored-fragments-inventory.json`. This is a local integration package, not a newly verified official baseline. Under ADR-0003, these observations inform independently defined capacity requirements; no source, assets, or private layout table were imported.

## Independent layout requirements

Use the existing 1685-pixel wide frame and four-column rendering mechanism, with a height of 920 pixels. Provide 56 miscellaneous entries in groups of 32 and 24; the existing fold mechanism starts the second group at entry 33. An initially considered 28/28 split would push the final column summary below the 920-pixel frame once fine, expense, and summary scroll sections are included. Boss capacity is the maximum of each existing BGNext capacity and the observed reference requirement. Consequently, the existing larger Auriaya and Algalon capacities are retained. Boss IDs, misc key `boss15`, fine key `boss16`, expense key `boss17`, and summary key `boss18` remain stable. Fine and expense capacities are unchanged. No migration or SavedVariables reads are needed.

Fragment aggregation, the single 25-player drop catalog, wishlist eligibility, auction rules, and all other raid layouts are unchanged. The new capacity is finite; this change does not add automatic unlimited row growth or discover new item definitions.

## Clear boundary and regression evidence

The original clear loop visited only 50 entries. Expanding the layout alone reproduced retained data beyond entry 50. The loot/fine clear loop now visits the greater of the existing 50-entry cleanup range and the raid section's actual capacity. Expense retention behavior is unchanged.

`tests/test_titan_p6_capacity.lua` first failed for the original three-column layout, then failed for uncleared expanded entries after the layout was changed, and passed after the clear boundary fix. It executes the actual Titan declarations, equipment-widget positioning/value restoration prefix, income function, and clear function. It covers all 56 saved misc entries, the fold anchor, preserved last-boss data, total income including entries 51-56, cleared item/amount/loot fields, and unchanged P5 layout. Widget mocks provide simulated evidence only; live client rendering, screen scaling, full-raid overflow, and reload behavior require in-game validation.
