# Agent entry point

Read the **Issue #1 body**, the **Issue #52 body**, and the current active Issue/PR. Do **not** scan #1 comments for live state. README is informational, not an additional instruction source.

- Astra leads and makes the final decisions.
- Luna is the default implementation sub-agent; use Sol when Astra judges independent review or deeper investigation worthwhile. Use the existing global sub-agent configuration; do not redefine it here.
- Make reasonable reversible decisions autonomously. Ask the owner only for genuine external blockers or an irreversible product choice that cannot be inferred safely.
- Use scoped Issues/PRs. Parallelize when useful, but avoid competing writers on the same ownership area. Never force-push or bypass protections.
- Treat valid unresolved P1/P2-equivalent review findings as active review debt even after the source PR was merged. Re-check against current `main`; carry still-valid debt in #52 or the active Issue. Do not let P3/nit/style-only churn interrupt delivery.
- Long local work must remain observable. At least once every 60 minutes, or sooner at a meaningful milestone, leave an executable GitHub checkpoint. Detailed implementation/test evidence belongs in the active Issue/PR; **#52 is only the concise current handoff** (HEAD, active work, verification summary, gaps, next action) and its body is replaced in place rather than appended as history.
- Target **90–95% player-perceived fidelity**, not perfect reconstruction; do not perform exploratory archaeology merely to discover more work.
- Unknowns are not blockers by default. Bound investigation, record a plausible fallback, continue, and defer non-blocking gaps rather than delay delivery.
- In polish/RC, investigate only reproducible player-visible discrepancies or failed agreed acceptance tests; do not expand release scope through discoveries.
- Do not use a blanket rule that original assets must stay off GitHub. Secrets stay out of GitHub, and this public code repo must not contain third-party original assets without publication rights. The owner-authorized canonical source is private Git/LFS repo `nurockplayer/richman4-remake-assets`; fresh clones retrieve its pinned revision through manifest/bootstrap. Do not substitute another storage backend.
- Treat ordinary Codex worktrees as **THIN**. Do not create another full Git LFS checkout, decoded original-asset tree, complete Godot import cache, export bundle, or other multi-GB duplicate merely for isolation. `tools/bootstrap_private_assets.sh` reuses the machine-wide pinned private-asset cache.
- Full asset/Godot materialization is exceptional. Reuse the single **FULL** validation lane; only materialize integrated assets/render/export when the active task genuinely requires it, run `bash tools/disk_guard.sh` first, and do not create a second FULL lane below the warning threshold.
- `.godot/`, `.local/imported-original/`, `.local/original-scenes/`, `build/`, `dist/`, test results and similar generated outputs are disposable caches, not authority.

Start building in Godot. Do not redo the engine decision or stop at documentation/prototypes when executable work is available. Only claim behavior or validation that was actually checked.
