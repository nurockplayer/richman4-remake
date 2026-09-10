# S34 存檔檔位後端契約

`game/platform/save_slots.gd` 是給 save/load picker 使用的獨立 `RefCounted`
JSON 儲存層。它不會把讀出的棋局指定給 `MainUI.game_state`；呼叫端仍須在
既有 presentation gate 與 legacy 三股市確認流程完成後，才自行套用讀出的
snapshot。

## 路徑與檔位

```gdscript
const SaveSlots = preload("res://game/platform/save_slots.gd")
var storage := SaveSlots.new("user://richman4-save-slots", "user://richman4_save.json")
```

- row `0` 對應既有 `user://richman4_save.json`，只能 `preview`／`read`，不可
  `write`。它是後續 UI 顯示「原有存檔」的唯讀 adapter。
- row `1..5` 對應專用目錄內的 canonical `slot-1.json` 至 `slot-5.json`。
  `slot_path()` 只接受整數檔位，不接受呼叫端提供的任意 slot path。
- 預設建構參數使用上述兩個 `user://` 路徑；測試及隔離執行應傳入自己的
  temporary root 與 default path，不得讀寫擁有者的 app data。
- 不處理原版 `SAVE%d.DAT`、`0x26` header、`AUTO` 語意，也不遷移、刪除或
  覆寫 row `0` 的既有檔案。

## 回傳狀態

`preview(slot_id)` 與 `read(slot_id)` 都會先讀 bytes、解析 JSON，再依序通過
`GameState.validate_save()` 與 `GameState.from_dict()`。只有通過的 snapshot
才會產生 metadata。

單一 row 的 `status` 如下：

| 狀態 | 意義 | `ok` |
| --- | --- | --- |
| `empty` | canonical path 尚不存在 | `true` |
| `valid` | JSON 與既有 save schema 均通過 | `true` |
| `corrupt` | bytes 不是可解析的 JSON dictionary | `false` |
| `invalid` | JSON 可解析，但既有 save validation 拒絕 | `false` |
| `unreadable` | path 存在但無法讀取 | `false` |
| `error` | row id 或 I/O 呼叫本身格式錯誤 | `false` |

有效 preview 會回傳 `slot`、canonical `path`、64 字元 SHA-256
`fingerprint` 與 `metadata`（`date`、`map_id`／`map_name`、`map_source`、
`map_number`／`map_preview_chunk`、`player_count`、`player_names`、
`player_character_ids`）。`map_number` 以來源的 1 起始編號保存，對應
`Data479`／`Data520` 的預覽 chunk 為 `map_number + 1`；缺少來源地圖身分時
會以 `-1` 表示未知，不猜測縮圖。`player_character_ids` 只保留驗證後
snapshot 明確提供的角色身分。`read()` 另外回傳通過驗證的 `snapshot`。empty row 的
fingerprint 是空字串；corrupt／invalid row 仍會以原始 bytes 產生 fingerprint，
unreadable row 則沒有可用 fingerprint。

`scan()` 回傳 `{ok: true, status: "scanned", slots: [...]}`。scan operation
成功不代表每一 row 都有效；呼叫端必須逐 row 查看 `status`，不可把未知或
invalid 狀態當成可讀棋局。

## 寫入與競態保護

```gdscript
var result := storage.write(slot_id, game_state.to_dict(), expected_fingerprint)
```

`write()` 僅接受 row `1..5` 與 dictionary payload。payload 會先以目前的
`validate_save()`／`from_dict()` 驗證，未通過時不會建立或替換 destination。
第三個參數 `expected_fingerprint` 可省略（`null`，不比較）或傳入 preview
取得的 fingerprint；空字串明確表示「preview 當時 destination 為空」。若
destination 在 preview 後被建立或改變，會回傳 `status: "stale"`、
`error: "stale_destination"`，且保留原有 bytes。

通過驗證後，後端依序將完全相同的 JSON bytes 寫入 destination 同目錄的
temporary sibling、讀回並比對 bytes、再次解析／驗證，最後才以 atomic rename
替換 destination。temporary write、readback 或 rename 失敗會回傳明確
`error`；只清理本次建立的 temporary，不動既有 destination。成功結果為
`status: "written"`，並包含 path、fingerprint、metadata 與寫入 snapshot。

## MainUI 接線邊界

MainUI 可用 `scan()` 建立六列 picker；選定 row 後保存 preview fingerprint，
寫入時傳回該 fingerprint。讀取成功後，使用 `read().snapshot` 建立候選
`GameState`，再沿用現有 `_load_blocked_by_presentation()`、legacy 三股市
continue／cancel 與 presentation guard。這個 module 不會改動 live game、
simulation 或 RNG，也不授權跳過既有 load guard。

## SourceSavePanel 接線

`game/ui/source_save_panel.gd` 是獨立的 640×480 來源構圖 picker。它只接收
`SaveSlots.scan()` 的結果（或其中的 `slots` 陣列），不建立 `GameState`、不讀寫
檔案，也不會把 snapshot 套用到目前棋局：

```gdscript
const SourceSavePanel = preload("res://game/ui/source_save_panel.gd")
var picker := SourceSavePanel.new()
picker.configure("Game", "load", storage.scan(), existing_visuals)
```

`existing_visuals` 是現有的 `OriginalVisuals` accessor；panel 不會自行建立
filesystem-backed accessor。Game 使用 Data resource `479`，
MultiverseJourney 使用 `520`；load 使用 chunk `0`（555×451），save 使用 chunk
`1`（555×381）。save frame 的來源位置是 `(40,48)`，load frame 與 callback 對齊
於 `(40,15)`；load rows 是 slot `0..5`，save rows 是 `1..5`，每列 72px，source
callback 的 hit geometry 為 x `129..577`。來源 frame 已含檔位數字；panel 會另外
以 Game chunk `6` 或 MultiverseJourney chunk `10` 畫出檔位背景，並在每列以
來源座標畫動態資料：日期年／月日的 x `165`、y `row+36`／`row+57`，地圖縮圖
的 x `209`、y `row`、尺寸 `72×72`，以及 Data resource `2` 肖像的
x `289 + 72*i`、y `row`、尺寸 `72×72`。地圖縮圖只依明確的
`map_number`／`map_preview_chunk` 對應來源 chunk `2..5`（Game）或 `2..9`
（MultiverseJourney）。

```gdscript
picker.slot_selected.connect(_on_slot_selected)
picker.confirmed.connect(_on_slot_confirmed)
picker.cancelled.connect(_on_slot_cancelled)
picker.overwrite_confirmation_requested.connect(_on_overwrite_requested)
```

上述訊號都帶有 `slot_id`、該列 preview 的 `fingerprint` 與 preview 深拷貝。
load 只允許 `valid` 列被選取；`empty`、`corrupt`、`invalid`、`unreadable` 會
保留明確狀態並停用讀取。save 的既有列會先開啟 panel 內的來源風格覆寫確認，
確認或返回都不會自行改變 previews。Data resource `2` 的肖像只在 preview
提供已映射的 `portrait_chunk`、`player_character_ids` 或 player
`character_id` 時透過 `OriginalVisuals.ui()` 取得，不以陣列位置猜測圖示順序。

Presentation fidelity remains `UNACCEPTED` until a root render and fresh original
comparison verify the combined screen.
