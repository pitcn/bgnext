# ADR-0005: Adopt official BGLite 2.4.2 Pure Edition baseline

## Status

Accepted — 2026-09-04

## Context

NetEase DD distributed BGLite Pure Edition 2.4.2 as the current official base for follow-on addon development. The maintainer supplied the installed package at `C:\World of Warcraft1\_classic_titan_\Interface\AddOns\BGLite` and confirmed that official BGLite source may be used directly as BGNext's base.

The supplied installation contains 186 files. Its byte-identical archive is preserved outside the live game directory, its complete source tree is committed at `5649f58ac2d7d57d3906c97f0aa679bbe5b3da44`, and `docs/baseline/BGLite-2.4.2.sha256` records every file hash.

Compared with 2.4.1, upstream removes `Core/FBUI/HistoryUIfunction.lua` and `Core/Module/History.lua`, updates package metadata, and adds team-identity guards before automatic new-lockout clearing. BGNext already carried equivalent team guards plus a stricter unsettled-content confirmation.

## Decision

BGNext adopts official BGLite Pure Edition 2.4.2 as its active upstream source baseline. The 2.4.0 and 2.4.1 baselines remain immutable history. BGNext retains its independently reviewed current-settlement privacy boundary and its confirmation before clearing unsettled content.

The official package's `dd_author.toc` signature remains preserved only in the upstream commit and integrity manifest. It is excluded from the BGNext working tree and release package because it identifies the official BGLite distribution rather than BGNext.

## Consequences

- Current metadata and documentation identify BGLite 2.4.2 as the active upstream.
- The two files removed by upstream are also removed from the BGNext working tree; neither was part of the active BGNext load graph.
- Baseline verification pins the 2.4.2 commit, manifest, exclusion list, and current override manifest.
- Historical 0.6.0 release notes remain unchanged because they describe the already published artifact.
