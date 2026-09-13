#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TACHIKO_SOURCE=${TACHIKO_SOURCE:-}
GODOT_BIN=${GODOT_BIN:-godot}
KEEP_EVIDENCE_VALUE=${KEEP_EVIDENCE:-}
case "$KEEP_EVIDENCE_VALUE" in
  ''|1) ;;
  *) echo "PRECONDITION_UNMET: KEEP_EVIDENCE must be empty or literal 1" >&2; exit 2 ;;
esac

HOME_VALUE=${HOME:-}
if [[ -z "$HOME_VALUE" ]]; then
  HOME_VALUE=$(cd ~ 2>/dev/null && pwd) || {
    echo "PRECONDITION_UNMET: HOME is unset and the user home cannot be resolved" >&2
    exit 2
  }
fi
CARGO_HOME_VALUE=${CARGO_HOME:-$HOME_VALUE/.cargo}
RUSTUP_HOME_VALUE=${RUSTUP_HOME:-$HOME_VALUE/.rustup}
[[ "$HOME_VALUE" == /* && "$CARGO_HOME_VALUE" == /* && "$RUSTUP_HOME_VALUE" == /* ]] || {
  echo "PRECONDITION_UNMET: HOME, CARGO_HOME, and RUSTUP_HOME must be absolute paths" >&2
  exit 2
}

# The launcher archives no untracked inputs: it snapshots the exact candidate
# HEAD in a detached worktree before the inner run. This keeps .serena and any
# other local material out of the evidence and prevents source mutation.
if [[ "${1:-}" == "--m7-inner" ]]; then
  shift
  ORIGINAL_ROOT=${M7_ORIGINAL_ROOT:-}
  WORK=${M7_WORK:-}
  SOURCE_ROOT=${M7_SNAPSHOT_ROOT:-}
  CANDIDATE_HEAD=${M7_CANDIDATE_HEAD:-}
  [[ -n "$ORIGINAL_ROOT" && -n "$WORK" && -n "$SOURCE_ROOT" && -n "$CANDIDATE_HEAD" && -d "$WORK" && -d "$SOURCE_ROOT" ]] || {
    echo "PRECONDITION_UNMET: invalid M7 snapshot handoff" >&2; exit 2
  }
  [[ "$SOURCE_ROOT" == "$WORK/richman4-snapshot" && "$CANDIDATE_HEAD" =~ ^[0-9a-f]{40}$ ]] || {
    echo "PRECONDITION_UNMET: snapshot handoff is not launcher-generated" >&2; exit 2
  }
  [[ "$(git -C "$SOURCE_ROOT" rev-parse HEAD 2>/dev/null || true)" == "$CANDIDATE_HEAD" ]] || {
    echo "PRECONDITION_UNMET: candidate snapshot HEAD mismatch" >&2; exit 2
  }
  [[ -z "$(git -C "$SOURCE_ROOT" status --porcelain 2>/dev/null || true)" ]] || {
    echo "PRECONDITION_UNMET: candidate snapshot is dirty" >&2; exit 2
  }
  [[ -f "$SOURCE_ROOT/tools/tachiko_fate_events_mirror/adapter.rs" && -f "$SOURCE_ROOT/tools/tachiko_fate_events_mirror/run_m7.sh" ]] || {
    echo "PRECONDITION_UNMET: M7 implementation is absent from candidate HEAD" >&2; exit 2
  }
  TACHIKO_WORKTREE=''
  cleanup() {
    if [[ -n "$TACHIKO_WORKTREE" ]]; then
      git -C "$TACHIKO_SOURCE" worktree remove --force "$TACHIKO_WORKTREE" >/dev/null 2>&1 || true
    fi
    git -C "$ORIGINAL_ROOT" worktree remove --force "$SOURCE_ROOT" >/dev/null 2>&1 || true
    [[ "$KEEP_EVIDENCE_VALUE" == 1 ]] || rm -rf "$WORK"
  }
  trap cleanup EXIT
elif [[ -n "${M7_ORIGINAL_ROOT:-}" || -n "${M7_WORK:-}" || -n "${M7_CANDIDATE_HEAD:-}" || -n "${M7_SNAPSHOT_ROOT:-}" ]]; then
  echo "PRECONDITION_UNMET: M7 handoff variables require the private inner sentinel" >&2
  exit 2
else
  ORIGINAL_ROOT=$ROOT
  if ! git -C "$ORIGINAL_ROOT" diff --quiet HEAD --; then
    echo "PRECONDITION_UNMET: richman checkout has tracked drift" >&2; exit 2
  fi
  git -C "$ORIGINAL_ROOT" ls-files --error-unmatch \
    tools/tachiko_fate_events_mirror/adapter.rs \
    tools/tachiko_fate_events_mirror/run_m7.sh >/dev/null 2>&1 || {
    echo "PRECONDITION_UNMET: M7 implementation must be present at candidate HEAD" >&2
    exit 2
  }
  CANDIDATE_HEAD=$(git -C "$ORIGINAL_ROOT" rev-parse HEAD) || {
    echo "PRECONDITION_UNMET: unable to resolve candidate HEAD" >&2; exit 2
  }
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/richman4-tachiko-m7.XXXXXX")
  SOURCE_ROOT="$WORK/richman4-snapshot"
  launcher_cleanup() {
    git -C "$ORIGINAL_ROOT" worktree remove --force "$SOURCE_ROOT" >/dev/null 2>&1 || true
  }
  trap launcher_cleanup EXIT
git -C "$ORIGINAL_ROOT" worktree add --detach "$SOURCE_ROOT" "$CANDIDATE_HEAD" >/dev/null
  [[ ! -e "$SOURCE_ROOT/.serena" ]] || {
    echo "PRECONDITION_UNMET: source snapshot unexpectedly contains untracked .serena" >&2; exit 2
  }
  exec env -i \
    PATH="$PATH" HOME="$HOME_VALUE" CARGO_HOME="$CARGO_HOME_VALUE" RUSTUP_HOME="$RUSTUP_HOME_VALUE" \
    TACHIKO_SOURCE="$TACHIKO_SOURCE" GODOT_BIN="$GODOT_BIN" KEEP_EVIDENCE="$KEEP_EVIDENCE_VALUE" \
    M7_ORIGINAL_ROOT="$ORIGINAL_ROOT" M7_CANDIDATE_HEAD="$CANDIDATE_HEAD" \
    M7_SNAPSHOT_ROOT="$SOURCE_ROOT" M7_WORK="$WORK" \
    "$SOURCE_ROOT/tools/tachiko_fate_events_mirror/run_m7.sh" --m7-inner "$@"
fi

TACHIKO_SHA=6900e975112576585fd9360f12d9fcf8b36ba466
TACHIKO_GIT_DIR=''
if [[ -z "$TACHIKO_SOURCE" ]] || ! TACHIKO_GIT_DIR=$(git -C "$TACHIKO_SOURCE" rev-parse --git-dir 2>/dev/null); then
  echo "PRECONDITION_UNMET: TACHIKO_SOURCE must be a clean Git checkout" >&2; exit 2
fi
[[ "$(git -C "$TACHIKO_SOURCE" rev-parse HEAD)" == "$TACHIKO_SHA" ]] || {
  echo "PRECONDITION_UNMET: TACHIKO_SOURCE must be $TACHIKO_SHA" >&2; exit 2
}
# M7 admits against this immutable, previously proven Tachiko commit.  A
# current remote-tracking `origin/main` may legitimately advance after that
# pin; requiring it to remain at the historic SHA would reject the exact
# source snapshot that this runner has already verified.
[[ -z "$(git -C "$TACHIKO_SOURCE" status --porcelain)" ]] || {
  echo "PRECONDITION_UNMET: TACHIKO_SOURCE is dirty" >&2; exit 2
}
GODOT_PATH=$(command -v "$GODOT_BIN") || {
  echo "PRECONDITION_UNMET: GODOT_BIN is not executable" >&2; exit 2
}

TACHIKO_WORKTREE=$(mktemp -d "$WORK/richman4-tachiko-m7-tachiko.XXXXXX")
[[ "$TACHIKO_WORKTREE" == "$WORK/"* && -d "$TACHIKO_WORKTREE" ]] || {
  echo "FAIL: Tachiko worktree escaped M7 WORK" >&2; exit 1
}
git -C "$TACHIKO_SOURCE" worktree add --detach "$TACHIKO_WORKTREE" "$TACHIKO_SHA" >/dev/null

echo "CANDIDATE_HEAD=$CANDIDATE_HEAD"
echo "TACHIKO_SHA=$TACHIKO_SHA"
echo "TACHIKO_SOURCE=$TACHIKO_SOURCE"
echo "TACHIKO_GIT_DIR=$TACHIKO_GIT_DIR"
echo "TACHIKO_WORKTREE=$TACHIKO_WORKTREE"
echo "WORK=$WORK"

CHECKER="${SOURCE_ROOT}/tests/tachiko_fate_events_mirror/check_fate_events.py"
WITNESS="${SOURCE_ROOT}/tests/tachiko_fate_events_mirror/source_oracle.gd"
uv run --no-project --offline python "$CHECKER" --self-test --source "$SOURCE_ROOT/game/core/fate_events.gd"
godot_rc=0
"$GODOT_PATH" --headless --path "$SOURCE_ROOT" --script "$WITNESS" >"$WORK/godot.log" 2>&1 || godot_rc=$?
[[ "$godot_rc" == 0 ]] || { echo "FAIL: Godot M7 witness exited $godot_rc" >&2; cat "$WORK/godot.log" >&2; exit 1; }
uv run --no-project --offline python "$CHECKER" --source "$SOURCE_ROOT/game/core/fate_events.gd" --godot-log "$WORK/godot.log"
sed -n 's/^RICHMAN4_FATE_EVENTS_ORACLE=//p' "$WORK/godot.log" >"$WORK/candidate.json"
[[ -s "$WORK/candidate.json" ]] || { echo "FAIL: empty M7 Godot candidate" >&2; exit 1; }

mkdir -p "$WORK/adapter-src/src"
cp "$SOURCE_ROOT/tools/tachiko_fate_events_mirror/adapter.rs" "$WORK/adapter-src/src/main.rs"
printf '%s\n' \
  '[package]' \
  'name = "richman4-tachiko-fate-events-mirror"' \
  'version = "0.1.0"' \
  'edition = "2024"' \
  '[dependencies]' \
  'serde = { version = "1.0", features = ["derive"] }' \
  'serde_json = "1.0"' \
  "tachiko-storage = { path = \"$TACHIKO_WORKTREE/crates/storage\" }" \
  "tachiko-workspace-engine = { path = \"$TACHIKO_WORKTREE/crates/workspace-engine\" }" \
  >"$WORK/adapter-src/Cargo.toml"

cargo build --manifest-path "$TACHIKO_WORKTREE/Cargo.toml" -p tachiko-cli --offline --quiet
cargo build --manifest-path "$WORK/adapter-src/Cargo.toml" --offline --quiet
CLI="$TACHIKO_WORKTREE/target/debug/tachiko"
ADAPTER="$WORK/adapter-src/target/debug/richman4-tachiko-fate-events-mirror"
[[ -x "$CLI" && -x "$ADAPTER" ]] || { echo "FAIL: real CLI or M7 adapter binary missing" >&2; exit 1; }

# Exercise every frozen checker negative through the typed adapter as well.
# Each deliberate rejection must happen before create_new, leaving no partial
# .ro output behind. The checker remains the contract owner; this temporary
# extraction only supplies its frozen payloads to the post-Ready pipeline.
NEGATIVE_DIR="$WORK/frozen-negatives"
mkdir -p "$NEGATIVE_DIR"
uv run --no-project --offline python - "$CHECKER" "$NEGATIVE_DIR" <<'PY'
import importlib.util
import sys
from pathlib import Path

checker_path = Path(sys.argv[1])
output_dir = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("m7_checker", checker_path)
if spec is None or spec.loader is None:
    raise SystemExit("unable to load frozen checker")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)
oracle = checker.decode(checker.read(checker.ORACLE_PATH))
baseline = checker.oracle_projection(oracle)
for name, payload in checker.negative_cases(baseline).items():
    (output_dir / (name + ".json")).write_bytes(payload)
PY
for negative in "$NEGATIVE_DIR"/*.json; do
  negative_name=${negative##*/}
  negative_output="$WORK/negative-${negative_name%.json}.ro"
  if "$ADAPTER" candidate "$negative" "$negative_output" >"$WORK/${negative_name}.log" 2>&1; then
    echo "FAIL: frozen negative unexpectedly admitted: $negative_name" >&2
    exit 1
  fi
  [[ ! -e "$negative_output" && ! -L "$negative_output" ]] || {
    echo "FAIL: frozen negative wrote partial output: $negative_name" >&2
    exit 1
  }
done
echo "CANDIDATE_NEGATIVES_PASS: frozen checker corpus rejected without partial output"

"$ADAPTER" import-log "$WORK/godot.log" "$WORK/base.ro" "$WORK/base-import-ids.json"
"$CLI" validate "$WORK/base.ro"
"$CLI" roproj materialize "$WORK/base.ro" "$WORK/base.roproj"
"$CLI" roproj validate "$WORK/base.roproj"
"$ADAPTER" compare-ro-roproj "$WORK/base.ro" "$WORK/base.roproj"

# A lexical negative zero is the integer zero, and must be admitted without
# changing the resulting canonical .ro.  Transform only the exact fate_id 0
# lexeme emitted by the real Godot witness, then exercise the typed adapter and
# real Tachiko validator.  Keep the fresh output boundary explicit so a failed
# admission cannot leave a partial artifact behind.
NEGATIVE_ZERO_CANDIDATE="$WORK/negative-zero-candidate.json"
NEGATIVE_ZERO_RO="$WORK/negative-zero.ro"
uv run --no-project --offline python - "$WORK/candidate.json" "$NEGATIVE_ZERO_CANDIDATE" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_bytes()
needle = b'"fate_id":0'
if source.count(needle) != 1:
    raise SystemExit("expected one canonical fate_id 0 in real Godot candidate")
transformed = source.replace(needle, b'"fate_id":-0', 1)
if transformed == source or transformed.count(b'"fate_id":-0') != 1:
    raise SystemExit("negative-zero candidate transform crossed its lexical boundary")
Path(sys.argv[2]).write_bytes(transformed)
PY
[[ ! -e "$NEGATIVE_ZERO_RO" && ! -L "$NEGATIVE_ZERO_RO" ]] || {
  echo "FAIL: negative-zero output unexpectedly pre-existed" >&2; exit 1;
}
if ! "$ADAPTER" candidate "$NEGATIVE_ZERO_CANDIDATE" "$NEGATIVE_ZERO_RO" >"$WORK/negative-zero.log" 2>&1; then
  echo "FAIL: lexical negative-zero candidate was rejected" >&2
  cat "$WORK/negative-zero.log" >&2
  [[ ! -e "$NEGATIVE_ZERO_RO" && ! -L "$NEGATIVE_ZERO_RO" ]] || {
    echo "FAIL: rejected negative-zero candidate wrote partial output" >&2; exit 1
  }
  exit 1
fi
[[ -f "$NEGATIVE_ZERO_RO" && ! -L "$NEGATIVE_ZERO_RO" ]] || {
  echo "FAIL: negative-zero candidate did not produce a regular .ro" >&2; exit 1
}
"$CLI" validate "$NEGATIVE_ZERO_RO"
cmp "$WORK/base.ro" "$NEGATIVE_ZERO_RO"
echo "NEGATIVE_ZERO_PASS: lexical -0 admitted, Tachiko-validated, and byte-equivalent to base.ro"

layout_sha256() {
  local tree=$1
  find "$tree" -print | LC_ALL=C sort | while IFS= read -r path; do
    local relative
    if [[ "$path" == "$tree" ]]; then relative=.; else relative=${path#"$tree"/}; fi
    if [[ -L "$path" ]]; then
      printf 'L %s %s\n' "$relative" "$(readlink "$path")"
    elif [[ -d "$path" ]]; then
      printf 'D %s\n' "$relative"
    elif [[ -f "$path" ]]; then
      printf 'F %s %s\n' "$relative" "$(shasum -a 256 "$path" | cut -d' ' -f1)"
    else
      echo "FAIL: unsupported project tree entry: $path" >&2; exit 1
    fi
  done | shasum -a 256 | cut -d' ' -f1
}
sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }

BASE_RO_SHA=$(sha256 "$WORK/base.ro")
if "$ADAPTER" import-log "$WORK/godot.log" "$WORK/base.ro" >"$WORK/ro-collision.log" 2>&1; then
  echo "FAIL: existing .ro collision unexpectedly accepted" >&2; exit 1
fi
[[ "$BASE_RO_SHA" == "$(sha256 "$WORK/base.ro")" ]] || { echo "FAIL: .ro collision changed bytes" >&2; exit 1; }
BASE_LAYOUT_HASH=$(layout_sha256 "$WORK/base.roproj")
if "$CLI" roproj materialize "$WORK/base.ro" "$WORK/base.roproj" >"$WORK/roproj-collision.log" 2>&1; then
  echo "FAIL: existing .roproj collision unexpectedly accepted" >&2; exit 1
fi
[[ "$BASE_LAYOUT_HASH" == "$(layout_sha256 "$WORK/base.roproj")" ]] || { echo "FAIL: .roproj collision changed layout" >&2; exit 1; }

"$CLI" export "$WORK/base.roproj" "$WORK/base-runtime.json"
"$ADAPTER" normalize "$WORK/base-runtime.json" "$WORK/base.json"

# Runtime normalization must reject non-integral lexemes that a lossy float
# conversion could round or underflow, without leaving any output artifact.
RUNTIME_PRECISION_NEGATIVES="$WORK/runtime-precision-negatives"
mkdir -p "$RUNTIME_PRECISION_NEGATIVES"
uv run --no-project --offline python - "$WORK/base-runtime.json" "$RUNTIME_PRECISION_NEGATIVES" <<'PY'
import sys
from pathlib import Path

runtime_path = Path(sys.argv[1])
output_dir = Path(sys.argv[2])
baseline = runtime_path.read_bytes()
needle = b'"fate_id": 0.0'
if baseline.count(needle) != 1:
    raise SystemExit("expected one canonical fate_id 0.0 in real runtime export")
for name, lexeme in (
    ("underflow", b"1e-400"),
    ("rounded", b"1.0000000000000001"),
):
    (output_dir / (name + ".json")).write_bytes(baseline.replace(needle, b'"fate_id": ' + lexeme, 1))
PY
for precision_negative in "$RUNTIME_PRECISION_NEGATIVES"/*.json; do
  precision_name=${precision_negative##*/}
  precision_output="$WORK/runtime-precision-${precision_name%.json}.json"
  if "$ADAPTER" normalize "$precision_negative" "$precision_output" >"$WORK/${precision_name}.log" 2>&1; then
    echo "FAIL: runtime precision negative unexpectedly normalized: $precision_name" >&2
    exit 1
  fi
  [[ ! -e "$precision_output" && ! -L "$precision_output" ]] || {
    echo "FAIL: runtime precision negative wrote partial output: $precision_name" >&2
    exit 1
  }
done
echo "RUNTIME_PRECISION_NEGATIVES_PASS: underflow and rounded lexemes rejected without output"

"$ADAPTER" identity "$WORK/base.roproj" "$WORK/base-persisted-ids.json"
cmp "$WORK/base-import-ids.json" "$WORK/base-persisted-ids.json"

# Repeat the exact source and reopen the persisted project through the real
# storage loader; all semantic bytes and opaque identities must remain stable.
"$ADAPTER" import-log "$WORK/godot.log" "$WORK/repeat.ro" "$WORK/repeat-import-ids.json"
cmp "$WORK/base.ro" "$WORK/repeat.ro"
"$CLI" roproj materialize "$WORK/repeat.ro" "$WORK/repeat.roproj"
"$CLI" roproj validate "$WORK/repeat.roproj"
"$CLI" export "$WORK/repeat.roproj" "$WORK/repeat-runtime.json"
"$ADAPTER" normalize "$WORK/repeat-runtime.json" "$WORK/repeat.json"
"$ADAPTER" identity "$WORK/repeat.roproj" "$WORK/repeat-persisted-ids.json"
cmp "$WORK/base.json" "$WORK/repeat.json"
cmp "$WORK/base-import-ids.json" "$WORK/repeat-import-ids.json"
cmp "$WORK/base-persisted-ids.json" "$WORK/repeat-persisted-ids.json"
[[ "$BASE_LAYOUT_HASH" == "$(layout_sha256 "$WORK/repeat.roproj")" ]] || { echo "FAIL: repeated project layout drift" >&2; exit 1; }
cp -R "$WORK/base.roproj" "$WORK/reopened.roproj"
"$CLI" roproj validate "$WORK/reopened.roproj"
"$ADAPTER" identity "$WORK/reopened.roproj" "$WORK/reopened-persisted-ids.json"

# Reordered presentation input must retain event-code keyed entities.
"$ADAPTER" reorder "$WORK/candidate.json" "$WORK/reordered-candidate.json"
"$ADAPTER" candidate "$WORK/reordered-candidate.json" "$WORK/reordered.ro"
"$CLI" validate "$WORK/reordered.ro"
"$CLI" roproj materialize "$WORK/reordered.ro" "$WORK/reordered.roproj"
"$CLI" roproj validate "$WORK/reordered.roproj"
"$CLI" export "$WORK/reordered.roproj" "$WORK/reordered-runtime.json"
"$ADAPTER" normalize "$WORK/reordered-runtime.json" "$WORK/reordered.json"
"$ADAPTER" identity-ro "$WORK/reordered.ro" "$WORK/reordered-import-ids.json"
"$ADAPTER" identity "$WORK/reordered.roproj" "$WORK/reordered-persisted-ids.json"
cmp "$WORK/base.json" "$WORK/reordered.json"
cmp "$WORK/base.ro" "$WORK/reordered.ro"
cmp "$WORK/base-import-ids.json" "$WORK/reordered-import-ids.json"
cmp "$WORK/base-persisted-ids.json" "$WORK/reordered-persisted-ids.json"
[[ "$BASE_LAYOUT_HASH" == "$(layout_sha256 "$WORK/reordered.roproj")" ]] || { echo "FAIL: reordered project layout drift" >&2; exit 1; }

# Sole semantic edit: fate id 36 label only, preserving schema and entity identity.
"$CLI" set "$WORK/base.roproj" fate_event_36.display_name '違規入獄（M7驗證）' --output "$WORK/edited.ro"
"$CLI" validate "$WORK/edited.ro"
"$CLI" roproj materialize "$WORK/edited.ro" "$WORK/edited.roproj"
"$CLI" roproj validate "$WORK/edited.roproj"
"$ADAPTER" compare-ro-roproj "$WORK/edited.ro" "$WORK/edited.roproj"
"$ADAPTER" check-edit "$WORK/base.roproj" "$WORK/edited.roproj"
"$CLI" export "$WORK/edited.roproj" "$WORK/edited-runtime.json"
"$ADAPTER" normalize "$WORK/edited-runtime.json" "$WORK/edited.json"
"$ADAPTER" identity "$WORK/edited.roproj" "$WORK/edited-persisted-ids.json"

uv run --no-project --offline python "$CHECKER" \
  --projection "$WORK/base.json" --edited-projection "$WORK/edited.json" \
  --identity-map "$WORK/base-import-ids.json" --identity-map "$WORK/base-persisted-ids.json" \
  --identity-map "$WORK/repeat-import-ids.json" --identity-map "$WORK/repeat-persisted-ids.json" \
  --identity-map "$WORK/reordered-import-ids.json" --identity-map "$WORK/reordered-persisted-ids.json" \
  --identity-map "$WORK/reopened-persisted-ids.json" --identity-map "$WORK/edited-persisted-ids.json"

MANIFEST="$WORK/evidence-manifest.txt"
{
  echo "candidate_head=$CANDIDATE_HEAD"
  echo "tachiko_head=$TACHIKO_SHA"
  echo "godot_binary=$(sha256 "$GODOT_PATH")"
  echo "adapter_source=$(sha256 "$SOURCE_ROOT/tools/tachiko_fate_events_mirror/adapter.rs")"
  echo "runner_source=$(sha256 "$SOURCE_ROOT/tools/tachiko_fate_events_mirror/run_m7.sh")"
  echo "checker_source=$(sha256 "$CHECKER")"
  echo "witness_source=$(sha256 "$WITNESS")"
  echo "source_fate_events=$(sha256 "$SOURCE_ROOT/game/core/fate_events.gd")"
  echo "oracle_json=$(sha256 "$SOURCE_ROOT/tests/tachiko_fate_events_mirror/oracle.json")"
  echo "godot_witness_log=$(sha256 "$WORK/godot.log")"
  echo "tachiko_cli_binary=$(sha256 "$CLI")"
  echo "adapter_binary=$(sha256 "$ADAPTER")"
  for artifact in candidate.json base.ro repeat.ro reordered-candidate.json reordered.ro edited.ro base.json repeat.json reordered.json edited.json base-import-ids.json base-persisted-ids.json repeat-import-ids.json repeat-persisted-ids.json reordered-import-ids.json reordered-persisted-ids.json reopened-persisted-ids.json edited-persisted-ids.json; do
    echo "$artifact=$(sha256 "$WORK/$artifact")"
  done
  echo "base.roproj.layout_sha256=$(layout_sha256 "$WORK/base.roproj")"
  echo "repeat.roproj.layout_sha256=$(layout_sha256 "$WORK/repeat.roproj")"
  echo "reordered.roproj.layout_sha256=$(layout_sha256 "$WORK/reordered.roproj")"
  echo "edited.roproj.layout_sha256=$(layout_sha256 "$WORK/edited.roproj")"
} >"$MANIFEST"
echo "EVIDENCE_MANIFEST=$MANIFEST"
cat "$MANIFEST"
echo "M7_PASS: 37 typed fate-event rows, deterministic .roproj roundtrip/reopen, stable fate-id identities, isolated fate-id-36 label edit, frozen negatives and collisions"
echo "EVIDENCE_DIR=$WORK"
