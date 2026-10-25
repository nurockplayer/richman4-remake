# Source calendar and three view modes

Port of the #154 S07/S35 calendar presentation onto current main. This is a bounded component/integration milestone, not all-screen or packaged-game acceptance.

## Two independent presentation choices

`SystemSettings.view` selects the source window group: 0 gives the full 200×280 player HUD and calendar; 1 gives the full HUD and minimap; 2 gives a compact 200×80 HUD, minimap at logical y80 and calendar at y280. The right column begins at logical x440. Source hotkey slot7 (default TAB) cycles 0→1→2→0; MainUI dispatches it in `_input` before Godot focus traversal. Slot17 (`M`) remains the separate full-map command.

The calendar's sun and moon choose day and month styles independently. `source_calendar_panel.gd` is consumed by the normal game shell, reads only the detached snapshot date, and uses `GameCalendar` including its original divisible-by-four leap rule (2100 remains a leap year). A missing or invalid date remains unavailable. No system-clock computation or regional holiday guessing enters the calendar.

## Provenance and layout

Private original `rich4.asm` functions `fcn_00415f69`, `fcn_004166f8`, `fcn_004169bc` and `fcn_00416e6d` establish the three layouts and compact HUD. Panel0 chunk4 is the compact background. Panel2 chunks0–3 are seasonal day backgrounds, 4–7 are month backgrounds with embedded weekday headers, and chunks8/11 supply the day-style sun/moon icons. The original manual printed page10 shows numeric month, day/week text, Sunday red and the current-day outline. Private references and derived images are excluded from Git; a missing catalog keeps the art-free fallback labels.

The source season table is Jan winter; Feb–Apr spring; May–Jul summer; Aug–Oct autumn; Nov–Dec winter. Month-grid first-day centers are (470+23×Sunday-first-weekday,378), advancing rows by14 logical units. The current-day outline is20×14 from center−(10,6). Calendar control hitboxes are x448–474 and478–504 inclusive, y288–314 inclusive. Texture pixel dimensions, logical geometry and output resolution remain independent.

## Persistence and input

A successful initial settings load applies view. Reopening the existing options presenter starts from the runtime view, so a TAB choice survives Options reopen/Cancel. TAB changes presentation in memory without a disk write; only a successful parent OK writes and applies the chosen view. Failed writes keep the change for the current run and stay explicit in the log, matching the existing options behaviour. The six-key settings schema stays unchanged. Day/month style is runtime presentation state.

The view key uses the existing MainUI title/modal/movement/pending-action gates. Hidden tabs and calendar regions do not capture pointer input. Camera/minimap projection and full-map state remain separate. Display changes do not mutate game saves or RNG.

## Verification limits

Focused and affected UI tests cover source geometry, dates, styles, input gates, persistence, camera continuity and save/RNG invariance. Native source-art captures from #154 are not repeated in this port; its headless checks are. Physical OS keyboard focus, the inherited monthly focus HOLD, Wine comparison and all-screen acceptance remain open. Regional holiday text/art and exact font rasterization remain bounded presentation uncertainty.
