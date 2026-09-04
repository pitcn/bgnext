# BGNext normal-risk safety summary

This is the short context for normal-risk Agent work. It does not replace the authoritative policies. Any uncertainty about data, communication, provenance, compatibility, permissions, packaging, or release scope escalates the task to high risk and requires reading the linked originals.

- Use only the verified BGLite baseline. Never copy historical BiaoGe code or assets; ADR-0003 permits read-only study of player-visible behavior, followed by an independent implementation.
- Never create player profiles, cross-raid dossiers, rankings, telemetry, hidden communication, background upload, or automatic external transmission.
- Current settlement data is limited to the current or most recent unsettled raid and at most seven days. Personal features and own-character information remain local-only.
- Store only fields required for the scoped feature. New persistent or communicated fields, schema changes, recipient changes, and external transmission are high risk.
- Do not claim client support without evidence. Simulation and automated tests are not real-client verification.
- Never publish private conversations, player identities, screenshots, SavedVariables contents, local paths, or unverifiable authorization claims.

Authoritative references:

- `SECURITY.md`
- `docs/policies/PRIVACY.md`
- `docs/policies/COMPLIANCE.md`
- `docs/security/data-inventory.md`
- `docs/adr/`
- `CONTEXT.md`

If this summary and an authoritative document differ, the authoritative document wins and the task is high risk.
