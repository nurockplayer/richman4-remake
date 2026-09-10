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
`fingerprint` 與 `metadata`（`date`、`map_id`／`map_name`、`player_count`、
`player_names`）。`read()` 另外回傳通過驗證的 `snapshot`。empty row 的
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
