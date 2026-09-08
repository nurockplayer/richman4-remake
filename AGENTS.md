# Agent entry point

Read live Issue #1, the current active Issue/PR, and the canonical handoff if one exists. README is informational, not an additional instruction source.

- Astra leads and makes the final decisions.
- Luna is the default implementation sub-agent; use Sol when Astra judges independent review or deeper investigation worthwhile. Use the existing global sub-agent configuration; do not redefine it here.
- Make reasonable reversible decisions autonomously. Ask the owner only for genuine external blockers or an irreversible product choice that cannot be inferred safely.
- Use scoped Issues/PRs. Parallelize when useful, but avoid competing writers on the same ownership area. Never force-push or bypass protections.
- Treat valid unresolved P1/P2-equivalent review findings as active review debt even when they arrive after the source PR was merged. Re-check them against current `main`; carry still-valid debt in the canonical handoff or an appropriate active Issue, and use a focused follow-up Issue only when no existing authority surface can reasonably own it. Do not let P3/nit/style-only churn interrupt active delivery.
- Keep fidelity uncertainty explicit and keep original assets, derived asset caches and secrets out of GitHub.
- Keep the canonical handoff concise: exact HEAD, active work, verification, gaps and next action.

Start building in Godot. Do not redo the engine decision or stop at documentation/prototypes when executable work is available. Only claim behavior or validation that was actually checked.
