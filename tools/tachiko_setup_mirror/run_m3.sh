#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TACHIKO_SOURCE=${TACHIKO_SOURCE:-}
TACHIKO_SHA=6900e975112576585fd9360f12d9fcf8b36ba466
if [[ -z "$TACHIKO_SOURCE" ]] || ! git -C "$TACHIKO_SOURCE" rev-parse --git-dir >/dev/null 2>&1; then
  echo "PRECONDITION_UNMET: TACHIKO_SOURCE must be a clean Git checkout" >&2; exit 2
fi
[[ "$(git -C "$TACHIKO_SOURCE" rev-parse HEAD)" == "$TACHIKO_SHA" ]] || { echo "PRECONDITION_UNMET: TACHIKO_SOURCE must be $TACHIKO_SHA" >&2; exit 2; }
[[ -z "$(git -C "$TACHIKO_SOURCE" status --porcelain)" ]] || { echo "PRECONDITION_UNMET: TACHIKO_SOURCE is dirty" >&2; exit 2; }

GODOT_BIN=${GODOT_BIN:-godot}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/richman4-tachiko-m3.XXXXXX")
cleanup(){ [[ -n "${KEEP_EVIDENCE:-}" ]] || rm -rf "$WORK"; }
trap cleanup EXIT
echo "TACHIKO_SHA=$TACHIKO_SHA"
echo "TACHIKO_SOURCE=$TACHIKO_SOURCE"
echo "TACHIKO_GIT_DIR=$(git -C "$TACHIKO_SOURCE" rev-parse --git-dir)"
echo "WORK=$WORK"

uv run --no-project --offline python "$ROOT/tests/tachiko_setup_mirror/check_setup.py" --self-test --runtime-source "$ROOT/game/ui/main_ui.gd" --research-source "$ROOT/docs/calendar-and-setup.md"
godot_rc=0
"$GODOT_BIN" --headless --path "$ROOT" --script "$ROOT/tests/tachiko_setup_mirror/source_oracle.gd" >"$WORK/godot.log" 2>&1 || godot_rc=$?
uv run --no-project --offline python "$ROOT/tests/tachiko_setup_mirror/check_setup.py" --godot-log "$WORK/godot.log" --godot-exit-code "$godot_rc"

mkdir -p "$WORK/adapter-src/src"
cp "$ROOT/tools/tachiko_setup_mirror/adapter.rs" "$WORK/adapter-src/src/main.rs"
cat >"$WORK/adapter-src/Cargo.toml" <<EOF
[package]
name = "richman4-tachiko-setup-mirror"
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
ADAPTER="$WORK/adapter-src/target/debug/richman4-tachiko-setup-mirror"
uv run --no-project --offline python "$ROOT/tests/tachiko_setup_mirror/check_setup.py" --adapter "$ADAPTER" --tachiko-cli "$CLI"
sed -n 's/^RICHMAN4_SETUP_ORACLE=//p' "$WORK/godot.log" >"$WORK/candidate.json"
awk 'BEGIN { done=0 } { if (!done && /"value":[[:space:]]*300000/) { sub(/"value":[[:space:]]*300000/, "\"value\":3e5"); done=1 } print }' "$WORK/candidate.json" >"$WORK/scientific-candidate.json"
grep -Fq '"value":3e5' "$WORK/scientific-candidate.json"
if cmp -s "$WORK/candidate.json" "$WORK/scientific-candidate.json"; then
  echo "FAIL: scientific candidate was not changed" >&2
  exit 1
fi
"$ADAPTER" candidate "$WORK/scientific-candidate.json" "$WORK/scientific.ro"
"$CLI" validate "$WORK/scientific.ro"

"$ADAPTER" import-log "$WORK/godot.log" "$WORK/base.ro" "$WORK/base-import-ids.json"
"$CLI" validate "$WORK/base.ro"
"$CLI" roproj materialize "$WORK/base.ro" "$WORK/base.roproj"
"$CLI" roproj validate "$WORK/base.roproj"
"$CLI" export "$WORK/base.roproj" "$WORK/base-runtime.json"
"$ADAPTER" normalize "$WORK/base-runtime.json" "$WORK/roundtrip-1.json"
"$ADAPTER" import-log "$WORK/godot.log" "$WORK/repeat.ro" "$WORK/repeat-import-ids.json"
"$CLI" roproj materialize "$WORK/repeat.ro" "$WORK/repeat.roproj"
"$CLI" roproj validate "$WORK/repeat.roproj"
"$CLI" export "$WORK/repeat.roproj" "$WORK/repeat-runtime.json"
"$ADAPTER" normalize "$WORK/repeat-runtime.json" "$WORK/roundtrip-2.json"
cmp "$WORK/roundtrip-1.json" "$WORK/roundtrip-2.json"
"$ADAPTER" identity "$WORK/base.roproj" "$WORK/base-persisted-ids.json"
"$ADAPTER" identity "$WORK/repeat.roproj" "$WORK/repeat-persisted-ids.json"

# The same witnessed candidate, reordered as presentation data, must retain every
# kind/index identity through real typed admission and storage reopen.
"$ADAPTER" reorder "$WORK/candidate.json" "$WORK/reordered-candidate.json"
"$ADAPTER" candidate "$WORK/reordered-candidate.json" "$WORK/reordered.ro"
"$CLI" validate "$WORK/reordered.ro"
"$CLI" roproj materialize "$WORK/reordered.ro" "$WORK/reordered.roproj"
"$CLI" roproj validate "$WORK/reordered.roproj"
"$ADAPTER" identity "$WORK/reordered.roproj" "$WORK/reordered-persisted-ids.json"
cmp "$WORK/base-import-ids.json" "$WORK/reordered-persisted-ids.json"

"$CLI" set "$WORK/base.roproj" setup_option_day_limit_5.value 31 --output "$WORK/edited.ro"
"$CLI" validate "$WORK/edited.ro"
"$CLI" roproj materialize "$WORK/edited.ro" "$WORK/edited.roproj"
"$CLI" roproj validate "$WORK/edited.roproj"
"$CLI" diff "$WORK/base.roproj" "$WORK/edited.roproj" >"$WORK/semantic-diff.txt"
"$ADAPTER" check-diff "$WORK/semantic-diff.txt"
"$CLI" export "$WORK/edited.roproj" "$WORK/edited-runtime.json"
"$ADAPTER" normalize "$WORK/edited-runtime.json" "$WORK/edited.json"
"$ADAPTER" identity "$WORK/edited.roproj" "$WORK/edited-persisted-ids.json"
"$ADAPTER" identity "$WORK/edited.roproj" "$WORK/reopened-persisted-ids.json"
uv run --no-project --offline python "$ROOT/tests/tachiko_setup_mirror/check_setup.py" --projection "$WORK/roundtrip-1.json" --repeat "$WORK/roundtrip-2.json" --edited-projection "$WORK/edited.json" --identity-maps "$WORK/base-import-ids.json" "$WORK/repeat-import-ids.json" "$WORK/base-persisted-ids.json" "$WORK/repeat-persisted-ids.json" "$WORK/edited-persisted-ids.json" "$WORK/reopened-persisted-ids.json"

tree_sha256() {
  local tree=$1
  find "$tree" -type f -print | LC_ALL=C sort | while IFS= read -r file; do
    printf '%s  %s\n' "$(shasum -a 256 "$file" | cut -d' ' -f1)" "${file#"$tree"/}"
  done | shasum -a 256 | cut -d' ' -f1
}
sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
MANIFEST="$WORK/evidence-manifest.txt"
{
  echo "richman_head=$(git -C "$ROOT" rev-parse HEAD)"
  echo "tachiko_head=$TACHIKO_SHA"
  echo "source_main_ui=$(sha256 "$ROOT/game/ui/main_ui.gd")"
  echo "research_calendar_setup=$(sha256 "$ROOT/docs/calendar-and-setup.md")"
  echo "oracle_json=$(sha256 "$ROOT/tests/tachiko_setup_mirror/oracle.json")"
  echo "godot_witness_log=$(sha256 "$WORK/godot.log")"
  for artifact in base.ro repeat.ro edited.ro roundtrip-1.json roundtrip-2.json edited.json base-import-ids.json repeat-import-ids.json base-persisted-ids.json repeat-persisted-ids.json edited-persisted-ids.json reopened-persisted-ids.json; do
    echo "$artifact=$(sha256 "$WORK/$artifact")"
  done
  echo "base.roproj.tree_sha256=$(tree_sha256 "$WORK/base.roproj")"
  echo "repeat.roproj.tree_sha256=$(tree_sha256 "$WORK/repeat.roproj")"
  echo "edited.roproj.tree_sha256=$(tree_sha256 "$WORK/edited.roproj")"
} >"$MANIFEST"
echo "EVIDENCE_MANIFEST=$MANIFEST"
cat "$MANIFEST"
echo "M3_PASS: 18 typed setup options, deterministic storage roundtrip, isolated day_limit/5 edit, six identity maps"
echo "EVIDENCE_DIR=$WORK"
