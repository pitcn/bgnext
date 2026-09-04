# ADR-0003: Reference study with original implementation

- Status: Accepted
- Date: 2026-08-31
- Supersedes: ADR-0002

## Context

ADR-0002 prohibited opening historical BiaoGe source so BGNext features could be developed under a strict clean-room boundary. The maintainer has since reviewed the enhancement activity's published explanation and records the following project interpretation: submitted code must be original, but studying an existing addon's behavior or implementation for research is not itself prohibited.

That interpretation does not grant a license to copy, redistribute, translate, adapt, or repackage third-party code or assets. The project therefore needs a boundary that permits useful compatibility and UX research while keeping BGNext implementation original and auditable.

## Decision

BGNext contributors may study legally obtained BGLite, BiaoGe, and other addon versions to understand:

- player-visible workflows, layout relationships, interaction timing, and terminology;
- client-version differences, specialization or talent models, API compatibility, and failure cases;
- expected inputs, outputs, state transitions, and interoperability requirements;
- defects or usability problems that BGNext should solve differently.

Source inspection is permitted for research. It is not permission to reuse the inspected implementation. BGNext must not copy, paste, translate, mechanically transform, line-by-line rewrite, or transplant third-party source. It must also not reproduce distinctive internal structure, identifiers, comments, private data tables, import formats, text, icons, artwork, fonts, sounds, or other assets unless a separate recorded license explicitly permits that exact reuse.

When source research materially influences a change, the design or pull request must record:

1. the addon and version studied;
2. the player-visible behavior or compatibility fact learned;
3. which BGNext requirements were derived from that research;
4. how the BGNext design and implementation remain independently authored;
5. any third-party material deliberately excluded or replaced.

Research notes should describe behavior and conclusions rather than preserve source excerpts. Implementation is written against BGNext's own module boundaries, Blizzard APIs, and repository conventions. Tests assert observable behavior and safety properties, not another addon's private function names or source layout.

The supplied and verified BGLite baseline remains governed by ADR-0001 and ADR-0004: official Pure Edition source may enter the repository as an immutable upstream baseline, baseline overrides are individually recorded and reviewed, and release packages are still built only from the approved runtime graph. Other historical or separately installed addon trees remain research inputs only and never enter the repository or release package.

## Consequences

- Future work is described as original BGNext implementation informed by disclosed reference study, not as strict clean-room implementation.
- Existing features that were completed under the clean-room boundary remain valid; historical design records are not rewritten.
- Similar player-visible behavior is allowed when it serves compatibility or usability, but copied implementation or assets remain prohibited.
- Reviewers can reject a change whose provenance is missing, whose structure appears mechanically derived, or whose rights are unclear.
- Reference study does not weaken security, privacy, data-minimization, platform-review, baseline-integrity, or release-package requirements.
