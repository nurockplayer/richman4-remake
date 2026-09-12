#!/usr/bin/env bash
set -eo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TACHIKO_SOURCE=$(printenv TACHIKO_SOURCE 2>/dev/null || true)
TACHIKO_SHA=6900e975112576585fd9360f12d9fcf8b36ba466

if [[ -z "$TACHIKO_SOURCE" ]] || ! git -C "$TACHIKO_SOURCE" rev-parse --git-dir >/dev/null 2>&1; then
  echo "PRECONDITION_UNMET: TACHIKO_SOURCE must be a clean checkout" >&2
  exit 2
fi
if [[ "$(git -C "$TACHIKO_SOURCE" rev-parse HEAD)" != "$TACHIKO_SHA" ]]; then
  echo "PRECONDITION_UNMET: TACHIKO_SOURCE must be $TACHIKO_SHA" >&2
  exit 2
fi
if [[ "$(git -C "$TACHIKO_SOURCE" rev-parse refs/remotes/origin/main 2>/dev/null || true)" != "$TACHIKO_SHA" ]]; then
  echo "PRECONDITION_UNMET: TACHIKO_SOURCE origin/main must be $TACHIKO_SHA" >&2
  exit 2
fi
if [[ -n "$(git -C "$TACHIKO_SOURCE" status --porcelain)" ]]; then
  echo "PRECONDITION_UNMET: TACHIKO_SOURCE is dirty" >&2
  exit 2
fi

GODOT_BIN=$(printenv GODOT_BIN 2>/dev/null || echo godot)
KEEP_EVIDENCE=$(printenv KEEP_EVIDENCE 2>/dev/null || true)
WORK=$(mktemp -d "/tmp/richman4-tachiko-m1.XXXXXX")
cleanup() { [[ -n "$KEEP_EVIDENCE" ]] || rm -rf "$WORK"; }
trap cleanup EXIT

echo "TACHIKO_SHA=$TACHIKO_SHA"
echo "TACHIKO_SOURCE=$TACHIKO_SOURCE"
echo "WORK=$WORK"

"$GODOT_BIN" --headless --path "$ROOT" --script tests/tachiko_mirror/source_oracle.gd >"$WORK/godot.log" 2>&1
uv run --no-project --offline python "$ROOT/tests/tachiko_mirror/check_catalog.py" \
  --source "$ROOT/game/content/original_inventory.gd" --godot-log "$WORK/godot.log"

mkdir -p "$WORK/adapter-src/src"
cp "$ROOT/tools/tachiko_mirror/adapter.rs" "$WORK/adapter-src/src/main.rs"
cat >"$WORK/adapter-src/Cargo.toml" <<EOF
[package]
name = "richman4-tachiko-mirror"
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
ADAPTER="$WORK/adapter-src/target/debug/richman4-tachiko-mirror"

sed -n 's/^RICHMAN4_CATALOG_ORACLE=//p' "$WORK/godot.log" >"$WORK/candidate.json"
"$ADAPTER" import-log "$WORK/godot.log" "$WORK/base.ro" "$WORK/identity-map.json"
"$CLI" validate "$WORK/base.ro"
"$CLI" roproj materialize "$WORK/base.ro" "$WORK/base.roproj"
"$CLI" roproj validate "$WORK/base.roproj"
"$CLI" export "$WORK/base.roproj" "$WORK/base-runtime.json"
"$ADAPTER" normalize "$WORK/base-runtime.json" "$WORK/roundtrip-1.json"

"$ADAPTER" import-log "$WORK/godot.log" "$WORK/repeat.ro" "$WORK/repeat-map.json"
"$CLI" roproj materialize "$WORK/repeat.ro" "$WORK/repeat.roproj"
"$CLI" roproj validate "$WORK/repeat.roproj"
"$CLI" export "$WORK/repeat.roproj" "$WORK/repeat-runtime.json"
"$ADAPTER" normalize "$WORK/repeat-runtime.json" "$WORK/roundtrip-2.json"

"$CLI" set "$WORK/base.roproj" tool_02.point_price 31 --output "$WORK/edited.ro"
"$CLI" validate "$WORK/edited.ro"
"$CLI" roproj materialize "$WORK/edited.ro" "$WORK/edited.roproj"
"$CLI" roproj validate "$WORK/edited.roproj"
"$CLI" diff "$WORK/base.roproj" "$WORK/edited.roproj" >"$WORK/semantic-diff.txt"
"$CLI" export "$WORK/edited.roproj" "$WORK/edited-runtime.json"
"$ADAPTER" normalize "$WORK/edited-runtime.json" "$WORK/edited.json"

uv run --no-project --offline python "$ROOT/tests/tachiko_mirror/check_catalog.py" \
  --projection "$WORK/roundtrip-1.json" --repeat "$WORK/roundtrip-2.json" \
  --edited-projection "$WORK/edited.json"
grep -q 'point_price: 30 -> 31' "$WORK/semantic-diff.txt"
cmp "$WORK/identity-map.json" "$WORK/repeat-map.json"

source_hash=$(shasum -a 256 "$ROOT/game/content/original_inventory.gd" | cut -d' ' -f1)
existing_ro_hash=$(shasum -a 256 "$WORK/base.ro" | cut -d' ' -f1)
destination_hash=$(find "$WORK/base.roproj" -type f -print | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256 | cut -d' ' -f1)
echo "SOURCE_SHA256=$source_hash"
echo "EXISTING_RO_SHA256=$existing_ro_hash"
echo "DESTINATION_SHA256=$destination_hash"
for kind in duplicate missing-identity wrong-type fraction negative-supply unknown-field; do
  "$ADAPTER" mutant "$WORK/candidate.json" "$WORK/$kind.json" "$kind"
  if "$ADAPTER" candidate "$WORK/$kind.json" "$WORK/$kind.ro"; then
    echo "FAIL: invalid candidate unexpectedly accepted: $kind" >&2
    exit 1
  fi
  [[ ! -e "$WORK/$kind.ro" ]] || { echo "FAIL: invalid candidate left output: $kind" >&2; exit 1; }
done
if "$ADAPTER" candidate "$WORK/candidate.json" "$WORK/base.ro"; then
  echo "FAIL: existing destination unexpectedly overwritten" >&2
  exit 1
fi
after_source_hash=$(shasum -a 256 "$ROOT/game/content/original_inventory.gd" | cut -d' ' -f1)
after_existing_ro_hash=$(shasum -a 256 "$WORK/base.ro" | cut -d' ' -f1)
after_destination_hash=$(find "$WORK/base.roproj" -type f -print | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256 | cut -d' ' -f1)
[[ "$source_hash" == "$after_source_hash" && "$existing_ro_hash" == "$after_existing_ro_hash" && "$destination_hash" == "$after_destination_hash" ]] || { echo "FAIL: preservation hashes changed" >&2; exit 1; }

echo "M1_PASS: 43 records, Rust typed model/storage, real .roproj validate/materialize/export, stable no-op bytes, 30->31 semantic edit, fail-closed candidate gates"
echo "EVIDENCE_DIR=$WORK"
