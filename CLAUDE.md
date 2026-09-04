# BGNext Agent Rules

This file intentionally mirrors the mandatory rules in `AGENTS.md`. Claude and Claude Code must apply these rules even when no file under `docs/` has been opened.

## Non-negotiable boundaries

1. Use only a verified BGLite baseline with recorded source, version, inventory, and hashes; a folder name or game-installation location is not proof of a clean baseline.
2. Do not copy historical BiaoGe code, algorithms, text, UI artwork, sounds, or other assets. BiaoGe may be studied only for workflow and layout habits unless a repository ADR records verifiable permission for the exact material and use.
3. Quarantine files containing restoration notes, private/VIP/AI hooks, anonymous auction logic, hidden communication, or unclear provenance. Do not build on them.
4. Never create cross-raid history, player profiles, reputation/attendance/spending/bid rankings, or views of another player’s stored information.
5. Retain only the current or most recent unsettled raid, for at most seven days. A new raid, manual clear, or expiry deletes the old scoped record. No archives, cross-raid search, aggregation, or ranking.
6. Wishlists, equipment filters, shopping summaries, auction presets, and own-character overview are local-only. Own-character data may be recorded only while logged into that character.
7. Trade/mail reconciliation stores only necessary scoped fields. Never retain mail bodies, unrelated chat, account/device identifiers, private notes, or unrelated history.
8. No automatic external upload, telemetry, analytics, remote logging, fingerprinting, or synchronization. Any future export must be manual, previewed, purpose- and recipient-disclosed, and cancellable.
9. Auto-bid must be explicitly armed per auction with visible increment and cap. It is memory-only and stops on cancel, auction/item change, UI close, group/world leave, send failure, cap, reload, or protocol anomaly. No hidden/background operation, random timing, offline behavior, or last-second sniping.
10. Preserve only the necessary transparent BGLite current-auction protocol. No hidden messages, stable cross-session identifiers, expanded recipients, or original BiaoGe compatibility without separate review.
11. Never claim a client version is supported without evidence; mark unavailable real-client testing as unverified.
12. Never publish private conversations, identities, screenshots, internal claims, or unverifiable authorization details, and never imply official status or endorsement.

## Execution workflow

`AGENTS.md` is authoritative and defines low, normal, and high risk work. Determine the minimum tier from the repository rules; you may upgrade but must never downgrade it.

- Low risk: read `AGENTS.md` and direct context.
- Normal risk: also read `docs/agents/safety-summary.md`, relevant modules and relevant ADRs; use a focused RED/GREEN test for behavior changes.
- High risk: read the complete security, privacy, compliance, data-inventory and relevant ADR set and perform the full audit required by `AGENTS.md`.

Before completion run the matching unified gate:

```powershell
pwsh -NoProfile -File tools/agent-verify.ps1 -Risk normal -Base origin/main -WriteHandoff
```

Use `-Risk low` or `-Risk high` only when appropriate. The command rejects risk downgrades, composes the existing Lua/baseline/diff checks, and creates the compact shared handoff for normal/high work. Complete emitted manual review items before claiming high-risk work is done.

Always use an isolated worktree or feature branch. Stop and report unclear provenance, undocumented authorization, privacy conflicts, unavailable required tests, or failed verification. Never bypass a stop condition through renaming, hidden code, hash changes, weaker documentation, or a lower requested risk.

## Agent skills

- GitHub Issues is the issue and PRD tracker; see `docs/agents/issue-tracker.md`.
- Use the five triage states in `docs/agents/triage-labels.md`.
- This is a single-context repository; see `docs/agents/domain.md` and `docs/design/`.
