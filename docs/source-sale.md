# Source SALE bulletin board

S21 ([Issue #164](https://github.com/nurockplayer/richman4-remake/issues/164))
is admitted from accepted S20 commit
`927cf76c57fe29590ee26dd0b94e2a1521d41002`. This document records the new
scope. The current branch is a functional draft checkpoint, stopped at the
owner-requested safe handoff. S21 acceptance is pending.

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
date and JSON continuation. Existing assertions remain unchanged except the owner-adjudicated single
`tests/stock_accounting.gd` subunit-cost assertion: the same fixture is accepted
by `StockAccounting.validate_player`; no other legacy assertion or stock formula
was changed. See PR #165 comments 5633815716 and 5634142422.

Final gates require affected integration, one justified public full milestone,
both editions at 1x/2x through actual MainUI, source/actual image comparison,
independent final code/integration/visual review and exact-head hosted CI.
Injected viewport input is not physical OS evidence. S22, integrated packaging
and All36 acceptance remain outside this scope; earlier monthly failures and
native-focus HOLD are retained, not relabelled as PASS.

## Functional checkpoint and next owner

Implemented: public durable SALE sessions and four listing categories, seven-slot
board/replacement, no escrow, full-cash payment to seller deposit with bank aggregate
headroom, finite inventory and property/stock transfer hooks, invalid-holding cleanup,
daily byte counters, source-derived bounded AI, and JSON continuation. Ordinary
MainUI toolbar and X route through a dedicated controller. Quantity/asking, own cancel,
buyer YES/NO, return, stale child/owner callbacks and modal blocking have focused checks.

This is a draft, not a fidelity or release completion. Panel73/74 is a private
66-frame overlay; the authorized six YES/NO frames use Game Data399 and MJ Data440
with equal decoded payload identity. The board portrait is still a placeholder and
explicitly makes `source_art_available()` false. Property presentation still needs
source-correct development/rent/lease formatting, and detail typography/art composition
needs completion. Exact source pointer warp, physical OS input, both-edition native
1x/2x comparison, confirmation visual/input coverage, full affected integration,
fresh independent final review and exact-head hosted gates remain pending.

Focused commands use Godot 4.7.2 and the existing Python runtime:

```sh
godot --headless --path . --script tests/stock_accounting.gd
godot --headless --path . --script tests/source_sale_stock_cost.gd
godot --headless --path . --script tests/source_sale_rules.gd
godot --headless --path . --script tests/source_sale_panel.gd
godot --headless --path . --script tests/source_sale_controller.gd
python3 tests/test_source_sale_assets.py
```

The actual catalog gate `tests/source_sale_catalog.gd` requires the pinned installed
12-map `RICHMAN4_MAP_CATALOG` (SHA-256
`ac6a07666ceb9d8b4f1be8a6df3d486a3ffbb1f643cd383fd58daf81c5449565`) and the
private `RICHMAN4_SCENE_MANIFEST` chained through SALE confirmation overlay
(SHA-256 `0bee35aab759500900879ef86a2d06e06e7241ceea6e77861eb5219afa83f52d`).
Configured asset tests require `SALE_PANEL7374_IDENTITY` and `SALE_SOURCE_ZIP`;
missing configuration is SKIPPED, never source-asset PASS. Original/derived assets
remain outside Git. Do not rebuild the corpus or weaken the FULL disk-space guard.

Resume only with new owner authorization. Start from live Issue #1, canonical
Issue #52, active Issue #164/PR #165 and repository AGENTS.md. Keep S20 and older
lanes frozen, preserve all recorded failed/setup attempts, and do not admit S22,
merge, force-push, package or claim All36 completion from this checkpoint.
