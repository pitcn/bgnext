# BGNext data inventory

BGNext stores new data only under the existing local SavedVariables namespace `BiaoGe.BGNext`. No field listed here is transmitted outside the game. Existing BGLite fields outside this namespace are not migrated, searched, aggregated, or exposed by BGNext enhancement modules.

| Field | Subject/source | Purpose | Storage and retention | Recipients | User control | Risk |
| --- | --- | --- | --- | --- | --- | --- |
| `schemaVersion` | Plugin constant | Safe migrations | Local until BGNext data is cleared | None | Clear all BGNext data | Low |
| `settings` | User choices | Module preferences | Local until changed or cleared | None | Settings/reset | Low |
| `wishlist[realmId][player][raidId][difficultyIndex][bossIndex][slotIndex]` | Item IDs explicitly selected by the current player for their own logged-in character | Reproduce the original boss-and-slot wishlist and local reminders | Local until the user removes a slot, clears the raid, or clears BGNext data | Current player UI only | Edit slot/right-click remove/clear/import | Medium |
| `wishlistUnplaced[realmId][player][raidId][itemId]` | Items from the temporary BGNext flat wishlist that cannot be mapped reliably to one boss | Preserve user-entered test data without guessing a boss | Local until manually cleared or successfully placed | Current player UI only | Review and clear locally | Medium |
| Manual wishlist import/export text | Raid, difficulty, boss position and item IDs selected by the current player | User-directed backup and restore | Visible edit box only; BGNext does not write it outside SavedVariables or send it | Recipient chosen manually by the user after copying | Explicit click, full preview, cancel available | Medium |
| `equipmentFilters[realmId][player]` | Filter profiles selected or edited only for the currently logged-in character; defaults are derived from that character's class and client capabilities | Locally weaken unsuitable item rows in the current bill, loot list and auction log | Local until that character's profiles are deleted/reset or all BGNext data is cleared | Current player UI only | Select/disable, create, edit, delete, reorder and reset | Low |
| `ownCharacters[clientFamily][realmId][player]` | Characters observed only while the user is logged into them | Own-character overview | Last-seen snapshot only, overwritten on re-login; raid status expires on weekly reset; cleared per character, per family, or all | Current player UI only | Delete character/clear family/clear all | Medium |
| `currentRaid` | Current raid identity and the user’s current-raid purchases | Personal current-raid shopping summary | One current raid; cleared on new raid, settlement completion, or manual clear | None | Clear current raid | Medium |
| `auctionPresets` | User-entered increment and cap | Personal auction presets | Local until preset is removed | Existing BGLite auction flow only after user activation | Remove/reset | Medium |
| `currentSettlement.raidId` | Current raid context | Enforce one-settlement scope | One settlement, maximum seven days | None | New raid/manual clear/expiry | Medium |
| `currentSettlement.startedAt` / `expiresAt` | Local/server time | Enforce retention | Cleared with settlement | None | Manual clear | Low |
| `currentSettlement.trades` | Current-settlement trade events | Reconciliation | One settlement, maximum seven days | None | Manual clear | Medium |
| `currentSettlement.mails` | Current-settlement mail events | Reconciliation | One settlement, maximum seven days | None | Manual clear | Medium |
| Local addon conflict inventory | Addon folder name, enabled/loaded state, `X-Project`, `X-Upstream` | Prevent simultaneous local loading of known conflicting addons | Memory only; discarded after the login check | Current player UI only | Explicit confirmation before disabling; cancel leaves addon state unchanged | Low |

## Allowed settlement record fields

Trade records may contain only `player`, `itemId`, `amount`, `time`, and `status`. Mail records may contain only `player`, `itemId`, `amount`, `time`, `status`, and `direction`. Both are accepted only when their `raidId` matches the active settlement.

Mail subject, body, unrelated attachments, chat text, account identifiers, device identifiers, GUIDs, private notes, and cross-raid aggregates are prohibited.

## Own-character overview data

Snapshots are stored at `BiaoGe.BGNext.ownCharacters[clientFamily][realmId][player]`, keyed by the realm and name of the character the user is logged into, and are overwritten on each re-login (last-seen only, no history array). The allowed fields are `player`, `realmId`, `realmName`, `faction`, `class`, `level`, `itemLevel`, `money`, `updatedAt`, `equipment`, `currencies`, `items`, `raidStates`, and `professions`; every nested table is whitelisted and sanitized on write. Raid status (`raidStates`) is dropped once its weekly `resetsAt` timestamp has passed.

No other-player, cross-account, historical, communication, or migration data is accepted: BGNext never reads or stores another player's identity or information, never keeps a previous-value or profile history, and never persists chat, mail body, account/device identifiers, GUIDs, notes, or cross-raid aggregates for this feature. Currency columns whose reliable in-game API is not yet verified render blank rather than fabricating a value.

## Runtime-only data

Automatic-bidding state is memory-only. Its auction identity, item identity, current price, increment, cap, next bid, status, and stop reason must not be written to SavedVariables. Reloading the UI destroys the state.

Local addon conflict detection reads only the current client’s addon metadata and enabled/loaded state. It sends no channel messages, writes no SavedVariables and does not inspect other players’ addon versions.

Wishlist import/export never calls `SendChatMessage`, `C_ChatInfo.SendAddonMessage`, clipboard APIs, HTTP, telemetry or file APIs. BGNext only displays or accepts the text after an explicit user action.

Equipment-filter profiles are not read from or migrated into the legacy `BiaoGe.FilterClassItemDB` path. They contain rule identifiers and presentation choices only; they do not contain inspected equipment, suitability judgments or records about another player.
