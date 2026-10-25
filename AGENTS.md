# Engineering guide

Ship a production-ready, high-fidelity Richman4 in Godot. Optimize for working
player-facing features and rapid delivery.

## Authority and startup

- [#1](https://github.com/nurockplayer/richman4-remake/issues/1) owns the product
  goal and v1.0 release criteria; [#204](https://github.com/nurockplayer/richman4-remake/issues/204)
  owns the release-candidate playtest; [#52](https://github.com/nurockplayer/richman4-remake/issues/52)
  is the current handoff. This file owns engineering workflow. Older process
  rules, queues and admission controls are historical.
- The lead (currently Claude Opus) decides sequencing, architecture, delegation,
  validation and merges. Reviewer advice informs, it does not gate.

## Work

- Continue autonomously across fixes and merges. Prefer the highest-impact gap
  between main and the #1 release criteria. Reuse existing research, drafts and
  tests; port useful drafts onto current main rather than re-deriving them.
- Refactor when it speeds delivery or fixes correctness. Keep simulation/RNG
  reproducible and save/load reliable; tests never touch the owner's saves.
- One writer per branch; branch every PR from main (never stack PR branches).
  One driver of a physical game session at a time.
- Ask the owner only for external access, publication rights or destructive
  actions on shared resources. Everything else is lead work.

## Delivery

- Merge gate: hosted Verify green, one review by someone other than the author
  (lead review counts for worker PRs; bots are advisory), and no unresolved
  valid P1/P2. Never force-push or weaken tests to obtain green.
- Use the cheapest sufficient checks: focused tests for a change, broader checks
  for cross-cutting risk. Rerun only affected tests after a rebase.
- Native input/visual verification happens in batched playtests of release
  candidates (#204), not per PR. Defects found there become ordinary bugs.
- Missing original art gets a playable placeholder and a follow-up, never a
  blocked merge.
- PR bodies: what changed, tests, CI link. Keep #52 to about five lines.

## Assets and local resources

- Secrets and original Richman4 assets stay out of this public repository. The
  canonical assets live in private `nurockplayer/richman4-remake-assets`
  (Git LFS, pinned manifest, `tools/bootstrap_private_assets.sh`); private
  packages and captures stay private.
- Reuse the shared asset cache. Run `bash tools/disk_guard.sh` before
  materializing assets/imports/packages and respect its hard stop.

The [2026-10-14 governance audit](docs/governance/2026-10-14-audit.md) and its
archive are historical.
