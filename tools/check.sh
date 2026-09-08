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
run_checked "$GODOT_BIN" --headless --path . --script tests/save_shapes.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/map_loader.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/graph_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/calendar.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/setup_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tools/replay.gd -- 42 4
run_checked "$GODOT_BIN" --headless --path . --script tests/ui_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/map_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/scene_visuals.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/setup_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/audio_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/inventory_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/inventory_runtime.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/inventory_effects.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/inventory_property_effects.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/inventory_property_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/inventory_ui.gd
run_checked "$GODOT_BIN" --headless --path . --quit-after 5
python3 -m unittest discover -s tools -p 'test_*.py'
