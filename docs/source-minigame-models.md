# Source minigame models

`SourceMinigameModel` is the deterministic gameplay boundary for S31 七彩氣球,
S32 企鵝挖寶 and S33 喜從天降. It is a `RefCounted` object and has no scene,
wall-clock timer, save I/O, or presentation dependency:

```gdscript
var model := SourceMinigameModel.new().configure("balloon", seed, input_data)
model.pointer(Vector2(320, 240), true)
model.tick()
var view_model: Dictionary = model.snapshot()
var points: int = model.reward()
```

`tick()` is one source step: 100 ms for balloons and penguins, 50 ms for
catching. The active deadlines are 150, 150 and 360 steps respectively. A
controller owns intro/result playback and decides whether focus permits a
step. `pointer()` receives source coordinates in the independent 640×480
canvas; it does not convert viewport pixels and it preserves the supplied
position in the snapshot.

The snapshot is a deep copy. Its stable common fields are `kind`, `seed`,
`tick`, `elapsed_ms`, `tick_ms`, `deadline_ticks`, `active`, `finished`,
`finish_reason`, `pointer`, `pressed`, `score` and `reward`.

Balloon snapshots additionally expose `balloons`, `counts`, `effects`,
`special_effect` and `spawn_attempts`. A balloon record contains `slot`, `id`,
`x`, `y`, `phase` and `pop_frame`. IDs 0–8 award ID+1 and ordinary additions
cap at 999. ID 9 doubles, ID 10 halves with integer truncation, and ID 11
selects the six source question-mark outcomes. Question-mark selection resets
the previous freeze and movement modifier; freeze consumes active ticks while
the 15-second deadline continues. The source spawn buckets, lanes, speeds,
inclusive hit bounds, overlap behavior and 16-slot lifecycle are represented
in the model.

Penguin snapshots expose `current_cell`, `target_cell`, `penguin_cell`,
`penguin_position`, `movement_state`, `movement_frame`,
`movement_ticks_per_step`, `reroute`, `counts`, `items_found` and `dig_count`.
The optional `penguin_mask` input is a 640×480 byte plane; a nonzero byte maps
to `(id % 9, id / 9)`. The optional `penguin_grid` input supplies exact source
anchors as an array of `Vector2i` records. For focused tests, `cell_items` may
map a cell index or `"x,y"` to item IDs 1–5. If no item map is supplied, a
deterministic source distribution places the source 3/12/3/9/1 item counts across
the 64 valid cells; the snapshot marks this as `grid_source`.

Penguin movement uses centered 16.16 coordinates, signed truncation toward
zero, four ticks per grid step, the source central-hole detour, and digs only
when the requested target is reached. Item IDs are bomb, coin, pink gem, blue
gem and pale cyan diamond. The score is `coin*5 + pink*12 + blue*8 + cyan*20`;
a bomb ends the active game while preserving points already earned.

Catching snapshots expose the source actor at y380, a direction latch, exact
private frame hitboxes when provided, sixteen first-free projectile slots,
the ordinary thrower state machine and a separate opposite-side bomb thrower.
Natural ordinary types follow the source rand20 buckets: coin45%, ingot30%,
bag15%, chest10%. Items start at y100 with velocity-16, arc upward, then fall
at source type speeds with perspective-scaled horizontal drift and sprites.
The360-tick deadline stops ordinary throwing while existing items drain;
terminal completion forbids later catches. A caught bomb preserves earned
counts. Tests may supply explicit item records, but normal play needs no such
injection. Private character frame metadata supplies the collision rectangle;
the source direction-zero initial state cannot catch, and collision precedes
mouse-follow movement. The original OS cursor warp is intentionally omitted.

`reward()` is calculated from model state and is always an integer bounded by
the existing 1e12 points representability limit. A caller cannot supply or
replace a reward through `configure()`; settlement and points ownership remain
the core/controller boundary.
