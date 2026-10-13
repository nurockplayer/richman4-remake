# Agent entry point

Read the **Issue #1 body**, the **Issue #52 body**, and the current active Issue/PR. Do **not** scan #1 comments for live state. README is informational, not an additional instruction source.

- **Terra leads the project and makes integration/scope decisions.** Terra owns sequencing, architecture, shared-writer changes, acceptance interpretation, merge decisions, hard blockers and final verification.
- **Use the configured WorkerRouter path as the default writer** for clear, bounded routine implementation, focused tests, exploration and mechanical work. Provider selection is routing policy, not workflow authority; do not bypass WorkerRouter by calling provider-specific wrappers merely for convenience.
- A WorkerRouter implementation worker owns only its prepared bounded write lane, runs focused self-tests, commits the exact result and returns a concise change/test/blocker summary. The worker does not decide product scope, push/merge, or final acceptance.
- **Oracle is the default read-only decision/review lane at explicit reasoning or exact-HEAD review boundaries.** Oracle is not an implementation writer, queue authority or polling heartbeat. Its result must return to the **same Terra orchestration session** that owns the active segment; Terra decides repair, revalidation and the next segment.
- Keep exactly one product writer for this repository at a time. Historical draft PRs are evidence/reference unless the active Issue explicitly re-admits their logical delta. Never force-push or bypass protections.
- Do not babysit workers. Prefer blocking/event waits; if polling is unavoidable, wait at least 3 minutes between status checks. Do not reread the repo or rerun tests merely to ask whether a worker finished.
- Reuse frozen source contracts, fixtures and prior verified evidence. Do not repeat source archaeology or broad repo scans unless new contradictory evidence requires it.
- Batch compatible low-interaction work when safe. Workers run focused self-tests; Terra pays affected/integration/native/full verification costs only at the appropriate segment or merge gate rather than duplicating each worker's checks. Successful test output should be summarized rather than copied verbatim unless needed to diagnose a failure.
- Make reasonable reversible decisions autonomously. Ask the owner only for genuine external blockers or an irreversible product choice that cannot be inferred safely.
- Use scoped Issues/PRs and serial writer ownership. Read-only research may be parallelized only when it cannot collide with the active writer.
- Treat valid unresolved P1/P2-equivalent review findings as active review debt even after the source PR was merged. Re-check against current `main`; carry still-valid debt in #52 or the active Issue. Do not let P3/nit/style-only churn interrupt delivery.
- **Before every serial segment, reread the live #52 body and active Issue/PR head/state.** The normal segment order is RECONCILE -> IMPLEMENT -> VALIDATE -> ORACLE -> bounded REPAIR if needed -> FINAL.
- **At the end of every segment, leave one compact executable GitHub checkpoint** on the active Issue/PR: segment, exact HEAD, concrete completed facts, PASS/FAIL/BLOCKED gate, and one next action. Do not dump raw logs.
- **#52 is only the concise current handoff** (HEAD, active work, verification summary, gaps, next action). Replace its body only when the live development boundary materially changes or a merge completes; do not append history there.
- Do not keep one Terra parent session alive indefinitely across milestones. Finish the current bounded write/verification first; Oracle review/repair for that segment stays in the same Terra session. At a natural completed milestone, replace #52 with a compact handoff and start the next milestone in a fresh Terra session. Do not rotate sessions mid-write merely to reduce context.

### SCD milestone relay

SCD 可在已授權範圍內跨正常階段與 milestone relay；此規則不新增產品、runtime、Hot Reload、source-of-truth 或 cutover 授權，也不授權 M5。每個 lane 仍只能有窄化且不重疊的 writer；不得 force-push 或繞過 acceptance、hosted verification、exact-head 或獨立 review gate。測試採分層且以足夠的最低成本層級為準；每 60 分鐘內及每個實質 milestone 都要留下可執行的 GitHub checkpoint，#52 只保留目前狀態與下一個可執行動作。

正常 `BLOCKED` 代表預期可在目前委派權限內以技術工作解決的 blocker；`ESCALATED` 代表需要較強模型或獨立調查，仍不等於需要 owner 輸入。兩者都應繼續既有窄 scope、focused/affected testing、有效 P1/P2 review 修正、exact-head hosted verification、適用的獨立 review gate（目前預設 Oracle；只有 active Issue 明確要求時才另用其他 reviewer）與 merge 流程；可另開獨立、可逆且不衝突的 base-regression lane，完成後回到暫停中的 milestone，不得藉此豁免 gate。

完成 merge 後，當前 parent 必須先以 exact merge/evidence 更新 #52，再在自然 checkpoint 結束；下一個 parent 必須是 fresh session，重新讀取 #1、#52、`AGENTS.md` 與 live active Issue/PR，進入 `RECALIBRATING`，檢查 current `main`、writers、未解決的 P1/P2 debt 與 mission constraints。只有在下一步是目前 owner-authorized lane 已明示的唯一最小、相干、可逆且低風險 successor 時，才可自行選取並繼續；否則停在 `OWNER_REQUIRED`。

只有下列情況才是 `OWNER_REQUIRED`：需要在多個合理且實質不同的產品方向間選擇；會改變產品/runtime authority、source-of-truth、Hot Reload/cutover、save/schema compatibility 或其他不可逆邊界；缺少 credentials、法律／公開發布許可、私有外部資料、硬體／人工操作等真實外部依賴；與 active writer 重疊且無法安全排序；唯一前進路徑是削弱或繞過 acceptance/hosted gate；下一 milestone 不是既有授權 lane 已明示；反覆的 bounded investigation 沒有產生新的 discriminating evidence，而採用 fallback 會實質改變產品行為；治理規則例外；或已無剩餘授權工作。一般 bug、可辨識的 flaky failure、review finding 與可逆實作選擇不會僅因其本身成為 `OWNER_REQUIRED`。

- Target **90–95% player-perceived fidelity**, not perfect reconstruction; do not perform exploratory archaeology merely to discover more work.
- Unknowns are not blockers by default. Bound investigation, record a plausible fallback, continue, and defer non-blocking gaps rather than delay delivery.
- In polish/RC, investigate only reproducible player-visible discrepancies or failed agreed acceptance tests; do not expand release scope through discoveries.
- Do not use a blanket rule that original assets must stay off GitHub. Secrets stay out of GitHub, and this public code repo must not contain third-party original assets without publication rights. The owner-authorized canonical source is private Git/LFS repo `nurockplayer/richman4-remake-assets`; fresh clones retrieve its pinned revision through manifest/bootstrap. Do not substitute another storage backend.
- Treat ordinary Codex worktrees as **THIN**. Do not create another full Git LFS checkout, decoded original-asset tree, complete Godot import cache, export bundle, or other multi-GB duplicate merely for isolation. `tools/bootstrap_private_assets.sh` reuses the machine-wide pinned private-asset cache.
- Full asset/Godot materialization is exceptional. Reuse the single **FULL** validation lane; only materialize integrated assets/render/export when the active task genuinely requires it, run `bash tools/disk_guard.sh` first, and do not create a second FULL lane below the warning threshold.
- `.godot/`, `.local/imported-original/`, `.local/original-scenes/`, `build/`, `dist/`, test results and similar generated outputs are disposable caches, not authority.

Start building in Godot. Do not redo the engine decision or stop at documentation/prototypes when executable work is available. Only claim behavior or validation that was actually checked.
