# Titan effective item-level compatibility research

## References studied

- Supplied BGLite 2.4.2 baseline.
- Locally obtained BiaoGe 2.3.5, BGLitePlus 2.4.8, BiaoGePlus 2.2.4, Skye/YeYue-style BGLite variants, and BGForge 0.2.0, for behavior comparison only.
- Blizzard Titan UI source snapshot `ba472e5e1b5580b557e3dbf02c9e5ff23b223347`, queried through wowdoc.

## Compatibility facts learned

- The compared BiaoGe-family table widgets use the sparse item level returned by the historical item-info API and keep labels limited to weapon and armor classes.
- Titan exposes the official detailed item-level API, and Blizzard's own item object uses it for a static item link's current level.
- Some separately obtained modules use a detailed-level-first fallback, but their implementation, identifiers, structure and text were not reused.

## BGNext requirement

- Resolve an item's effective level through the official namespaced API when available, use the historical global API on clients that expose only that form, and otherwise preserve the existing sparse value.
- Keep the existing weapon/armor visibility boundary.
- Use the same resolved level in table labels, loot insertion, auction windows and records, trade-delivery rows, and unsold-item announcements so one item does not show conflicting levels.
- API absence, an unloaded item, an error, a non-item row or a non-equipment item must retain the previous behavior without blocking the surrounding workflow.

## Independent implementation boundary

BGNext implements a small compatibility adapter against Blizzard API contracts and routes existing BGNext/BGLite call sites through that adapter. No third-party source, data table, identifier, message text, asset or import format is copied or repackaged.
