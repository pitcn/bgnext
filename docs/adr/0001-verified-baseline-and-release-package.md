# ADR-0001: Verified baseline and runtime-only release packages

- Status: Accepted
- Date: 2026-08-29

## Context

BGNext started from a distributed BGLite 2.4.0 snapshot. ADR-0004 adopts the later official BGLite 2.4.1 Pure Edition as the active upstream baseline while preserving the 2.4.0 commit as history.

## Decision

The active BGLite baseline is identified by commit `31b4942`, a complete SHA-256 manifest, an explicit repository-exclusion list, and an explicit override manifest. Every changed baseline file is reviewed and recorded individually.

Player releases are built from the active TOC/XML load graph, approved runtime assets, and required third-party notices. They are not made by compressing the repository or the full upstream snapshot. Quarantined history and inactive receiver modules remain available only for provenance review and are excluded from release archives.

## Consequences

- Baseline verification and release-package verification are separate gates.
- A matching hash establishes identity, not safety.
- Adding a runtime file or asset requires an auditable package-rule change.
- Repository-only governance, tests, handoffs, and quarantined source never enter the player archive.
