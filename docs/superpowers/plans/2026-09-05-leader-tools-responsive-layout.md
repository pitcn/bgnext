# Leader Tools Responsive Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every leader-tools tab remain contained and readable across supported UI scales without changing business behavior.

**Architecture:** Add a pure `LeaderToolsLayout` module as the single source of geometry and scale calculations. Make `LeaderToolsUI` consume those values, reserve shared header/footer regions, and put auction rows in a native scroll frame.

**Tech Stack:** WoW Lua 5.1, Blizzard Frame API, repository Lua test harness.

---

### Task 1: Pure layout contract

**Files:**
- Create: `Core/BGNext/LeaderToolsLayout.lua`
- Modify: `BGLite.toc`
- Create: `tests/test_leader_tools_layout.lua`
- Modify: `tests/run.lua`

- [ ] **Step 1: Write the failing test**

Test `scaleFor(720,500)==1`, smaller parent dimensions produce a bounded scale, and the exported template/history/auction/settlement vertical regions satisfy `top < bottom` and do not overlap their footer.

- [ ] **Step 2: Run test to verify it fails**

Run `lua tests/run.lua`; expect failure because `LeaderToolsLayout.lua` is absent.

- [ ] **Step 3: Write minimal implementation**

Export `WIDTH=720`, `HEIGHT=500`, `SCREEN_MARGIN=16`, `MIN_SCALE=0.70`, page content constants, `scaleFor(width,height)`, and `auctionVisibleRows(contentHeight)` capped at 20. Add the module before `LeaderToolsUI.lua` in the TOC.

- [ ] **Step 4: Run test to verify it passes**

Run `lua tests/run.lua`; expect all tests to pass.

### Task 2: Shared responsive window

**Files:**
- Modify: `Core/BGNext/LeaderToolsUI.lua`
- Modify: `tests/test_leader_tools_ui.lua`

- [ ] **Step 1: Write the failing fake-widget test**

Build the real window with fake frames and assert 720×500 logical size, clamped positioning, a callable screen-fit refresh, and content anchors below the tab row and above the bottom inset.

- [ ] **Step 2: Run test to verify it fails**

Run `lua tests/run.lua`; expect the new window geometry assertions to fail against 680×470.

- [ ] **Step 3: Implement shared geometry**

Require `LeaderToolsLayout`, size the frame from its constants, add `fitToScreen()` using `UIParent:GetWidth/GetHeight`, call it on build and `OnShow`, and keep title, close button, tabs and content in their reserved regions.

- [ ] **Step 4: Run test to verify it passes**

Run `lua tests/run.lua`; expect all tests to pass.

### Task 3: Contained page layouts

**Files:**
- Modify: `Core/BGNext/LeaderToolsUI.lua`
- Modify: `tests/test_leader_tools_ui.lua`

- [ ] **Step 1: Add failing geometry assertions**

Assert template actions anchor upward from the bottom, history body is bounded between search and footer, auction hint occupies its own row and rows live under a scroll child, and settlement text ends above its footer.

- [ ] **Step 2: Run test to verify it fails**

Run `lua tests/run.lua`; expect overlap/anchor assertions to fail.

- [ ] **Step 3: Re-anchor all four pages**

Replace vertical fixed offsets with top/bottom anchors, introduce footer frames for template/history/settlement actions, and create `UIPanelScrollFrameTemplate` plus scroll child for auction rows. Preserve all existing button scripts and Runtime/Store calls.

- [ ] **Step 4: Run focused and full tests**

Run `lua tests/run.lua`; expect all tests to pass with no changed business-test expectations.

### Task 4: Release-grade verification

**Files:**
- Modify: `docs/baseline/BGNext-overrides.sha256` only if an upstream override hash changed.

- [ ] **Step 1: Verify syntax and baseline**

Run all Lua files through `luac -p`, then run `tools/verify-baseline.ps1`; expect zero failures.

- [ ] **Step 2: Verify packaging and diff**

Run `tools/build-release.ps1 -OutputPath artifacts/BGNext-issue-109.zip -Force` and `git diff --check`; expect a valid package and clean diff.

- [ ] **Step 3: Commit and open PR**

Commit the tested code, push `codex/issue-109-leader-tools-layout`, open a PR with `Closes #109`, and wait for all CI checks. Leave the game screenshot check clearly marked as the only human validation item.
