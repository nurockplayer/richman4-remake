# Engineering guide

Build a fully playable, high-fidelity Richman4 in Godot. Optimize for verified
player outcomes and rapid delivery; choose engineering methods from evidence.

## Authority and startup

- Read the bodies of [#1](https://github.com/nurockplayer/richman4-remake/issues/1)
  (product goals and release acceptance), [#204](https://github.com/nurockplayer/richman4-remake/issues/204)
  (native playtest and repair mission), and [#52](https://github.com/nurockplayer/richman4-remake/issues/52)
  (current handoff), plus the active Issue/PR. Reconcile current source, work in
  progress and unresolved material findings before changing anything.
- This file owns engineering workflow. #52 records state, not new policy.
  Older routing directives, queues and session rules are historical where they
  conflict with these authorities; do not scan #1 comments for live state.
- Astra leads engineering: sequencing, architecture, implementation strategy,
  validation and merge decisions. Delegate clear bounded work when useful;
  no provider wrapper, worker model or fixed stage sequence is mandatory.
  Reviewer advice informs the lead's decision; it does not replace evidence.

## Work autonomously

- Continue the authorized mission across fixes and merges. Update the handoff
  at material boundaries; start a fresh session when useful, not after every
  merge. Reconcile live state when resuming or when another writer may have acted.
- Prefer the highest-impact reproducible playability or fidelity failure.
  Reuse existing research and tests. Bound uncertain investigations, record
  reasonable minor fallbacks, and avoid work that does not improve delivery.
- Challenge technical decisions when evidence warrants it. Refactor as far as
  correctness and delivery justify; neither a mandatory tiny patch nor cleanup
  for its own sake is a goal. Preserve reproducible simulation and save/load.
- Keep one owner for each write lane, serialize shared-file/integration changes,
  and use only one driver of a physical game session. Independent work may run
  in parallel without overlapping writes or competing for the same runtime.
- Ask the owner for unavailable external access, publication rights, destructive
  actions or material changes to product/safety boundaries. Routine bugs,
  test failures, repair decisions and reversible technical choices are lead work.

## Evidence and delivery

- Use the cheapest sufficient checks: focused tests for a change, affected
  integration for a feature, broader checks for cross-cutting risk. A repeated
  failure without new information calls for a better diagnostic, not blind reruns.
- Merge gate: hosted Verify green, one independent nonauthor review (the
  CodeRabbit bot is advisory; do not wait on it when stuck), and no unresolved
  valid P1/P2 finding. After a rebase, rerun only the affected tests. Never
  force-push, bypass branch protections or weaken tests to obtain green.
- Functional, native/package and original-presentation verdicts are tracked
  separately, and only the functional verdict gates merge. Native verification
  is a merge prerequisite only for PRs that change input, focus, window or
  rendering behavior; otherwise open a follow-up under #204. Missing original
  art gets a playable placeholder and a fidelity follow-up, not a blocked merge.
  Release and #1 closure require all three verdicts. Report only what was
  checked; headless runs and source review do not prove native reachability.
- Keep PR bodies short: what changed, which tests, CI link. Write failing tests
  first where useful, without frozen-RED commits or quoted check counts.
- Publish safe source changes to a branch/PR early enough to avoid losing work.
  Historical drafts and unavailable candidates are evidence, not automatically
  integrated code. Work on an explicitly identified available baseline; never
  call a reconstruction identical without verifying it.
- Record material decisions, failures, evidence and rationale on the active
  Issue/PR. Keep #52 to about five lines: main SHA, active PR/owner, blockers,
  next action. Do not accumulate history or receipts in the handoff. Prefer
  event waits and avoid redundant status checks.

## Assets and local resources

- Keep secrets and third-party original assets without publication rights out
  of this public repository. The canonical asset source remains private
  `nurockplayer/richman4-remake-assets` with Git LFS and a pinned, verified
  manifest/bootstrap. Keep restricted captures and packages private.
- Reuse the shared asset cache and a single FULL validation lane. Ordinary
  worktrees stay THIN. Run `bash tools/disk_guard.sh` before materializing
  assets/imports/packages; do not override its hard stop without owner approval.
  Existing caches are reusable, disposable outputs, not source authority.
- Product/runtime authority changes, Hot Reload/cutover and previously
  unapproved migration work (including Tachiko M5) remain outside this mission.

The [2026-10-14 governance audit](docs/governance/2026-10-14-audit.md) records
superseded rules and their rationale; its archive is historical only.
