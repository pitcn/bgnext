# BGNext Design Language

BGNext uses a dense, translucent, dark interface designed to remain readable while the player can still see the game world. Its visual structure is adapted from the single-accent, surface-ladder, hairline-border principles documented in VoltAgent's MIT-licensed [Linear DESIGN.md](https://github.com/VoltAgent/awesome-design-md/blob/main/design-md/linear.app/DESIGN.md), translated to the constraints of World of Warcraft Lua frames.

## Atmosphere

- Quiet, precise and data-first; the table is the product.
- Translucent navy-black surfaces preserve battlefield visibility.
- Depth comes from small changes in surface value and 1px borders, never shadows, glow, gradients or decorative models.
- Dense information is acceptable; competing accents are not.

## Semantic colors

| Role | Hex | Use |
| --- | --- | --- |
| Brand | `#00E6FF` | Selected navigation, focus, section identity |
| Primary text | `#E8F1F8` | Emphasized labels and values |
| Secondary text | `#8EA6BA` | Boss names, hints, metadata |
| Tertiary text | `#626F7C` | Disabled and inherited values |
| Canvas | `#050B13` | Main translucent scrim |
| Surface 1 | `#07182A` | Ordinary controls and list rows |
| Surface 2 | `#0C2033` | Raised controls |
| Surface 3 | `#10314A` | Hovered controls |
| Hairline | `#24445E` | Default 1px border |
| Danger | `#FF8098` | Destructive actions and missing-ledger warning |
| Success | `#38C878` | Confirmed completion only |

Equipment quality colors and Blizzard class colors remain authoritative data colors. They must never be reused for navigation, Boss grouping, decoration or arbitrary headings.

## Typography

- Main/module navigation: 15px.
- Button label and section heading: 14px.
- Table body: 12–13px according to existing density.
- Caption, hint and metadata: 12px.
- Use one font voice. Hierarchy comes from size and color, not a different color per section.
- Avoid repeating labels inside every row when a column or mode already explains the meaning.

## Controls

- Ordinary button: Surface 2, hairline border, primary or restrained gold text where legacy affordance requires it.
- Hover: Surface 3, brighter hairline, primary text.
- Selected: lifted dark-cyan surface with one brand-cyan hairline.
- Disabled/inherited: Surface 1, secondary or tertiary text.
- Destructive action: danger color only when the action is currently available; hide inactive row-level delete controls.
- List navigation: no prominent box around every row. Normal rows use a nearly invisible hairline; only hover and selected rows gain emphasis.

## Layout and spacing

- Base unit: 4px. Preferred gaps: 4, 8, 12, 16.
- Preserve the one-screen ledger, reconciliation and wishlist grids.
- Use empty translucent canvas as whitespace instead of inserting decorative panels.
- Reuse existing row pools and fixed object budgets. Styling must not add recurring timers, OnUpdate handlers or per-row decorative textures.

## Do

- Let item quality and class colors communicate game data.
- Keep ordinary Boss names and structural labels neutral.
- Make selection obvious through one accent and surface lift.
- Keep focus and hover states reversible on classic and preview themes.

## Do not

- Give every Boss, column or section a different saturated color.
- Use boss models, glow, atmospheric gradients or animated decoration behind tables.
- Show a red clear icon when no explicit value exists.
- add visual objects in proportion to the number of items when a pooled or shared treatment is possible.

