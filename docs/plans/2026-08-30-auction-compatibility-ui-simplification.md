# Auction Compatibility UI Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove meaningless auction protocol/mode choices while always starting a single legacy-compatible normal auction.

**Architecture:** Keep the existing first-generation wire protocol and all shared BGNext auction behavior. Centralize the compatibility decision in `BG.SendStartAuctionMsg`, simplify the start window to duration, price, quantity and start controls, and leave second-generation receiving code untouched.

**Tech Stack:** WoW Lua 5.1, BiaoGe-LibUIDropDownMenu compatibility library, repository Lua test harness, PowerShell baseline verifier.

---

### Task 1: Lock every outgoing start path to the compatible protocol

**Files:**
- Modify: `tests/test_auction_sender.lua`
- Modify: `Core/Module/Auction.lua:316-445`
- Modify: `Core/Module/AuctionLog.lua:300-325,2255-2268`
- Modify: `Core/Module/Trade.lua:245-256`

- [ ] **Step 1: Write failing source-contract tests**

Add assertions that `BG.SendStartAuctionMsg` has the four-argument signature `(itemID, money, duration, link)`, formats `StartAuction` with `normal`, and that no caller passes `isGen2`, `mod` or `resetThreshold`.

- [ ] **Step 2: Run the suite and confirm RED**

Run `lua tests/run.lua`. Expected: `test_auction_sender.lua` fails because outgoing calls still select protocol generation and mode.

- [ ] **Step 3: Implement the compatibility boundary**

Replace the sender with the fixed first-generation form:

```lua
function BG.SendStartAuctionMsg(itemID, money, duration, link)
    local text = format("StartAuction,%s,%s,%s,%s,,normal,%s",
        GetTime(), itemID, money, duration, link)
    C_ChatInfo.SendAddonMessage("BiaoGeAuction", text, "RAID")
end
```

Update direct, auction-log, re-auction and trade callers to pass only `itemID`, `money`, `duration` and `link`. Remove outgoing reads of `BiaoGe.Auction.gen`, `BiaoGe.Auction.mod` and `BiaoGe.Auction.resetThreshold`.

- [ ] **Step 4: Run the suite and confirm GREEN**

Run `lua tests/run.lua`. Expected: all suites pass.

### Task 2: Remove obsolete start-window controls and compact the layout

**Files:**
- Modify: `tests/test_auction_sender.lua`
- Modify: `Core/Module/Auction.lua:316-1045`

- [ ] **Step 1: Write failing UI source-contract tests**

Assert the start-window construction no longer contains version/mode dropdown creation, `resetThreshold_OnEnter`, `dropDown2`, or `UpdateFrame`, while the duration, price and quantity edit boxes remain.

- [ ] **Step 2: Run the suite and confirm RED**

Run `lua tests/run.lua`. Expected: the new UI assertions fail on the three obsolete controls.

- [ ] **Step 3: Remove the controls with minimal layout changes**

Delete the version and mode dropdown blocks, the reset-threshold block, their tooltip/hook/update helpers, and Roll-only start branches. Keep the fixed `normal` behavior in the sender. Position duration at the first left column, quantity at the first right column and price below duration. Store quantity as `Edit3`, reduce `mainFrameHeight` from `217` to `177`, and retain the existing start/quick-money anchoring.

- [ ] **Step 4: Run the suite and confirm GREEN**

Run `lua tests/run.lua`. Expected: all suites pass.

### Task 3: Update integrity evidence and verify the test package

**Files:**
- Modify: `docs/baseline/BGNext-overrides.sha256`

- [ ] **Step 1: Recalculate changed upstream hashes**

Update only the entries for `Core/Module/Auction.lua`, `Core/Module/AuctionLog.lua`, and `Core/Module/Trade.lua` using SHA-256. Do not modify the upstream `BGLite-2.4.0.sha256` manifest.

- [ ] **Step 2: Run full verification**

Run:

```powershell
lua tests/run.lua
pwsh -NoProfile -File tools/verify-baseline.ps1
git diff --check
```

Expected: Lua suites pass, 188 baseline files verify, and diff check is clean.

- [ ] **Step 3: Build and inspect the test archive**

Run `tools/build-release.ps1` with output `D:\vibe coding\BGN\.local\packages\BGNext-0.2.1-auction-compatibility-test.zip`. Expected: the only archive root is `BGNext/`, denied legacy files are absent, and a SHA-256 sidecar is generated.

- [ ] **Step 4: Commit and push**

Commit the implementation and tests to `codex/0.2.2-bugfixes`, push it to PR #14, and wait for the Lua, baseline and package checks to pass.
