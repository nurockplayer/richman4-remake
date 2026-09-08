# 原版資產匯入

原版檔案只從遊戲擁有者的本機安裝讀取。`tools/import_original.py` 會列出來源檔案與 SHA-256，驗證 MKF 索引表，並將可安全解析的地圖資料寫到 `.local/`。原始執行檔、MKF、音訊、影片與匯入快取都不進 Git。

先以 `--dry-run` 檢查來源，不會建立輸出檔：

```sh
python3 tools/import_original.py \
  --source /path/to/dfw4cskzl_136622 \
  --dry-run
```

確認來源後建立本機資料：

```sh
python3 tools/import_original.py \
  --source /path/to/dfw4cskzl_136622 \
  --output .local/imported-original \
  --extract-map-payloads
```

`--source` 可以是包含 `Game/`、`MultiverseJourney/` 的安裝根目錄，也可以直接指定其中一個含有 `map.mkf` 的目錄。工具只會選取直接含有 `map.mkf` 的版本目錄，並跳過 `DxWnd`、`Media`、符號連結與其他不屬於遊戲版本的目錄。`--edition Game` 或 `--edition MultiverseJourney` 可限制匯入版本。

輸出目錄包含：

| 路徑 | 用途 |
| --- | --- |
| `manifest.json` | 版本目錄、檔案相對路徑、大小、SHA-256，以及每個 MKF 的索引表與資源界線。 |
| `maps/catalog.json` | 所有可解析地圖的 JSON 目錄；每張地圖保留來源版本與 `map.mkf` resource index。 |
| `raw/<edition>/map-XX.bin` | 只有指定 `--extract-map-payloads` 時建立的未壓縮地圖 payload 原始副本。 |

MKF 是小端格式。檔案第一個 32 位元整數指向檔尾索引表；索引表的數值是資源的絕對起點，第一個資源從位移 4 開始。每筆資源有 16 位元組標頭，後接由下一個索引值界定的 payload。工具會檢查索引嚴格遞增、標頭和 payload 尺寸吻合、影像範圍不超出解碼尺寸；失敗時會停止匯入。

原版的壓縮資源使用私有 codec。工具會在 `manifest.json` 中標為 `compression: "private"`，保留尺寸與界線證據，並不把它當成 zlib、ZIP 或其他通用格式解碼。現有 `map.mkf` 地圖資源都是未壓縮記錄，因此可以在沒有私有 codec 的情況下產生地圖目錄。其他 `Data.mkf`、`Effect.mkf`、`help.mkf`、`jump.mkf`、`Panel.mkf`、`Speaking.mkf` 資源仍須後續完成 codec 與像素／音訊驗證。

地圖 JSON 永遠保留 `name_bytes_hex`。目前所有非空的土地、設施與景觀名稱都能以 CP950（Windows Big5 擴充）嚴格解碼後再編碼回相同位元組，因此工具另外提供 `display_name`、`display_name_encoding: "cp950"` 與 `display_name_confidence: "inferred-roundtrip"`；ASCII 名稱也保留 `name_ascii`。這是跨目前地圖 payload 的編碼證據，不等同於原版 UI 顯示驗證。節點、土地、設施、企業與景觀的未知欄位也保留為十六進位欄位，供之後對照原始執行時驗證。

匯入完成後可檢查 Git 是否仍為乾淨的資產範圍：

```sh
git status --short --ignored .local/imported-original
```

`.local/` 已由 `.gitignore` 排除。請不要以 `git add -f` 強制加入原始檔或上述衍生資料。

格式研究另參考 [mytbk/rich4](https://github.com/mytbk/rich4/tree/54ff26750e7e7f585da6fe68c4e8972cd22ed509) 的容器／地圖欄位記錄，再以本機資料的界線、欄位與 round-trip 結果核對。匯入器為 Python 獨立實作；該研究 repo 與解碼程式沒有納入此 repo 或遊戲包。

地圖節點 JSON 同時保留原始 `status_bits` 與 `field_0x22`，並提供可供 runtime 使用的 `event_code`（`status_bits & 0xff`）與 `visual_index`（`field_0x22`）。事件碼的落地 dispatch 已由原版 `player_core_actions.asm` jump table 核對；`field_0x22` 是視覺／資源索引，不應用來判斷事件。

土地與設施的價格欄位依原始結構解析。housing land 的 `+0x1c` 是 `land_price`、`+0x1e` 是 `house_price`；土地的 `+0x20..+0x2b` 是六個 little-endian `u16`，輸出為 `rent_by_level`。為維持既有 schema v1 呼叫端，`price_per_level` 仍輸出，但它是 `house_price` 的相容別名，不是另一個欄位。facility 的 `+0x22`／`+0x24` 分別是 `land_price`／`house_price`，同樣提供 `price_per_level` 相容別名。原始 12 個租金位元組仍保留在 `reserved_hex`。
