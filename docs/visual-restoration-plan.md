# Visual restoration execution index

This is a compact execution index for the owner-authorized fidelity continuation. It does **not** replace Issue #1, Issue #52, `AGENTS.md`, or the active Issue/PR.

## Do not rediscover existing authority

Before new source archaeology, reuse:

- `docs/fidelity.md` — current fidelity evidence and known gaps.
- `docs/original-scenes.md` — imported board/background/sprite provenance, logical-coordinate rules, and known board rendering gaps.
- `docs/manual-rules.md` — original manual index.
- `docs/image-format.md` — decoded panel/image format evidence.
- relevant `docs/original-*.md` files — system-specific source contracts already established.
- #99 / #101 / #102 — screen coverage and acceptance gates.
- #164 / PR #165 — current S21 SALE draft and its unfinished player-visible boundaries.

Do not rerun broad source research merely to recreate facts already frozen in those sources.

## Current execution order

| Batch | Scope | Current authority | Exit condition |
| --- | --- | --- | --- |
| 0 | S21 SALE current draft | #164 / PR #165 | Finish one coherent player-visible presentation/evidence package on the current draft; do not reopen completed transaction work. |
| 1 | Launch/new-game + main board/HUD + stock presentation | #99 / #101 | Comparable original/remake board and stock states are functional and receive a batched visual review. |
| 2 | Character/map/options selection; purchase/upgrade; bank/ATM | #102 | Required screens/flows have source provenance, working interaction and reviewed rendered evidence. |
| 3 | Cards/tools/shop; targeting/reactions; SALE and related player interactions | #102 plus relevant active system Issues | Same per-screen acceptance; reuse already accepted components instead of rebuilding them. |
| 4 | News/fate/event overlays; save/load/settings | #102 | Same per-screen acceptance. |
| 5 | Settlement/restart and remaining source-established player-facing dialogs/overlays | #102 | Coverage matrix has no silent required-screen omissions. |
| 6 | Integrated native acceptance | #99 / #102 | Exact-HEAD packaged flow, screen coverage and final evidence accepted; #1 remains the Mission close gate. |

The rows are work batches, not permission to start them in parallel when writers would overlap.

## Per-batch loop

1. **Terra freezes the smallest reference contract**: exact original version/provenance, entry/state, visible information/controls and allowed deviations. Reuse existing docs before researching more.
2. **DeepSeek handles bounded implementation/tests/mechanical changes** through `~/.local/bin/deepseek-worker` when the write boundary is isolated and explicit.
3. Worker returns exact files changed, focused checks and blockers. Terra reviews the diff; worker exit code alone is not acceptance. **If DeepSeek has one substantive failure, loops, or returns poor-quality/incomplete work, do not keep retrying it: hand the same frozen bounded task to `~/.local/bin/luna-worker`. If Luna also fails or the task proves ambiguous/shared/core, Terra takes it back.**
4. Render/capture a coherent screen/system batch only after the implementation is stable enough to review.
5. **Astra reviews the actual rendered batch** against the pinned original references and reports only material visual/interaction differences, ordered by impact.
6. **Terra decides** which findings are worth fixing. Bounded fixes follow the same **DeepSeek → Luna → Terra** fallback; Astra is not an implementation fallback. Terra then owns integration/native/final verification.
7. Leave a GitHub checkpoint at a meaningful milestone or at least every 60 minutes during long work; update #52 only when the concise handoff materially changes.

## Visual priority

Fix in this order unless a functional blocker requires otherwise:

1. Large composition/layout/scale/hierarchy mismatches.
2. Missing visible screens, controls, assets, portraits/icons, effects or source-backed information.
3. Typography, spacing, sizing, alignment, hover/input affordances and timing that materially affect resemblance or use.
4. Cheap polish. Do not spend disproportionate time on pixel archaeology below the existing 90–95% player-perceived fidelity target.

## Evidence required before calling a screen GREEN

Record only what was actually checked:

- original version/provenance and comparable entry/state;
- remake exact HEAD/package/catalog identity where relevant;
- actions required to reach and use the screen;
- original/remake rendered evidence for comparable states;
- focused functional/input checks where relevant;
- permitted deviations / unresolved bounded gaps;
- Astra visual/interaction verdict for the coherent batch;
- Terra integration/acceptance decision.

A screenshot by itself is not a functional PASS, and functional tests by themselves are not a presentation PASS.

## Resource / writer constraints

- Run `bash tools/disk_guard.sh` before any work that could materialize FULL assets/render/export; the previous S21 checkpoint hit ENOSPC.
- Ordinary workers stay THIN. Do not duplicate full Git LFS/original-scene/Godot caches.
- One writer owns shared `game/ui/main_ui.gd`, shared core/save/schema/AI/payment seams and common controllers at a time.
- No force-push, no overlapping writes, no repeated broad/full regressions for tiny visual edits.
