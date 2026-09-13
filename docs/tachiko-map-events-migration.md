# Tachiko SCD M5 — static map event-kind mirror

Issue: #184 (parent #168)

M5 is a consumer-local **Mirror → Verify preparation/qualification seed**. It
mirrors only the static `EVENT_NAMES` dictionary in
`game/content/original_maps.gd`; it does not switch the Richman4 runtime source
of truth or authorize gameplay work.

## Frozen source and projection

The selection-time source is pinned by its Git blob:

`game/content/original_maps.gd` =
`a27ac49aba28548c5d40800b6332af00da1dec7f`

The source contains exactly 17 entries, with keys `0..16`. The consumer
projection has one root field, `event_names`, containing exactly 17 records.
Each record has exactly these fields:

```json
{"event_code": 0, "display_name": "道路"}
```

`event_code` is an exact integer in `0..16` and is the stable semantic identity
input. `display_name` is non-empty Text and is a mutable label, never an
identity. The frozen values are in `tests/tachiko_map_events_mirror/oracle.json`.
Duplicate labels are valid (codes `0` and `1` are both `道路`). Input row
order is presentation/storage detail: valid reordered input normalizes by
`event_code` to the same projection and identity map. The source witness also
requires the pinned source-key order.

## Boundary and exclusions

The preparation seed is limited to these new paths:

- `docs/tachiko-map-events-migration.md`;
- `tests/tachiko_map_events_mirror/**`.

`game/content/original_maps.gd` is read-only source authority. M5 does not
mirror, infer, edit or publish map geometry, routes, tiles, coordinates, graph
topology, facilities, companies, stocks, event/news/fate execution, lottery or
minigame behavior, landing resolution, player/save/RNG/AI/economy/payment state,
or any UI/native flow. It does not touch `game/core/**`, `game/ui/**`, private or
FULL assets, Tachiko Core/API/plugin/Sheet, Hot Reload, or runtime cutover.
Runtime/gameplay fields such as `status_bits`, `type_and_idx`, `visual_index`,
`owner` and `cost` are explicitly rejected by the seed checker.

## Ready qualification

From the repository root, run the independent checker and static source parser:

```sh
uv run --no-project --offline python tests/tachiko_map_events_mirror/check_map_events.py \
  --self-test --source game/content/original_maps.gd
```

Then run the real headless Godot witness, which preloads the source and reads
only `EVENT_NAMES` (it does not instantiate a game scene or invoke map/runtime
helpers):

```sh
E=$(mktemp -d "${TMPDIR:-/tmp}/richman4-tachiko-m5.XXXXXX")
godot_rc=0
"${GODOT_BIN:-godot}" --headless --path "$PWD" \
  --script tests/tachiko_map_events_mirror/source_oracle.gd >"$E/godot.log" 2>&1 \
  || godot_rc=$?
uv run --no-project --offline python tests/tachiko_map_events_mirror/check_map_events.py \
  --source game/content/original_maps.gd --godot-log "$E/godot.log"
test "$godot_rc" -eq 0
```

Ready requires the source blob, committed oracle, parser, and independent
Godot projection to agree; all checker self-tests and frozen negative cases to
pass; and no overlapping writer. Missing adapter/Tachiko admission before
implementation is `PRECONDITION_UNMET`, not behavioral RED. Do not create
`tools/tachiko_map_events_mirror/**` until this exact seed is Ready-qualified.

## Frozen acceptance cases

The checker rejects missing/extra fields, wrong field types, empty labels,
duplicate/gapped/out-of-range/fractional/unsafe codes, duplicate JSON keys,
malformed JSON, non-finite numbers, oversized input, and runtime/gameplay
leakage. It normalizes valid reorderings and compares complete document,
schema, field and row identities. The sole semantic edit is isolated to code
`16`: `魔法屋` → `魔法屋（M5驗證）`; the code-derived identity must remain
unchanged and every other row must remain byte-equivalent in the candidate
projection.

## Post-Ready implementation and completion

After Ready, implementation may add only a bounded consumer-local adapter/runner
under `tools/tachiko_map_events_mirror/**`. It must use the already-proven real
Tachiko typed Rust/storage path; no new Core/API/wire format is defined. M5 is
not complete until one exact candidate head proves Godot witness → typed Rust
admission → `.ro` materialization → `.roproj` validate/export/reopen, repeat
determinism, stable identities across imports/reorder/reopen, all frozen
negative/no-partial-output and collision-preservation cases, and the isolated
edit. Exact-head hosted Verify, fresh independent final review, Steward
acceptance and merge remain required. Passing this preparation seed alone is
not M5 PASS and does not authorize runtime cutover.
