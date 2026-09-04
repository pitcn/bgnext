# ADR-0004: Adopt official BGLite 2.4.1 Pure Edition baseline

- Status: Accepted
- Date: 2026-09-03

## Context

NetEase DD distributed BGLite Pure Edition 2.4.1 as the official base for follow-on addon development. Its embedded guide explicitly encourages developers to build safe and stable enhancements on the Pure Edition and documents compatibility with the standard BiaoGe auction protocol. The maintainer confirmed that official BGLite source may be used directly and that BGNext is required to use it as its base.

The supplied installation contains 188 files. Its byte-identical archive is preserved outside the live game directory, its complete source tree is committed at `31b4942e3251d8bba5c6e6be56fc427da2ae045f`, and `docs/baseline/BGLite-2.4.1.sha256` records every file hash.

## Decision

BGNext adopts official BGLite Pure Edition 2.4.1 as its active upstream source baseline. The previous 2.4.0 baseline remains immutable history. BGNext enhancements remain explicit overrides and may intentionally retain stricter behavior, including confirmation before clearing an unsettled table.

The official package's `dd_author.toc` signature is preserved in the upstream commit and integrity manifest but excluded from the BGNext working tree and release package because it identifies the official BGLite distribution rather than BGNext. All other runtime inclusion continues to follow the reviewed TOC/XML release graph.

The permission recorded here applies only to the official BGLite Pure Edition baseline. It does not authorize copying historical BiaoGe, third-party forks, or unrelated addon source and assets.

## Consequences

- BGNext metadata and current documentation identify BGLite 2.4.1 as the active upstream.
- Upstream fixes are merged with BGNext overrides instead of replacing reviewed BGNext behavior wholesale.
- Baseline verification pins commit `31b4942`, the 2.4.1 manifest, the explicit exclusion list, and the current override manifest.
- Compatibility claims remain limited by actual automated and in-game evidence.
