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
| Panel / 75 | 六欄股票價格、七欄持股、公司資訊底圖 | Game 與資料片三張底圖逐張 byte-identical；資料片實際截圖只支援共用構圖，不能證明 Game 公司數值 |
| Game jump / 4 | 新局設定 atlas（全部 bounded chunks） | Game edition 固定索引；chunk 0 為 440×155 人物框、chunk 1 為 192×461 設定條；不包含 jump 0–3 地圖背景或 jump 5+ 動畫 |
| MultiverseJourney jump / 8 | 新局設定 atlas（全部 bounded chunks） | MJ edition 固定索引；chunk 0/1 與 Game setup atlas 對位，另保留 MJ 的 edition-specific map/setup chunks；不借用 Game jump / 4 |
| Game Data / 479 / chunk 0–1 | 存讀檔 LOAD／SAVE 構圖 | chunk 0 為 555×451 六列 LOAD，chunk 1 為 555×381 五列 SAVE；Data / 520 是 MJ 索引，不套用到 Game |
| MultiverseJourney Data / 520 / chunk 0–1 | 存讀檔 LOAD／SAVE 構圖 | 與 Game 對應 PNG 逐位元相同，但保留 MJ 的來源 archive／resource 身分 |
| Game Data / 560 | Loading 畫面 | headerless 640×480 RGB555；零值保持不透明黑底；不當作 SMP/SPR header 解析 |
| MultiverseJourney Data / 601 | Loading 畫面 | headerless 640×480 RGB555；與 Game Data / 560 的 PNG 逐位元相同；固定 MJ 索引 |
| Game／MultiverseJourney help / 0 | 說明 frame 與 bounded icons（全部 chunks） | 400×400 frame 及 help source 使用的 icons；頁面文字與 section 順序仍由 runtime 繪製／核對 |

來源：[官方手冊](https://cdn.akamai.steamstatic.com/steam/apps/2059810/manuals/%E5%A4%A7%E5%AF%8C%E7%BF%814%E8%AA%AA%E6%98%8E%E6%9B%B8.pdf)、[官方 Game 商店](https://store.steampowered.com/app/2059810/)、[Kenki 原版遊玩紀錄](https://kenki2515.pixnet.net/blog/posts/10353819854)。私有本機比較證據包含各圖 URL、SHA 與版別；沒有將原圖或擁有者截圖放入公開 Git。

`python3 tools/decode_original_ground.py --source /本機原作 --output .local/original-scenes` 的 CLI 一併匯出這些限定 UI 圖；Python `decode_source` 保留 `include_ui=False` 的舊呼叫預設，新的 UI 呼叫必須明確傳 `include_ui=True`。FULL lane 的一次正式生成才執行此命令；一般 UI 修改重用既有資料，不重新生成整組 ground。

UI 圖以 RGB555 解碼，word zero 作透明背景，使不規則圖示能疊在原版底板。這是依原版合成畫面作的明確呈現選擇；非零的黑色 word 0x8000 保持不透明。原始素材不變，逐幕檢視若發現差異再縮小到該資源調整。

`OriginalVisuals.ui(edition, archive, resource, chunk)` 回傳帶 logical bounds 的 frame，再由既有 `texture()` 驗證檔案雜湊及尺寸。每個 resource record 同時保留 `source`（edition、archive、entry、payload／archive SHA）與 `output`（PNG、pixel format、zero transparency policy）；frame 的 `path`／PNG SHA 只描述衍生輸出。這讓 reader 可以繼續使用同一個 accessor，而不把來源身份與顯示位置混在一起。

`package_scene_images.py` 遞迴收集並檢查 UI PNG，只攜帶 manifest 實際引用的檔案。headerless Loading resource 使用 `signature: "RAW-RGB555"`、`format: "raw-rgb555"` 與單一 chunk 0；它不含 visual header，只有明確綁定的 640×480×2 bytes 來源大小才會輸出。所有受支援的 edition/index 與缺失 chunk 都 fail closed，避免把 Game / 479、MJ / 520 或 Game / 560、MJ / 601 互相替代。

一般 FULL lane 仍可使用：

```sh
python3 tools/decode_original_ground.py \
  --source /本機原作 --output .local/original-scenes
```

若只需把這個 bounded UI slice 加入既有、已驗證的 scene manifest，可使用 UI-only incremental entrypoint：

```sh
python3 tools/original_ui_assets.py \
  --source /本機原作 \
  --manifest .local/original-scenes/manifest.json \
  --edition Game \
  --edition MultiverseJourney
```

這個命令只讀取表內的 archive entries，先將 PNG 與合併後 manifest 放入 private staging，再以 package validator 驗證並 atomic replace；既有 map、character 與其他 UI 檔案保持原狀。`--edition` 可重複指定單一 edition。它需要既有 `richman4.scene-images/v1` manifest，不會建立新的 ground 或 character corpus。原始素材與衍生 PNG 仍只能留在 private ignored output，不可提交至 public Git。這些來源／打包邊界不代表畫面已通過 #99，也不代表 save/load、Loading timing 或 help 互動已驗收。
