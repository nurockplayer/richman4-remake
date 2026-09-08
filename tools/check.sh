#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-godot}"
mkdir -p .local build
touch build/.gdignore
run_checked() {
  local check_log
  check_log="$(mktemp "$PWD/.local/check.XXXXXX")"
  if ! "$@" >"$check_log" 2>&1; then
    cat "$check_log"
    return 1
  fi
  cat "$check_log"
  # Godot can report a script parse/runtime error yet return status zero.
  if grep -Eq '(^|[[:space:]])(SCRIPT ERROR|ERROR):' "$check_log"; then
    echo "Godot reported an error; evidence: $check_log" >&2
    return 1
  fi
}
run_checked "$GODOT_BIN" --headless --editor --path . --import
run_checked "$GODOT_BIN" --headless --path . --script tests/run.gd
run_checked "$GODOT_BIN" --headless --path . --script tools/replay.gd -- 42 4
run_checked "$GODOT_BIN" --headless --path . --quit-after 5
python3 -m unittest discover -s tools -p 'test_*.py'
