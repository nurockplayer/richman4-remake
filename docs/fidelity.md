# 保真度狀態

本頁只記載目前有本機位元組、解析結果或說明書頁面支持的內容。原始執行檔尚未提供可重現的跨平台執行時觀察，因此資料保真、規則保真、視覺保真與操作節奏分開記錄。

## 已由本機資料核對

`tools/import_original.py` 以 owner-provided `dfw4cskzl_136622` 的 `Game/` 與 `MultiverseJourney/` 為輸入，驗證到下列結果：

| 來源版本 | `map.mkf` resource index | 地圖數 | 節點／土地／設施／企業／景觀數量 |
| --- | --- | ---: | --- |
| `Game` | 1、3、5、7 | 4 | 103/50/4/3/21；144/73/8/4/26；110/49/5/6/16；118/55/8/6/16 |
| `MultiverseJourney` | 1、3、5、7、9、11、13、15 | 8 | 103/50/4/3/21；144/73/8/4/26；110/49/5/6/16；118/55/8/6/16；135/47/5/3/2；135/60/3/12/143；141/55/6/3/154；101/0/20/7/79 |

每張地圖的 40 位元組標頭（10 個 32 位元欄位）、dummy record、固定 record size、section offset 與 payload 結尾都通過邊界核對；目前這 12 張地圖的節點鄰接欄位沒有指向不存在節點的值。土地、設施與景觀名稱永遠保留原始位元組；目前所有非空名稱都通過 CP950 嚴格解碼與回編碼相等核對，因此匯入資料附帶 `display_name` 與 `display_name_confidence: "inferred-roundtrip"`。這是目前 payload 的編碼證據，原版 UI 的字型與顯示仍需執行時觀察。

Runtime loader 另外核對雙向鄰接、住宅參照唯一性與住宅從起點的可達性。超時空之旅第 5 張地圖有 20 個無鄰接的非住宅節點，匯入時保留它們，不補造道路；所有住宅均可到達。第 8 張只有商業設施而沒有住宅，商業系統完成前不開放對局。第 6 張有一筆名稱全零的住宅，以「未命名住宅 48」呈現，不虛構來源名稱。

節點輸出保留原始 `status_bits` 與 `field_0x22`，另提供 `event_code = status_bits & 0xff` 與 `visual_index = field_0x22`。原版落地 dispatch 的 jump table 將 1–16 對應到事件／UI；`field_0x22` 在繪圖路徑中作資源索引，因此兩者在重製 runtime 中必須分開。這些欄位對應由 `.local/research-rich4/asm/rich4_player_core_actions.asm` 的 `rich4_handle_player_land_on_node` 與相關繪圖反組譯核對，並以 `catalog.json` 的原始節點值交叉檢查。

價格欄位也已依反組譯與本機 fixture 核對：housing land 結構的 `+0x1c` 是 `land_price`，`+0x1e` 是 `house_price`；`+0x20..+0x2b` 是六個 rent `u16`，輸出為 `rent_by_level`。購買成本使用 `(land_price + level * house_price) * price_index`；`price_per_level` 僅保留為等於 `house_price` 的舊欄位別名。facility 結構的 `+0x22`／`+0x24` 則分別是 `land_price`／`house_price`。原版來源證據位於 `.local/research-rich4/csrc/land.h` 與 `.local/research-rich4/asm/rich4_player_core_actions.asm`；目前未宣稱所有事件高位旗標或完整 UI 行為已核對。

節點類型數值依原始欄位保留。`2000–3999` 目前標為土地、`4000–5999` 標為設施、`6000–7999` 標為企業，其餘值標為 `other`；這是對資料欄位的保守分類，不是完整事件規則的證明。土地所有權欄位在匯入的初始地圖資料中為 0。

## 狀態分層

| 面向 | 狀態 | 證據與缺口 |
| --- | --- | --- |
| 容器與地圖結構 | 已核對 | MKF 絕對 offset、16 位元組 resource header、40 位元組地圖標頭（10 個 32 位元欄位）、五種資料表與鄰接界線均由本機檔案驗證。 |
| 原作規則 | 部分核對 | [manual-rules.md](manual-rules.md) 索引了說明書頁面；起始金額、完整租金表、事件順序與部分例外仍需原版執行觀察或更多資料對照。 |
| 地圖內容 | 部分核對 | 12 張地圖的節點、座標、鄰接、原始名稱位元組、CP950 round-trip display name 與物件欄位已輸出；物件圖像、字型、地圖排序與原版 UI 顯示仍待驗證。 |
| 其他內容資源 | 未完成 | `Data.mkf`、`Effect.mkf`、`help.mkf`、`jump.mkf`、`Panel.mkf`、`Speaking.mkf` 含私有壓縮記錄；目前只有 container inventory，沒有宣稱已完成解碼。 |
| 音樂與音效 | 部分核對 | 本機播放路徑已成功載入並播放 25 個 OGG 曲目；`Midi.txt`、`InstOK.wav`、`InstSel.wav` 與版本目錄內的媒體已列入來源清單。曲目映射、混音曲線、播放時機與音效節奏尚未由原版執行證實。 |
| UI、動畫與操作節奏 | 未完成 | Godot 目前可在沒有私有素材的 checkout 執行；這個 fallback 畫面不是原版 UI、動畫或時序的保真度證據。 |
| 可重現遊戲狀態 | 部分核對 | Godot 端的 deterministic remake 測試仍在建立；原版骰子、回合、存檔、隨機數與事件序列尚未有 golden traces，因此不能宣稱與原作一致。 |

## 重新核對規則

每次替換 owner-provided 安裝或更新匯入結果，都應重新執行：

```sh
python3 tools/import_original.py \
  --source /path/to/dfw4cskzl_136622 \
  --output .local/imported-original \
  --dry-run
```

`manifest.json` 的檔案 SHA-256 是該次資料來源的識別證據。只有在相同輸入雜湊、相同 parser 版本與成功的邊界／結構驗證都成立時，才可把地圖資料視為同一個匯入基線。規則、文字、圖像、聲音或執行時序的新增主張，必須附上對應的原始資料或可重現觀察結果。

## 目前可操作的重製版本

Godot 桌面版本已具備 2–4 人新局、固定 seed、擲骰／買地／逐次加蓋、租金與破產、AI 接手、銀行／股票、五種卡片、存讀檔、結算重開，以及從本機原版資料夾讀取音樂。測試涵蓋重製核心的可重現行為；這不等同原版 golden trace。

原版 catalog 已接入選圖、座標路網、分岔選路與地圖身分存檔；沒有本機 catalog 時顯示明確標示的 40 格測試棋盤。住宅採來源地價、建屋成本及六級租金表；路口允許玩家選方向，AI 只走原始鄰接邊。經過卡片／點數／銀行格有對應處理，其他尚未還原的特殊格顯示「待還原」。

本機驗證以 seed 42、四位 AI 跑完 11 張有住宅地圖，每局在 95–268 個後續回合內結束；JSON 存讀檔後續玩一致。第 8 張超時空地圖拒絕開局。這是目前重製規則的完整對局與重播證據，並非原版執行軌跡對照。

起始金額、部分經濟參數、簡化日曆及破產資產分配仍屬暫定。完整 30 種卡片、13 種道具、神明、特殊人物、企業、商業設施、拍賣互動、小遊戲、原作角色圖像與動畫仍有缺口。#1 保持未完成並持續推進。
