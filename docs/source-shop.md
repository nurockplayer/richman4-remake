# Source shop (S20)

Complete-company graph games open a finite human shop visit on an ordinary event-15 landing. The visit belongs to its player, node, and turn; card offers are weighted copies sampled once, and available source tools appear once in source order. Repainting, tab changes, and save/load preserve offers. Purchases and sales are one item per source interaction. Sold offer rows remain holes, and held-card sales use the selected occurrence.

The core exposes `shop_visit_snapshot`, `acknowledge_shop_gift`, and `leave_shop`. Setup keeps the current default: player 0 is human and the remaining players are AI. Pending human visits have no ordinary actions and cannot be taken over by AI. AI visits trade directly and close synchronously without sampling human offer RNG. Venue gift and accumulated contribution reuse existing inventory and company accounting fields. Development saves missing both new visit fields receive an empty structural initialization; no save version changes.

MainUI presents the visit through a transient, owner- and visit-guarded controller on the 640×480 reference canvas. Source left-down buys or sells one row. Tabs and EXIT latch on down and activate on up; right-up closes. A pending owned-venue gift gates actions for 1.5 seconds of visible time. Shop modal lifetime blocks unrelated controls and saves, and window-close requests leave the shop.

`tools/prepare_source_shop.py` accepts only the bounded Panel10 source slice, preserves the resolved S19 scene references, and refuses publication when inherited paths are missing. It does not decode unrelated original art or make a full-package claim. Private source art stays outside this public repository.
