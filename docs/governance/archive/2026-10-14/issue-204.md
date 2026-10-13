## Owner directive — 2026-09-27

This Issue is the **current P0 product-execution authority** for Richman4 ordinary human playability. It supersedes the old serial product queue in #200/#52 where that queue would admit #199 SALE before the ordinary player journey is actually playable. Mission/product constraints in #1, fidelity authority in #99/#101/#102, and concrete defect evidence in #167 remain authoritative.

The current product is **not accepted as playable** merely because subsystems, fixtures, headless tests, injected states, component captures, or historical packaged runs pass.

### Completion objective

Drive current `main` from an ordinary native launch until a normal human can play Richman4 naturally and continuously. Sol has broad engineering discretion to discover, sequence, repair, refactor where justified, open/close child Issues, and choose the smallest or deeper correct solution. Do not optimize for preserving the old S-stage queue when it conflicts with actual playability.

At minimum, prove the real ordinary-entry spine:

1. launch/title/new game;
2. source-oriented character/map/opening setup with actual human selection;
3. enter the board in a valid human turn;
4. visible/usable dice interaction;
5. roll -> movement -> route choice when applicable -> landing;
6. purchase/upgrade/cancel and other mandatory landing continuations;
7. turn handoff to AI and back to a human;
8. repeat multiple consecutive turns without developer intervention;
9. reachable critical ordinary surfaces do not soft-lock the game, including bank/ATM, stock, cards/tools/shop, help/modal dismissal, events and save/load where encountered or required by #167;
10. packaged/native ordinary input path agrees with authoritative state and remains playable after restart/save-load where applicable.

#115/#118 setup work, #101 board/HUD playable slice and #167 native playability findings are inputs/children of this objective. Deduplicate rather than creating parallel ownership.

### Acceptance philosophy

Evidence must follow the player. A code path existing is not proof that a player can reach/use it.

For the completion spine, fixture/injected/headless evidence is supporting evidence only. Final acceptance requires fresh current-HEAD **ordinary native interaction from normal launch using real UI input**, with enough consecutive play to demonstrate continuity. Preserve deterministic/focused/hosted gates as useful engineering evidence, but never substitute them for the native player journey.

Do not claim Mission/release completion from selected components or historical evidence. Any blocker encountered on the ordinary path is prioritized by impact: P0/P1 playability before peripheral fidelity/polish.

### Engineering authority and operating model

Follow the latest Conductor operating model represented by tachiko-conductor #134/#132 and Richman4 #200, with this Issue taking precedence for the current product queue:

- **GPT-6 Sol is the lead/integrator and highest engineering decision authority inside this owner-authorized mission.** Sol owns sequencing, architecture, scope interpretation, implementation strategy, validation strategy, repair disposition, merge readiness and technical tradeoffs.
- GPT-6 Luna may implement bounded write packages chosen by Sol. Keep one authoritative product writer at a time.
- Oracle/Ego-lite provide independent read-only review where Sol judges it useful/required by risk and existing gates. Review advice does not own disposition.
- **Astra is available to Sol for architecture/systemic ambiguity, difficult failures, wrong-abstraction suspicion, cross-cutting risk, or high-impact product/UX engineering judgment.** Sol retains the decision. Record the question, advice and Sol disposition.
- Owner escalation is for genuine external dependencies or irreversible product choices, not routine engineering judgment.

This directive intentionally does **not** prescribe implementation details, file boundaries, patch size, or a fixed number of stages. Sol should use its engineering judgment and may revise the plan when evidence changes.

### Mandatory reconstruction before work

At the start of every fresh Sol session, and after every terminal merge, reconstruct from GitHub rather than chat history:

1. #1;
2. #52 canonical handoff;
3. this Issue;
4. #200 and relevant live child Issues/PRs;
5. current AGENTS/adopted agent policy state, including #203/#134 status;
6. current `main`, writers, review debt, checks and native evidence.

After a merge, **stop the completed context**. Update #52, then continue only as a fresh Sol context/session that rereads GitHub and independently admits the next work. This is the Richman4 application of tachiko-conductor #132's hard-reset boundary.

### GitHub stage/decision receipts

Work must remain reconstructable without chat history.

After every meaningful stage, checkpoint the active Issue/PR:

```
STAGE: <name>
HEAD: <exact sha>
DONE: <facts/evidence>
GATE: <PASS|FAIL|BLOCKED>
DECISION: <material Sol decision + rationale, if any>
NEXT: <one executable next action>
```

A material Sol decision about architecture, sequencing, scope, accepted risk, validation, fallback, repair disposition, or changing the active child must be recorded on GitHub before proceeding. Keep receipts concise; link evidence rather than dumping logs.

At each material boundary reread #52/live state so stale context cannot silently become authority.

### Merge and continuation rule

Merge only when the admitted child/lane satisfies its own acceptance and does not regress the ordinary playable spine. Immediately after every merge:

- update #52 with exact merged main, proven player-visible capability, remaining blockers and next executable action;
- terminate the current lead context;
- start/reconstruct as a fresh Sol session from GitHub;
- decide the next highest-impact blocker from live evidence.

Do **not** automatically resume #199 merely because it was previously next. #199 may be admitted when Sol determines the ordinary playable spine is sufficiently established and SALE is genuinely the next highest-value blocker/capability.

### Done

This Issue is complete only when fresh exact-current packaged/native evidence demonstrates that an ordinary human can start a game through the normal UI and play continuously through the core Richman4 loop, with no known untriaged P0/P1 on that ordinary journey. Sol must leave a final GitHub decision explaining the evidence and any explicitly deferred non-blocking fidelity debt.

This Issue does not lower the 90–95% player-perceptible fidelity target in #1. It restores the prerequisite that there is a real playable game to apply fidelity work to.