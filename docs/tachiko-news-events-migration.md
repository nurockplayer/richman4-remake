# Tachiko SCD M6 — static common-news name mirror

Issue: #186 (parent #168)

M6 is a consumer-local **Mirror → Verify preparation/qualification seed**. It
mirrors only the static `COUNT` constant and `_NAMES` table in
`game/core/news_events.gd`; it does not switch the Richman4 runtime source of
truth or authorize gameplay work.

## Frozen source and projection

The selection-time source is pinned by its Git blob:

`game/core/news_events.gd` =
`d452a6b8f82668e7c4d0e8c732ca3e099bc31c90`

The source declares `COUNT := 36` and a `_NAMES` table. The projection is derived
from those two constants only. It has one root field, `news_names`, containing
exactly 36 records. Each record has exactly these fields:

```json
{"news_id": 0, "display_name": "監獄釋放"}
```

`news_id` is the exact integer `0..35` and is the stable semantic identity
input. `display_name` is non-empty Text and is a mutable label, never an
identity. The source is read-only authority: the seed never edits it. The frozen
values are in `tests/tachiko_news_events_mirror/oracle.json`. Duplicate labels
are valid (ids `5` and `19` are both `土地查封`; ids `30` and `33` are both
`企業虧損`). Input row order is presentation/storage detail: valid reordered
input normalizes by `news_id` to the same projection and identity map. The
source witness also requires the pinned source-table order and that `COUNT`
agrees with the `_NAMES` length.

## Boundary and exclusions

The preparation seed is limited to these new paths:

- `docs/tachiko-news-events-migration.md`;
- `tests/tachiko_news_events_mirror/**`.

M6 does not mirror, infer, edit or publish the news deck order, cursor, draw
count, last-result payload, draw/sampling algorithm, eligibility or target
selection, effect plans, money/asset/stock/company mutations, unsupported-id
handling (`UNSUPPORTED_IDS`), or any player/save/RNG/AI/economy/payment/native
flow. It does not touch any other `game/core/**` file, `game/ui/**`, private or
FULL assets, Tachiko Core/API/plugin/Sheet, Hot Reload, or runtime cutover.
Runtime/adapter fields derived from the same module — such as `adapter_status`,
`id`, `name`, `unsupported`, `order`, `cursor`, `draw_count`, `last`, `targets`,
`changes` and `summary` — are explicitly rejected by the seed checker.

## Ready qualification

From the repository root, run the independent checker and static source parser:

```sh
uv run --no-project --offline python tests/tachiko_news_events_mirror/check_news_events.py \
  --self-test --source game/core/news_events.gd
```

Where `~/.cache/uv` is not writable, prefix both `uv` commands with
`UV_CACHE_DIR=$(mktemp -d)`.

Then run the real headless Godot witness, which preloads the source and reads
only `COUNT` and `_NAMES` (it does not instantiate a game scene or invoke
news/selection/effect helpers). The isolated `HOME` keeps Godot's user data in a
writable scratch directory:

```sh
E=$(mktemp -d "${TMPDIR:-/tmp}/richman4-tachiko-m6.XXXXXX")
mkdir -p "$E/home"
godot_rc=0
HOME="$E/home" "${GODOT_BIN:-godot}" --headless --path "$PWD" \
  --script tests/tachiko_news_events_mirror/source_oracle.gd >"$E/godot.log" 2>&1 \
  || godot_rc=$?
uv run --no-project --offline python tests/tachiko_news_events_mirror/check_news_events.py \
  --source game/core/news_events.gd --godot-log "$E/godot.log"
test "$godot_rc" -eq 0
```

The witness log must contain exactly one oracle marker and no `SCRIPT ERROR` or
`ERROR` line.

Ready requires the source blob, committed oracle, parser, and independent Godot
projection to agree; all checker self-tests and frozen negative cases to pass;
and no overlapping writer. Missing adapter/Tachiko admission before
implementation is `PRECONDITION_UNMET`, not behavioral RED. Do not create
`tools/tachiko_news_events_mirror/**` until this exact seed is Ready-qualified.

## Frozen acceptance cases

The checker rejects missing/extra fields, wrong field types, empty labels,
duplicate/gapped/out-of-range/fractional/unsafe ids, duplicate JSON keys,
malformed JSON, non-finite numbers, oversized input, and runtime/adapter leakage.
It normalizes valid reorderings and compares complete document, schema, field and
row identities. The sole semantic edit is isolated to id `35`: `企業翻倍` →
`企業翻倍（M6驗證）`; the id-derived identity must remain unchanged and every
other row must remain byte-equivalent in the candidate projection.

## Post-Ready implementation and completion

After Ready, implementation may add only a bounded consumer-local adapter/runner
under `tools/tachiko_news_events_mirror/**`. It must use the already-proven real
Tachiko typed Rust/storage path; no new Core/API/wire format is defined. M6 is
not complete until one exact candidate head proves Godot witness → typed Rust
admission → `.ro` materialization → `.roproj` validate/export/reopen, repeat
determinism, stable identities across imports/reorder/reopen, all frozen
negative/no-partial-output and collision-preservation cases, and the isolated
edit. Exact-head hosted Verify, fresh independent final review, Steward
acceptance and merge remain required. Passing this preparation seed alone is
not M6 PASS and does not authorize runtime cutover.

Completion evidence is produced by the post-Ready runner against a real Tachiko
source checkout:

```sh
TACHIKO_SOURCE=/path/to/tachiko-work bash tools/tachiko_news_events_mirror/run_m6.sh
```

The runner must snapshot the exact candidate HEAD, then drive the checker with
its full surface (`--self-test`, `--source`, `--godot-log`, `--projection`,
`--edited-projection`, repeated `--identity-map`, and `--candidate-adapter` /
`--tachiko-cli`) and fail on any partial output, mutation of its input, or
identity drift.
