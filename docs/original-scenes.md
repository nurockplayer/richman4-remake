# 本機原版場景

`python3 tools/decode_original_ground.py --source /本機/原作 --output .local/original-scenes`
會匯入兩版本的 12 張底圖、12 位角色各 8 個靜態方向，以及各地圖 5 級住宅。
原作、PNG、manifest、私人套件皆不得提交或上傳。

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

## 已驗證與差異

已在私人 macOS 套件查看台灣地圖，擲骰、直接點選分岔與縮放可運作。
另以本機 Godot 渲染測試局，配置不同等級住宅及角色，確認房屋落在土地框、角色位於道路。
合成 UI 測試驗證載入、hash mismatch fallback、路線點擊及縮放平移後的命中位置。

目前只有底圖、靜態住宅與角色站姿。地景、特殊建物、行走／交通工具動畫、角色隨移動轉向、
屋主 palette 換色尚未還原；屋主用道路色點表示，住宅可見原始 cyan 色邊。
同格角色略微錯開以便辨識。開局道路仍沿用既有路網 heuristic，尚未查證原作初始位置。
