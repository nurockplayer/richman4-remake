> **2026-09-26 owner routing amendment:** [#200](https://github.com/nurockplayer/richman4-remake/issues/200) is the current model-routing/serial-execution authority. It supersedes older Terra/DeepSeek/Astra-lead/Oracle-only role text only where conflicting; this Issue's product scope and acceptance contract remain authoritative. GPT-6 Sol leads, GPT-6 Luna implements, Oracle + Ego-lite independently review exact final HEAD, and Astra is advisory escalation for architecture/difficult blockers.

Parent / release context: #1, #99, #102. Current handoff remains #52; `AGENTS.md` remains execution authority.

## Why this exists

Owner native play on 2026-09-12 exposed multiple **functional** failures in ordinary player-visible flows. This is not another broad fidelity-archaeology campaign and does not replace #102. It is a bounded playability pass to find dead controls, soft locks, broken turn continuity and debug/fallback interaction that static/headless PASS can miss.

Owner-observed starting findings (reproduce on the exact current subject before claiming root cause or opening a repair PR):

- Human dice/roll does not produce the expected playable movement flow.
- Route-choice presentation exposes raw/debug-like choices such as `→ 01`, `→ 34` / `route`; verify whether the interaction itself matches the targeted original before changing it.
- Bank/ATM amount keypad is visible but number-key clicks do not respond in the observed native flow.
- Toolbar `?` opens `說明資料無法顯示`; the overlay has no working dismissal in the observed flow, leaving the game soft-locked.

Do not publish owner screenshots or restricted original artwork to this public repo. Safe textual findings, hashes, commands and nonrestricted evidence metadata are fine.

## Ownership / routing

- **Terra is QA captain for this umbrella.** Astra remains integration steward/final authority under `AGENTS.md`.
- Terra may delegate multiple **non-overlapping** audit/reproduction packages to Luna in parallel. Prefer read-only exploration, focused tests and isolated THIN worktrees.
- Do **not** let multiple workers drive the same physical native Godot window/input session concurrently. Keep one physical-OS/native UI driver at a time unless sessions are truly isolated; parallelize code inspection, headless/focused repros and unrelated flows around it.
- Discovery lanes do not modify production code. Once a finding is reproducible, dedupe it against existing Issues (#98/#101/#102/#130/#135 and current active work). Link the existing owner when applicable; otherwise open a small child Issue.
- A bounded child fix may go to Luna only when file/state ownership is unambiguous and non-overlapping with #52/current active PR. `main_ui.gd`, shared core/save/AI, modal/turn ownership and cross-system integration remain single-writer and escalate to Astra/integration owner.
- No new FULL lane, corpus duplication, package/export campaign or source archaeology merely for this audit. Use cheapest sufficient verification and existing evidence/assets.

## First-pass coverage

Run from an ordinary native launch/new game and record **actual interaction**, not “implemented in code”. Keep source/original comparison only where behavior is uncertain.

1. Launch/new game → human turn readiness.
2. Dice input → visible roll → movement → branch/route choice → landing → purchase/upgrade/cancel → next player.
3. Open/use/close all reachable top-level HUD/toolbar surfaces, including help and every modal dismissal path (button, cancel, right-click/ESC where source-backed).
4. Bank/ATM: amount keypad, clear/backspace/MAX/percent/confirm/cancel, deposit/withdraw and return-to-board continuity.
5. Stocks: open/select/buy/sell/cancel/close/reopen; state and displayed funds/holdings agree.
6. Cards/tools/shop/targeting/reactions: at least one ordinary legal action plus cancel/close; no dead overlay or hidden input capture.
7. News/fate/other reachable event dialogs: enter, acknowledge/resolve, return to play.
8. Save/load/restart/settings/quit confirmations where currently reachable.
9. AI turn and handoff back to human; continue for several consecutive turns without manual developer intervention.

If an early P0 blocks later coverage, preserve the repro and continue unblocked areas using only existing legal fixtures/drivers. Clearly label fixture-only evidence; it does not replace ordinary-entry verification.

## Finding record

For each distinct problem record compactly:

`ID | severity | area | exact HEAD/build | entry/action | expected/source | actual | repro rate | evidence | existing/child Issue`

Severity:
- **P0**: soft lock/crash/core turn cannot continue / ordinary game becomes unplayable.
- **P1**: major normal flow or required interaction broken, but session can recover/work around.
- **P2**: localized control/state defect with bounded impact.
- **P3**: presentation/fidelity/polish only; do not let it interrupt P0/P1 recovery.

Do not infer a cause from appearance alone. Separate `FUNCTIONAL`, `NATIVE INPUT`, and `FIDELITY` verdicts.

## Suggested parallel audit packages

- **A — Turn core:** dice, movement, route, landing, purchase, turn handoff.
- **B — Finance/modals:** bank/ATM, amount pad, stock interactions, modal close/focus.
- **C — Toolbar/inventory:** help, cards, tools, shop, targeting/reactions, settings/save/load entry.
- **D — Continuity:** AI turns, events, save/load continuation, restart/return-to-board and stale-overlay cleanup.

Workers return only concise repro evidence and likely ownership; Terra deduplicates and verifies the highest-severity findings before any repair fan-out.

## Checkpoints

Leave a short executable checkpoint in this Issue at meaningful milestones and at least once per ~60 minutes of active work: exact subject, coverage completed, new P0/P1s, child/existing issue links, blockers and next batch. Do not dump raw logs or poll workers frequently.

Update #52 only with the concise live handoff when this audit changes the current active boundary; detailed findings stay here / in child Issues.

## Exit gate for the audit phase

The first audit is complete when:

- every first-pass area above has a PASS, a reproducible finding linked to an Issue, or a specific external blocker;
- no discovered P0/P1 remains untriaged;
- owner-reported dice, route, bank keypad and help-soft-lock observations have exact-subject dispositions;
- Terra provides a prioritized child-Issue repair queue with ownership boundaries and the smallest verification plan for each.

This umbrella does **not** close #1/#99/#102 and does not itself declare fidelity or release PASS.