# ADR-0001: Verified baseline and runtime-only release packages

- Status: Accepted
- Date: 2026-08-29

## Context

BGNext starts from a distributed BGLite 2.4.0 snapshot. The repository retains the complete upstream tree for provenance, including files that BGNext must not load or distribute.

## Decision

The BGLite baseline is identified by commit `9e0b119`, a complete SHA-256 manifest, and an explicit override manifest. Every changed baseline file is reviewed and recorded individually.

Player releases are built from the active TOC/XML load graph, approved runtime assets, and required third-party notices. They are not made by compressing the repository or the full upstream snapshot. Quarantined history and inactive receiver modules remain available only for provenance review and are excluded from release archives.

## Consequences

- Baseline verification and release-package verification are separate gates.
- A matching hash establishes identity, not safety.
- Adding a runtime file or asset requires an auditable package-rule change.
- Repository-only governance, tests, handoffs, and quarantined source never enter the player archive.
