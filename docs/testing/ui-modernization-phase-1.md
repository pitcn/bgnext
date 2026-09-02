# UI modernization phase 1 verification

## Automated scope

- Theme enum defaults to classic and rejects unknown values.
- Brand token values and alpha bounds are fixed and tested.
- Preview application is idempotent and classic restores the captured visual state.
- Any exception or geometry mismatch rolls back to classic.
- Parent, all points, width and height are compared for the main frame and explicit navigation tabs.
- The skin source contains no geometry mutation, event replacement, polling, object creation, communication, or transparency-setting writes.
- Only an explicit successful user choice persists `BiaoGe.BGNext.settings.uiTheme`.

## Maintainer game-client acceptance (not yet verified)

For each available client family (permanent 60, TBC, Titan/Mists, Retail):

1. Back up SavedVariables and log in with the classic default.
2. Open a populated ledger and capture screenshots at 1920x1080 and 2560x1440 where available.
3. Record main frame, raid tabs, boss/area sections, summary, bottom actions, and full screenshot boundary.
4. Switch to BGNext preview without reload and confirm the same positions, dimensions, row/column capacity, text clipping, clicks, focus, auction entry, and screenshot composition.
5. Fill or load approximately 100 equipment rows and confirm one-image sharing remains practical.
6. Test the user's existing background alpha and the 0.58 reference while combat scenery remains visible.
7. Switch repeatedly classic -> preview -> classic and confirm no drift, darkening, duplicated scripts, or new objects.
8. Reload in preview, then switch back to classic; verify preference persistence and exact rollback.
9. Verify item-quality colors, class colors, error/success/warning colors, and input focus remain distinguishable.

Do not mark a client visually verified until the maintainer records the result from that client.
