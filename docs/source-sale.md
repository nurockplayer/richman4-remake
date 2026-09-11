# Source SALE bulletin board

S21 ([Issue #164](https://github.com/nurockplayer/richman4-remake/issues/164))
is admitted from accepted S20 commit
`927cf76c57fe29590ee26dd0b94e2a1521d41002`. This document records the new
scope; implementation and acceptance are pending.

## Frozen source contract

Ordinary SALE entry opens the original player bulletin board. Each player
has seven compact offers, with stock, property, tool and card listing pickers,
source quantity/total-asking input, own cancellation, buyer YES/NO and return
to play. Listings coexist with holdings without escrow. The public model must
preserve durable offer identity/revision, same-item replacement, invalid-holding
cleanup, daily counters and save continuation. No seven-day expiry is established.

The buyer must hold the full asking amount in cash; successful settlement
credits the seller's deposit. Stock transfers use the exact quantity and source
float32 cost basis; property and finite inventory transfers use their existing
ownership/supply hooks. Source tool/card listings transfer one item. Reject
invalid, stale, over-capacity or unaffordable requests without partial mutation.
The source's positive stock cost below one is a required new accounting case.

Source evidence consists of the owner's pinned cached MJ static assembly and
selected Panel73/74 artwork, supported by the prepared offer-lifecycle,
acceptance-payment and listing-input notes. This is not original-runtime
equivalence. Reuse source amount/confirmation components and the latest private
shop overlay; original artwork, disassembly and derived images stay private.

## Verification boundary

Preserve a fixed meaningful RED at the exact predecessor through the installed
12-map catalog, normal new game and ordinary SALE entry before implementation.
Focused cases cover every listing category, capacity/bounds, seven/full/update,
cash-to-deposit payment, finite supply, low stock cost, stale actions, status/AI,
date and JSON continuation. Existing assertions remain unchanged.

Final gates require affected integration, one justified public full milestone,
both editions at 1x/2x through actual MainUI, source/actual image comparison,
independent final code/integration/visual review and exact-head hosted CI.
Injected viewport input is not physical OS evidence. S22, integrated packaging
and All36 acceptance remain outside this scope; earlier monthly failures and
native-focus HOLD are retained, not relabelled as PASS.
