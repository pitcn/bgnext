# ADR-0002: Clean-room BGNext enhancements

- Status: Superseded by ADR-0003
- Date: 2026-08-29

## Context

The enhancement activity authorizes development from the supplied BGLite distribution. It does not establish a general right to copy historical BiaoGe source, algorithms, text, artwork, sounds, or other assets.

## Decision

BGNext may study publicly visible player workflow to define behavior requirements. New features are designed and implemented independently from those requirements, Blizzard's public addon APIs, and the reviewed BGLite baseline.

Historical BiaoGe source or assets must not be opened, imported, copied, transformed, or used as implementation templates. A future exception requires verifiable permission covering the exact material and use, recorded by a superseding ADR before the material enters a branch or build.

References to BiaoGe in user-facing or repository documentation are limited to compatibility, provenance, or comparative behavior. BGNext does not claim ownership of upstream or third-party content.

## Consequences

- Similar player-visible behavior is not evidence of shared implementation.
- Tests describe observable behavior and safety properties, not private source structure.
- Provenance is disclosed rather than hidden by cosmetic rewriting.
- Unclear material is quarantined and blocks release until reviewed.
