# ADR-0006: Scoped reuse of Titan P6 item facts

- Status: Accepted
- Date: 2026-10-08
- Supplements: ADR-0003

## Decision

The maintainer has confirmed permission for BGNext to use the Ulduar item
data supplied in AtlasLootMY 2.6.0 / DungeonsAndRaids 3.0.0. The approved scope
is item IDs, boss associations and token/reward relationships needed to maintain
BGNext's Titan P6 catalog. This is a source-specific permission decision, not a
general license for AtlasLootMY or other third-party addons.

Source identity and the normalized factual inventory are recorded in
`docs/maintenance/titan-p6-data.json`. The active Ulduar `NORMAL` list is used;
commented historical catalogs, page markers, achievements and set-page identifiers
are excluded. Bosses are matched by name to BGNext's existing fourteen-boss order.

No AtlasLootMY program logic, UI, comments, translations, artwork, sounds or
private player data is incorporated. BGNext's loader and exchange-list construction
are independently authored against its existing `BG.Loot` schema. The installation
is read only during maintenance; BGNext neither requires nor reads AtlasLootMY at
runtime. The general ADR-0003 boundary continues to apply outside this exact scope.

## Limits

This decision records the maintenance permission; it does not claim official
endorsement or a blanket sublicense. Private authorization communications and
identities are not distributed. Source completeness is relative to the supplied
version, not proof of live-server completeness or every later hotfix.

The fragment's supplementary page is a multi-step legendary chain, not a direct
token exchange. It is deliberately not treated as proof that owning one fragment
means owning a finished weapon. Only explicit immediate token/reward mappings are
included; no new legendary monitoring or automation is added.
