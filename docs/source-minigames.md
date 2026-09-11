# Source minigames S31–S33

Bounded recovery repairs the initial balloon native HOLD: one source random
bucket per empty slot, lane exclusion below y300, decrement-before-movement
freeze handling and independent pop progression. Immutable focused recovery
checks reproduced5/4 RED and5/0 GREEN. Preserved native tests pass132/0 in each
edition at1x/2x, including natural balloon clicks. Independent final review
and exact-head hosted validation remain separate gates; all36 screens remain
UNACCEPTED and Mission completion is not claimed.

Normal original map event6 admits S32 企鵝挖寶, event7 S31 七彩氣球 and
event8 S33 喜從天降. Source object/facility priority remains authoritative.
The core owns a deterministic pending session with an encounter identity;
UI snapshots and callbacks cannot choose a reward. Completion adds point
coupons within the existing points bound exactly once, restores await_action,
and leaves ordinary end-turn/calendar/lottery/autosave ordering with the host.

Only a current human actor with animation enabled plays interactively. Native
AI, public-settings trustees and animation-off humans receive the source50–69
shortcut and result feedback. The host passes cached settings at admission;
no tick reads settings from disk. Active sessions exclude ordinary actions,
manual save and load. Active snapshots are deliberately not valid save files;
load/new-owner replacement cancels old controller generations. After return,
normal saves and deterministic continuation work as before.

## Controls and timing

- Balloon: source point/click,150×100ms active ticks, source16 slots and spawn
  buckets. IDs0–8 score1–9; ordinary addition clamps999 separately from
  special doubling/halving/question effects. Freeze20 stops movement while
  the deadline continues; speed modifiers double or halve upward velocity.
- Penguin: source Panel81 click plane and private81-record coordinate table,
  four ticks per DDA step and four ticks per dig. Invalid mask bytes cannot
  fall through to a nearest-cell hit. Walking/digging ignores new targets;
  local water detours retain the original target. Bomb ends play with prior
  points; source item counts and coupon weights are preserved.
- Catching: horizontal mouse follow,10 logical pixels per50ms when distance>8.
  Direction starts0 and stays latched after movement; collision precedes the
  new movement. Natural throwers, source arc/perspective, private active-frame
  hitboxes, separate bombs and the360-tick stop-throwing/airborne-drain boundary
  are modeled. Bombs retain already-earned points.

Render intervals accumulate fixed simulation ticks; focus loss and blocked
presentation pause both model and presentation time. Panel78 plays20 frames
at114ms separately from gameplay. Ending animation precedes a2second result
hold; penguin result clicks can shorten that final hold. Input coordinates are
Godot GUI-local logical coordinates, independent of source pixels or1x/2x
physical output. No OS cursor warp or physical-input automation is used.

## Private preparation

`tools/prepare_minigame_assets.py` reads the owner ZIP in place, extending a
new private scene manifest through the frozen predecessor's image symlink.
It only decodes Panel78–111 and the semantic catching_bomb effect (Game
Data485 / MultiverseJourney Data526), plus raw Panel81 input and Panel92
background. SMP WORD0 is transparent only for overlay roles;0x8000 black
stays opaque. HUD digits0–9 and backgrounds are opaque. FLIC palette index0
is transparent. No original assets or derived caches belong in GitHub.

Use RICHMAN4_SCENE_MANIFEST for the new scene-manifest.json and
RICHMAN4_MINIGAME_MANIFEST for its manifest.json (or the scoped private
.local/source-minigames-scene link). A pinned private coordinate JSON and
source thrower lookup are explicit preparation inputs. Canonical private
asset repository authority is unchanged; this batch does not package/export.

## Evidence and explicit limits

The installed twelve-map catalog acceptance was pinned before implementation
and reproduced25 checks/18 behavioral failures, then25/0 unchanged. Five
additional source assertions reproduced missing natural catching, wrong actor
baseline, missing drain, invalid-mask fallback and render-tick loss. Initial
worker snapshots/tests remain privately preserved; their instant penguin dig
and instant catching completion at360 were rejected against source, not used
as accepted contracts. Corrected focused tests preserve those behavioral
assertions with source timing and use public nativeAI/trustee setup.

Source observations are from the pinned MJ controller and documented bounded
Game binary matches, not a new original-runtime replay. Exact first-WM_PAINT
prelude timing, repeat-entry carried throwAt value and detailed sound/voice
remain uncertain. The Godot catcher does not warp the global mouse cursor.
The terminal drain safely waits for an already-started bomb throw instead of
letting a source local flag discard an emission in that same tick. Numeric
representability uses existing1e12 bounds rather than source16-bit overflow.
Missing private art is explicit fallback and never counts as visual acceptance.
Physical OS input remains PRECONDITION_UNMET; monthly PR138 native focus HOLD
and all36-screen UNACCEPTED status remain independent.

## Running the batch gates

`bash tools/check.sh` includes the asset-free model, source-reclaim, balloon
recovery, panel and controller tests. When `RICHMAN4_MAP_CATALOG` is supplied,
it also runs immutable installed-catalog/core tests and the actual-host return
and daily-autosave test. Without the private catalog those gates explicitly
report PRECONDITION_UNMET; public CI does not prove installed content access.
The separate local installed-catalog checks remain required evidence.

Native replay uses `godot --path . --script tests/source_minigame_native.gd`
with `RICHMAN4_MAP_CATALOG`, `RICHMAN4_SCENE_MANIFEST`,
`RICHMAN4_MINIGAME_EDITION` (Game or MultiverseJourney), and
`RICHMAN4_MINIGAME_CAPTURE` (private output directory). The private input
manifest must also resolve via the environment or scoped symlink above.
These are viewport-injected events and focus notifications, not physical OS
input. Preserved native assertions prove natural balloon scoring, penguin
click-plane walking, catching follow/natural throws, intro/result and return;
they do not establish original-runtime timing or physical input equivalence.

An independent FFmpeg9 RGB oracle matched all78 declared FLIC frames across
Panel78 and Data526 in both editions against the unchanged derived PNGs.
Each physical extra frame is the first-frame loop duplicate. This verifies
RGB decoding within the declared frame range, not alpha caller semantics,
resource mapping, actual runtime cadence or whole-controller equivalence.

The final bounded mapping extension uses one `catching_bomb` descriptor in
the prepared scene for both resource selection and ending duration. Game485
and MJ526 have byte-identical payloads; Game526 is a different animation and
is never substituted or relabeled. The importer verifies both archives and
payload identity. `--bomb-overlay-only` prepares just the corrected pair over
a frozen scene image symlink; it does not alter predecessor assets.

The immutable native resource gate reproduced16 checks/6 failures and then
17/0 (the additional source-chunk assertion becomes available after repair).
It probes actual renderer frame selection and the911ms ending/912ms result
boundary. Supplemental legal viewport input produced nonzero penguin and
catching scores, then natural bomb endings in both editions at1x/2x:116/0,
24 additional native images. No item lists, rewards or gameplay RNG were
injected. Actor placement and palette-index0 transparency remain the bounded
source caller contract, not a claim of original-runtime playback.

Set `RICHMAN4_MINIGAME_NATIVE_CHECKS=1` alongside the required private paths
to opt into the native gates from `tools/check.sh`. The ordinary full suite
remains headless. On macOS use installed Bash5 when executing this repository's
existing BASHPID-dependent full script; no shell/toolchain migration is made.
Local milestone evidence was composed from the successful prefix, explicit
Bash5 continuation, unchanged map_ui replay after the optional dispatcher hook
guard, and the successful remaining checks. Final hosted full validation is
a separate exact-HEAD gate.
