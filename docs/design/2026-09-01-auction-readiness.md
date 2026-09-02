# Team auction readiness design

- Date: 2026-09-01
- Issue: #40
- Status: Implemented; in-game validation required

## Player problem

The old footer exposed separate guild, addon-version and auction-version counters. A missing reply was labelled as if the member definitely had no addon, while the guild count was not a reliable measure of raid auction compatibility. A raid leader therefore could not tell which current raid members had actually loaded an endpoint capable of receiving the active auction protocol.

## Reference study and provenance

The legally obtained BiaoGe 2.3.5 installation and the verified BGLite 2.4.0 baseline were studied under ADR-0003. Both request and collect a main-addon version and an auction-endpoint version in raids, then expose separate counters and per-member versions. BiaoGe also initiates a guild version query; the studied BGLite build retains guild display code without the equivalent active guild query. Both use an ambiguous missing-response label.

BGNext derives only these observable requirements: reuse the existing mixed-client raid handshake, treat an auction-endpoint reply as the evidence of current auction readiness, and distinguish missing evidence from confirmed absence. The status model, wording, request coordination, tests and implementation are independently authored. No BiaoGe code, identifiers, UI assets, strings or internal data structures are copied into BGNext.

## Behavior

- Outside a raid, the readiness footer remains visible as `not in a raid` so the feature is discoverable, while all response state is cleared and no request is sent.
- In a raid, one compact footer reports `ready/total` for the current roster.
- Hovering shows every member with one of four evidence-based states: ready, main addon only, no response, or offline.
- A response on the existing `BiaoGeAuction` prefix proves readiness for the currently retained first-generation normal auction protocol. A main-addon response alone is diagnostic and does not count as ready.
- No response is never described as proof that an addon is not installed.
- A raid leader or master looter may click the footer to request another check. Readiness never blocks auction start.

## Performance and communication

There is no ticker, polling loop, combat-log subscription or background full-table scan. Roster work is bounded by the raid size (at most 40) and runs only after a roster event, on a version reply, or while rendering the tooltip. Rapid roster events are coalesced with a one-second generation guard.

Automatic requests are initiated only by the active raid auction controller. Manual requests are limited to a raid leader or master looter and locally rate-limited to once per 15 seconds. Existing per-sender and global reply limits remain in force. Current raid member names are cached only for the session so each reply does not re-read the complete Blizzard roster; the cache is replaced on roster change and discarded on raid leave.

The implementation reuses the existing `BiaoGe` and `BiaoGeAuction` `VersionCheck`/version-reply messages and the RAID distribution. It adds no prefix, opcode, field, recipient, whisper, chat message or protocol generation.

## Privacy and security

Readiness state contains only the current live raid names already supplied by Blizzard plus in-session version replies. It is memory-only, never enters SavedVariables, is never uploaded outside the game and is cleared when the roster changes or the player leaves the raid. Incoming version replies are accepted only from a name that matches the cached current raid roster using the existing cross-realm identity helper.

## Compatibility evidence

- BGLite 2.4.0 and BiaoGe 2.3.5 protocol behavior: code-studied.
- BGNext state model, request limits and roster cleanup: automatically tested.
- Permanent 60, Anniversary TBC, Anniversary Titan, Mists Classic and Retail UI/runtime behavior: unverified until tested in game.

Issue #15 remains responsible for any future protocol-generation upgrade or explicit minimum-version capability matrix.
