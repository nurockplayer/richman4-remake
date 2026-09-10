# 原版遊戲說明

#139 屬於 #102 的 S35 說明視窗。棋盤工具列可開啟同版的八個分類、99 個主題，
選擇分類／主題、翻動主題清單與內文，再以右鍵放開回到原棋局。一般選項、日期、
快捷鍵設定仍是後續視窗；本批沒有把尚未接入的操作說明當成已實作功能。

## 來源與私人內容

擁有者授權的 `rich4_ui_help.asm` entry 1211–1293、renderer 62–601、callback
620–1168、tables 1945–2175 與 `help.mkf` 為主要依據。resource0 的 12 個 chunks
構成 400×400 視窗，置於 640×480 logical canvas 的 (120,40)；視窗外保留棋盤。
分類數量為 1／6／12／3／16／18／30／13；resources1–99 對應原始說明文字。

兩版文字分開匯入，46 個主題的分頁內容不同。以 NUL 切行後才辨認獨立 `@` 行，
保留空白行、原字詞及 CP950 解碼結果，每頁最多 14 行。原始內文與產生的 JSON
均留在私人 bundle，public repo 只有程式、短 UI 標籤與合成測試文字。

`export_original_help.py` 只需要兩個版本的 `help.mkf`，不要求無關的 `map.mkf`。
每個 topic 同時保存原始解碼 bytes 的 `source_payload_sha256` 與分頁 JSON 的
`payload_sha256`，另有 archive／edition-file digest。指定 `--asset-root` 驗證時，
重新核對原始 bytes 與頁面內容相等；只改頁面再重算 bundle digest 仍不能冒充原作。
輸出限全新的私人目錄，失敗只清除本次建立的輸出。

`original_help.gd` 依 `RICHMAN4_HELP_MANIFEST`、套件內
`Contents/Resources/Original/help/manifest.json`、開發用 `.local/original-help/manifest.json`
順序載入。Index 上限 64 KiB、每版內容 2 MiB；格式、整數、頁面、數量、相對路徑、
雜湊與版別不符時回報 unavailable，不借用另一版文字。回傳內容為獨立複本。
`package_help.py` 與 `package_macos.sh` 提供選擇性私人打包；目前僅驗證小型 bundle
複製與重新驗證，未宣稱已產生包含本批功能的新套件。

## 操作與 host

純 presenter 只接收已載入的內容與同版圖像 resolver。來源 logical 座標不依賴 PNG
尺寸；兩倍尺寸的替代材質仍使用相同 hitboxes。分類／主題在左鍵按下時選取；
清單箭頭與內文箭頭在按下時顯示按壓圖、放開時翻頁，清單每次最多移動八項並保留
可見列序。PageUp／PageDown 使用來源的按下／放開 bookkeeping；右鍵放開關閉。
缺文字與缺圖像各自明示，缺文字的視窗仍可關閉，不提供捏造內文。

Controller 保留同一個 game ownership，關閉 callback 受 generation 保護；新局或
讀入其他棋局時取消舊視窗。MainUI 阻擋底層棋局操作、AI、其他 modal、存讀檔與
新局入口；關閉後恢復工具列，完整帳務與 RNG 保持相同。新局顯示棋盤時立即更新
說明入口，不等待下一個 action。右鍵先標記輸入已處理，再發出可能移除 panel 的
同步 closed callback，避免對已離開場景的 panel 取 viewport。

## 驗證與限制

- 原始 loader/exporter worker 留有 missing-component availability RED；它沒有成功
  建立事前 test-only commit。Parent 後續保存測試／實作，沒有把它改稱為事前 commit。
  初版為 Python 28、runtime 38；加入來源 bytes 雜湊後為 35／45。新增測試檔的 RED
  複本在修改正式程式前保存，exporter/runtime 複本與交回測試 bytes 相同。
- Parent 的 immutable `923b75f` 重現重新改寫頁面仍通過來源驗證的 1／1 failure，
  修正後通過。`1dd437d` 重現完整 help-only source 因缺少無關 map 檔而被拒絕，
  修正後 exporter 37／0，含 bounded packaging 的 Python 合計 42／0；runtime 45／0。
- 純 presenter worker 的第一個成品有參數數量 parse error，該執行不算行為 RED／PASS。
  Parent 修正參數後發現測試把單主題分類當成多主題分類，以及跨 repaint 保留已釋放
  Label；`76437b1` 修正測試 setup，保留所有頁面／內容斷言，重現 1008／1：
  unavailable view 重新開啟時，右鍵放開沒有關閉。改成 active-modal input 處理後
  headless／native 1008／0。未刪除或減少既有斷言。
- MainUI immutable `657e806` 以有效新局重現 5／2：工具列仍停用與公開說明請求
  沒有回應。整合後入口測試 22／0；第一次整合另發現 closed callback 後 viewport
  已為 null，以及 show-game 後工具列未立即更新；上述兩個時序均已修正。
- 實際已安裝的十二地圖 catalog，由既有預設 setup／public new-game 建立 Game:1、
  MultiverseJourney:7，沒有注入說明模型、地圖能力或棋局資料。要求實際內容與圖像
  有效的版本為 headless／native 26／0；pure controller 12／0。
- 六張 native MainUI 畫面涵蓋兩版首頁、Game 說明第二頁、MJ 日月曆第二頁及兩版
  卡片清單最後八項。透過 viewport 左鍵／PageDown／右鍵流程完成 41／0，帶 HEAD、
  catalog／help／scene manifest digest 與模型／圖像 provenance。Root 已直接核對
  原圖框架、logical 座標、文字行距、選擇圖像與箭頭；兩版差異文字保持獨立。
  初次擷取誤要求只有一頁的 MJ 操作說明進入第二頁；修正的是私人擷取腳本，改用
  原本三頁的日月曆範例，未改動產品或原始內容。初次 40／1 不算完整擷取 PASS。
- 共用原始快取在本批期間消失，原因未明。從既有私人封存只取回兩個 help archive，
  共 726712 bytes；與 live GitHub pinned revision `bb6d12b` 的 manifest digest 與
  每檔 digest 一致。僅重新產生並複製小型 help bundle，沒有完整素材匯入。

完整 affected/integration regression 與新的獨立 exact-head review 尚待完成。
SubViewport 輸入與畫面證據不等於一般 OS 操作；原版執行中的完整 help 畫面對照、
目前套件與 S35 所有子視窗仍待驗收。本文件不宣稱 S35 或 Mission 完成。
