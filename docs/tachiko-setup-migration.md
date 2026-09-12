# M3: static setup-option Mirror → Verify

Owner: #176 under #168. This is a Steward-owned **acceptance seed**, not an importer,
production Ready decision, successful Godot/Rust run, or runtime cutover.
Read live #1, #52, AGENTS.md and #176 before pickup. Do not restart M2 or #165/#167.

## Fixed source and meaning

Prepared base: `2adbbfbba1efab0375f03fb9686e8b5684207c25`.

| Input | Exact Git blob |
| --- | --- |
| `game/ui/main_ui.gd` | `18b69b0ffe167085329f3363b958b0b561e70902` |
| `docs/calendar-and-setup.md` | `0f8aa4666aefec90aed8caefeca591e86b742b46` |

The existing research records equal little-endian u32 tables in Game and
MultiverseJourney. M3 consumes that frozen research; it does not rerun reverse
engineering or retrieve the private executables. The witness reads compiled MainUI
constants without constructing MainUI, running `_ready`, opening a native window or
starting a game. Dependencies must compile in a THIN checkout; missing dependencies
are preconditions, not permission to substitute a hard-coded witness.

The full source-blob pin check and runtime witness are separate evidence. The source
reader is bounded at 2 MiB; JSON/log/research evidence is bounded at 128 KiB. A larger
source file must not accidentally inherit the small evidence-reader bound (M2 lesson).

| kind | legacy_index 0 → 5 values |
| --- | --- |
| `initial_fund` | 300000, 200000, 100000, 50000, 30000, 10000 |
| `day_limit` | 0, 730, 365, 182, 91, 30 |
| `wealth_multiplier` | 0, 100, 50, 10, 5, 3 |

The only projection root is `setup_options`, containing exactly 18 records with
`kind`, `legacy_index`, `value`. Canonical output order is the table order above,
then legacy index; incoming record order and Tachiko storage order are not identity.
`kind` is ordinary Tachiko Text with a **consumer-only** closed domain, not a new
Core Enum. Index is integral Number 0..5. Values are nonnegative exact integers at
most `9007199254740991`. Integral JSON Number spellings such as `300000.0` are valid;
Text, Boolean, fractions, non-finite and lossy tokens reject before binary64 conversion.
The JSON spelling `9007199254740993.0` and sub-binary64 fractional tokens must not round
into accepted values. This is a bounded consumer fidelity rule, not a Core Number change.

Opaque identity bootstraps from `kind + legacy_index`, not numeric value, label,
position or path. Pin the imported document/schema/field identities as well as row
identities. The sole demonstration edit is `day_limit / 5: 30 → 31` in an isolated
candidate; this neither changes the original source nor endorses a 31-day game rule.

**Excluded:** AI cash ratios, human/AI cash/deposit allocation, defaults/date,
player/save/RNG state, maps, characters/assets, MainUI behavior, gameplay/economics,
Tachiko Core/API/plugin/Sheet, Hot Reload, package/export of the game and cutover.
Do not change accepted M1/M2 files, global CI/toolchain, runtime or private/FULL assets.

## Pickup: qualification before production

Use this exact prepared branch in one THIN lane; the issue records its commit.
No second implementation branch/PR or acceptance-only merge. Preserve the four seed
files and their independent expectations. Before mutation verify live base/source
pins and absence of another M3 writer. A moved main needs explicit reconciliation;
never force-push or change source pins just to make a test green.

Run from the repository root (not inside another active writer's checkout):

```sh
uv run --no-project --offline python tests/tachiko_setup_mirror/check_setup.py \
  --self-test --runtime-source game/ui/main_ui.gd \
  --research-source docs/calendar-and-setup.md

E=$(mktemp -d "${TMPDIR:-/tmp}/richman4-tachiko-m3.XXXXXX")
godot_rc=0
"${GODOT_BIN:-godot}" --headless --path "$PWD" \
  --script tests/tachiko_setup_mirror/source_oracle.gd >"$E/godot.log" 2>&1 || godot_rc=$?
uv run --no-project --offline python tests/tachiko_setup_mirror/check_setup.py \
  --godot-log "$E/godot.log" --godot-exit-code "$godot_rc"
```

Use a **clean immutable** Tachiko checkout at the M1/M2-proven
`6900e975112576585fd9360f12d9fcf8b36ba466`. Admit real linked worktrees through
`git -C "$TACHIKO_SOURCE" rev-parse --git-dir`, compare HEAD to that SHA, and require
empty `git status --porcelain`. Record the actual source/build/toolchain. Do not assume
`.git` is a directory. M3 pins immutable source, not the moving `origin/main`; do not
reset a user's branch or remote-tracking ref to manufacture eligibility. A different
producer SHA requires explicit qualification, not reuse of the old evidence.

The current preparation environment has no Godot/Cargo, and clone failed DNS.
Connector source inspection and Python self-tests do **not** substitute for those
runs. Record the real source/witness/Tachiko preflight in #176; production remains
REFINE until the live Steward readiness decision is satisfied.

## Executable acceptance map

| Requirement | Seed / final binding |
| --- | --- |
| 18 records, exact source values, zero preservation | `oracle.json`, source pins, Godot witness, `--projection` |
| Independent deterministic outputs | Two fresh imports → two materializations → exports; `--projection A --repeat B` checks both parsed values and identical bytes |
| Isolated 30 → 31 edit | Existing typed Rust edit/diff; `--edited-projection` checks the complete expected result |
| Identity survives real storage | `--identity-maps` compares six complete maps; provenance requirements below |
| Wrong/missing/duplicate/leaking/lossy input | `negative_cases()` freezes 28 invalid candidates; `--adapter` invokes the real adapter on every case |
| No partial output / source mutation / collision overwrite | Real candidate positive control, real Rust admission/materialization, then negative/collision assertions in `--adapter` |
| No gameplay/upstream change | Exact base-to-head diff, focused affected gates and independent final review |

After Ready, implement only a consumer-local adapter/runner, preferably under
`tools/tachiko_setup_mirror/`, using existing typed Rust/storage/CLI capabilities.
The test-only process convention is `ADAPTER candidate INPUT.json ABSENT_OUTPUT.ro`:
exit 0 means success; exit 1 means deliberate candidate/destination rejection;
missing executable/setup/compile/crash is never counted as a rejection PASS.
No new public SDK/wire/format is defined. Caller-selected paths are local scratch.

```sh
uv run --no-project --offline python tests/tachiko_setup_mirror/check_setup.py \
  --adapter "$ADAPTER" --tachiko-cli "$CLI"
uv run --no-project --offline python tests/tachiko_setup_mirror/check_setup.py \
  --projection "$E/roundtrip-1.json" --repeat "$E/roundtrip-2.json" \
  --edited-projection "$E/edited.json" \
  --identity-maps "$E/base-import-ids.json" "$E/repeat-import-ids.json" \
  "$E/base-persisted-ids.json" "$E/repeat-persisted-ids.json" \
  "$E/edited-persisted-ids.json" "$E/reopened-persisted-ids.json"
```

The candidate-boundary runner establishes native admission, 28 negative candidates,
and both `.ro` / `.roproj` no-overwrite cases. It does not establish the complete
roundtrip/edit/diff/identity journey. Its temporary outputs are not retained artifacts;
the final M3 runner must separately retain exact-head evidence, hashes and provenance.
A static checker PASS is not a generic Rust validation or product claim.

## Identity and final evidence: carry forward the M2 repair

An evidence map is an object with `document_id`, `schema_id`, `field_ids` (exact keys
`kind`, `legacy_index`, `value`) and `rows` (18 objects with `kind`, `legacy_index`,
`entity_id`). IDs are nonempty opaque strings; rows and fields have distinct IDs.
It is consumer test evidence, not a new canonical storage representation.

Generate both import maps independently. Generate each persisted map by **loading
its actual `.roproj` through existing storage**, never re-running ID generation from
legacy keys. Require base-import == base-persisted, repeat-import == repeat-persisted,
base-persisted == repeat-persisted == edited-persisted == freshly-reopened-persisted.
Prove a reordered input keeps key-to-ID mapping. Independent review must inspect the
storage path; six copies of an invented JSON map are not proof.

Use the existing real CLI to validate/materialize/export each independent candidate
and the edited project. Inspect actual semantic diff to require **exactly one changed
value**, not merely grep for the expected line while overlooking additional changes.
Preserve original source/oracle, both original materializations and their hashes.
No unobserved native/UI/gameplay, cross-platform or runtime-cutover claim follows.

Final evidence: exact source/Tachiko/PR HEADs; actual commands/results and tool versions;
retained project/projection/identity hashes; applicable implementer unit tests and
hosted Verify; fresh independent exact-final-head review with blocking debt resolved.
Use one writer and one eventual PR. Stop after M3 closeout; another domain needs SCD
recalibration. Never weaken a gate to save tokens or label unavailable tooling RED.
