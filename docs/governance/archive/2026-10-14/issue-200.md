## Owner directive — 2026-09-27 playable-spine amendment

This Issue remains the Richman4 **engineering operating-model authority**. Product sequencing is now controlled by #204: ordinary human playability is P0 and supersedes the former automatic #199-next queue.

The operating model follows the current Tachiko Conductor direction (#134, #132): roles are conceptually Lead / Worker / Reviewer / Consultant; current qualified bindings are below. Repository/product authority remains local.

## Roles and engineering authority

- **GPT-6 Sol — Lead/integrator and highest engineering decision authority inside the owner-authorized lane.** Sol owns sequencing, architecture, scope interpretation, implementation strategy, shared integration, validation strategy, acceptance interpretation, repair disposition, merge readiness and technical tradeoffs.
- **GPT-6 Luna — Worker.** Sol may delegate bounded implementation/tests/mechanical work. One authoritative product writer at a time.
- **Oracle / Ego-lite — independent read-only Reviewer paths.** Use according to active acceptance/risk and Sol judgment. A review provides evidence; it does not own engineering disposition.
- **Astra — Consultant escalation.** Sol may consult Astra for architecture/systemic ambiguity, difficult failures, wrong-abstraction suspicion, cross-cutting risk or high-impact engineering/product/UX decisions. Record the question, advice and Sol disposition. Sol retains final engineering authority.
- Ask the owner only for genuine external dependencies or irreversible product choices.

Do not resurrect Terra/WorkerRouter routing merely because stale prose remains elsewhere. #203 owns migration to the versioned shared policy after tachiko-conductor #134 is ready.

## Current product priority

**#204 — Ordinary human playable spine to completion** is the current P0 execution authority.

Do not automatically admit #199 SALE. Sol must prioritize live ordinary-player blockers discovered from normal native launch. Existing #115/#118, #101 and #167 are authoritative inputs and should be reconciled/deduplicated under #204.

Peripheral fidelity work may proceed only when Sol judges it does not displace a higher-impact P0/P1 ordinary-play blocker.

## Session reconstruction and merge reset

Every fresh Sol lead starts from GitHub, not chat memory. Read at minimum:

- #1;
- #52 canonical handoff;
- #204;
- this Issue;
- relevant active Issue/PR;
- current AGENTS/adoption state including #203;
- live main/writer/review/check/native evidence.

At every terminal merge, update #52, **end that lead context**, and continue only from a fresh Sol session/context that reconstructs authority and live state from GitHub before admitting the next work. This applies tachiko-conductor #132's hard-reset boundary.

## Stage and decision receipts

Sol chooses the stages appropriate to the problem; the old fixed stage list is not a constraint. After every meaningful stage, post a compact checkpoint to the active Issue/PR:

```
STAGE: <name>
HEAD: <exact sha>
DONE: <concrete facts/evidence>
GATE: <PASS|FAIL|BLOCKED>
DECISION: <material Sol decision + rationale, if any>
NEXT: <one executable next action>
```

Any material decision changing architecture, sequencing, scope interpretation, validation strategy, accepted risk, fallback, repair disposition or active child must be recorded on GitHub before proceeding.

Reread #52/live state at material boundaries. Keep receipts concise and link evidence; do not dump raw logs.

## Validation and review principles

- Evidence must match the claim. Headless/fixture/component evidence cannot prove ordinary native playability.
- For #204's playable spine, final acceptance requires fresh current-HEAD ordinary native interaction from normal launch using real UI input and demonstrated multi-turn continuity.
- Preserve existing deterministic, hosted, exact-HEAD, asset/privacy and stronger child acceptance gates where applicable.
- Do not weaken tests or redefine failures to get green.
- Reviewer findings are independently dispositioned by Sol. If a required exact-HEAD review becomes stale after repair, refresh it.
- Sol may choose deeper refactoring when evidence shows the current abstraction is the problem; there is no blanket small-patch constraint.

## Handoff discipline

#52 is the single concise live handoff: exact main/active HEAD, active lane, proven player-visible capability, current blockers/gates, material decisions and next executable action. Update it whenever the live boundary materially changes and after every merge.

Historical PRs/issues remain evidence, not current authority when they conflict with #52/#204/current main.

## Completion direction

Continue autonomously, merge by merge and fresh context by fresh context, until #204's ordinary playable spine is genuinely complete. Then Sol recalibrates against #1/#99/#102/#167 and chooses the next highest-value fidelity/release work from live evidence.