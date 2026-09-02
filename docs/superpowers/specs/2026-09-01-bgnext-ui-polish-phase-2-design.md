# BGNext UI Polish Phase 2 Design

## Status and decision authority

The maintainer has delegated the visual decisions for this phase and asked implementation to proceed without further mockup approval. This specification therefore fixes the scope before code changes and treats the in-game screenshots from 2026-09-01 as the visual baseline.

## Problem

The preview theme preserves the familiar one-screen BiaoGe ledger, transparency, and screenshot workflow, but it still reads as a classic interface with a dark tint. Repeated grey borders, class-colored selected tabs, mixed button treatments, and an undifferentiated price-preset page prevent the interface from feeling coherent or premium.

The role overview already demonstrates the desired direction: restrained dark surfaces, deliberate spacing, quiet separators, strong text hierarchy, and cyan used as a state color rather than decoration.

## Goals

- Keep the complete ledger visible on one screen and preserve its current geometry.
- Keep the user's existing background transparency so combat and the game world remain visible.
- Establish one BGNext visual language across navigation, buttons, and the price-preset page.
- Use the logo cyan as the primary state color and warm gold only for secondary actions or legacy business emphasis.
- Make selected, hover, inactive, and disabled states visually distinct without animation or polling.
- Improve the price-preset page's two-column hierarchy without reducing its 24–60 reusable-row capacity.
- Keep the preview reversible; classic appearance restores the previous visual state, except removed boss models remain removed as already decided.

## Non-goals

- No ledger layout, row count, column width, anchoring, font-size, or screenshot-boundary redesign.
- No changes to auction, settlement, wishlist, filtering, pricing, communication, persistence, or SavedVariables behavior.
- No third-party code, textures, fonts, icons, sounds, or copied BiaoGe assets.
- No animation, `OnUpdate`, timers, background work, or per-frame styling.
- No attempt to restyle item-quality, class, success, warning, or error colors.

## Considered approaches

### A. Full ledger reconstruction

Rebuild the ledger with new containers, controls, and responsive layout. This offers the strongest visual change but breaks the five-year screenshot and muscle-memory workflow, creates extensive cross-version risk, and is outside this phase.

### B. Scoped visual system over the existing geometry — selected

Keep every existing ledger frame in place. Extend the original BGNext theme tokens, apply them to known navigation controls through the reversible skin, modernize the shared button palette, and give the BGNext-owned price page its own quiet surfaces and button treatment. This creates a coherent result with limited runtime and compatibility risk.

### C. Price page only

Polish only the new price-preset page. This is safest but leaves the selected tabs and general plugin controls inconsistent, so the product still feels assembled from two visual systems.

## Visual system

### Palette

- Window: `#010F23`, used at the user's existing alpha.
- Surface: `#07182A`, for navigation and large local groupings.
- Raised surface: `#0C2033`, for controls and hover elevation.
- Border: `#24445E`, quiet default outline.
- Strong border: `#2A7896`, hover and focus outline.
- Brand cyan: `#00E6FF`, selected state, active underline, and current context.
- Warm gold: `#F5B230`, secondary action text and retained ledger emphasis.
- Primary text: `#E8F1F8`; secondary text: `#8EA6BA`.
- Danger remains red and item/class/business colors remain untouched.

### State rules

- Inactive navigation: transparent raised navy, quiet border, secondary or gold text.
- Hover: slightly brighter raised navy, strong border, primary text.
- Selected navigation: cyan-tinted navy fill, cyan border or underline, primary text.
- Truly disabled action: low-contrast surface and secondary text; it must not look selected.
- No glow, pulse, scale, fade, or moving highlight.

## Ledger treatment

The main window keeps its current alpha, dimensions, position, and all row controls. The preview skin continues to style only an explicit registry of known widgets. It will:

- deepen the window and title surfaces without applying alpha twice;
- replace class-colored selected module and raid navigation with cyan state treatment;
- restore preview colors after tab selection changes, because the legacy tab handler currently reapplies class color;
- leave equipment names, buyer class colors, amounts, boss colors, and all edit-box geometry untouched;
- remain idempotent and roll back to classic on error or geometry mismatch.

The shared legacy button factory receives palette-only changes so settings and secondary plugin controls no longer introduce unrelated black/class-color gradients. The factory's geometry and scripts remain intact.

## Price-preset page treatment

The page keeps the approved left boss navigation plus two equipment columns. Changes are visual and local:

- boss navigation and item area receive separate low-alpha navy surfaces with quiet borders;
- a subtle divider separates the two equipment columns;
- BGNext-owned buttons use flat navy states instead of the legacy black gradient;
- selected raid, mode, and boss controls use cyan treatment;
- destructive clear/delete controls retain red semantics;
- the scrollbar keeps its narrow cyan thumb but gains a low-contrast track consistent with the border token;
- row count and filtering behavior remain unchanged.

Only a handful of background/divider textures are created once with the page. The existing 24–60 reusable equipment rows remain the only item-row objects.

## Architecture

`UITheme.lua` remains the token and pure state contract. `LegacyLedgerSkin.lua` remains the reversible adapter for the established ledger. A small BGNext-only `UIStyle.lua` module owns conversion of hex tokens and styling of explicit button/surface widgets; it does not enumerate the UI tree or store data. `AuctionPriceUI.lua` uses this module only for its own widgets.

The legacy `BG.CreateButton` and module-tab color functions receive narrowly reviewed palette changes so subsequent hover/leave/tab clicks do not overwrite preview state with class green or black gradients. They consult the saved preview choice without adding a new field.

## Performance and compatibility

- Styling runs only when widgets are created, refreshed because their selected state changes, or the appearance is switched.
- No continuous hooks, timers, scans, or event listeners are added.
- The price page adds at most four decorative regions and no additional item rows.
- Client-specific API use is limited to APIs already used by the addon: backdrop colors, color textures, gradients, and font colors.
- Real-client appearance remains `needs_game_validation` for each client family until tested in game.

## Testing

- Pure tests lock the token values and button-state palette.
- Fake-widget tests verify preview apply, repeated apply, tab-state reapply, exact classic restore, and geometry rollback.
- Source-safety tests reject polling, communication, and geometry mutation in the reversible skin and style helper.
- Price-page tests confirm the two-column capacity remains unchanged and decorative object counts are bounded.
- Full Lua, baseline-integrity, package-content, and whitespace checks run before delivery.

## Acceptance criteria

- Selected bottom and raid tabs use BGNext cyan rather than the player's class color while preview is active.
- The main ledger remains a single screenshot with unchanged positions and capacity.
- The game world remains visible at the user's configured alpha.
- Price presets retain two columns and show up to 60 reusable rows with clearer visual grouping.
- Classic/preview switching is immediate and reversible for colors and surfaces.
- Boss models never return in either theme.
- No runtime data, communication, or gameplay behavior changes.
