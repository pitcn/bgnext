# UI semantic hierarchy verification

## Scope

This pass adapts the single-accent, surface-ladder and hairline-border principles described by VoltAgent's MIT-licensed `awesome-design-md` Linear analysis into BGNext's own translucent cyan design language. No third-party runtime source, artwork, font, CSS or asset is included in the addon package.

Runtime changes are presentation-only:

- shared ordinary button typography changes from 15px to 14px;
- preview-theme Boss labels use semantic brand, secondary and danger roles;
- price rows use compact values and hide inactive clear controls;
- own-character headings use one neutral hierarchy while preserving Blizzard class colors and item icons;
- top utility labels and role-overview controls receive reversible preview states.

No SavedVariables field, data retention rule, auction protocol, communication recipient, timer, polling loop or player-data collection path changes.

## Automated evidence

- `tests/test_ui_style.lua`: semantic tokens, list emphasis, idempotent application, live classic restoration and utility-button restoration.
- `tests/test_auction_price_ui.lua`: inherited/explicit leader prices, unset/explicit personal prices, clear-action visibility contract and scoped Boss-list styling.
- `tests/test_own_character_ui.lua`: cyan title, gray-blue hints, neutral headers, class-color preservation and pooled rendering constraints.
- `tests/test_role_overview_entry.lua`: fixed compact controls, hover feedback and unchanged privacy/communication invariants.
- `tools/verify-baseline.ps1`: the three changed upstream runtime files are explicit BGNext overrides.

## Manual validation still required

The appearance remains `needs_game_validation` on permanent 60, TBC, Titan/Mists and Retail clients. In-game review should confirm font readability at common UI scales, Boss-label contrast over bright scenes, correct classic/preview switching, and that hidden clear controls reappear immediately after entering an explicit item price.

