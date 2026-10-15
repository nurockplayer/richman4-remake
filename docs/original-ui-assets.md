# 原版 UI 素材載入

#101 使用既有 `richman4.scene-images/v1` 的選用 `ui` 欄位，按 edition、archive、resource、chunk 取圖。缺少 Game 素材不會借用 MultiverseJourney。原始 archive/payload SHA、衍生 PNG SHA 與 logical bounds 分別保留；顯示位置由 UI 決定，不取決於 texture pixel dimensions。

目前有來源對照的限定資源如下；這是本次匯出範圍，不是完整畫面驗收清單。

| Archive / resource | 素材用途 | 參考與限制 |
| --- | --- | --- |
| Data / 1 | 標題與 START / LOAD / OPTION | 原版官方手冊 PDF 第 5 頁與標題圖；尚需完整互動驗收 |
| Data / 2 | 12 名角色肖像 | 主棋盤 HUD 及角色選擇；按 character id 選取 |
| Data / 3 | 選角、設定、日曆的候選素材 | 個別組合仍須逐幕核對，不因匯出就標示還原 |
| Panel / 0 | 200×280 人物資訊面板與 tabs | 官方 Game 商店截圖主棋盤右側 |
| Panel / 1 | 439×40 工具列與圖示 | 官方 Game 商店截圖上方；排列由 UI reference 決定 |
| Panel / 2 | 四季日曆與星期覆蓋 | 官方手冊 PDF 第 11 頁；實際狀態另外綁定 |
| Panel / 21 | 128×192 金額計算機 | Game 與 MultiverseJourney 均限定 chunks 0..25；#130 / #135 的限定來源範圍 |
| Panel / 23 | 640×480 銀行前／後景 | 兩版均限定 chunks 0..23；Panel / 22 是非視覺資源，不匯出 |
| Panel / 24 | 320×338 ATM | 兩版均限定 chunks 0..29；尺寸為來源 logical bounds，匯出完整性不等同原生畫面驗收 |
| Panel / 75 | 六欄股票價格、七欄持股、公司資訊底圖 | Game 與資料片三張底圖逐張 byte-identical；資料片實際截圖只支援共用構圖，不能證明 Game 公司數值 |

來源：[官方手冊](https://cdn.akamai.steamstatic.com/steam/apps/2059810/manuals/%E5%A4%A7%E5%AF%8C%E7%BF%814%E8%AA%AA%E6%98%8E%E6%9B%B8.pdf)、[官方 Game 商店](https://store.steampowered.com/app/2059810/)、[Kenki 原版遊玩紀錄](https://kenki2515.pixnet.net/blog/posts/10353819854)。私有本機比較證據包含各圖 URL、SHA 與版別；沒有將原圖或擁有者截圖放入公開 Git。

`python3 tools/decode_original_ground.py --source /本機原作 --output .local/original-scenes` 的 CLI 一併匯出這些限定 UI 圖；Python `decode_source` 保留 `include_ui=False` 的舊呼叫預設，新的 UI 呼叫必須明確傳 `include_ui=True`。FULL lane 的一次正式生成才執行此命令；一般 UI 修改重用既有資料，不重新生成整組 ground。

UI 圖以 RGB555 解碼，word zero 作透明背景，使不規則圖示能疊在原版底板。這是依原版合成畫面作的明確呈現選擇；非零的黑色 word 0x8000 保持不透明。原始素材不變，逐幕檢視若發現差異再縮小到該資源調整。

`OriginalVisuals.ui(edition, archive, resource, chunk)` 回傳帶 logical bounds 的 frame，再由既有 `texture()` 驗證檔案雜湊及尺寸。`package_scene_images.py` 遞迴收集並檢查 UI PNG，只攜帶 manifest 實際引用的檔案。此變更只建立來源、載入與打包邊界，不表示畫面已通過 #99。

銀行圖集一旦存在，匯出及打包驗證均拒絕缺漏或多餘的 chunk。一般 scene 驗證仍接受 inventory/shop 所用的部分 UI manifest；`--require-bank-ui` 額外要求 Game 與 MultiverseJourney 的 Panel / 21、23、24 全部存在，並驗證每個 chunk 的影像記錄及 logical bounds。`tools/package_macos.sh` 在提供 `RICHMAN4_SCENE_MANIFEST` 時，於驗證、複製及複製後檢查均啟用此要求；未提供私有 scene manifest 的公開建置流程不變。
