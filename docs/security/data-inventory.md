# BGNext data inventory

BGNext stores new data only under the existing local SavedVariables namespace `BiaoGe.BGNext`. No field listed here is transmitted outside the game. Existing BGLite fields outside this namespace are not migrated, searched, aggregated, or exposed by BGNext enhancement modules.

| Field | Subject/source | Purpose | Storage and retention | Recipients | User control | Risk |
| --- | --- | --- | --- | --- | --- | --- |
| `schemaVersion` | Plugin constant | Safe migrations | Local until BGNext data is cleared | None | Clear all BGNext data | Low |
| `settings` | User choices | Module preferences | Local until changed or cleared | None | Settings/reset | Low |
| `wishlist` | User-entered item choices for self | Personal reminders | Local until item/list is cleared | None | Add/remove/clear | Low |
| `equipmentFilters` | User choices and current-character capabilities | Local display filtering | Local until profile is cleared | None | Edit/reset | Low |
| `ownCharacters` | Characters observed only while the user is logged into them | Own-character overview | Local until character/module/all data is cleared | None | Delete character/disable/clear | Medium |
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

## Runtime-only data

Automatic-bidding state is memory-only. Its auction identity, item identity, current price, increment, cap, next bid, status, and stop reason must not be written to SavedVariables. Reloading the UI destroys the state.

Local addon conflict detection reads only the current client’s addon metadata and enabled/loaded state. It sends no channel messages, writes no SavedVariables and does not inspect other players’ addon versions.
