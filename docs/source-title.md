# 來源標題與版本入口

`game/ui/source_title_panel.gd` 是獨立的 640×480 來源標題元件。它只負責畫面構成、來源 hit region、hover 呈現與意圖訊號；版本、地圖 catalog、開局設定、存檔及離開視窗的決策仍由 host（`GameShell`／`MainUI`）負責。

元件以 `configure(edition, visuals)` 接收已建立的 `OriginalVisuals` 類 accessor。accessor 需要提供 `.ui(edition, "Data", 1, chunk)` 與 `.texture(frame)`；傳入 `null` 時會使用可讀的 fallback，不會自行尋找 manifest 或讀取檔案。未知 edition 會 fail closed，隱藏標題表面並停止所有入口訊號。

來源 `Data1` 的 chunk 0 是完整 640×480 背景，已包含 START、LOAD、OPTION 及相應版本的 NEW STAGE normal art。EXIT 不在背景內，因此另外繪製 normal chunk 7。hover 使用 chunk 2／4／6／8；`MultiverseJourney` 額外使用 chunk 10。hover texture 以來源 anchor 減去 logical anchor 定位，Button 本身維持固定的 logical hit rect，不以實體 texture 像素或 icon minimum size 推導區域。

| 入口 | anchor | hover chunk | logical hit size／anchor | stage |
| --- | --- | --- | --- | --- |
| START | (190, 380) | 2 | 116×113 / (59, 57) | 0 |
| LOAD | (328, 380) | 4 | 114×99 / (55, 54) | — |
| OPTION | (468, 378) | 6 | 103×98 / (53, 46) | — |
| EXIT | (328, 450) | 8 | 58×19 / (29, 10) | — |
| NEW STAGE（僅 MJ） | (62, 380) | 10 | 90×107 / (45, 52) | 1 |

`buttons` 對外固定提供 `start`、`load`、`option`、`exit`、`new_stage` 五個 key；節點名稱分別為 `SourceTitleStart`、`SourceTitleLoad`、`SourceTitleOption`、`SourceTitleExit`、`SourceTitleNewStage`。Game 版本會從 scene tree 移除 NEW STAGE，MJ 才加入它。所有 Button style 都是透明的來源覆蓋層；只有缺少來源背景或 EXIT normal art 時才顯示文字 fallback。OPTION 預設啟用，host 可在 S35 前以 `set_option_enabled(false)` 或直接設定 button `disabled`。

元件本身維持 `REFERENCE_SIZE`，不建立或套用 viewport／canvas scale。父 shell 必須將這個 640×480 surface 放入自己的 source canvas，並只在該處做一次 contain scaling。Button 的 focus 與 Godot 一般 `ui_accept` 鍵盤啟動是無障礙 fallback；來源程式的鍵盤語意仍未宣稱已還原。

`tests/source_title_panel.gd` 使用注入的 synthetic visuals 驗證兩個 edition 的 chunk 來源、anchor hit bounds、physical texture 尺寸與 logical geometry 分離、first／last pointer hover、neutral 清除 hover、EXIT normal 保留、意圖訊號、disabled／hidden input、缺圖 fallback 及未知 edition fail-closed。這些 component checks 不等同於原版畫面对照、實體輸入、原生視窗或打包驗收。
