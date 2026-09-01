# BGNext domain context

BGNext is an independent community enhancement built on the verified BGLite 2.4.0 distribution supplied for the enhancement activity. It is not an official BiaoGe, BGLite, Blizzard, NetEase, or NetEase DD project.

## Domain terms

- **BGLite baseline** — the immutable 188-file upstream snapshot identified by commit `9e0b119` and `docs/baseline/BGLite-2.4.0.sha256`.
- **BGNext override** — a reviewed modification to a baseline runtime file, recorded in `docs/baseline/BGNext-overrides.sha256`.
- **BGNext module** — independently authored code under `Core/BGNext/`.
- **Current auction protocol** — the existing in-game BGLite messages needed for a live raid auction. It is not a general synchronization channel or a historical record.
- **Current settlement** — one current or most recent unsettled raid, retained locally for no more than seven days.
- **Own-character snapshot** — last-seen local data collected only while the user is logged into that character. It is not an account scan or a character history.
- **Compatibility evidence** — one of: code-covered, automatically tested, simulated, tested in game, or unverified. Only tested-in-game behavior may be described as verified support.
- **Release package** — the auditable runtime-only archive built from the TOC/XML load graph plus approved media and third-party license files. It is not a copy of the repository tree.

## Invariants

1. Legally obtained BGLite, BiaoGe, and other addon versions may be studied under ADR-0003 to derive behavior and compatibility requirements. BGNext code, text, data structures, and assets remain independently authored; third-party implementation and assets are not copied, transformed, or repackaged.
2. New BGNext data stays under `BiaoGe.BGNext` unless a reviewed ADR and data-inventory change explicitly say otherwise.
3. Personal features remain local-only. Current-auction interoperability uses only the minimum existing BGLite protocol.
4. Release packages exclude quarantined and unloaded source files.
5. Missing provenance, failed security gates, or missing compatibility evidence blocks release rather than being converted into a passing claim.

Durable decisions are recorded in `docs/adr/`. Runtime data fields are recorded in `docs/security/data-inventory.md`.
