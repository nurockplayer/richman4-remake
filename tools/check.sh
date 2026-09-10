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
# Issue #104 bank transfer headroom and UI cap acceptance.
run_checked "$GODOT_BIN" --headless --path . --script tests/bank_headroom.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/bank_headroom_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/map_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/board_camera.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/scene_visuals.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/setup_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/market_entry_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/market_entry_active_presentation.gd
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
run_checked "$GODOT_BIN" --headless --path . --script tests/stock_accounting.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/stock_presentation.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/legacy_stock_bounds.gd
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

# Issue #81 時光機與傳送機 target, save, deterministic and UI acceptance.
run_checked "$GODOT_BIN" --headless --path . --script tests/time_transport_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/time_transport_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/time_transport_ui.gd

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

# Original 飛彈 and 核子飛彈 target, save and backpack UI acceptance.
run_checked "$GODOT_BIN" --headless --path . --script tests/missiles_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/missiles_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/missiles_ui.gd

# Original 拍賣 card bidding, settlement, save continuation and UI.
run_checked "$GODOT_BIN" --headless --path . --script tests/auctions_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/auctions_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/auctions_ui.gd

# Original 同盟 card runtime, save, finance, UI and focused boundary checks.
run_checked "$GODOT_BIN" --headless --path . --script tests/alliances_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/alliances_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/alliances_financial.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/alliances_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/alliances_boundary.gd

# Original 搶奪 card transfer, save continuation and picker integration.
run_checked "$GODOT_BIN" --headless --path . --script tests/theft_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/theft_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/theft_eviction.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/theft_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/sleep_cards_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/sleep_cards_lifecycle.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/sleep_cards_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/sleep_cards_release.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/sleep_cards_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/sleep_cards_modal.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/sleep_cards_focus.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/sleep_cards_ai.gd

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

run_checked "$GODOT_BIN" --headless --path . --script tests/engineering_vehicle_action_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/engineering_vehicle_stationary.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/engineering_vehicle_capability.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/engineering_vehicle_restore_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/engineering_vehicle_god_ai.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/engineering_vehicle_card_ai.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/engineering_vehicle_landing_ai.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/news_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/news_eligibility.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/news_price_and_rewards.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/news_save_limits.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/news_public_tax.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/news_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/news_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/news_bank_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/news_timing.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/fate_timing.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/movement_presentation.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/movement_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/movement_continuation.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/fate_flow.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/fate_contract_regressions.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/fate_state_contract.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/fate_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/fate_graph.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/fate_public_charge.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/fate_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/financial_fees.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/financial_tax.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/financial_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/financial_ui.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/financial_focus.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/financial_boundaries.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/financial_source_save.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/financial_fee_cap.gd
run_checked "$GODOT_BIN" --headless --path . --script tests/sleep_fee_copy.gd
