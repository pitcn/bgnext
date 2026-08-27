# Own-character overview — clean-room verification

This feature is a clean-room reimplementation of the BiaoGe-visible table workflow. It stores only last-seen snapshots of the locally logged-in player and renders the approved two-section horizontal table. It reads no other player, registers no chat/combat/inspect/addon-message event, and sends nothing.

## Client-family compatibility status

A catalog entry only means BGNext can build a column list for that family. It does **not** mean the family is supported. Status is assigned only from actual evidence.

| Family | Detection | Column coverage | Raid-status API | Currency APIs | Status |
| --- | --- | --- | --- | --- | --- |
| Anniversary / Titan | `IsTitan` | Raids + equipment + money + professions + Titan-shard/emblem columns defined | Code-covered | Titan-shard/emblem IDs code-covered | **Code-covered, awaiting in-game validation** (first full validation target) |
| Vanilla | `IsVanilla` | Raids + equipment + money + professions | Code-covered | None verified | Code-covered / simulated / unverified |
| The Burning Crusade | `IsTBC` | Raids + equipment + money + professions | Code-covered | None verified | Code-covered / simulated / unverified |
| Wrath of the Lich King | `IsWLK` | Raids + equipment + money + professions + emblem | Code-covered | Emblem ID code-covered | Code-covered / simulated / unverified |
| Cataclysm | `IsCTM` | Raids + equipment + money + professions + valor | Code-covered | Valor ID code-covered | Code-covered / simulated / unverified |
| Mists of Pandaria | `IsMOP` | Raids + equipment + money + professions + valor | Code-covered | Valor ID code-covered | Code-covered / simulated / unverified |
| Retail | `IsRetail` | Raids + equipment + money + professions | Code-covered | None verified | Code-covered / simulated / unverified |

No family is marked "supported". The Anniversary/Titan client is the first in-game validation target; every other family remains explicitly unverified until a real client confirms detection, raid status, and each currency column that BGNext declares visible.

## Automated evidence

- `tools/run-lua-tests.ps1` — all suites report `failed=0` (`passed=22` at last run).
- `tools/verify-baseline.ps1` — 188-file upstream manifest intact, with explicit BGNext override hashes for only the files changed here.
- `git diff --check` — no whitespace errors.
- Privacy scan (`SendAddonMessage|SendChatMessage|C_ChatInfo|INSPECT_READY|COMBAT_LOG_EVENT|CHAT_MSG` across `Core/BGNext/OwnCharacters*.lua` and `Core/BGNext/RoleOverview*.lua`) — no matches.

## Items requiring in-game validation

Capture on the Anniversary/Titan client with matching resolution, UI scale, realm, raid and sample characters:

1. Default view — current realm only, characters as rows, raid/resource columns as headers.
2. Shift view — all local realms, including two same-name characters on different realms with a short realm prefix.
3. Hidden raid column (e.g. 熔火之心) — window shrinks immediately, snapshot data is not deleted.
4. Hidden resource/currency column (e.g. 泰坦碎片) — window shrinks, snapshot data is not deleted.
5. Pinned window (middle-click or Ctrl+left on the 角色总览 entry) and drag/save position.
6. Settings panel — raid and resource column checkboxes plus 恢复当前版本默认列.
7. Live collection chain — logging in / entering the world / changing gear, level, gold, bag, currency, raid lock, or professions updates the current character; the refresh control re-collects rather than redraws.
8. `/bgn role` and `/bgnext role` toggle the overview without a `hooksecurefunc("SlashCmdList", …)`.
9. Right-click a character row deletes it after the confirmation dialog, using the full family+realmId+player key (same-name cross-realm characters stay distinct).
10. Window position is saved as point/relativePoint/x/y only and restored on open; a corrupt or off-screen position resets to a safe default.
11. Real raid-reset countdown, official Blizzard item tooltips on hover, and the settings/refresh/close controls ordered left-to-right with close at the far right.
12. The settings button opens the 角色总览 page directly; the 清空当前版本角色数据, 清空全部角色数据, and 启用角色总览 controls clear or disable as labelled (destructive clears confirm first).
13. Titan saved-instance tuples use the 14th `instanceID` and third `reset` result; grouped columns aggregate the BGLite baseline instance sets (`548+550`, `533+615+616`, `309+649`, `568+580`).
14. `RequestRaidInfo()` runs only at module installation and explicit user refresh, never on ordinary equipment, money, bag, currency or profession event collection.
15. Countdown maintenance runs once per minute only while the overview is visible and stops when hidden or disabled.

Do not mark the feature complete, and do not publish a Release, until these screenshots are approved by the maintainer and the independent provenance audit passes.
