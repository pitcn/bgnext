# BGNext data inventory

BGNext stores new data only under the existing local SavedVariables namespace `BiaoGe.BGNext`. No field listed here is transmitted outside the game. Existing BGLite fields outside this namespace are not migrated, searched, aggregated, or exposed by BGNext enhancement modules.

| Field | Subject/source | Purpose | Storage and retention | Recipients | User control | Risk |
| --- | --- | --- | --- | --- | --- | --- |
| `schemaVersion` | Plugin constant | Safe migrations | Local until BGNext data is cleared | None | Clear all BGNext data | Low |
| `settings` | User choices | Module preferences | Local until changed or cleared | None | Settings/reset | Low |
| `settings.roleOverviewEnabled` | User toggle | Enable/disable the own-character overview module; disables collection and refresh, deletes nothing | Local until changed or cleared | None | Settings checkbox | Low |
| `settings.roleOverviewPoint` | Window anchor (point, relativePoint, x, y only) | Restore the overview window position; frame references are never written | Local until moved or cleared | None | Drag window | Low |
| `roleOverviewColumns[clientFamily][section][columnId]` | User-hidden column choices, booleans only | Per-family column visibility | Local until reset or cleared | None | Settings checkboxes/reset | Low |
| `wishlist[realmId][player][raidId][difficultyIndex][bossIndex][slotIndex]` | Item IDs explicitly selected by the current player for their own logged-in character | Reproduce the original boss-and-slot wishlist and local reminders | Local until the user removes a slot, clears the raid, or clears BGNext data | Current player UI only | Edit slot/right-click remove/clear/import | Medium |
| `wishlistUnplaced[realmId][player][raidId][itemId]` | Items from the temporary BGNext flat wishlist that cannot be mapped reliably to one boss | Preserve user-entered test data without guessing a boss | Local until manually cleared or successfully placed | Current player UI only | Review and clear locally | Medium |
| Manual wishlist import/export text | Raid, difficulty, boss position and item IDs selected by the current player | User-directed backup and restore | Visible edit box only; BGNext does not write it outside SavedVariables or send it | Recipient chosen manually by the user after copying | Explicit click, full preview, cancel available | Medium |
| `equipmentFilters[realmId][player]` | Filter profiles selected or edited only for the currently logged-in character; defaults are derived from that character's class and client capabilities | Locally weaken unsuitable item rows in the current bill, loot list and auction log | Local until that character's profiles are deleted/reset or all BGNext data is cleared | Current player UI only | Select/disable, create, edit, delete, reorder and reset | Low |
| `ownCharacters[clientFamily][realmId][player]` | Characters observed only while the user is logged into them | Own-character overview | Last-seen snapshot only, overwritten on re-login; raid status expires on weekly reset; cleared per character, per family, or all | Current player UI only | Delete character/clear family/clear all | Medium |
| `currentRaid` | Current raid identity and the user’s current-raid purchases | Personal current-raid shopping summary | One current raid; cleared on new raid, settlement completion, or manual clear | None | Clear current raid | Medium |
| `currentSettlement.raidId` | Current raid context | Enforce one-settlement scope | One settlement, maximum seven days | None | New raid/manual clear/expiry | Medium |
| `currentSettlement.sourceFb` / `sourceRealm` | Existing BGLite table key and current realm | Keep the settlement identity stable when BGLite refreshes its roster timestamp after each boss | Cleared with settlement | None | New raid/manual clear/expiry | Low |
| `currentSettlement.startedAt` / `expiresAt` | Local/server time | Enforce retention | Cleared with settlement | None | Manual clear | Low |
| `currentSettlement.trades` | Current-settlement trade events | Reconciliation | One settlement, maximum seven days | None | Manual clear | Medium |
| `currentSettlement.mails` | Current-settlement mail events | Reconciliation | One settlement, maximum seven days | None | Manual clear | Medium |
| Local addon conflict inventory | Addon folder name, enabled/loaded state, `X-Project`, `X-Upstream` | Prevent simultaneous local loading of known conflicting addons | Memory only; discarded after the login check | Current player UI only | Explicit confirmation before disabling; cancel leaves addon state unchanged | Low |

## Allowed settlement record fields

Trade records may contain only `player`, `itemId`, `amount`, `time`, and `status`. Mail records may contain only `player`, `itemId`, `amount`, `time`, `status`, and `direction`. Both are accepted only when their `raidId` matches the active settlement, and the accepted record is rebuilt field by field from that whitelist, so `raidId` itself is never copied into a record: it exists only once, as `currentSettlement.raidId`.

The values of `status` and `direction` are whitelisted as well, so free text cannot reach storage through them. Trade `status` accepts only `complete`, `pending`, `failed`, or `cancelled`; mail `status` accepts only `sent`, `pending`, or `failed`; mail `direction`, when present, accepts only `outgoing` or `incoming`. A record whose whitelisted fields are all equal to an already stored record is rejected, so a repeated event cannot become a second row.

`currentSettlement.raidId` is initially derived from BGLite's existing per-table `BiaoGe[<table>].raidRoster` stamp (its raid table key and `time`). BGLite refreshes that timestamp after every boss, so BGNext keeps the first identity stable while BGLite's existing same-team check still identifies the group as the same. A different table, a same-instance new-team result, explicit table clear, or expiry replaces it. `sourceFb` and `sourceRealm` contain only that attribution metadata; roster content is never copied into `BiaoGe.BGNext`.

Runtime attribution is stricter than storage validation: a trade or batch-mail result is accepted only when its counterparty appears in BGLite's existing roster for the active settlement. That roster is read transiently and is not copied. Batch mail must also originate from the existing `raid` recipient scope; custom recipient lists are rejected. Identical client result messages are guarded by memory-only attempt state before they reach storage.

Mail subject, body, unrelated attachments, chat text, account identifiers, device identifiers, GUIDs, private notes, and cross-raid aggregates are prohibited. `BiaoGe.tradeHistory`, `BiaoGe.mailHistory`, and `BiaoGe.History` are never read or migrated.

## Own-character overview data

Snapshots are stored at `BiaoGe.BGNext.ownCharacters[clientFamily][realmId][player]`, keyed by the realm and name of the character the user is logged into, and are overwritten on each re-login (last-seen only, no history array). The allowed fields are `player`, `realmId`, `realmName`, `faction`, `class`, `level`, `itemLevel`, `money`, `updatedAt`, `equipment`, `currencies`, `items`, `raidStates`, and `professions`; every nested table is whitelisted and sanitized on write. Equipment and profession textures accept only a Blizzard string path or numeric file ID. Grouped raid states may additionally store numeric `completedParts` and `totalParts`; raid status is dropped once its weekly `resetsAt` timestamp has passed.

On the Titan client, `currencies` may contain only the locally read values for the explicitly declared currency columns. `items` may additionally contain numeric counts keyed as `legendary:<itemId>` or `upgrade:<itemId>` for the fixed legendary-summary item lists. These values come only from `GetItemCount` for the logged-in character and are used only to reproduce the local “已有橙武” and “升级物品” columns; they are not inventory history and are overwritten with the next character snapshot.

No other-player, cross-account, historical, communication, or migration data is accepted: BGNext never reads or stores another player's identity or information, never keeps a previous-value or profile history, and never persists chat, mail body, account/device identifiers, GUIDs, notes, or cross-raid aggregates for this feature. Currency columns whose reliable in-game API is not yet verified render blank rather than fabricating a value.

## Runtime-only data

Automatic-bidding state is memory-only. Its auction identity, item identity, current price, increment, cap, next bid, status, and stop reason must not be written to SavedVariables. Reloading the UI destroys the state.

Local addon conflict detection reads only the current client’s addon metadata and enabled/loaded state. It sends no channel messages, writes no SavedVariables and does not inspect other players’ addon versions.

Wishlist import/export never calls `SendChatMessage`, `C_ChatInfo.SendAddonMessage`, clipboard APIs, HTTP, telemetry or file APIs. BGNext only displays or accepts the text after an explicit user action.

Equipment-filter profiles are not read from or migrated into the legacy `BiaoGe.FilterClassItemDB` path. They contain rule identifiers and presentation choices only; they do not contain inspected equipment, suitability judgments or records about another player.
