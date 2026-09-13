#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TACHIKO_SOURCE=${TACHIKO_SOURCE:-}
TACHIKO_SHA=6900e975112576585fd9360f12d9fcf8b36ba466
TACHIKO_GIT_DIR=""
if [[ -z "$TACHIKO_SOURCE" ]] || ! TACHIKO_GIT_DIR=$(git -C "$TACHIKO_SOURCE" rev-parse --git-dir 2>/dev/null); then
  echo "PRECONDITION_UNMET: TACHIKO_SOURCE must be a clean Git checkout" >&2
  exit 2
fi
[[ "$(git -C "$TACHIKO_SOURCE" rev-parse HEAD)" == "$TACHIKO_SHA" ]] || {
  echo "PRECONDITION_UNMET: TACHIKO_SOURCE must be $TACHIKO_SHA" >&2
  exit 2
}
[[ "$(git -C "$TACHIKO_SOURCE" rev-parse refs/remotes/origin/main 2>/dev/null || true)" == "$TACHIKO_SHA" ]] || {
  echo "PRECONDITION_UNMET: TACHIKO_SOURCE origin/main must be $TACHIKO_SHA" >&2
  exit 2
}
[[ -z "$(git -C "$TACHIKO_SOURCE" status --porcelain)" ]] || {
  echo "PRECONDITION_UNMET: TACHIKO_SOURCE is dirty" >&2
  exit 2
}

GODOT_BIN=${GODOT_BIN:-godot}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/richman4-tachiko-m4.XXXXXX")
TACHIKO_WORKTREE=$(mktemp -d "${TMPDIR:-/tmp}/richman4-tachiko-linked.XXXXXX")
git -C "$TACHIKO_SOURCE" worktree add --detach "$TACHIKO_WORKTREE" "$TACHIKO_SHA" >/dev/null
cleanup() {
  git -C "$TACHIKO_SOURCE" worktree remove --force "$TACHIKO_WORKTREE" >/dev/null 2>&1 || true
  [[ -n "${KEEP_EVIDENCE:-}" ]] || rm -rf "$WORK"
}
trap cleanup EXIT

echo "TACHIKO_SHA=$TACHIKO_SHA"
echo "TACHIKO_SOURCE=$TACHIKO_SOURCE"
echo "TACHIKO_GIT_DIR=$TACHIKO_GIT_DIR"
echo "TACHIKO_WORKTREE=$TACHIKO_WORKTREE"
echo "WORK=$WORK"

python3 "$ROOT/tests/tachiko_gods_mirror/check_gods.py" --self-test
godot_rc=0
"$GODOT_BIN" --headless --path "$ROOT" --script "$ROOT/tests/tachiko_gods_mirror/source_oracle.gd" >"$WORK/godot.log" 2>&1 || godot_rc=$?
[[ "$godot_rc" == 0 ]] || {
  echo "FAIL: Godot M4 witness exited $godot_rc" >&2
  cat "$WORK/godot.log" >&2
  exit 1
}
python3 "$ROOT/tests/tachiko_gods_mirror/check_gods.py" \
  --source "$ROOT/game/content/original_gods.gd" \
  --godot-log "$WORK/godot.log"
sed -n 's/^RICHMAN4_GODS_ORACLE=//p' "$WORK/godot.log" >"$WORK/candidate.json"
[[ -s "$WORK/candidate.json" ]] || { echo "FAIL: empty Godot candidate" >&2; exit 1; }

mkdir -p "$WORK/adapter-src/src"
cp "$ROOT/tools/tachiko_gods_mirror/adapter.rs" "$WORK/adapter-src/src/main.rs"
cat >"$WORK/adapter-src/Cargo.toml" <<EOF
[package]
name = "richman4-tachiko-gods-mirror"
version = "0.1.0"
edition = "2024"
[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
tachiko-storage = { path = "$TACHIKO_WORKTREE/crates/storage" }
tachiko-workspace-engine = { path = "$TACHIKO_WORKTREE/crates/workspace-engine" }
EOF
cargo build --manifest-path "$TACHIKO_WORKTREE/Cargo.toml" -p tachiko-cli --offline --quiet
cargo build --manifest-path "$WORK/adapter-src/Cargo.toml" --offline --quiet
CLI="$TACHIKO_WORKTREE/target/debug/tachiko"
ADAPTER="$WORK/adapter-src/target/debug/richman4-tachiko-gods-mirror"

tree_sha256() {
  local tree=$1
  find "$tree" -type f -print | LC_ALL=C sort | while IFS= read -r file; do
    printf '%s  %s\n' "$(shasum -a 256 "$file" | cut -d' ' -f1)" "${file#"$tree"/}"
  done | shasum -a 256 | cut -d' ' -f1
}

python3 "$ROOT/tests/tachiko_gods_mirror/check_gods.py" \
  --candidate-adapter "$ADAPTER" --tachiko-cli "$CLI"

"$ADAPTER" import-log "$WORK/godot.log" "$WORK/base.ro"
"$CLI" validate "$WORK/base.ro"
"$CLI" roproj materialize "$WORK/base.ro" "$WORK/base.roproj"
"$CLI" roproj validate "$WORK/base.roproj"
"$CLI" export "$WORK/base.roproj" "$WORK/base-runtime.json"
"$ADAPTER" normalize "$WORK/base-runtime.json" "$WORK/base.json"
"$ADAPTER" identity-ro "$WORK/base.ro" "$WORK/base-import-ids.json"
"$ADAPTER" identity "$WORK/base.roproj" "$WORK/base-ids.json"
cmp "$WORK/base-import-ids.json" "$WORK/base-ids.json"

# Re-importing the same witnessed source is deterministic and keeps the same
# semantic document/entity identities after a real storage reopen.
"$ADAPTER" import-log "$WORK/godot.log" "$WORK/repeat.ro"
cmp "$WORK/base.ro" "$WORK/repeat.ro"
"$ADAPTER" identity-ro "$WORK/repeat.ro" "$WORK/repeat-import-ids.json"
"$CLI" roproj materialize "$WORK/repeat.ro" "$WORK/repeat.roproj"
"$CLI" roproj validate "$WORK/repeat.roproj"
"$CLI" export "$WORK/repeat.roproj" "$WORK/repeat-runtime.json"
"$ADAPTER" normalize "$WORK/repeat-runtime.json" "$WORK/repeat.json"
"$ADAPTER" identity "$WORK/repeat.roproj" "$WORK/repeat-ids.json"
cmp "$WORK/base.json" "$WORK/repeat.json"
cmp "$WORK/base-import-ids.json" "$WORK/repeat-import-ids.json"
cmp "$WORK/base-ids.json" "$WORK/repeat-ids.json"
[[ "$(tree_sha256 "$WORK/base.roproj")" == "$(tree_sha256 "$WORK/repeat.roproj")" ]] || {
  echo "FAIL: repeated .roproj tree drifted" >&2
  exit 1
}

# Presentation reorder must be accepted while identity remains keyed by the
# legacy ID, not by input row position.
"$ADAPTER" reorder "$WORK/candidate.json" "$WORK/reordered-candidate.json"
"$ADAPTER" candidate "$WORK/reordered-candidate.json" "$WORK/reordered.ro"
"$CLI" validate "$WORK/reordered.ro"
"$CLI" roproj materialize "$WORK/reordered.ro" "$WORK/reordered.roproj"
"$CLI" roproj validate "$WORK/reordered.roproj"
"$CLI" export "$WORK/reordered.roproj" "$WORK/reordered-runtime.json"
"$ADAPTER" normalize "$WORK/reordered-runtime.json" "$WORK/reordered.json"
"$ADAPTER" identity-ro "$WORK/reordered.ro" "$WORK/reordered-import-ids.json"
"$ADAPTER" identity "$WORK/reordered.roproj" "$WORK/reordered-ids.json"
cmp "$WORK/base.json" "$WORK/reordered.json"
cmp "$WORK/base-import-ids.json" "$WORK/reordered-import-ids.json"
cmp "$WORK/base-ids.json" "$WORK/reordered-ids.json"
python3 "$ROOT/tests/tachiko_gods_mirror/check_gods.py" \
  --projection "$WORK/reordered.json"

# The one permitted semantic edit changes only god 1's display text.
"$CLI" set "$WORK/base.roproj" god_01.display_name '小財神（M4驗證）' --output "$WORK/edited.ro"
"$CLI" validate "$WORK/edited.ro"
"$CLI" roproj materialize "$WORK/edited.ro" "$WORK/edited.roproj"
"$CLI" roproj validate "$WORK/edited.roproj"
"$CLI" export "$WORK/edited.roproj" "$WORK/edited-runtime.json"
"$ADAPTER" normalize "$WORK/edited-runtime.json" "$WORK/edited.json"
"$ADAPTER" identity "$WORK/edited.roproj" "$WORK/edited-ids.json"
"$ADAPTER" identity "$WORK/edited.roproj" "$WORK/reopened-ids.json"

python3 "$ROOT/tests/tachiko_gods_mirror/check_gods.py" \
  --projection "$WORK/base.json" \
  --edited-projection "$WORK/edited.json" \
  --identity-map "$WORK/base-ids.json" \
  --identity-map "$WORK/base-import-ids.json" \
  --identity-map "$WORK/repeat-ids.json" \
  --identity-map "$WORK/repeat-import-ids.json" \
  --identity-map "$WORK/reordered-ids.json" \
  --identity-map "$WORK/reordered-import-ids.json" \
  --identity-map "$WORK/edited-ids.json" \
  --identity-map "$WORK/reopened-ids.json"

sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
MANIFEST="$WORK/evidence-manifest.txt"
{
  echo "richman_head=$(git -C "$ROOT" rev-parse HEAD)"
  echo "tachiko_head=$TACHIKO_SHA"
  echo "source_original_gods=$(sha256 "$ROOT/game/content/original_gods.gd")"
  echo "oracle_json=$(sha256 "$ROOT/tests/tachiko_gods_mirror/oracle.json")"
  echo "godot_witness_log=$(sha256 "$WORK/godot.log")"
  for artifact in candidate.json base.ro repeat.ro reordered-candidate.json reordered.ro edited.ro base.json repeat.json reordered.json edited.json base-import-ids.json repeat-import-ids.json reordered-import-ids.json base-ids.json repeat-ids.json reordered-ids.json edited-ids.json reopened-ids.json; do
    echo "$artifact=$(sha256 "$WORK/$artifact")"
  done
  echo "base.roproj.tree_sha256=$(tree_sha256 "$WORK/base.roproj")"
  echo "repeat.roproj.tree_sha256=$(tree_sha256 "$WORK/repeat.roproj")"
  echo "reordered.roproj.tree_sha256=$(tree_sha256 "$WORK/reordered.roproj")"
  echo "edited.roproj.tree_sha256=$(tree_sha256 "$WORK/edited.roproj")"
} >"$MANIFEST"
echo "EVIDENCE_MANIFEST=$MANIFEST"
cat "$MANIFEST"
echo "M4_PASS: 15 typed gods, reciprocal references, real .roproj roundtrip/reopen, stable IDs, isolated display edit, frozen negatives and collisions"
echo "EVIDENCE_DIR=$WORK"
