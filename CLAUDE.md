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

## Mandatory execution rules

- Before runtime work, read `AGENTS.md`, `SECURITY.md`, `PRIVACY.md`, `docs/COMPLIANCE.md`, the approved design, and relevant ADR/data-inventory files.
- Use test-first development for behavior changes: observe the expected failing test before production code.
- Document every new persistent or communicated field in the data inventory before merging.
- Review each modified baseline file and update only its explicit hash; never bulk-accept baseline drift.
- Use an isolated worktree or feature branch. Never publish an unreviewed Release.
- Run `pwsh -NoProfile -File tools/run-lua-tests.ps1`, `pwsh -NoProfile -File tools/verify-baseline.ps1`, and `git diff --check` before every runtime commit and Release.
- Stop and report unclear provenance, undocumented authorization, privacy conflicts, unavailable required tests, or failed verification. Never bypass a stop condition through renaming, hidden code, hash changes, or weaker documentation.

## Agent skills

- GitHub Issues is the issue and PRD tracker; see `docs/agents/issue-tracker.md`.
- Use the five triage states in `docs/agents/triage-labels.md`.
- This is a single-context repository; see `docs/agents/domain.md` and `docs/superpowers/specs/`.
