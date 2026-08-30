# Auction and reconciliation security checks

Status: code-covered; pending in-game verification.

## Covered behavior

- Auction control messages still require the current raid leader or master looter.
- Bid senders must be current raid members.
- Auction and item identifiers, durations and amounts must be finite integers within explicit bounds.
- Live bids are limited per sender and auction to one accepted message per second.
- Auction cheer messages independently permit at most one trigger per sender and auction every five seconds.
- Rate-limit maps are memory-only and capped at 256 keys.
- Reconciliation remains inactive until the player clicks “Start reconciliation”.
- The first valid current-raid bill sender is bound as the only source for subsequent chat and addon fragments.
- Chat lines, parsed entries and individual message lengths have fixed limits; overflow or timeout stops and clears capture.
- Reconciliation uses `BG.sessionDuizhang` only. It does not read or write `BiaoGe.duizhang`, raw chat or copied raid rosters.
- Logout and roster changes clear the current reconciliation session.

## Automated verification

```powershell
lua tests/run.lua
pwsh -NoProfile -File tools/verify-baseline.ps1
pwsh -NoProfile -File tools/build-release.ps1 -OutputPath .local/packages/BGNext-security-review.zip -Force
git diff --check
```

Automated checks do not prove behavior inside every supported game client. Before release, test one ordinary manual bid, one automatic bid, rapid repeated bids, one normal bill reconciliation and one stop/reload/leave-raid cleanup path in game.
