# Source lottery purchase and draw

Issue #155 follows the frozen calendar milestone. This restores the S29/S30
lottery rules and entry points; it does not accept the whole screens or Mission.

The source contract is based on the owner-authorized Game and
MultiverseJourney executable regions and existing Panel resources. Private
source hashes, comparisons and images remain outside this public repository.

## Rules and integration

There are 36 exclusive numbers, 01–36. A human can buy with exactly 1,000 cash;
an AI requires more than 1,000. Each encounter permits one purchase, immediately
transferring 1,000 cash into the existing shared company `jackpot`. Cancel,
sold numbers and out-of-grid clicks do not buy anything. Normal source event9
nodes reach the lottery through the original map factory. Original company
capability owns its shared pool; smaller development boards do not acquire an
independent lottery economy.

On the 15th, dividend settlement precedes the lottery draw. An empty ticket
array advances the saved draw identity without drawing a number or opening a
lottery presentation. If any one player owns more than ten tickets, the number
is chosen uniformly among all sold numbers; otherwise it is chosen among all
36 numbers. The remake uses its saved deterministic RNG.

A winning owner receives the entire pool as cash, then every ticket and the
pool clear. If nobody owns the drawn number, both tickets and pool remain.
Bankruptcy clears only the bankrupt owner's tickets. These source oddities
are intentional; the rules do not implement monthly ticket expiration.

Core settlement is synchronous. The host queues detached dividend and lottery
presentations, then releases daily autosave and next-actor input. The source
pays at the end of its modal; this implementation settles before presenting
and makes acknowledgement financially inert. This internal timing deviation
preserves the player-facing modal order and deterministic saved continuation.
A saved elapsed-day identity prevents repeated settlement, and starting a new
game on the 15th does not replay a draw. Loaded event history is never used to
reopen a historical modal. Report players contain display identity only, not
copies of unrelated stock-accounting state.

## Explicit bounds

Cash and pool retain the existing 1e12 representation bound. A purchase whose
pool would overflow is refused. If a possible winner cannot receive the whole
pool, that date's draw is recorded as blocked without consuming lottery RNG,
truncating money, or clearing tickets. This is a bounded safety deviation at
an otherwise unrepresentable financial state.

The direct loss helper `_pay_from_player` currently routes creditor -1 losses
to the bank, whereas the original core's corresponding destination contributes
to the lottery pool. The existing bankrupt-company holdings contribution to
`jackpot` is reused. General event/god/tax loss routing remains an explicit
unrestored financial gap; this batch does not silently rewrite every existing
fee source or introduce a second pool.

Native rendering and injected input evidence do not prove physical OS input.
Physical input remains PRECONDITION_UNMET; the preceding monthly focus HOLD is
unchanged. No package, original runtime comparison or whole-screen acceptance
is implied by focused functional checks.

## Presentation bounds

The purchase scene reuses the baked number grid, source dealer/speech art,
source amount plaque and numeric glyphs. Source Panel14 loops at the observed
100 ms caller interval. Draw Panel16 and Panel17 progress at the observed
50 ms interval, with their source logical origins and palette-index-zero
transparency contract. No runtime FFmpeg or RGB-black color key is used.
The source initial/final hosts, participant icons and ticket digits are reused.
Pool values wider than the source glyph plaque use the complete Godot text
label, preserving the existing larger money representation bound.

Speech text uses concise Traditional Chinese equivalents and the existing
Godot font; exact original speech/audio cadence is not reproduced. A purchase
shows the original selected-number ring for 0.5 seconds before returning.
The draw uses the two decoded animation durations, then displays its result;
acknowledgement may skip presentation and cannot change financial settlement.
The detailed original dialogue/host micro-animation sequence is simplified.
The participant list follows the source's twelve displayed tickets per player
limit. Sold cells use a bounded darkening approximation instead of the source
palette-index transform. These are visible component limitations to review,
not a claim of whole-screen acceptance.

## Private asset preparation

Reuse the existing `richman4.scene-images/v1` scene manifest and the decoded
`richman4.original-images/v1` manifest containing Panel12/13/15. The bounded
helper reads the owner's ZIP in place and emits only Panel14/16/17 animation
frames and bounded SMP overlays. Existing scene images and opaque Panel12/15
backgrounds remain symlinked. Overlays are re-emitted from source 16-bit words:
only word zero becomes transparent; RGB black from nonzero words is retained.
Source, existing-cache and output hashes are recorded separately.

```sh
python3 tools/prepare_lottery_assets.py \
  --zip /private/source/original.zip \
  --base-manifest /private/source/scene/manifest.json \
  --existing-art /private/source/decoded/manifest.json \
  --output /private/source/lottery
RICHMAN4_SCENE_MANIFEST=/private/source/lottery/scene-manifest.json godot --path .
```

All paths above are placeholders for local owner-authorized files. Preparation
requires no runtime FFmpeg and publishes no original or derived asset files.
The generated manifest records source payload and output frame SHA256 values;
independent decode comparison is separate validation evidence.
