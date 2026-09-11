# Source calendar and three view modes

Issue #153 implements S07/S35 presentation on the frozen PR #152 baseline. This is a bounded component/integration milestone, not all-screen or packaged-game acceptance.

## Two independent presentation choices

`SystemSettings.view` selects the source window group: 0 gives the full 200×280 player HUD and calendar; 1 gives the full HUD and minimap; 2 gives a compact 200×80 HUD, minimap at logical y80 and calendar at y280. The right column begins at logical x440. Source hotkey slot7 (default TAB) cycles 0→1→2→0. Slot6 has no confirmed consumer and remains unused. Slot17 (`M`) remains the full-map command.

The calendar's sun and moon choose day and month styles independently. `source_calendar_panel.gd` is consumed by the normal game shell, reads only the detached snapshot date, and uses `GameCalendar` including its original divisible-by-four leap rule (2100 remains a leap year). A missing or invalid date remains unavailable. No system-clock computation or regional holiday guessing enters the calendar.

## Provenance and layout

Private original `rich4.asm` functions `fcn_00415f69`, `fcn_004166f8`, `fcn_004169bc` and `fcn_00416e6d` establish the three layouts and compact HUD. Panel0 chunk4 is the compact background. Panel2 chunks0–3 are seasonal day backgrounds, 4–7 are month backgrounds with embedded weekday headers, and chunks8/11 supply the day-style sun/moon icons. The original manual printed page10 shows numeric month, day/week text, Sunday red and the current-day outline. Private references and derived images are excluded from Git.

The source season table is Jan winter; Feb–Apr spring; May–Jul summer; Aug–Oct autumn; Nov–Dec winter. Month-grid first-day centers are (470+23×Sunday-first-weekday,378), advancing rows by14 logical units. The current-day outline is20×14 from center−(10,6). Calendar control hitboxes are x448–474 and478–504 inclusive, y288–314 inclusive. Texture pixel dimensions, logical geometry and output resolution remain independent.

## Persistence and input

Successful initial settings load applies view. Options receives a validated integer runtime view overlay only after a successful settings read; corrupt/unavailable reads remain explicit errors. TAB changes presentation in memory without a disk write. Reopening Options and cancelling preserves the runtime choice. Only successful parent OK writes and applies the chosen view. Failed writes preserve runtime view and permit retry/cancel. The six-key settings schema stays unchanged. The existing quit path does not add a new persistence write; a TAB choice is saved only through a later successful Options OK. Day/month style remains runtime presentation state.

The view key is dispatched before Godot focus traversal and uses the existing MainUI title/modal/movement/pending-action gates. Hidden tabs and calendar regions do not capture pointer input. Camera/minimap projection and full-map state remain separate. Display changes do not mutate game saves or RNG.

## Verification limits

Focused and affected UI tests cover source geometry, dates, styles, input gates, persistence, camera continuity and save/RNG invariance. Native source-art captures use the actual installed 12-map catalog with normal game creation. Injected viewport inputs and native rendering do not establish physical OS keyboard/mouse focus. The inherited monthly focus HOLD, physical hotkey PRECONDITION_UNMET, Wine comparison, current package and all36 screen acceptance remain open. Regional holiday text/art and exact font rasterization remain bounded presentation uncertainty.

## Initial review recovery

The initial 166043ac review found two P2: black Sunday day-style text and a hidden mode 1 calendar reopened by ordinary snapshot refresh. Recovery preserves the standalone presenter's `present()` opening contract and reasserts shell-owned view visibility after presentation; Sunday day and weekday use source red. New immutable behavioral checks exercise weekday→Sunday→weekday, same/new-date ordinary MainUI refresh, modes 0/1/2, and hidden-pointer/stale-callback exclusion at 1x/2x. The initial review and successful evidence remain historical; recovery requires its own exact-head validation and independent review.
