# Auction and Ledger Security Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bound and authenticate live auction and reconciliation messages without persisting another player's ledger history.

**Architecture:** Extend the pure `AuctionSender` policy with strict numeric parsing and memory-only rate limits, then call it independently from both auction consumers. Add a pure `LedgerCapture` policy for explicit activation, source binding and fixed capacities; keep the reconciliation UI but redirect its list to memory and remove persistent raw-chat and roster behavior.

**Tech Stack:** World of Warcraft Lua 5.1, repository Lua test harness, PowerShell baseline and release verification.

---

### Task 1: Strict auction protocol values

**Files:**
- Modify: `tests/test_auction_sender.lua`
- Modify: `Core/BGNext/AuctionSender.lua`

- [ ] **Step 1: Write failing tests**

Add assertions that valid integral bids pass and that zero or negative IDs, negative bids, fractions, `1e309`, values above `M.MAX_MONEY`, and invalid start fields return `nil`.

- [ ] **Step 2: Verify RED**

Run `lua tests/run.lua`. Expected: failures for infinite, fractional and excessive values.

- [ ] **Step 3: Implement strict parsing**

Add exported bounds and a private integer parser:

```lua
M.MAX_ID = 2147483647
M.MAX_MONEY = 10000000

local function boundedInteger(value, minimum, maximum)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
    if number % 1 ~= 0 or number < minimum or number > maximum then return nil end
    return number
end
```

Use it in `parseBid` and `parseStart`, with duration limited to `1..3600`.

- [ ] **Step 4: Verify GREEN and commit**

Run `lua tests/run.lua`; expected `failed=0`. Commit the policy and tests.

### Task 2: Receive-side auction and cheer rate limits

**Files:**
- Modify: `tests/test_auction_sender.lua`
- Modify: `Core/BGNext/AuctionSender.lua`
- Modify: `Core/Module/AuctionWAEvent.lua`
- Modify: `Core/Module/Auction.lua`

- [ ] **Step 1: Write failing policy and integration tests**

Test `Sender.shouldAcceptAuctionMessage(state, sender, realm, members, auctionID, now, interval)`: first acceptance, repeated rejection inside the interval, acceptance after it, independent auctions, outsider rejection and backwards-time rejection. Add source assertions proving both handlers call it with one-second and five-second intervals.

- [ ] **Step 2: Verify RED**

Run `lua tests/run.lua`. Expected: missing-helper and integration failures.

- [ ] **Step 3: Implement and integrate**

Canonicalize the sender, verify current membership, validate the auction ID, and store only the last accepted timestamp under `state.byKey[senderKey .. ":" .. auctionID]`. In `AuctionWAEvent.lua`, apply a one-second limit before scanning frames. In the cheer handler, independently parse, rebuild the roster, verify membership and apply a five-second limit before `SendChatMessage`.

- [ ] **Step 4: Verify GREEN and commit**

Run `lua tests/run.lua`; expected `failed=0`. Commit policy, tests and both baseline overrides.

### Task 3: Explicit bounded ledger-capture policy

**Files:**
- Create: `Core/BGNext/LedgerCapture.lua`
- Create: `tests/test_ledger_capture.lua`
- Modify: `tests/run.lua`
- Modify: `BGLite.toc`

- [ ] **Step 1: Write failing tests**

Define tests for `new`, `start`, `stop`, `bindSource`, `acceptSource`, `appendLine` and `appendEntry`. Assert inactive rejection, normalized source binding, different-sender rejection, maximum line and entry counts, maximum text length, timeout and reset clearing.

- [ ] **Step 2: Verify RED**

Register the suite and run `lua tests/run.lua`. Expected: missing module failure.

- [ ] **Step 3: Implement the pure policy**

Use defaults of 200 chat lines, 200 ledger entries, 255 bytes per line and 50 seconds per capture. Store ordinary memory tables only and use `PlayerIdentity.same` for source checks. Load the module after `PlayerIdentity.lua`.

- [ ] **Step 4: Verify GREEN and commit**

Run `lua tests/run.lua`; expected `failed=0`. Commit module, TOC and tests.

### Task 4: Reconciliation runtime privacy conversion

**Files:**
- Create: `tests/test_ledger_runtime_privacy.lua`
- Modify: `tests/run.lua`
- Modify: `Core/Module/DuiZhang.lua`
- Modify: `Locales/zhCN.lua`
- Modify: `Locales/zhTW.lua`
- Modify: `Locales/enUS.lua`

- [ ] **Step 1: Write failing source tests**

Assert the module uses `BG.sessionDuizhang`, never reads or writes `BiaoGe.duizhang`, never stores `msgTbl` or `member`, checks explicit capture state, binds addon fragments to the same sender, and registers group/logout cleanup.

- [ ] **Step 2: Verify RED**

Run `lua tests/run.lua`. Expected: privacy assertions fail against the automatic persistent implementation.

- [ ] **Step 3: Convert storage and parsing**

Create `BG.sessionDuizhang = {}` and redirect all reconciliation list access in this module to it. Remove raw chat collection, roster snapshots, 24-hour persistence and member-list export. Gate recognition behind `LedgerCapture`; bind the first valid header sender and require every subsequent chat or addon fragment to match.

- [ ] **Step 4: Add explicit UI control and cleanup**

Add a footer button toggling “开始对账” and “停止对账”, with a tooltip explaining current-session handling. Clear capture and the session list on stop, logout, leaving raid or roster identity change. Completion stops collection after placing the normalized result into the memory list for immediate comparison.

- [ ] **Step 5: Enforce capacities**

Pass every accepted chat line and parsed entry through `LedgerCapture`. On overflow or timeout, clear the partial capture, stop collection and show one local message. Add no new channel message and no SavedVariables field.

- [ ] **Step 6: Verify GREEN and commit**

Run `lua tests/run.lua`; expected `failed=0`. Commit runtime, tests and locale text.

### Task 5: Documentation and release gates

**Files:**
- Modify: `docs/security/data-inventory.md`
- Create: `docs/testing/auction-ledger-security.md`
- Modify: `docs/baseline/BGNext-overrides.sha256`

- [ ] **Step 1: Document the boundary**

Record that authorization, limits and current comparison state are memory-only; no other-player ledger, raw chat or roster is persisted. State that old `BiaoGe.duizhang` data is ignored but not silently deleted.

- [ ] **Step 2: Refresh override hashes**

Update hashes only for changed upstream baseline files and add newly changed baseline files where required.

- [ ] **Step 3: Run full verification**

Run `lua tests/run.lua`, `pwsh -NoProfile -File tools/verify-baseline.ps1`, `pwsh -NoProfile -File tools/build-release.ps1 -OutputPath .local/packages/BGNext-security-review.zip -Force`, and `git diff --check`. Expected: zero test failures, 188-file baseline verified, release archive created without denied files, and no whitespace errors.

- [ ] **Step 4: Inspect and commit**

Confirm only planned files changed and no exploit reproduction text or user data is present, then commit documentation and manifests.

### Task 6: Independent security PR

**Files:**
- No source changes expected.

- [ ] **Step 1: Push the branch**

Push `codex/security-auction-ledger-hardening` to `origin`.

- [ ] **Step 2: Create the PR**

Create a PR against `main`, link Issue #3, describe security properties without publishing executable exploit details, and disclose protocol handling, unchanged SavedVariables schema, baseline overrides and pending in-game verification.

- [ ] **Step 3: Check CI**

Read the PR checks once. Diagnose and fix any failure on the same branch before reporting readiness.
