# Richman4 → Tachiko M2：靜態角色 catalog

Authority: #168 / #172。此文件只定義第二個 Mirror → Verify 資料域；不是 runtime cutover、#1 Mission、#165/#167 或 S21 驗收。

## SCD boundary

本 slice 只處理原作 12 個可選角色的**穩定 legacy character ID 與顯示姓名**。

| Source | Exact identity |
| --- | --- |
| Richman4 baseline | `d2d58689937599de07a7d1a83138a32260203a84` |
| `game/core/game_state.gd` | Git blob `dd03614fd8bf5cef7a32bcbbb29c579d4af1a05e` |
| `docs/calendar-and-setup.md` | Git blob `0f8aa4666aefec90aed8caefeca591e86b742b46` |
| Tachiko capability baseline | reuse validated M1 pin `6900e975112576585fd9360f12d9fcf8b36ba466` unless Steward records a newer compatible pin |

`docs/calendar-and-setup.md` records the two owner executables' 12×104-byte character table: record `+19` is character ID `0..11`, with the same 12 decoded names. Runtime exposes the names through `SETUP_CHARACTER_NAMES` and count 12.

The source research also records `init_cash_ratio`; `game_state.gd` additionally contains initial funds, day limits, wealth multipliers, start date and other setup/runtime constants. **They are intentionally excluded from M2.**

## Canonical M2 projection

Normalized consumer projection contains exactly `characters[]`, each record exactly:

```json
{"legacy_id": 0, "display_name": "約翰喬"}
```

Field contract:
- `legacy_id`: Number, exact integer `0..11`; stable import identity input.
- `display_name`: Text, non-empty mutable label; never semantic identity.

Opaque Tachiko entity identity must deterministically bootstrap from stable legacy character ID and survive `display_name` edits/reopen/export. Do not derive identity from row position, display name, UI coordinate or storage path.

## Hard exclusions

M2 must not mirror, infer, edit or publish `AI_CASH_RATIOS` / `init_cash_ratio`, `SETUP_INITIAL_FUNDS`, `SETUP_DAY_LIMITS`, `SETUP_WEALTH_MULTIPLIERS`, `SETUP_DEFAULT_START_DATE`, human/AI role, current player state, cash/deposit, save/RNG state, portraits/assets or MainUI setup behavior.

An extra normalized field such as `init_cash_ratio` is an acceptance failure even though source research knows the value.

## Steward acceptance seed

`tests/tachiko_character_mirror/oracle.json` freezes 12 IDs/names and both source blobs. `check_characters.py` is strict read-only acceptance logic; it does not create Tachiko projects or prove Rust provenance. `source_oracle.gd` is read-only and outputs only the allowed static catalog.

Preparation:

```sh
uv run --no-project --offline python tests/tachiko_character_mirror/check_characters.py \
  --self-test \
  --runtime-source game/core/game_state.gd \
  --research-source docs/calendar-and-setup.md
```

Godot witness:

```sh
evidence=$(mktemp -d "${TMPDIR:-/tmp}/richman4-tachiko-character.XXXXXX")
godot --headless --path "$PWD" \
  --script tests/tachiko_character_mirror/source_oracle.gd > "$evidence/godot.log" 2>&1
uv run --no-project --offline python tests/tachiko_character_mirror/check_characters.py \
  --godot-log "$evidence/godot.log"
```

## Production acceptance after Ready

Implementation remains consumer-local. Prefer separate bounded `tools/tachiko_character_mirror/` adapter/runner; do not refactor the accepted cards/tools adapter merely to share code unless correctness requires it.

Final exact-head evidence must prove:

1. exact pinned source/research blobs + successful headless Godot projection;
2. 12 records through actual typed Rust validation/storage and real `.roproj` materialize/validate/export/reopen on a recorded clean Tachiko revision;
3. exact no-op parity and byte-identical two independent fresh normalized projections;
4. stable opaque identities across two imports and save/reopen, bootstrapped from legacy ID rather than name/row position;
5. isolated semantic edit only for character 0 `display_name`: `約翰喬` → `約翰喬（M2驗證）`; identity and all other records unchanged;
6. real candidate rejection for missing/duplicate/out-of-range legacy ID, wrong ID/name type, empty name, unknown field and gameplay leakage, with no silent drop/coerce/valid partial output;
7. valid candidate cannot overwrite existing direct `.ro` or `.roproj`; source/destination hashes remain unchanged;
8. no Richman4 runtime/core/MainUI/save/AI/payment/#165/#167/private assets/FULL/default-loader or Tachiko Core/API/plugin diff;
9. applicable exact-head local tests, hosted Verify and fresh independent final review are green before Steward merge acceptance.

## Acceptance-first applicability decision

No M2 adapter exists before implementation, so missing adapter/binary is PRECONDITION_UNMET rather than behavioral RED. This Steward seed freezes independent source/oracle/negative outcomes before Ready; after Ready the delivery agent must bind these same cases to the real candidate adapter and prove fail-closed/preservation before merge.

Godot witness and actual Tachiko roundtrip remain final acceptance evidence. Seed/checker PASS alone is never M2 PASS.

## Endpoint

M2 completion proves only that the 12-character static ID/name catalog can be managed through existing Tachiko capabilities. It does not authorize runtime cutover or expansion into AI/setup semantics. After merge SCD recalibrates before selecting M3/cutover work.
