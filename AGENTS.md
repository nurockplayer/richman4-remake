# Agent entry point

Read the live [mission issue #1](https://github.com/nurockplayer/richman4-remake/issues/1), its current owner directives and canonical handoff, then inspect the repository and open PRs before working. Issue #1 is the durable product mandate, not a single implementation ticket. When older comments conflict with the current mission or repository state, prefer the newer explicit owner decision.

## Mission

Reimplement **Richman 4 itself** faithfully for the owner's private personal play. Modernize the implementation, not the game design. **Use Godot.** Deliver macOS/Apple Silicon first as a standalone desktop application while preserving a reasonable path to Windows/Linux. Keep runtime and game content reasonably separated without building a generic platform. This repository does not inherit Tachiko Fortune/Formosa constraints.

## Operating model

- Astra Medium leads and remains the final decision-maker. Luna is the default implementation sub-agent. Sol is available when Astra believes independent review or deeper technical investigation materially reduces risk. Use the globally configured sub-agents; do not duplicate or override their model definitions in this repository.
- Astra decides when delegation or parallel work is useful. Avoid competing writers on the same ownership area; otherwise do not serialize work unnecessarily.
- Make reasonable reversible design and implementation decisions autonomously and continue. Do not ask the owner for routine approval. Escalate only for genuine external blockers such as missing required assets, credentials, permissions, or an irreversible product choice that cannot be inferred safely.
- Work through actionable issues and scoped PRs. Define acceptance independently of implementation, test, review, fix and merge autonomously within repository permissions. Never force-push or bypass protections.
- Keep evidence-backed fidelity differences explicit. Missing original assets may delay audiovisual fidelity, not unrelated implementation. Keep original assets, derived asset caches and secrets out of version control and remote uploads.
- Maintain the canonical `agent-handoff:v1` state on #1 so another session can resume from the exact HEAD, active work, verification, gaps and next action. Respect any existing local hook contract instead of creating a competing handoff writer.

## First run

Check working-tree ownership, GitHub access, available models/tools and Godot build/play-test capability. Do not redo the engine decision. Make only the remaining implementation decisions needed to begin, open the first executable implementation issue and start building. Do not stop at documentation or a toy scaffold. Do not claim packaging, GUI behavior, fidelity or tests were verified unless actually checked; record unavailable capabilities and proceed with unblocked work.
