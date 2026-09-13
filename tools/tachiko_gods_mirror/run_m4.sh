#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TACHIKO_SOURCE=${TACHIKO_SOURCE:-}
GODOT_BIN=${GODOT_BIN:-godot}

# The first invocation is a thin launcher. It rejects tracked drift, archives
# the exact candidate HEAD (thereby excluding untracked .serena and any other
# local inputs), and executes this same runner from that isolated snapshot.
# Only this branch may mint the private handoff values; ordinary invocations
# with a pre-set handoff environment fail closed below.
if [[ "${1:-}" == "--m4-inner" ]]; then
  shift
  ORIGINAL_ROOT=${M4_ORIGINAL_ROOT:-}
  WORK=${M4_WORK:-}
  SOURCE_ROOT=${M4_SNAPSHOT_ROOT:-}
  CANDIDATE_HEAD=${M4_CANDIDATE_HEAD:-}
  [[ -n "$ORIGINAL_ROOT" && -n "$WORK" && -n "$CANDIDATE_HEAD" && -d "$WORK" && -d "$SOURCE_ROOT" ]] || {
    echo "PRECONDITION_UNMET: invalid M4 source snapshot handoff" >&2
    exit 2
  }
  [[ "$SOURCE_ROOT" == "$WORK/richman4-snapshot" ]] || {
    echo "PRECONDITION_UNMET: M4 source snapshot path is not launcher-generated" >&2
    exit 2
  }
  [[ "$CANDIDATE_HEAD" =~ ^[0-9a-f]{40}$ ]] || {
    echo "PRECONDITION_UNMET: invalid M4 candidate HEAD handoff" >&2
    exit 2
  }
  [[ -f "$SOURCE_ROOT/tools/tachiko_gods_mirror/run_m4.sh" && ! -e "$SOURCE_ROOT/.serena" ]] || {
    echo "PRECONDITION_UNMET: incomplete or contaminated M4 source snapshot" >&2
    exit 2
  }
  if ! git -C "$ORIGINAL_ROOT" diff --quiet HEAD --; then
    echo "PRECONDITION_UNMET: richman checkout has tracked drift" >&2
    exit 2
  fi
  [[ "$(git -C "$ORIGINAL_ROOT" rev-parse HEAD)" == "$CANDIDATE_HEAD" ]] || {
    echo "PRECONDITION_UNMET: richman candidate HEAD changed during snapshot handoff" >&2
    exit 2
  }
elif [[ -n "${M4_ORIGINAL_ROOT:-}" || -n "${M4_WORK:-}" || -n "${M4_CANDIDATE_HEAD:-}" || -n "${M4_SNAPSHOT_ROOT:-}" ]]; then
  echo "PRECONDITION_UNMET: M4 handoff variables require the private inner sentinel" >&2
  exit 2
else
  ORIGINAL_ROOT=$ROOT
  if ! git -C "$ORIGINAL_ROOT" diff --quiet HEAD --; then
    echo "PRECONDITION_UNMET: richman checkout has tracked drift" >&2
    exit 2
  fi
  CANDIDATE_HEAD=$(git -C "$ORIGINAL_ROOT" rev-parse HEAD) || {
    echo "PRECONDITION_UNMET: unable to resolve richman candidate HEAD" >&2
    exit 2
  }
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/richman4-tachiko-m4.XXXXXX")
  SOURCE_ROOT="$WORK/richman4-snapshot"
  mkdir -p "$SOURCE_ROOT"
  git -C "$ORIGINAL_ROOT" archive --format=tar HEAD | tar -xf - -C "$SOURCE_ROOT"
  [[ ! -e "$SOURCE_ROOT/.serena" ]] || {
    echo "PRECONDITION_UNMET: source snapshot unexpectedly contains untracked .serena" >&2
    exit 2
  }
  exec env -i \
    PATH="$PATH" \
    TACHIKO_SOURCE="$TACHIKO_SOURCE" \
    GODOT_BIN="$GODOT_BIN" \
    M4_ORIGINAL_ROOT="$ORIGINAL_ROOT" \
    M4_CANDIDATE_HEAD="$CANDIDATE_HEAD" \
    M4_SNAPSHOT_ROOT="$SOURCE_ROOT" \
    M4_WORK="$WORK" \
    "$SOURCE_ROOT/tools/tachiko_gods_mirror/run_m4.sh" --m4-inner "$@"
fi

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

GODOT_PATH=$(command -v "$GODOT_BIN") || {
  echo "PRECONDITION_UNMET: GODOT_BIN is not executable" >&2
  exit 2
}
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

python3 "$SOURCE_ROOT/tests/tachiko_gods_mirror/check_gods.py" --self-test
godot_rc=0
"$GODOT_PATH" --headless --path "$SOURCE_ROOT" --script "$SOURCE_ROOT/tests/tachiko_gods_mirror/source_oracle.gd" >"$WORK/godot.log" 2>&1 || godot_rc=$?
[[ "$godot_rc" == 0 ]] || {
  echo "FAIL: Godot M4 witness exited $godot_rc" >&2
  cat "$WORK/godot.log" >&2
  exit 1
}
python3 "$SOURCE_ROOT/tests/tachiko_gods_mirror/check_gods.py" \
  --source "$SOURCE_ROOT/game/content/original_gods.gd" \
  --godot-log "$WORK/godot.log"
sed -n 's/^RICHMAN4_GODS_ORACLE=//p' "$WORK/godot.log" >"$WORK/candidate.json"
[[ -s "$WORK/candidate.json" ]] || { echo "FAIL: empty Godot candidate" >&2; exit 1; }

mkdir -p "$WORK/adapter-src/src"
cp "$SOURCE_ROOT/tools/tachiko_gods_mirror/adapter.rs" "$WORK/adapter-src/src/main.rs"
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
(cd "$TACHIKO_WORKTREE" && cargo build --manifest-path Cargo.toml -p tachiko-cli --offline --quiet)
(cd "$WORK/adapter-src" && cargo build --manifest-path Cargo.toml --offline --quiet)
CLI="$TACHIKO_WORKTREE/target/debug/tachiko"
ADAPTER="$WORK/adapter-src/target/debug/richman4-tachiko-gods-mirror"

tree_sha256() {
  local tree=$1
  find "$tree" -type f -print | LC_ALL=C sort | while IFS= read -r file; do
    printf '%s  %s\n' "$(shasum -a 256 "$file" | cut -d' ' -f1)" "${file#"$tree"/}"
  done | shasum -a 256 | cut -d' ' -f1
}

layout_sha256() {
  local tree=$1
  find "$tree" -print | LC_ALL=C sort | while IFS= read -r path; do
    local relative
    if [[ "$path" == "$tree" ]]; then
      relative=.
    else
      relative=${path#"$tree"/}
    fi
    if [[ -L "$path" ]]; then
      printf 'L %s %s\n' "$relative" "$(readlink "$path")"
    elif [[ -d "$path" ]]; then
      printf 'D %s\n' "$relative"
    elif [[ -f "$path" ]]; then
      printf 'F %s %s\n' "$relative" "$(shasum -a 256 "$path" | cut -d' ' -f1)"
    else
      echo "FAIL: unsupported project tree entry: $path" >&2
      exit 1
    fi
  done | shasum -a 256 | cut -d' ' -f1
}

python3 "$SOURCE_ROOT/tests/tachiko_gods_mirror/check_gods.py" \
  --candidate-adapter "$ADAPTER" --tachiko-cli "$CLI"

"$ADAPTER" import-log "$WORK/godot.log" "$WORK/base.ro"
"$CLI" validate "$WORK/base.ro"
"$CLI" roproj materialize "$WORK/base.ro" "$WORK/base.roproj"
"$CLI" roproj validate "$WORK/base.roproj"
"$ADAPTER" compare-ro-roproj "$WORK/base.ro" "$WORK/base.roproj"
BASE_LAYOUT_HASH=$(layout_sha256 "$WORK/base.roproj")
if "$CLI" roproj materialize "$WORK/base.ro" "$WORK/base.roproj" >"$WORK/base-roproj-collision.log" 2>&1; then
  echo "FAIL: existing base .roproj destination unexpectedly accepted" >&2
  exit 1
fi
[[ "$BASE_LAYOUT_HASH" == "$(layout_sha256 "$WORK/base.roproj")" ]] || {
  echo "FAIL: existing base .roproj collision changed complete tree layout" >&2
  exit 1
}
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
"$ADAPTER" compare-ro-roproj "$WORK/repeat.ro" "$WORK/repeat.roproj"
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
"$ADAPTER" compare-ro-roproj "$WORK/reordered.ro" "$WORK/reordered.roproj"
"$CLI" export "$WORK/reordered.roproj" "$WORK/reordered-runtime.json"
"$ADAPTER" normalize "$WORK/reordered-runtime.json" "$WORK/reordered.json"
"$ADAPTER" identity-ro "$WORK/reordered.ro" "$WORK/reordered-import-ids.json"
"$ADAPTER" identity "$WORK/reordered.roproj" "$WORK/reordered-ids.json"
cmp "$WORK/base.json" "$WORK/reordered.json"
cmp "$WORK/base-import-ids.json" "$WORK/reordered-import-ids.json"
cmp "$WORK/base-ids.json" "$WORK/reordered-ids.json"
python3 "$SOURCE_ROOT/tests/tachiko_gods_mirror/check_gods.py" \
  --projection "$WORK/reordered.json"

# The one permitted semantic edit changes only god 1's display text.
"$CLI" set "$WORK/base.roproj" god_01.display_name '小財神（M4驗證）' --output "$WORK/edited.ro"
"$CLI" validate "$WORK/edited.ro"
"$CLI" roproj materialize "$WORK/edited.ro" "$WORK/edited.roproj"
"$CLI" roproj validate "$WORK/edited.roproj"
"$ADAPTER" compare-ro-roproj "$WORK/edited.ro" "$WORK/edited.roproj"
"$ADAPTER" check-edit "$WORK/base.roproj" "$WORK/edited.roproj"
"$CLI" export "$WORK/edited.roproj" "$WORK/edited-runtime.json"
"$ADAPTER" normalize "$WORK/edited-runtime.json" "$WORK/edited.json"
"$ADAPTER" identity "$WORK/edited.roproj" "$WORK/edited-ids.json"
"$ADAPTER" identity "$WORK/edited.roproj" "$WORK/reopened-ids.json"

python3 "$SOURCE_ROOT/tests/tachiko_gods_mirror/check_gods.py" \
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
  echo "candidate_head=$CANDIDATE_HEAD"
  echo "tachiko_head=$TACHIKO_SHA"
  echo "godot_binary=$(sha256 "$GODOT_PATH")"
  echo "adapter_source=$(sha256 "$SOURCE_ROOT/tools/tachiko_gods_mirror/adapter.rs")"
  echo "runner_source=$(sha256 "$SOURCE_ROOT/tools/tachiko_gods_mirror/run_m4.sh")"
  echo "checker_source=$(sha256 "$SOURCE_ROOT/tests/tachiko_gods_mirror/check_gods.py")"
  echo "witness_source=$(sha256 "$SOURCE_ROOT/tests/tachiko_gods_mirror/source_oracle.gd")"
  echo "source_original_gods=$(sha256 "$SOURCE_ROOT/game/content/original_gods.gd")"
  echo "oracle_json=$(sha256 "$SOURCE_ROOT/tests/tachiko_gods_mirror/oracle.json")"
  echo "godot_witness_log=$(sha256 "$WORK/godot.log")"
  echo "tachiko_cli_binary=$(sha256 "$CLI")"
  echo "adapter_binary=$(sha256 "$ADAPTER")"
  for artifact in candidate.json base.ro repeat.ro reordered-candidate.json reordered.ro edited.ro base.json repeat.json reordered.json edited.json base-import-ids.json repeat-import-ids.json reordered-import-ids.json base-ids.json repeat-ids.json reordered-ids.json edited-ids.json reopened-ids.json; do
    echo "$artifact=$(sha256 "$WORK/$artifact")"
  done
  echo "base.roproj.tree_sha256=$(tree_sha256 "$WORK/base.roproj")"
  echo "repeat.roproj.tree_sha256=$(tree_sha256 "$WORK/repeat.roproj")"
  echo "reordered.roproj.tree_sha256=$(tree_sha256 "$WORK/reordered.roproj")"
  echo "edited.roproj.tree_sha256=$(tree_sha256 "$WORK/edited.roproj")"
  echo "base.roproj.layout_sha256=$(layout_sha256 "$WORK/base.roproj")"
  echo "repeat.roproj.layout_sha256=$(layout_sha256 "$WORK/repeat.roproj")"
  echo "reordered.roproj.layout_sha256=$(layout_sha256 "$WORK/reordered.roproj")"
  echo "edited.roproj.layout_sha256=$(layout_sha256 "$WORK/edited.roproj")"
} >"$MANIFEST"
echo "EVIDENCE_MANIFEST=$MANIFEST"
cat "$MANIFEST"
echo "M4_PASS: 15 typed gods, reciprocal references, real .roproj roundtrip/reopen, stable IDs, isolated display edit, frozen negatives and collisions"
echo "EVIDENCE_DIR=$WORK"
