# S34 來源存讀檔選單控制器

`game/ui/source_save_menu.gd` 是 `SourceSavePanel` 與 `MainUI` 之間的窄控制邊界。
它本身是可掛在 `GameShell` 外層 `Control` 的 full-rect 節點，子 picker 保留
來源 640×480 構圖與縮放；不要把這個節點掛到 shell 的
`reference_canvas`。控制器只負責掃描、一次性驗證讀寫與等待來源 Loading 畫面，
不把 snapshot 套用到 live `GameState`。

## Controller API

```gdscript
const SourceSaveMenu = preload("res://game/ui/source_save_menu.gd")

var menu := SourceSaveMenu.new()
menu.storage = SaveSlots.new(slot_directory, default_path)
menu.operation_guard = Callable(self, "_source_save_operation_allowed")
menu.load_ready.connect(_on_source_slot_load_ready)
menu.closed.connect(_on_source_menu_closed)
menu.saved.connect(_on_source_slot_saved)
add_child(menu)

menu.open("load", "Game", visuals)
```

公開的 `picker`、`loading_overlay`、`message_label` 可供 host 或隔離測試檢查。
`storage` 預設為 `SaveSlots.new()`，但建構與建立節點不會掃描或讀寫 owner 的檔案；
測試可以在 `open()` 前替換成隔離儲存器。`operation_guard` 為空時允許操作，設置
後必須在掃描、寫入，以及兩次 `process_frame` 後的讀取前後通過。拒絕時選單保持
可見並顯示理由，不進行存檔 I/O。

`open(mode, edition, visuals, payload)` 會深拷貝 SAVE 用的已驗證 payload、顯示
picker 並呼叫一次 `storage.scan()`。picker 的 `confirmed(slot, fingerprint, preview)`
會把同一個 preview fingerprint 傳給 `storage.write()` 或 `storage.read()`；讀取
成功後只發出深拷貝的 `load_ready(snapshot)`，由 MainUI 執行既有 presentation 與
legacy adoption 決策。`resolve_load(true)` 關閉選單；`resolve_load(false)` 清除
待決狀態、恢復原 picker 選擇且不重新讀取磁碟。`cancel()` 會使排隊中的讀取世代
失效並發出 `closed`。

SAVE 寫入成功會發出 `saved(slot_id)` 與 `closed`。寫入或讀取錯誤會保留 chooser、
顯示訊息，並在可執行 guard 時重新掃描列。row 0 仍由 `SaveSlots` 作為既有檔案的
唯讀 adapter；控制器不呼叫 MainUI 的 path load/save API。

## Loading 畫面

LOAD 確認後控制器進入 busy，將來源 Loading frame 置於最上層、阻擋滑鼠，再等待
兩個 `process_frame` 讓 native texture 有機會完成呈現，之後重新檢查世代、可見性與
`operation_guard` 才執行帶 fingerprint 的 `storage.read()`。Game 使用 Data resource
560，MultiverseJourney 使用 601，兩者皆取 chunk 0；frame 的 `logical.width` 與
`logical.height` 保持自然尺寸並置中於來源畫布。若 accessor 缺少有效 texture，只顯示
「讀取中」，不把 fallback 稱作來源畫面。讀取完成會隱藏 Loading；在 host 尚未完成
legacy/adoption 決策前仍維持 busy，因此重複 confirmed 不會觸發第二次 I/O。
