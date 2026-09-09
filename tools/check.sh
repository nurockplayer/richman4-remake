#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-godot}"
mkdir -p .local build
# Private source/derived data under .local is read through explicit FileAccess
# paths. Keep Godot from scanning/importing those multi-GB local caches into a
# second per-worktree .godot/imported copy.
touch .local/.gdignore build/.gdignore
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
run_checked "$GODOT_BIN" --headless --path . --script tests/audio_bootstrap.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/inventory_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/inventory_runtime.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/inventory_effects.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/inventory_property_effects.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/inventory_property_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/inventory_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/facility_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/facility_save_recovery.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/facility_ai.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/facility_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/gods_map_loader.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/gods_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/gods_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/gods_recovery.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/gods_review_regressions.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/gods_ai.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/gods_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/gods_facility_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/company_market.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/company_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/company_finance.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/company_insurance.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/company_market_cards.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/company_ai.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/company_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/company_json_index.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/company_construction.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/company_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/status_loader.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/status_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/status_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/status_ai.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/status_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/hazard_loader.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/hazard_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/hazard_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/hazard_ai.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/hazard_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/hazard_review.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/property_card_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/property_card_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/property_card_ai.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/property_card_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/property_card_loader.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/remodel_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/remodel_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/remodel_ai.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/remodel_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/remodel_loader.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/remodel_mutations.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/remodel_review.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/research_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/research_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/research_loader.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/research_mutations.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/research_construction.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/research_landing.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/research_followup.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/research_admission.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/research_status_cards.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/research_ai.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/research_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/trap_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/trap_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/trap_ai.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/trap_ui.gd
run_checked "$GODOT_BIN" --headless --path . --quit-after 5
python3 -m unittest discover -s tools -p 'test_*.py'

# v13 building-card acceptance.
run_checked "$GODOT_BIN" --headless --path . --script tests/building_card_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/building_card_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/building_card_loader.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/building_card_ai.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/building_card_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/building_card_type_guard.gd

# God cards reuse the current save schema.
run_checked "$GODOT_BIN" --headless --path . --script tests/god_card_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/god_card_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/god_card_loader.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/god_card_ai.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/god_card_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/god_card_distance.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/god_card_bankruptcy.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/god_card_ai_terminal.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/engineering_vehicle_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/engineering_vehicle_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/engineering_vehicle_ai.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/engineering_vehicle_ui.gd
