Upstream canonical owner: `nurockplayer/tachiko-conductor#46`

## Goal

Adopt the shared Tachiko Conductor GSD token-efficiency improvements in `richman4-remake` and verify them with one representative end-to-end development run.

This is an **adoption/benchmark Issue only**. Do not reimplement or fork orchestration policy locally.

## Dependencies

Adopt after the upstream Conductor work under #46 is proven through the Conductor pilot and earlier external adoption. Richman is intentionally later in the rollout because long-running game-development agents and asset/test workflows can expose different runtime behavior.

If Richman exposes a genuine incompatibility, report/fix the shared behavior upstream unless it is inherently game/repository-specific.

## Scope

- Update Richman's GSD/SCD integration/configuration to use the shared optimized path.
- Preserve game-specific build/test, asset boundaries, worktree ownership and independent final review.
- Select one representative implementation Issue with worker activity, validation and final independent review.
- Capture upstream per-run token/turn metrics.
- Compare against the pre-change baseline where reasonably comparable.
- Pay particular attention to long-running worker waits/status handling and reviewer restart count.

## Explicit non-goals

- No Richman-local polling engine.
- No local reviewer lifecycle fork.
- No local replacement for Conductor telemetry.
- No blanket model/reasoning downgrade.
- No weakening of game/asset safety or independent final review.

## Acceptance

- [ ] Richman uses the shared Conductor token-efficient execution path.
- [ ] No duplicate local orchestration implementation is introduced.
- [ ] One representative end-to-end run completes under the new path.
- [ ] Run report includes model turns, wait/status wakeups, reviewer starts/restarts, context mode, token metrics where available, and largest tool result.
- [ ] Existing validation and final independent review remain valid.
- [ ] Shared-runtime incompatibilities are fed back to `tachiko-conductor#46` rather than permanently patched around locally.
- [ ] Adoption result records concise before/after observations.