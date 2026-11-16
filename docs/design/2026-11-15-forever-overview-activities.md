# Forever overview: Booty Bay weekly and profession cooldowns

## Requirements and evidence

The user requests local own-character activity and profession timers on the
existing multi-client addon, followed by direct installation for testing.
Their screenshot identifies quest 96076, 紧俏货——远古精灵奇珍. It is weekly,
not daily. Blizzard explicitly calls Pix Xizzix's dungeon quests weekly:
https://worldofwarcraft.blizzard.com/en-us/news/24315281/wow-forever-hotfixes-november-13-2026
The quest's public objectives and completion ID are documented at:
https://www.wowhead.com/forever/quest=96076/in-demand-ancient-elven-curiosities

Independently queried local Blizzard data is recorded in
`docs/maintenance/forever-overview-data.json`: wowf, CN, zhCN,
1.60.1.70938. The four quest IDs share UniqueBitFlag 69516. That proves
shared completion evidence, not that all four variants are currently offered.
No rotation schedule is invented. No separate daily is added for this quest.

The same data establishes shared transmute category 310 for Arcanite,
Legionite, essence and elemental-fire recipes. Mooncloth and Salt Shaker
have independent cooldowns. Iron to Gold and Mithril to Truesilver each have
an independent one-hour cooldown. Runtime reads actual cooldown values;
these DB2 durations are evidence only and never countdown constants.

Versioned API evidence is in `docs/maintenance/forever-overview-api.json`:
wow-ui-source / forever / tag 1.60.1 / commit
ca8368f2f2380cbe696854f7f2646387c278a61b. It covers quest flags, weekly reset,
spell ownership, spell cooldowns, item ownership, item cooldowns and bag events.
This is source evidence, not an in-game acceptance claim.

## Implementation

- Add a default-visible Booty Bay weekly column to the Forever catalog only.
  Reuse the existing weekly reader, model, projection and tooltip. Missing
  reset or unreliable completion returns unknown; expired offline observations
  are removed. Reuse the visible countdown's single reset refresh for the
  logged-in character, generalizing the memory-only Titan activity deadline.
- Add five cooldown columns: shared transmute, Mooncloth, Salt Shaker,
  Iron to Gold, Mithril to Truesilver. A recipe must be learned before its
  cooldown is read. Shared transmute picks a learned recipe and displays one
  timer. The shared header explains why these recipes are grouped.
- Salt Shaker is an item, not a learned recipe. Require learned Leatherworking
  plus ownership of item 15846 before reading the item timer. Missing evidence
  leaves the timer unavailable. Item counts are transient and never saved.
- Reuse debounced trade-skill updates and extend Forever bag updates to refresh
  only cooldown data. No combat spell-cast listener or periodic recipe scan.
- Preserve explicit column visibility preferences and all other client catalogs.
  No new SavedVariables container, migration, messages or recipients.

All code and labels are independently authored against existing BGNext modules
and Blizzard interfaces. No third-party addon implementation, assets or private
data tables were copied or packaged. Reviewed upstream changes are only four
locale entries in each of the three locale files; hash overrides are updated
individually. Other changes are original BGNext modules, tests and evidence.

## Verification

New behavioral tests were observed failing before each implementation slice:
missing weekly declaration, current-character reset refresh, missing profession
columns, cooldown refresh events and independent one-hour transmute columns.
Coverage includes unreliable quest/reset evidence, each shared transmute recipe,
ownership filtering, ready/countdown states, offline expiry, no hidden polling,
scoped updates preserving gold, and unrelated wishlist data preservation.
The repository gate and packaged-byte installation checks are recorded in the
canonical local handoff. Real client display and crafting remain user testing.
