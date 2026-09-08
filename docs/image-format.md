# 原版圖片解碼器

`tools/decode_original_images.py` 會從擁有者本機的《大富翁 4》安裝目錄
讀取 MKF 封裝，解出其中可界定邊界的 `SPR` 與 `SMP` 圖片資源，並在本機
輸出每個圖塊的 RGBA PNG。原版安裝檔與產生的圖片快取都留在 `.local/` 或
其他本機目錄，不會加入 Git。

## 使用方式

```sh
python3 tools/decode_original_images.py \
  --source /path/to/dfw4cskzl_136622 \
  --output .local/original-images
```

`--source` 可以是同時包含 `Game/`、`MultiverseJourney/` 的安裝根目錄，
也可以直接指定其中一個版本目錄。輸出包含：

* `manifest.json`：來源檔案雜湊、MKF 索引、資源壓縮狀態、圖塊尺寸與 PNG
  雜湊。
* `images/<edition>/<archive>/resource-XXXX/chunk-XXXX.png`：每個通過
  結構檢查的 `SPR` 或 `SMP` 圖塊。

重新匯入會先在輸出目錄建立暫存 `images/`，完成所有解碼並寫好暫存
manifest 後，才替換工具管理的 `output/images/` 與 `manifest.json`。因此
來源移除 archive 或 chunk，或成功結果沒有任何可視資源時，舊 PNG 都會被
整批替換掉，並發布空的 `images/` 與新 manifest；輸出根目錄的其他檔案會
保留。解碼或發佈失敗會清理暫存內容並嘗試回復上一個有效的 images 與
manifest，不會刪除或移動來源檔案。edition 與 archive 名稱在寫入前會先
經過清理及不分大小寫的輸出路徑碰撞檢查。

預設以原版常見的 RGB555 解讀 16 位元像素（`--pixel-format rgb555`），
並把 `SPR` palette index `0` 輸出為透明像素。可選格式為 `rgb565`、
`swapped`、`rgb444`；若要讓 index `0` 也保持不透明，可加上
`--opaque-index-zero`。這些選項只影響 PNG 顏色轉換，不會改寫解出的
原始圖塊資料。

## MKF 封裝

MKF 的第一個 little-endian `u32` 是索引表偏移。檔案尾端的每個 `u32`
是資源起點，資源範圍由目前起點到下一個起點（最後一筆到索引表）決定。
每筆資源開頭是四個 little-endian `u32`：

| 欄位 | 意義 |
| --- | --- |
| `uncompressed_size` | 解碼後資源大小 |
| `compressed_size` | 緊接在 16-byte header 後的 payload 大小 |
| `image_data_offset` | 資源內圖片資料起點 |
| `image_data_size` | 圖片資料大小 |

`compressed_size == uncompressed_size` 時 payload 直接保存；其餘 payload
使用原版的 adaptive Huffman 與 LZ back-reference 私有壓縮格式。解碼器以
宣告的大小及來源 payload 的實際範圍為上限，拒絕越過下一筆資源或索引表的
讀取，也拒絕無效的回溯距離、截斷 bit stream、超過大小限制的配置與不完整
的輸出。

## SPR 與 SMP

解碼後的可視資源以四位元組 signature 開頭，接著是 little-endian
`u32 chunk_count` 與 `u32 start_offset`。每個 12-byte chunk entry 的
欄位為 `<hhhhI>`：寬度、高度、x、y 與 graph byte size。

* `SPR` 在 `start_offset` 放置 256 個 little-endian 16-bit palette 顏色，
  因此 palette 佔 512 bytes；圖塊資料接在 palette 後方，每個像素一個
  palette index。
* `SMP` 沒有 palette；圖塊資料從 `start_offset` 開始，每個像素是一個
  little-endian 16-bit 顏色值。

目前 PNG writer 將 SMP 像素輸出為不透明 RGBA。原版對 SMP 的 color-key
或透明繪製語意尚未由執行期路徑完全核實，因此角色周圍的黑色像素目前只
代表來源的 16-bit 值，不應視為已確認的原作透明效果。

解碼器要求每個 `graph_size` 等於 `width * height`（SPR）或
`width * height * 2`（SMP），而所有圖塊的 graph 結尾必須剛好等於宣告的
資源大小。`image_data_offset` 必須指向 palette（SPR）或整段 graph（SMP），
`image_data_size` 也必須相符。這些檢查讓 PNG writer 不會把 table、header
或其他資源內容當成像素。

## 尚未輸出的資源

`GND` 地圖背景資源目前只會被列為略過，因為其長尾資料仍需要另外的格式
還原；未知 signature 也不會猜測為圖片。這不影響已通過完整 graph 邊界
檢查的 `SPR`/`SMP` 輸出。所有解碼限制都可由 CLI 的
`--max-resource-bytes`、`--max-dimension` 與 `--max-chunks` 調低，限制
單筆資源、單張圖像與每筆圖塊數；整批輸出大小仍隨來源數量增加。

## 格式依據與驗證

格式研究參考 [mytbk/rich4 的 MKF 格式記錄](https://github.com/mytbk/rich4/blob/54ff26750e7e7f585da6fe68c4e8972cd22ed509/csrc/mkf/mkf-format.md)
及同一 commit 的研究用解碼器，並以擁有者本機位元組核對。本工具獨立實作，
沒有將該 GPL 專案的原始碼納入本 repo。

2026-09-08 本機逐筆比對兩個版本全部 878 筆壓縮資源（Game 417、
MultiverseJourney 461），解碼 bytes 與研究用 C oracle 全部一致。Panel
樣本產生 100 筆 SPR/SMP 資源、1,451 張 PNG，另實際查看面板、人物及
透明金幣樣本。位元組一致不等於已核實所有色彩、透明與遊戲中的組合方式。
