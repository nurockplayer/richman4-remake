# S04 trustee settings

The ordinary AI toolbar opens the source-sized 435×355 trustee panel on the
640×480 logical canvas at (102,62). Only living, non-bankrupt original humans
appear. The initial-human metadata remains authoritative when current control
changes. Selecting a different row precedes toggling that row; the selected
human's card/tool flags, personality and two ratios remain draft until OK.
Cancel, right-button release and the hosting window's close signal discard the
draft. Each opening owns its callbacks and the current GameState identity.

## Runtime boundary

`TrusteePreferences` stores a small optional map in `trustee_preferences`, keyed
by canonical string player IDs. Each entry has exactly `use_cards`, `use_tools`,
`personality`, `cash_ratio` and `stock_ratio`. All eligible rows commit atomically,
including settings for humans who are not delegated. Dead original actors keep
previous preferences without changing their control flags. Native AI never
acquires trustee identity. `init_cash_ratio` stays opening metadata, and the
existing `set_player_ai` fixture/public helper keeps its prior contract.

Save validation rejects malformed or foreign-actor preference records. JSON
integer-valued numbers are accepted without accepting fractional values or
string coercion. The optional field is a feature-state extension, with no new
legacy gameplay-version branch or historical replay.

`run_ai_turn` remains the deterministic public dispatcher. During that dispatch,
card/tool requests obey the saved flags; existing pending trap, finance, auction,
sleep, movement and actor handoffs keep their ownership. Bank balancing uses
cash/(cash+deposit) and existing transfer limits, once per dispatched turn, with
the source's effective 10–90% clamp even though the UI permits 0–100. Stock
purchases respect the target ratio of holdings to cash+deposit+holdings; zero
prevents investment. Corporate share acquisition is subject to the same budget.

## Bounded source decisions

- Personality has a real conservative/normal/aggressive property-upgrade reserve
  of 1000/500/0 in the existing policy. This is a reversible interpretation;
  exact original character-specific personality tactics are not established.
- Exact source early/late-month bank target adjustments are deferred. Existing
  deterministic trading cadence and security selection are retained.
- All-trustee Escape or right-button release sets a deferred recovery request.
  At the next real actor admission, recover original human player0 as observed
  in the Game source; if player0 is no longer eligible, use the first living
  original human. Native AIs remain AIs. MJ help omits the Game recovery wording;
  this does not prove different behavior, so the same bounded policy applies.
- Active bank/monthly/help/options, movement, pending responses and daily
  autosave prevent opening trustee settings. Completing a draft cannot advance
  the game or bypass these pending actions. Daily snapshots still follow report
  acknowledgment and precede the next actor's work.

## Assets and verification limits

Each edition's actual Panel77 was independently decoded and matched to its
archive hash. Both payloads are byte-identical and contain 18 chunks; the
runtime still requests the current edition explicitly. The bounded exporter
includes these chunks and rejects incomplete atlases. No original pixels are
part of this repository. Missing private assets remain an explicit fallback.

Focused public AI, save/continuation and MainUI tests are separate from source
art captures and native injected lifecycle evidence. Physical OS input, the
inherited monthly-focus HOLD, Wine comparison, current packaging and all 36
screen/flow acceptance groups remain open. This component does not close the
Mission or a whole-screen acceptance gate.
