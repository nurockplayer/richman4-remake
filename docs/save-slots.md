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

`preview(slot_id)` 會先讀 bytes、解析 JSON，再由 `GameState.from_dict()`
沿用既有 migration 與驗證，並對產生的 `to_dict()` snapshot 做嚴格驗證。
`read(slot_id)` 也會執行相同流程，並回傳正規化且通過驗證的 snapshot；
原始檔案不會因此重寫，save version 與 RNG continuation 仍保留。
只有通過的 snapshot 才會產生
metadata。讀取流程可傳入先前 preview 的 fingerprint：
`read(slot_id, expected_fingerprint)` 會以同一次讀入的 bytes 計算 fingerprint，
若不相符便回傳 `status: "stale"` 且不包含 snapshot，避免 preview 後被替換的
有效存檔靜默套用。`expected_fingerprint` 為 `null` 時是明確的 raw-read API，
不做比對；空字串表示 preview 當時檔位為空。格式不合法的 expected fingerprint
會在讀取前回傳 `status: "error"`／`error: "invalid_expected_fingerprint"`。

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

通過驗證後，先以 filesystem 原子 mkdir 取得該檔位的 `.write-lock` 目錄。
兩個遵循此協定的遊戲執行個體不能同時進入 fingerprint 比對、temporary
讀寫驗證與 rename 區段。未取得 lock 時回傳 `slot_write_busy`，不清理其他
writer 的檔案。temporary 名稱含 process／instance／sequence，且只在取得
互斥所有權後使用；不同檔位各自取得 lock。此協定不宣稱阻止手動或外部工具
不遵守 lock 的檔案改寫，preview 的二次 fingerprint 檢查仍保留。

正常結束與寫入失敗都釋放自己取得的 lock。若程式崩潰留下 lock，後續寫入
明確失敗，不猜測擁有者或自動刪除；確認所有遊戲執行個體已關閉後才可移除
對應的空 `.write-lock` 目錄。rename 成功後若 lock 清理失敗，回傳的成功
結果保留並附 `lock_cleanup_error`，不把已提交的存檔誤報為寫入失敗。

取得 lock 後，後端依序將完全相同的 JSON bytes 寫入 destination 同目錄的
temporary sibling、讀回並比對 bytes、再次解析／驗證，最後才以 atomic rename
替換 destination。temporary write、readback 或 rename 失敗會回傳明確
`error`；只清理本次建立的 temporary，不動既有 destination。成功結果為
`status: "written"`，並包含 path、fingerprint、metadata 與寫入 snapshot。

## MainUI 接線邊界

MainUI 可用 `scan()` 建立六列 picker；選定 row 後保存 preview fingerprint，
讀取時呼叫 `read(slot_id, selected_fingerprint)`，寫入時也傳回該 fingerprint。
讀取成功後，使用 `read(slot_id, selected_fingerprint).snapshot` 建立候選
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
（MultiverseJourney）。外框與檔位背景固定跟隨 panel 的 `edition`；每一列的
地圖與肖像則跟隨該列已驗證 metadata 的 `map_edition`。若列沒有可辨識的
來源 edition，panel 不猜測另一套 atlas，也不畫出動態地圖／肖像。

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

## Existing migration regression

Sol found that strict validation before `from_dict()` rejected supported older
news-road saves. Tests-only `181c3f9` preserves the original suite and adds row0
and writable-row reads for the existing news/fate migrations: qualified RED
244 checks /20 failures, with no script or invocation errors. The first draft
also assumed old fate inputs failed strict validation; that fixture assertion
was corrected before implementation and is not included as product RED.
Reads now return the core's canonical migrated candidate while fingerprinting
and preserving the original file bytes. Explicitly saving that candidate uses
the unchanged strict-write contract. Forged source classifications remain
invalid; no new migration or compatibility branch is introduced.

Final component review found that empty/corrupt/invalid/unreadable row0 placed
its status over「原有存檔」. Tests-only `aebdd1d` adds both-edition checks for all
five non-valid statuses:171 checks/10 overlap failures before repair,171/0
after moving only row0 status below its identity. Both texts stay within the
72px row; invalid rows remain disabled. Component composition is DIRECTION_ONLY,
not ordinary native/package acceptance. Source click/cancel semantics are
being reconciled under #129 before final interaction acceptance.

## Review repair evidence

Row0 now says「原有存檔」above the date; the read API accepts the selected fingerprint and returns stale without a snapshot on replacement. Both focused suites run in check.sh. Tests-only1c0cc50 supplied the first regressions, but its two-argument call against the old one-argument API produced invocation errors, so that storage RED is not accepted as behavioral proof. Test-only3a2136b preserves every assertion and detects the available signature solely to replay the actual old public read API. Replayed unchanged against78a5888, valid A is replaced by valid B and the old API really returns B:163 checks/8 failures, without script or invocation errors. The identical test passes163/0 on the repaired implementation. Panel121/3 and runner two missing-call assertions are independently reproduced on78a5888; panel121/0 and runner PASS follow the repair. This is a retrospective evidence correction after implementation, not a claim that the initial API-error run was valid acceptance RED. Ordinary MainUI adoption and screen/native/package gates remain pending.


並行回歸 `tests/save_slots_concurrency.gd` 以兩個獨立 store、真實檔案 I/O
與 Thread／Semaphore 排程原問題：兩方先觀察同一個不存在的 temporary，
A 驗證 A 的 bytes 後，B 替換並驗證 B，兩者均已讀到舊 fingerprint，最後
由 A rename。Tests-onlye19cde1 合格13/2（無 timeout／script error），修復後
同一測試13/0；A 成功結果與實際 destination bytes 完全相同，B 不覆寫 A，
釋放後下一筆交易可正常寫入。原248 assertions 保留；FaultIO 只改為繼承
正式 filesystem adapter，以使用新增 lock API。
