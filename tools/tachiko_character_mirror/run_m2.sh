#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TACHIKO_SOURCE=${TACHIKO_SOURCE:-}
TACHIKO_SHA=6900e975112576585fd9360f12d9fcf8b36ba466
[[ -n "$TACHIKO_SOURCE" && -d "$TACHIKO_SOURCE/.git" ]] || { echo "PRECONDITION_UNMET: TACHIKO_SOURCE must be a clean checkout" >&2; exit 2; }
[[ "$(git -C "$TACHIKO_SOURCE" rev-parse HEAD)" == "$TACHIKO_SHA" ]] || { echo "PRECONDITION_UNMET: TACHIKO_SOURCE must be $TACHIKO_SHA" >&2; exit 2; }
[[ "$(git -C "$TACHIKO_SOURCE" rev-parse refs/remotes/origin/main 2>/dev/null || true)" == "$TACHIKO_SHA" ]] || { echo "PRECONDITION_UNMET: TACHIKO_SOURCE origin/main must be $TACHIKO_SHA" >&2; exit 2; }
[[ -z "$(git -C "$TACHIKO_SOURCE" status --porcelain)" ]] || { echo "PRECONDITION_UNMET: TACHIKO_SOURCE is dirty" >&2; exit 2; }

GODOT_BIN=${GODOT_BIN:-godot}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/richman4-tachiko-character.XXXXXX")
cleanup() { [[ -n "${KEEP_EVIDENCE:-}" ]] || rm -rf "$WORK"; }
trap cleanup EXIT
echo "TACHIKO_SHA=$TACHIKO_SHA"
echo "TACHIKO_SOURCE=$TACHIKO_SOURCE"
echo "WORK=$WORK"

uv run --no-project --offline python "$ROOT/tests/tachiko_character_mirror/check_characters.py" --self-test --runtime-source "$ROOT/game/core/game_state.gd" --research-source "$ROOT/docs/calendar-and-setup.md"
"$GODOT_BIN" --headless --path "$ROOT" --script tests/tachiko_character_mirror/source_oracle.gd >"$WORK/godot.log" 2>&1
uv run --no-project --offline python "$ROOT/tests/tachiko_character_mirror/check_characters.py" --godot-log "$WORK/godot.log"

mkdir -p "$WORK/adapter-src/src"
cp "$ROOT/tools/tachiko_character_mirror/adapter.rs" "$WORK/adapter-src/src/main.rs"
cat >"$WORK/adapter-src/Cargo.toml" <<EOF
[package]
name = "richman4-tachiko-character-mirror"
version = "0.1.0"
edition = "2024"
[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
tachiko-storage = { path = "$TACHIKO_SOURCE/crates/storage" }
tachiko-workspace-engine = { path = "$TACHIKO_SOURCE/crates/workspace-engine" }
EOF
cargo build --manifest-path "$TACHIKO_SOURCE/Cargo.toml" -p tachiko-cli --offline --quiet
cargo build --manifest-path "$WORK/adapter-src/Cargo.toml" --offline --quiet
CLI="$TACHIKO_SOURCE/target/debug/tachiko"
ADAPTER="$WORK/adapter-src/target/debug/richman4-tachiko-character-mirror"
sed -n 's/^RICHMAN4_CHARACTER_ORACLE=//p' "$WORK/godot.log" >"$WORK/candidate.json"

"$ADAPTER" import-log "$WORK/godot.log" "$WORK/base.ro" "$WORK/base-ids.json"
"$CLI" validate "$WORK/base.ro"
"$CLI" roproj materialize "$WORK/base.ro" "$WORK/base.roproj"
"$CLI" roproj validate "$WORK/base.roproj"
"$CLI" export "$WORK/base.roproj" "$WORK/base-runtime.json"
"$ADAPTER" normalize "$WORK/base-runtime.json" "$WORK/roundtrip-1.json"
"$ADAPTER" import-log "$WORK/godot.log" "$WORK/repeat.ro" "$WORK/repeat-ids.json"
"$CLI" roproj materialize "$WORK/repeat.ro" "$WORK/repeat.roproj"
"$CLI" roproj validate "$WORK/repeat.roproj"
"$CLI" export "$WORK/repeat.roproj" "$WORK/repeat-runtime.json"
"$ADAPTER" normalize "$WORK/repeat-runtime.json" "$WORK/roundtrip-2.json"
cmp "$WORK/roundtrip-1.json" "$WORK/roundtrip-2.json"
cmp "$WORK/base-ids.json" "$WORK/repeat-ids.json"

"$CLI" set "$WORK/base.roproj" character_00.display_name '約翰喬（M2驗證）' --output "$WORK/edited.ro"
"$CLI" validate "$WORK/edited.ro"
"$CLI" roproj materialize "$WORK/edited.ro" "$WORK/edited.roproj"
"$CLI" roproj validate "$WORK/edited.roproj"
"$CLI" diff "$WORK/base.roproj" "$WORK/edited.roproj" >"$WORK/semantic-diff.txt"
"$CLI" export "$WORK/edited.roproj" "$WORK/edited-runtime.json"
"$ADAPTER" normalize "$WORK/edited-runtime.json" "$WORK/edited.json"
"$ADAPTER" identity "$WORK/base.roproj" "$WORK/base-roproj-ids.json"
"$ADAPTER" identity "$WORK/edited.roproj" "$WORK/edited-roproj-ids.json"
cmp "$WORK/base-roproj-ids.json" "$WORK/edited-roproj-ids.json"
uv run --no-project --offline python "$ROOT/tests/tachiko_character_mirror/check_characters.py" --projection "$WORK/roundtrip-1.json" --repeat "$WORK/roundtrip-2.json" --edited-projection "$WORK/edited.json"
grep -q 'display_name: "約翰喬" -> "約翰喬（M2驗證）"' "$WORK/semantic-diff.txt"

source_hash=$(shasum -a 256 "$ROOT/game/core/game_state.gd" | cut -d' ' -f1)
existing_ro_hash=$(shasum -a 256 "$WORK/base.ro" | cut -d' ' -f1)
destination_hash=$(find "$WORK/base.roproj" -type f -print | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256 | cut -d' ' -f1)
if "$CLI" roproj materialize "$WORK/base.ro" "$WORK/base.roproj" >"$WORK/existing-roproj-collision.log" 2>&1; then echo "FAIL: existing .roproj destination unexpectedly overwritten" >&2; exit 1; fi
grep -E -q 'already exists|refusing to overwrite' "$WORK/existing-roproj-collision.log"
for kind in duplicate-key missing-identity duplicate-id out-of-range wrong-id-type wrong-name-type empty-name unknown-field gameplay-leak; do
  "$ADAPTER" mutant "$WORK/candidate.json" "$WORK/$kind.json" "$kind"
  if "$ADAPTER" candidate "$WORK/$kind.json" "$WORK/$kind.ro"; then echo "FAIL: invalid candidate unexpectedly accepted: $kind" >&2; exit 1; fi
  [[ ! -e "$WORK/$kind.ro" ]] || { echo "FAIL: invalid candidate left output: $kind" >&2; exit 1; }
done
if "$ADAPTER" candidate "$WORK/candidate.json" "$WORK/base.ro"; then echo "FAIL: existing .ro destination unexpectedly overwritten" >&2; exit 1; fi
after_source_hash=$(shasum -a 256 "$ROOT/game/core/game_state.gd" | cut -d' ' -f1)
after_existing_ro_hash=$(shasum -a 256 "$WORK/base.ro" | cut -d' ' -f1)
after_destination_hash=$(find "$WORK/base.roproj" -type f -print | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256 | cut -d' ' -f1)
[[ "$source_hash" == "$after_source_hash" && "$existing_ro_hash" == "$after_existing_ro_hash" && "$destination_hash" == "$after_destination_hash" ]] || { echo "FAIL: preservation hashes changed" >&2; exit 1; }
echo "M2_PASS: 12 typed characters, real .roproj roundtrip/export/reopen, stable identity, unique name edit, fail-closed negatives, collision preservation"
echo "EVIDENCE_DIR=$WORK"
