# S19 source cards and tools held lists

Issue #160 restores the two ordinary source toolbar/hotkey entries as distinct
Panel11 held lists. The actual catalog-derived capability path controls admission.
Card slots preserve held order and duplicates. Tools compact positive source types
1–13 in source order, with separate visible-slot/source-ID mapping and quantities.
Equipped motorcycle/car return uses source command 14 in fixed final slot 14; an
engineering vehicle does not create that ordinary return command.

The source logical canvas is 640×480. Panel11 chunks 0/1 draw at(14,130); selection
uses x[19,419), y[135,303), five columns × three rows with 80×56 stride. Left-down
latches a source ID, left-up commits it even outside the grid, release-only and
empty cells are inert, and right-up cancels. Empty entire lists remain reachable.
These logical coordinates do not depend on replacement texture pixel dimensions.

The card renderer centers text at panel-local(45+80col,33+56row). Tool sprites
use(29+80col,33+56row) minus the source graph anchors; quantities are right-aligned
at(79+80col,23+56row). The tool list does not add item-name text. Vehicle chunks 15/16
use local(325,117), or canvas(339,247). Text uses source size 20 and white foreground
with dark outline. Exact Windows font rasterization remains unverified. Pressed
items move down/right one logical pixel with top/left shading; exact source
background pixel shifting is not claimed.

The presenter only holds a detached snapshot. MainUI reuses existing validated
public core actions and target adapters. Passive or rejected use returns to the
list without consumption; target cancellation returns to the list; successful use
returns to the board or the existing reaction flow. Source vehicle return uses
public `set_vehicle(walking)`, preserving the accepted quantity 9→10 exception,
walking/dice 1 and shared supply. The complete target/reaction appearance remains
S22. Shop S20 and SALE S21 are outside this change.

The list and its target adapter hold modal/owner/generation ownership across
movement, AI, save/load/new-game and daily checkpoint boundaries. A canceled
target attempt cannot apply a queued old callback. Source close/reopen and
inventory/trustee handoffs preserve the prior window quit policy. Native tests
inject viewport events and `close_requested`; they do not prove physical OS input.

`tools/prepare_inventory_assets.py` prepares only Panel11 from the authorized
private source with pinned identity metadata, and references the existing private
scene images through an overlay. Backgrounds 0/1 and vehicle 15/16 are opaque;
icons 2–14 skip source WORD 0. No original/derived artwork is distributed here.
The canonical asset source remains the existing private Git/LFS manifest.

Validation uses the immutable ordinary-toolbar installed-catalog RED→GREEN,
source component fixtures, public action/lifecycle checks, affected subsystem
checks and native actual-art comparisons for both editions at 1×/2×. Shared source
art identity is not proof of every Game controller behavior. Original runtime,
physical input, the final integrated package, All36 and Mission #1 remain open.
