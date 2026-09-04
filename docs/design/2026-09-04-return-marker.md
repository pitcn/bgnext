# Current-settlement return marker

- Status: ready for review; in-game validation pending
- Issue: #89
- Scope: one current settlement, maximum seven days

## Player problem

A buyer may trade an already assigned item back to the raid leader. If the
leader forgets to update the bill or refund state, settlement can be wrong.

## Decision

The completed incoming trade is only a candidate. In the current trade window,
the leader/master looter right-clicks its status. BGNext matches the received
item and counterparty against current bill rows. One match still requires a
confirmation; multiple matches show a row selector before confirmation. The
marker stores the selected row and its original buyer/amount as a short audit
fact. It does not edit the bill and does not perform a refund.

Pending markers append a visible return state to the trade record, draw a small
red `退` badge on the selected bill item, and block the settlement checklist.
Right-clicking the same trade status again asks to clear the reminder after the
leader has handled it. Cleared markers remain only until the current settlement
is cleared/replaced/expires.

## Data and communication

The marker is stored under `BiaoGe.BGNext.currentSettlement.returns` with only
the selected trade/bill coordinates, item id, counterparty, original bill facts,
time and bounded status. No addon/chat message, external transmission, automatic
bill edit, automatic refund, legacy-history access, or cross-raid archive is
introduced.

## Compatibility and provenance

This is independently authored BGNext behavior built on the verified official
BGLite 2.4.2 baseline. No third-party implementation or asset is used. The UI
reuses existing BGNext/BGLite frame helpers only. Automated Lua coverage exists;
real-client UI layout and interaction remain unverified until in-game testing.
