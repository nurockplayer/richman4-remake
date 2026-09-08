# Agent entry point

Read live Issue #1, the current active Issue/PR, and the canonical handoff if one exists. README is informational, not an additional instruction source.

- Astra leads and makes the final decisions.
- Luna is the default implementation sub-agent; use Sol when Astra judges independent review or deeper investigation worthwhile. Use the existing global sub-agent configuration; do not redefine it here.
- Make reasonable reversible decisions autonomously. Ask the owner only for genuine external blockers or an irreversible product choice that cannot be inferred safely.
- Use scoped Issues/PRs. Parallelize when useful, but avoid competing writers on the same ownership area. Never force-push or bypass protections.
- Treat valid unresolved P1/P2-equivalent review findings as active review debt even when they arrive after the source PR was merged. Re-check them against current `main`; carry still-valid debt in the canonical handoff or an appropriate active Issue, and use a focused follow-up Issue only when no existing authority surface can reasonably own it. Do not let P3/nit/style-only churn interrupt active delivery.
- Long local work must remain observable. At least once every 60 minutes, or sooner at a meaningful milestone, leave an executable GitHub checkpoint: a pushed commit/PR, or a substantive Issue/handoff update that names the exact branch/HEAD, completed implementation, verification evidence, current blocker if any, and next action. Do not let more than 120 minutes pass without such a checkpoint.
- Keep fidelity uncertainty explicit.
- Do not use a blanket rule that original assets must stay off GitHub. Secrets must stay out of GitHub, and this public code repository must not contain third-party original assets unless the owner has the rights needed to publish them here. Owner-authorized project assets must instead have a reproducible, versioned source of truth that a fresh clone can retrieve with the owner's credentials; prefer a private Git/LFS asset repository or an equivalent authenticated store, plus a manifest/bootstrap path from this repo. A local game installation may be an import source, but must not remain the only source needed to reconstruct the owner's full development environment.
- Keep the canonical handoff concise: exact HEAD, active work, verification, gaps and next action.

Start building in Godot. Do not redo the engine decision or stop at documentation/prototypes when executable work is available. Only claim behavior or validation that was actually checked.
