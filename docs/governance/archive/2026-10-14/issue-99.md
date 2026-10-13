## Decision

Owner rejected the installed main-board and stock screens on 2026-09-10. Treat this as a **high-fidelity mission acceptance failure**, not post-release cosmetic polish. Mission #1 is reopened. Preserve #89's historical packaging/game-flow evidence, but it is insufficient to close the high-fidelity mission.

**Owner clarification: Astra owns restoration and verification of ALL player-facing screens and flows of the targeted original version, not just the screenshots the owner reports.** The board/stock slice is an early direction checkpoint, not the final scope. Complete screen coverage does not mean perfect pixel archaeology: #1's player-perceived fidelity target and explicitly approved minor deviations still apply. Do not switch engines or expand into other games/versions.

Reviewed code baseline: `b8bce96170c1174f6264b85d23e876a6cccb6d97`; previously installed production source recorded in #89: `159aeb036a71194badc564a2064e750655bd7484`. #100 subsequently established the actual installed executable/catalog/save identity: installed159aeb036 matches the recorded artifact, the catalog contains the intended twelve companies, and loading the owner's valid v4 development save selects the three-stock capability path. See #100 diagnosis and #52 for current implementation/evidence; this acceptance gate remains open.

## Evidence and limits

- Owner screenshots: main board embedded in a large navy dashboard, permanent logs/text status cards; stock popup is three form rows named `tech`, `transport`, `energy`, with a cash balance. Screenshots remain in the owner conversation; do not publish them or original reference artwork into this public repository without publication rights. Capture reproducible local evidence at the first checkpoint.
- `game/ui/main_ui.gd`: `_stock_symbols_for_ui` / `_stock_name_for_ui` retain the three-symbol fallback. `_update_stocks_popup` selects deposit for original-company games and cash otherwise. The initial hypothesis was verified by #100 through actual installed-app entry and the owner save: loading that valid v4 development save selects the legacy/simplified path. Reviewed PR110 makes the continue/cancel decision explicit and blocks silent broken production content; revised packaged verification is still pending.
- `docs/original-companies.md` and `game/content/original_maps.gd` define the twelve-stock capability. Implemented code does NOT prove that the owner-facing launch reaches it.
- `docs/manual-rules.md` indexes the official original manual. Existing source research is reusable, but it is not a golden-screen approval. No original-versus-remake screen set has been approved in this intervention.

## Execution order / ownership

1. Establish actual installed-build/catalog/save provenance and rejected baseline. Independently inventory the targeted original screens/flows, while freezing main-game/stock references first. Use the owner's pinned original version; distinguish base Game from MultiverseJourney.
2. Correct #100's production capability routing and deliver #101's main-board/stock slice. Obtain an actual original/remake comparison and independent review before propagating the presentation approach.
3. Complete the full inventory under #102 and perform integrated native acceptance. Do not stop after #101 or wait for the owner to discover each remaining mismatch.

Astra remains lead under `AGENTS.md` and is accountable for product appearance and interaction, not only delegation or passing tests. Luna gets bounded non-overlapping work after its source/layout contract is established. Require fresh independent Sol review of exact-HEAD code and actual comparison images. One writer for `main_ui.gd` and shared core. Preserve #98's restart/bank/tooltip requirements. No automatic close of #1 by a child PR.

## Complete screen coverage

Astra must derive a compact coverage matrix from the original manual, source assets and observable original flows, then cross-check it against remake entry points. **The following is a starting inventory, not an exhaustive whitelist:**

| Stage | Screens / states |
| --- | --- |
| First slice | Original launch/new-game entry, main board/HUD before and after dice/movement, stock overview/selected stock/trade outcome |
| Follow-through | New-game character/map/options selection, purchase/upgrade confirmation, bank/ATM, cards/tools/shop and targeting/reaction, news/fate, save/load, settlement/restart |

Include original menus, subviews, dialogs, overlays, targeting, confirmations and temporary event states wherever the targeted original actually has them. A screen absent from the remake is a missing item, not outside scope. Distinct screen/interaction states require coverage; every changing number, map coordinate or sprite frame does not require a separate screenshot. Record original provenance, remake entry, implementation/capability status, comparison evidence and independent verdict for each item. No silent omissions or converting whole missing screens into 'minor fallback'. Genuine source/access blockers must be reported specifically while unblocked work continues; do not make the owner supply a screen-by-screen specification.

## Acceptance contract

### Source reference

Astra should independently obtain and inspect original references using existing authorized assets, manual and available runtime evidence. Model familiarity can guide discovery; it is not proof of exact layout, version or behavior. For each screen record original version/provenance, entry/state/actions, expected information, reference dimensions and permitted deviations. Keep restricted images private and only safe metadata/tests in public code. Reuse existing research; do not invent dimensions, company names, charts or timings. An unverified screen cannot be marked accepted merely because tests pass; minor within-screen unknowns remain bounded under #1.

### Product outcome

- Normal launch/new game presents an original-game-oriented flow and board/HUD, not the rejected dashboard/debug shell. Debug logs, fallback-board controls and internal IDs are not the default presentation.
- Board framing/scale, HUD hierarchy, portraits/icons, screen information and interaction are compared against the same original version and comparable state. Required actions must work; a static original screenshot overlay or nonfunctional skin fails.
- Stock presentation must reach the intended original catalog/capabilities. Recoloring three placeholder rows is not a fix. Restore source-backed information and controls shown by the reference; do not invent modern trading-terminal features.
- Opening/closing/selecting does not mutate simulation or consume RNG. Trade/cancel/error effects follow domain contracts; retain #98's safety regressions.

### Evidence / close gate

Keep functional, native/package and original-presentation verdicts separate. Passing one never implies the others. Use focused tests first, affected UI/integration at the batch gate, and the sole FULL lane with disk guard only for necessary native capture/export. Do not rerun the full suite/corpus for every visual edit.

Before a screen is GREEN, provide original/remake comparisons and necessary interaction evidence, exact build/package/catalog identity, reproducible setup/actions, results, permitted deviations and an independent review tied to those artifacts. Screenshot existence or self-approved pixel baselines alone cannot pass. Label seeded fixture states; they cannot replace normal launch/new-game verification.

Before closing #1, the complete coverage matrix must have no unaccepted required screen/flow, and Steward must accept the rendered evidence. An explicit owner-approved scope exception must remain visible, never be relabelled as restored. Do not claim a measured 90–95% score without an actual defined measurement.

## First checkpoint

Within 30–60 minutes of resumed work, report actual executable/catalog/save identity, market-path diagnosis, located main-board/stock references, initial full-screen inventory and the smallest executable slice. This is a checkpoint target, not a promise of completed fidelity in one hour. Update #52 concisely; detailed evidence belongs to the active Issue/PR. Keep event waits / >=180-second polling and owner-save/asset protections.