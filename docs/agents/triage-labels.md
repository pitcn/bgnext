# Triage labels

Use exactly these workflow labels:

- `needs-triage`: maintainer evaluation required.
- `needs-info`: waiting for reproducible details or a user decision.
- `ready-for-agent`: fully specified and safe for an agent to implement.
- `ready-for-human`: requires human access, judgment, authorization, or in-game verification.
- `wontfix`: intentionally rejected, with a concise reason.

Security and privacy stop conditions take precedence over workflow state. A task cannot become `ready-for-agent` while provenance, authorization, data scope, or required verification remains unresolved.
