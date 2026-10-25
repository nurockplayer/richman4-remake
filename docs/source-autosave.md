# S35 daily autosave

Refs #149; builds on frozen options host #147 / PR #148.

The source setting now has a real consumer. A successful public game action
must advance the authoritative day and finish in `await_roll` after day
processing and next-actor admission. Ordinary player turns do not trigger a
save. `SourceAutosave` captures `to_dict()` without adding save-schema fields,
changing RNG, or altering initial setup metadata. Core simulation is unchanged.

The host waits for movement, news/fate/auction, finance/bank surfaces and all
queued monthly reports to finish before writing the captured state. Monthly
acknowledgment is presentation-only; it neither settles money again nor changes
the checkpoint. Pending checkpoints gate actors and save/load/new-game entry.
An application exit before acknowledgment therefore retains the previous AUTO.
Terminal `game_over` transitions do not create a new checkpoint in this batch.

A setting committed before the next day wrap controls that wrap. Enabling
mid-day does not backfill a previous day; disabling before wrap suppresses it.
The options host cannot change settings while a checkpoint is pending. Loading
adopts a new owner without scanning old logs or replaying a historical write.
Duplicate delivery of the same transition is ignored. Owner replacement clears
pending snapshots, and retry/cancel callbacks are bound to their dialog, owner
and presentation generation.

## Storage and row identity

- Automatic writes use `user://richman4-save-slots/auto.json` through
  `SaveSlots.write_automatic()`. Manual rows 1–5 keep their existing paths and
  behavior. `write(0)` remains read-only.
- Row 0 selects an existing automatic file and visibly says `AUTO`. A corrupt
  automatic file remains corrupt; the picker does not silently load legacy
  data instead. If automatic is absent, row 0 is the read-only legacy fallback
  and visibly says `原有存檔`.
- Row results carry `source_identity`; the automatic fingerprint has a separate
  source domain, so an identical-byte legacy/AUTO source replacement is stale
  after preview. Manual and legacy fingerprint behavior is unchanged.
- The caller's legacy path is preserved. Conflicting configured automatic/manual
  and legacy paths reject automatic writes with `automatic_path_conflict`.
  No automatic operation writes the legacy owner file.
- Both automatic and manual writes share strict payload validation, destination
  locking, unique temporary files, readback validation and atomic replacement.

Failure keeps the previous file intact and opens a visible Retry / Skip this
checkpoint dialog. Retry submits the same admitted snapshot; there is no busy
retry loop. Skip resumes the game, and the next actual enabled wrap can save
again. This error dialog uses the existing Godot dialog style; its original-game
appearance is not accepted.

## Evidence boundaries

Tests use explicitly owned paths or in-memory storage. Focused tests cover real
human and AI cycles, finance continuation, monthly pending/ack, settings commits,
ordinary AUTO menu loading, deterministic continuation, duplicate callbacks,
owner replacement and disk failures. Existing slot/payload/migration tests remain.
Native SubViewport injection and source-art captures are component evidence;
ordinary OS-focus/physical input, the inherited monthly focus HOLD, current
package and all 36 screen/flow acceptance groups remain open. No package or
full asset duplication is part of this lane.

The current native capture harness has an additional unresolved render-stability
boundary: an expansion AUTO capture was partial; a diagnostic obtained a complete
ordinary frame, but forced and subsequent captures were black with unchanged
555×451 source-frame/texture geometry and six rows. These artifacts are retained;
no speculative production rendering change was made. A good individual capture
is not evidence that this boundary is stable. This is separate from the inherited
monthly focus HOLD.
