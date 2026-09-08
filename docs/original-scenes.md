# 本機原版場景

`python3 tools/decode_original_ground.py --source /本機/原作 --output .local/original-scenes`
會匯入兩版本的 12 張底圖、12 位角色各 8 個靜態方向，各地圖 5 級住宅，以及來源明示的地景與企業圖像。
public code repo 不提交未確認公開分發權的原作檔案；private asset repo 只保存 owner-authorized 原始來源。PNG、場景 manifest 與私人套件是可重建的本機衍生輸出，留在 `.local/` 或套件輸出目錄，不作為 public code repo 的素材來源。

Godot 依 `RICHMAN4_SCENE_MANIFEST`、私人套件 Resources/Original/scenes/manifest.json、
`.local/original-scenes/manifest.json` 的順序尋找素材。地圖 ID、來源 archive SHA 與 graph payload SHA
必須與目前路網一致；每張 PNG 另查 SHA。缺少或不相符時使用可操作的路網圖。

私人打包同時設定 `RICHMAN4_MAP_CATALOG` 與 `RICHMAN4_SCENE_MANIFEST` 後執行
`bash tools/package_macos.sh`。只複製 manifest 引用的圖像，複製前後驗證，最後重新簽署。

## 已查證的格式

擁有者兩版本 GND payload 均為 0x512a90 bytes：72×72 個 32×32 圖塊，
RGB555 palette 位於 0x10、5184 個 uint16 placement 位於 0x210、圖塊庫位於 0x2a90。
placement 為 row-major；色號零在底圖中不透明。合成測試驗證非恆等排列及實際 PNG RGBA bytes。
每張 GND 後一筆是對應地圖 graph，兩者保留獨立 SHA。

本機原作執行檔的資源索引運算確認角色站姿為 Game Data.mkf `87 + 21 * character_id`、
資料片 `128 + 21 * character_id`；21 為十進位。兩版本分別可在 0x40b43e–0x40b450、
0x40b954–0x40b966 看見乘法／base。人物名稱與 ID 由 #14 開局設定另行接入。
住宅為 Game map.mkf `27 + 5 * map_index + level - 1`，資料片 base 為 39；
相應指令位於 0x407a98–0x407aa7、0x407e22–0x407e2e。
土地座標與道路座標不同，房屋使用 land.x/y；方向為 `(8 - field_0x1b) & 7`（目前 rotation=0）。
SPR 的 x/y 為 anchor，繪製左上角從世界位置減去 anchor。

道路／事件節點圖示使用地圖圖資的獨立 SMP：Game 為 `map.mkf` resource 12、17 個圖塊，
資料片為 resource 24、58 個圖塊。原作繪圖路徑讀取節點 `field_0x22`，以 1-based 值
索引 SMP 圖塊；值 0 不繪製。匯入器會輸出每個圖塊，manifest 的 `road_sprites` 以
`visual_index` 對應並保留 PNG 像素尺寸及 `frame.logical` 的尺寸／anchor；`road_source`
同時綁定 map archive 與 SMP payload SHA。SMP 的 16-bit word 0 只在這個已核實的道路
輸出路徑作透明 color-key；一般 `write_png` 呼叫預設仍輸出不透明像素，`0x8000` 的黑色
word 也保持不透明。

## 已驗證與差異

已在私人 macOS 套件查看台灣地圖，擲骰、直接點選分岔與縮放可運作。
另以本機 Godot 渲染測試局，配置不同等級住宅及角色，確認房屋落在土地框、角色位於道路。
合成 UI 測試驗證載入、hash mismatch fallback、路線點擊及縮放平移後的命中位置。

目前包含底圖、靜態住宅／地景／企業與角色站姿。設施升級圖像、行走／交通工具動畫、角色隨移動轉向、
屋主 palette 換色尚未還原；屋主用道路色點表示，住宅可見原始 cyan 色邊。
同格角色略微錯開以便辨識。開局道路仍沿用既有路網 heuristic，尚未查證原作初始位置。

地景紀錄大小 28 bytes，+0x18 為方向、+0x1a 為 sprite ID；企業紀錄大小52，
+0x1b 為方向、+0x20 為 sprite ID。Game資源為 ID+26，資料片為 ID+38。
已直接檢查兩個原作執行檔的 0x407b39／0x407b8b 與 0x407f01／0x407f52 加法，
並實看 Game ID61→resource87 的醫院圖。圖層依螢幕 y 排序，讓前方建物遮住後方角色。

## 呈現座標與圖片解析度

manifest 的 `world_rect` 是 GND 圖塊格式推導的地圖世界範圍，不是 UI 或螢幕的固定解析度。
每張 PNG 的 `width`／`height` 僅描述與驗證該張 texture 的像素；sprite 另有 `logical`
呈現尺寸與 `anchor_x`／`anchor_y`。初次匯入採原作 SPR 座標與 GND 圖塊尺度；後續替換
2×／4× 圖像只更新像素尺寸、路徑與 hash，保留 logical／world_rect 即可。
路網、hitbox、camera 與存檔完全不讀 texture 尺寸。尚未宣稱原版 canonical UI logical resolution。

Board 明確使用 `TEXTURE_FILTER_NEAREST`，保留原圖像素邊界。合成測試用 4／8／16 像素
背景與住宅／人物 texture，驗證相同 logical 矩形、anchor、鏡頭與選路命中位置；包裝驗證亦接受
同一 world_rect 的不同像素尺寸。像素上限 16384 是載入資源限制，不是遊戲幾何。

目前 Board 以來源 GND 的平面 world 座標繪製路網，將節點圖示放在 map node 座標，
並讓道路圖示位於住宅與角色圖層之下。缺少或驗證失敗的圖示會保留 graph edge 與節點
命中區，避免路線變成不可見。來源執行檔另有透視／旋轉的座標投影表；本實作尚未還原
原版 perspective 或 rotation，也未宣稱目前視圖是原版鏡頭。
