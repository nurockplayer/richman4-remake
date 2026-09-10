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
後必須在掃描、寫入，以及兩次 `process_frame` 後的讀取前通過。MainUI 在採用候選
之前也會重新檢查 presentation guard。拒絕時選單保持
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

## MainUI 與驗證

標題 LOAD 與 HUD LOAD／SAVE 均開啟來源檔位選單。選單保留原本的 title／board
可見狀態；取消與錯誤不另開新局。MainUI 的 modal／AI timer guard 包含此選單，
開啟時也使先前排隊的 callback 失效。SAVE 直接深拷貝核心 `to_dict()`，不走
會加入呈現 metadata、限制人類回合的遊戲指令 adapter，因此穩定的 AI 回合亦可存檔。

LOAD 只採用 `read(slot, selected_fingerprint)` 回傳的已驗證候選，不重新開啟 path。
舊三股市候選仍走原有 continue／cancel；取消恢復 picker，確認沿用記憶體中的
同一候選。移動、事件與其他 modal 期間拒絕開啟，延後讀取前再檢查一次。

Tests-only `685013d` 在未接線版本從實際 title button signal 重現直接讀 default path、
未開 picker：3 checks／2 failures。較早草稿的不存在資料夾 cleanup 錯誤不列入 RED。
後續測試的外部替換 fixture 改由正式 factory 建立，避免手改 seed 破壞 seed_text／RNG
契約；先前四項連帶失敗屬 fixture 問題，不冒稱產品修復。

Tests-only `8eb0ab5` 在接線初版重現 SAVE 混入呈現 metadata、AI 回合無法存檔：
39 checks／2 failures，沒有 script／invocation error。改為直接取得核心快照後，同一
測試在 synthetic 與實際十二地圖 catalog 都為42／0。完整棋局比較使用核心 canonical
serializer，避免測試用 JSON 浮點 round-trip 誤判大型 RNG 整數；早先此誤判不算產品 RED。
測試亦涵蓋 slot stale、覆寫確認／取消、default 唯讀、legacy 候選、排隊讀取取消、
presentation 重查，以及選單期間的 AI callback 阻擋。

相關 source setup52／factory18、market entry82／active presentation24、HUD153、
storage248／panel121、save shapes126、simulation454 全部通過。新測試已列入
`tools/check.sh`。這些 signal／headless evidence 不等於實體輸入；來源 Loading
實際呈現、一般原生互動與打包 gate 仍待核對，S34 維持 UNACCEPTED。


## 來源檔位互動修正

原版 `rich4_ui_save_load.asm` 的 LOAD／SAVE handler 以 WM_MOUSEMOVE 選取列，
WM_LBUTTONDOWN／WM_LBUTTONDBLCLK 直接啟用，WM_RBUTTONUP 取消；沒有頁尾的
確認／取消按鈕。此次移除誤植頁尾及其17項幾何 assertions，保留其餘154項原有
panel assertions，新增34項兩版滑鼠事件 assertions。按下有效列直接讀取；空白
SAVE 列直接寫入，已有內容則進入 #129 明訂的覆寫確認。無效 LOAD 列可呈現 hover，
但不得啟用或誤讀上一列。GUI 事件依原有 modal 遮擋分派，隱藏面板不攔截輸入。

原作 save helper 直接以 `wb` 寫入，沒有覆寫提示。本重製版的覆寫確認與既有
legacy continue／cancel 是已接受的資料安全偏離，不列入來源 runtime 還原證據。
Escape 是平台操作 fallback。所有候選 fingerprint、原有檔案唯讀與 RNG 保證不變。

`44ad281` tests-only RED188／20 已重現直接啟用與右鍵取消缺漏；當時合成 viewport
尚未通知滑鼠進入、覆寫取消缺少右鍵按下配對，因此它不能單獨證明 hover／該取消
分支。`4ab21df` 修正這兩個測試 transport 前置條件，原有 assertions 不變；將同一
測試回放到未修復 panel 後仍為188／20，再於修復版取得188／0。此回放是測試證據
補正，不冒稱初版 transport 已完整。MainUI 的42項測試也改走960×720 SubViewport
內實際滑鼠事件，保留每項原有狀態、寫入、取消、舊存檔與 AI assertions。
