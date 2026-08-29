# Chat YY number copy design

- Status: approved for implementation
- Date: 2026-08-29
- Issue: [#6](https://github.com/pitcn/bgnext/issues/6)

## Goal

Turn an explicitly labelled YY channel number in a newly displayed chat message into a local hyperlink. Clicking the number opens a selectable edit box containing only that number.

This restores the useful player-visible workflow without restoring YY ratings, lookups, sharing, automatic history, or any other removed service.

## Supported messages

The feature applies to newly displayed messages from:

- public channels, say and yell;
- guild and officer chat;
- party, raid and instance chat, including leader variants;
- incoming and outgoing game whispers;
- incoming and outgoing Battle.net whispers.

System messages and previously displayed chat history are not processed.

## Recognition rules

Recognition is deliberately strict. A candidate must:

- use the case-insensitive ASCII label `YY`;
- use one of these visible forms: `YY123456`, `YY: 123456`, `YY：123456`, `YY号 123456`, or `YY频道 123456`;
- contain between 3 and 12 ASCII digits;
- have no adjacent digit extending the candidate beyond the limit;
- not continue into an ASCII letter, so text such as `yyds` is not a candidate.

Only the digits become clickable. Multiple unambiguous candidates in one message may be linked independently.

The transformer preserves WoW colour/control codes and must not rewrite text inside an existing hyperlink or texture escape. Malformed markup is returned unchanged rather than partially rewritten.

## Interaction

The generated link uses a BGNext-owned link type and contains only the validated digits. A normal left click opens a BGNext copy popup whose edit box:

- contains the digits exactly, without quotes or surrounding text;
- selects the full value and receives focus;
- closes with Escape or the confirmation button.

No rating, query, context menu, automatic clipboard access, chat insertion, or network action is attached to the link.

## Architecture

Add one independent module under `Core/BGNext/` with a small public surface:

1. a pure parser/transformer that accepts one chat message and returns either the unchanged message or its linked display form;
2. a validated custom-link decoder;
3. runtime installation that registers the approved chat filters and one `SetItemRef` hook;
4. a dedicated copy popup that displays the decoded digits exactly.

The module is loaded from `BGLite.toc`. It does not load or call `Receive.lua`, and it does not depend on the removed YY evaluation functions. Existing BGLite copy helpers are not used because their popup adds quotation marks.

## Privacy and data handling

Processing is memory-only and synchronous while WoW is displaying the message. BGNext does not retain the message, sender, Battle.net identity, channel, timestamp, or YY number. It writes no SavedVariables, sends no addon/chat messages, performs no telemetry, and makes no game-external request.

Because no field is stored, the data inventory requires no new SavedVariables entry. The Pull Request must still disclose the transient processing of currently visible chat text.

## Compatibility and failure handling

The module is client-neutral and should register only APIs and events present in the running client. A missing chat-filter or popup API disables the affected presentation path without producing fabricated output or errors. Installation must be idempotent within one UI session.

## Verification

Tests exercise observable behavior through the module interface:

- every accepted label/separator form;
- lowercase and uppercase `YY`;
- minimum and maximum lengths;
- rejection of too-short, too-long, adjacent-digit and letter-continuation candidates;
- rejection of unrelated prices, item levels, dates and `yyds`;
- multiple YY numbers in one message;
- preservation of colour codes;
- no rewriting inside existing hyperlinks or textures;
- malformed markup remains unchanged;
- link decoding accepts only the BGNext link type and 3–12 digits;
- the popup receives digits only;
- the registered event list includes Battle.net whispers and excludes system/history processing;
- no SavedVariables, addon messages, chat sends, telemetry or file access are introduced.

Repository verification includes the Lua suite, baseline integrity, `git diff --check`, privacy/communication scans, and release-package inspection.
