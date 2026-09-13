# Tachiko SCD M4 — static god-definition mirror

Issue: #178

M4 is a **consumer-local qualification milestone**, not a gameplay migration. It mirrors only the 15 static rows in `game/content/original_gods.gd::GOD_ROWS` through the already-proven Tachiko `.ro` → `.roproj` path.

## Frozen projection

| Source | M4 field | Meaning |
| --- | --- | --- |
| dictionary key | `legacy_id` | stable source identity (`1..15`) |
| `name` | `display_name` | source display text |
| `pair` | `pair_legacy_id` | typed reference to another god row, or `0` |
| `days` | `duration_days` | source duration scalar |
| `role` | `role_key` | source role key as data |

Selection-time source blob:

`game/content/original_gods.gd` = `77fff4152210fae9f33d991e6653372398996948`

The acceptance oracle freezes the current source values. Row order is presentation only; `legacy_id` is identity. Non-zero pair references must target another row and remain reciprocal.

## What M4 does not own

M4 must not mirror, execute or modify:

- `INITIAL_IDS`;
- `valid_id`, `definition`, `name_for`, `pair_for`, `days_for`, `role_for`;
- `initial_ids`, `is_attachable`, `is_spawnable`;
- tile eligibility or spawn candidates;
- god effects, acquisition/lifecycle logic, current game state, save/RNG/AI/economy;
- any `game/core/**` or `game/ui/**` behavior;
- Hot Reload, a runtime read switch, or source-of-truth transfer;
- Tachiko Core/API/plugin/Sheet.

The Godot witness therefore preloads the source and reads **only `GOD_ROWS`**.

## Steward acceptance seed

The Steward-owned files are:

- `tests/tachiko_gods_mirror/oracle.json`
- `tests/tachiko_gods_mirror/check_gods.py`
- `tests/tachiko_gods_mirror/source_oracle.gd`

The checker freezes strict JSON typing, exact field sets, IDs `1..15`, relational pair integrity, source pinning, Godot witness parsing, reordered-input normalization, identity-map comparison, a negative corpus, `.ro`/`.roproj` collision expectations, and the one allowed semantic edit (`display_name` of god `1`).

Local seed checks:

```sh
python3 tests/tachiko_gods_mirror/check_gods.py --self-test
godot --headless --path . --script tests/tachiko_gods_mirror/source_oracle.gd > /tmp/m4-gods.log
python3 tests/tachiko_gods_mirror/check_gods.py \
  --source game/content/original_gods.gd \
  --godot-log /tmp/m4-gods.log
```

Absence of the future M4 adapter or Tachiko CLI is a **precondition**, not behavioral RED.

## Implementation budget

After the Steward marks #178 Ready, implementation may add only:

- `tools/tachiko_gods_mirror/adapter.rs`
- `tools/tachiko_gods_mirror/run_m4.sh`

unless a fresh reconciliation explicitly changes that writer budget.

The implementation must use the real Tachiko Rust codec/CLI path already proven by M1–M3; no substitute serialization format is acceptable.

## Completion evidence

M4 is complete only after the exact candidate head proves:

1. Godot witness → Rust adapter → valid `.ro`;
2. real Rust admission and `.roproj` materialize/validate/export/reopen;
3. deterministic repeat/no-op behavior;
4. stable document/schema/field/entity identity across import/materialize/reopen and reordered input;
5. exact typed values and pair references;
6. frozen negative rejection with no partial output;
7. unchanged `.ro` and `.roproj` destinations on collision;
8. an isolated `小財神` → `小財神（M4驗證）` edit changes only that field value and preserves row identity;
9. exact-head hosted Verify success;
10. fresh independent review with `No blocking findings.`;
11. Steward final acceptance and merge.

Passing M4 still does **not** authorize runtime cutover.
