# Tachiko SCD M7 — static fate-event-name mirror

Issue: #188 (parent #168).

M7 is a consumer-local **Mirror → Verify preparation/qualification seed**. It
mirrors only the static fate display-name catalog. It does not change the
Richman4 runtime source of truth and does not authorize gameplay work.

## Frozen source and projection

The selection-time source authority is read-only and pinned by its Git blob:

`game/core/fate_events.gd` =
`c04741a32b41df601dc20147f143a3507a83fb17`

The only source values admitted by M7 are `COUNT == 37` and `_NAMES`, with one
label for each fate ID `0..36`. The projection has one root field,
`fate_names`, containing exactly 37 records. Every record has exactly these
fields:

```json
{"fate_id": 0, "display_name": "拆除房屋"}
```

`fate_id` is an exact integer and the stable semantic identity input.
`display_name` is bounded non-empty Text and is a mutable label, never an
identity. Input order is presentation/storage detail: valid reordered input
normalizes by `fate_id` to the same projection and identity map. Duplicate
labels are valid. The immutable values are in
`tests/tachiko_fate_events_mirror/oracle.json`.

## Read-only boundary and exclusions

Preparation may add only these paths:

- `docs/tachiko-fate-events-migration.md`;
- `tests/tachiko_fate_events_mirror/**`.

`game/core/fate_events.gd` is read-only source authority. M7 does not mirror,
infer, modify, or depend on `COMMON_COUNT`, `UNSUPPORTED_IDS`,
`MAP_PRISON_DAYS`, income/expense tables, `LAST_KEYS`, adapter support status,
deck order/state, RNG, target eligibility, effects, amounts, map-slot
semantics, resolver output, save state, economy, player/property/company
mutations, prison/hospital execution, or gameplay execution. Runtime/gameplay
leakage fields are rejected by the checker. It does not touch `game/core/**`,
`game/ui/**`, private/FULL assets, Tachiko Core/API/plugin/Sheet, Hot Reload,
runtime source-of-truth, or cutover.

After the exact seed is Ready-qualified, the only implementation writer path is
`tools/tachiko_fate_events_mirror/**`. Any need to edit existing Richman4
source/runtime/gameplay files is a stop-and-reconcile event. No adapter or
tool is created by this preparation seed.

## Ready qualification commands

From the repository root, run the independent strict parser/self-test and
pinned source check:

```sh
uv run --no-project --offline python tests/tachiko_fate_events_mirror/check_fate_events.py \
  --self-test --source game/core/fate_events.gd
```

Then run the real headless Godot witness. It preloads the source and reads only
`COUNT` and `_NAMES`; it does not instantiate a game scene or invoke a catalog,
resolver, state, RNG, eligibility, or gameplay helper.

```sh
E=$(mktemp -d "${TMPDIR:-/tmp}/richman4-tachiko-m7.XXXXXX")
godot_rc=0
"${GODOT_BIN:-godot}" --headless --path "$PWD" \
  --script tests/tachiko_fate_events_mirror/source_oracle.gd >"$E/godot.log" 2>&1 \
  || godot_rc=$?
uv run --no-project --offline python tests/tachiko_fate_events_mirror/check_fate_events.py \
  --source game/core/fate_events.gd --godot-log "$E/godot.log"
test "$godot_rc" -eq 0
```

Ready requires the pinned source blob, committed oracle, independent source
parser, and independent Godot projection to agree; all checker self-tests and
frozen negative cases to pass; and no overlapping writer. The checker is
strictly fail-closed. Missing adapter/Tachiko admission before implementation
is `PRECONDITION_UNMET` (exit status 2), not behavioral RED and not evidence
that the seed failed.

## Frozen acceptance cases

The checker rejects root/row missing or extra fields, wrong JSON types, empty or
oversized labels, duplicate/gapped/out-of-range/fractional/unsafe IDs,
duplicate JSON keys, malformed JSON, non-finite numbers, oversized input, and
runtime/gameplay leakage. Explicitly rejected leakage includes support, effect,
state, amount, map-slot, deck, RNG, eligibility, resolver, target, outcome,
changes, cursor and draw-state fields. Valid reorderings normalize to the
same semantic catalog and identity map.

The sole semantic edit is isolated to `fate_id 36`:
`違規入獄` → `違規入獄（M7驗證）`. The ID-derived identity remains unchanged and
every other row remains byte-equivalent in the candidate projection.

Preparation passing is not M7 PASS and does not authorize runtime cutover.
Completion still requires the post-Ready typed Rust/Tachiko path, `.ro` and
`.roproj` validation/materialization/export/reopen, deterministic repeat and
identity evidence, frozen no-partial-output/collision checks, exact-head hosted
Verify, fresh independent review, Steward acceptance, and merge.
