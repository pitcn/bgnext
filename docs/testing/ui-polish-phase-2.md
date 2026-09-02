# BGNext UI polish phase 2 verification

## Automated evidence

- Visual-state tokens are deterministic for normal, hover, selected, disabled, and danger controls.
- Repeated state application is idempotent.
- The reversible ledger skin restores captured classic colors and surfaces after preview use.
- Navigation refresh preserves parent, anchors, width, and height and rolls back on mismatch.
- The style layer contains no geometry mutation, script replacement, polling, timers, addon communication, chat communication, or SavedVariables writes.
- Shared controls retain their classic fallback and use the scoped adapter only for the explicit preview preference.
- The price-preset page retains two columns, 12–30 rows per column, and at most 60 reusable item rows.
- Price-page decoration is bounded to one divider region plus backdrop styling on existing container frames; no per-item decoration is added.
- Decorative boss models remain outside the runtime load graph in both themes.

## Security, privacy, and provenance

- No data field, retention rule, message, recipient, export, automation, or external transmission changed.
- No third-party code, font, texture, icon, sound, or copied BiaoGe asset was added.
- The changed BGLite baseline files are limited to the TOC load entry and palette routing in existing button/navigation factories; each override is reviewed and hashed individually.

## Maintainer game-client acceptance

Status: `needs_game_validation`.

For each available client family (permanent 60, TBC, Titan/Mists, Retail):

1. Open a populated ledger at the user's normal transparency and verify the entire ledger still fits one screenshot.
2. Confirm the world and combat situation remain visible behind the ledger.
3. Switch among table, reconciliation, wishlist, and price-preset tabs and verify selected controls remain cyan rather than changing to the player's class color.
4. Hover normal, selected, disabled, and destructive buttons and verify the state returns correctly after leaving.
5. Open price presets and verify the boss navigation and two item columns have distinct quiet surfaces, one divider, up to 60 visible reusable rows, and a narrow scrollbar only on overflow.
6. Switch preview to classic and back without reload; verify no anchor, size, row capacity, focus, click target, or cumulative darkening changes.
7. Confirm boss models do not return in either appearance.

Do not describe any client family as visually verified until these checks are recorded from that real game client.
