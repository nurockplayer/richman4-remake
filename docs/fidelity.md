# 保真度狀態

本頁把兩種證據分開記錄：一種是擁有者授權的原作位元組、解析結果、反組譯與說明書頁面，另一種是 Godot 重製版目前的執行時行為。兩者都不能單獨推出「與原作完全相同」或一個保真度百分比。

目前發行來源是 [`159aeb0`](https://github.com/nurockplayer/richman4-remake/commit/159aeb036a71194badc564a2064e750655bd7484)。[Issue #89](https://github.com/nurockplayer/richman4-remake/issues/89) 的最終 release acceptance 已通過：在 ARM64 M2 Pro 上以 plain packaged app 完成一名人類手動擲骰／選路、三名 AI 持續循環的新局；另完成四名 AI 的 30 日／120 次操作 settlement，最終由沙隆巴斯於第 121 回合獲勝。驗收也通過磁碟存檔／讀檔／再存檔相等、production JSON encoding equality、重開、音樂 next-track，以及正常退出且沒有 engine errors；套件不依賴開發用素材路徑、`audio.cfg` 或環境變數。產物已移至 `/Users/tachikoma/Applications/大富翁 4 · 城市棋局.app` 並通過 codesign，擁有者存檔已逐位元還原，`audio.cfg` 恢復原先不存在的狀態，暫時移開的開發素材目錄也已還原。

這是重製版套件與流程的 release 證據，不是原作等價證明。目前沒有原作執行檔在同一環境下的可重現 golden trace，也沒有量測出的保真度百分比；原作規則、媒體映射、鏡頭與操作節奏仍須以對應來源或可重現觀察逐項核對。

## 已由本機資料核對

`tools/import_original.py` 以 owner-provided `dfw4cskzl_136622` 的 `Game/` 與 `MultiverseJourney/` 為輸入，驗證到下列結果：

| 來源版本 | `map.mkf` resource index | 地圖數 | 節點／土地／設施／企業／景觀數量 |
| --- | --- | ---: | --- |
| `Game` | 1、3、5、7 | 4 | 103/50/4/3/21；144/73/8/4/26；110/49/5/6/16；118/55/8/6/16 |
| `MultiverseJourney` | 1、3、5、7、9、11、13、15 | 8 | 103/50/4/3/21；144/73/8/4/26；110/49/5/6/16；118/55/8/6/16；135/47/5/3/2；135/60/3/12/143；141/55/6/3/154；101/0/20/7/79 |

每張地圖的 40 位元組標頭（10 個 32 位元欄位）、dummy record、固定 record size、section offset 與 payload 結尾都通過邊界核對；目前這 12 張地圖的節點鄰接欄位沒有指向不存在節點的值。土地、設施與景觀名稱永遠保留原始位元組；目前所有非空名稱都通過 CP950 嚴格解碼與回編碼相等核對，因此匯入資料附帶 `display_name` 與 `display_name_confidence: "inferred-roundtrip"`。這是目前 payload 的編碼證據，原版 UI 的字型與顯示仍需執行時觀察。

Runtime loader 另外核對雙向鄰接、住宅參照唯一性與住宅從起點的可達性。超時空之旅第 5 張地圖有 20 個無鄰接的非住宅節點，匯入時保留它們，不補造道路；所有住宅均可到達。第 8 張只有商業設施而沒有住宅，v5 商業系統接入後已開放對局。第 6 張有一筆名稱全零的住宅，以「未命名住宅 48」呈現，不虛構來源名稱。

12 張來源地圖共有 15 個 `event_code == 14` 銀行服務節點，均同時具有企業物件編號。銀行服務保留原作經過 ATM／停留銀行的 dispatch；完整十二股 catalog 啟用 v7 時，另以來源企業 ID 接入持股與經營權。

節點輸出保留原始 `status_bits` 與 `field_0x22`，另提供 `event_code = status_bits & 0xff` 與 `visual_index = field_0x22`。原版落地 dispatch 的 jump table 將 1–16 對應到事件／UI；`field_0x22` 在繪圖路徑中作資源索引，因此兩者在重製 runtime 中必須分開。這些欄位對應由 `.local/research-rich4/asm/rich4_player_core_actions.asm` 的 `rich4_handle_player_land_on_node` 與相關繪圖反組譯核對，並以 `catalog.json` 的原始節點值交叉檢查。

價格欄位也已依反組譯與本機 fixture 核對：housing land 結構的 `+0x1c` 是 `land_price`，`+0x1e` 是 `house_price`；`+0x20..+0x2b` 是六個 rent `u16`，輸出為 `rent_by_level`。購買成本使用 `(land_price + level * house_price) * price_index`；`price_per_level` 僅保留為等於 `house_price` 的舊欄位別名。facility 結構的 `+0x22`／`+0x24` 則分別是 `land_price`／`house_price`。原版來源證據位於 `.local/research-rich4/csrc/land.h` 與 `.local/research-rich4/asm/rich4_player_core_actions.asm`；目前未宣稱所有事件高位旗標或完整 UI 行為已核對。

節點類型數值依原始欄位保留。`2000–3999` 目前標為土地、`4000–5999` 標為設施、`6000–7999` 標為企業，其餘值標為 `other`；這是對資料欄位的保守分類，不是完整事件規則的證明。土地所有權欄位在匯入的初始地圖資料中為 0。

## 狀態分層

| 面向 | 狀態 | 證據與缺口 |
| --- | --- | --- |
| 容器與地圖結構 | 已核對 | MKF 絕對 offset、16 位元組 resource header、40 位元組地圖標頭（10 個 32 位元欄位）、五種資料表與鄰接界線均由本機檔案驗證。 |
| 原作規則 | 部分核對 | [manual-rules.md](manual-rules.md) 索引了說明書頁面；起始金額、完整租金表、事件順序與部分例外仍需原版執行觀察或更多資料對照。 |
| 地圖與靜態場景 | 已接入；原作差異未量化 | 12 張地圖的節點、座標、鄰接、名稱位元組與物件欄位已輸出；底圖、靜態住宅／地景／企業與角色八方向站姿可由本機素材呈現。設施升級圖像、原版 UI 顯示、屋主 palette 與地圖排序仍待驗證。 |
| 其他內容資源 | 部分盤點；私有壓縮內容未解碼 | `Data.mkf`、`Effect.mkf`、`help.mkf`、`jump.mkf`、`Panel.mkf`、`Speaking.mkf` 已有 container inventory，但私有壓縮記錄仍沒有完成 codec、像素、音訊或語音驗證。 |
| 音樂與音效 | 重製版已接入；原作映射未核對 | 套件內含經驗證的音樂，release acceptance 已確認播放 next-track；本機來源共有 25 個 OGG 曲目。`Midi.txt`、`InstOK.wav`、`InstSel.wav` 與版本目錄媒體已列入來源清單，但曲目映射、混音曲線、播放時機、音效與語音節奏仍是 Unknown。 |
| UI、動畫與操作節奏 | 部分接入；原作差異未量化 | Board 目前以平面地圖、八方向站姿移動與既定路線呈現；沒有宣稱原版步態、交通工具動畫、原作 timing、透視或旋轉鏡頭已還原。缺素材時仍保留可操作路網 fallback。 |
| 可重現遊戲狀態 | 重製版 release acceptance 已通過；原作對照 Unknown | 重製版已驗證固定 seed、存讀檔／再存檔、重開與長局 AI 流程；尚未有原版骰子、回合、存檔、隨機數與事件序列 golden trace，因此不能宣稱與原作一致。 |

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

Godot 桌面版本已具備 2–4 人新局、固定 seed、擲骰／買地／逐次加蓋、租金與破產、AI 接手、銀行／股票、已接入的卡片與道具效果、存讀檔、結算重開，以及隨 app 附帶的音樂。上述可操作範圍已納入 [Issue #89](https://github.com/nurockplayer/richman4-remake/issues/89) 的 release acceptance；它描述重製版行為，不等同原版 golden trace。

原版 catalog 已接入選圖、座標路網、分岔選路與地圖身分存檔；沒有本機 catalog 時顯示明確標示的 40 格測試棋盤。住宅採來源地價、建屋成本及六級租金表；路口允許玩家選方向，AI 只走原始鄰接邊。經過卡片／點數／銀行格有對應處理，其他尚未還原的特殊格顯示「待還原」。

v5 商業設施版本已在本機十二張來源地圖完成四位 AI 的三十日對局，並核對 JSON 存讀後的續玩一致。此為重製規則的對局與重播證據，並非原版執行軌跡對照；後續版本的最終驗證另記於各 PR。

新局已接開局金額／角色選擇與真實日曆，詳見 [calendar-and-setup.md](calendar-and-setup.md)。原版場景與角色靜態站姿詳見 [original-scenes.md](original-scenes.md)。v4 已接 30 張卡片與 13 種工具的目錄、有限供給、背包與點券商店，詳見 [original-inventory.md](original-inventory.md)；目前發行版本已接入全 30 張卡片與 13 種工具的效果入口（見 [Issue #89](https://github.com/nurockplayer/richman4-remake/issues/89)），但入口不代表每個效果已按原作核對，未實作效果不得回報成功或消耗物品。v5 已接公園、旅館、購物中心與加油站，詳見 [original-facilities.md](original-facilities.md)。v6 已接神明附身、每日倒數、財神／窮神收費、福神建設、天使／惡魔／土地公停留結算及惡犬住院，詳見 [original-gods.md](original-gods.md)。v7 接入來源十二股、企業持股、服務、分紅與保險，詳見 [original-companies.md](original-companies.md)。v8 接入住院／入獄移動與自身回合，以及陷害、免罪、嫁禍與復仇流程，詳見 [original-statuses.md](original-statuses.md)。v9 接入地雷、定時炸彈與機器娃娃，修正最終落地觸發與道路物件供給守恆，詳見 [original-road-hazards.md](original-road-hazards.md)。v10 接入換地／換屋與可見目標選擇，詳見 [original-property-cards.md](original-property-cards.md)。v11 接入改建與住宅連鎖店、相應租金及既有建造／破壞路徑，詳見 [original-remodel.md](original-remodel.md)。v12 接入研究所建造、產品選擇與擁有者回合生產，詳見 [original-research.md](original-research.md)。v13 接入天使、惡魔與怪獸建物卡；送神符與請神符直接重用既有神明遊局，沒有新增存檔版本，見 [original-gods.md](original-gods.md)。Issue #81 接入時光機與傳送機的目標選擇、傳送效果、volatile anchor 與回合延續邊界，詳見 [original-time-transport.md](original-time-transport.md)。工程車沿既有背包與存檔模型接入，使用獨立載具規則模組，見 [original-engineering-vehicle.md](original-engineering-vehicle.md)。搶奪卡沿用現有有限背包，接入可見對手及物品選取、容量特例與 AI，見 [original-theft.md](original-theft.md)。Issue #78 拍賣卡沿用現有有限背包，接通住宅／設施出價、流標、成交與存讀檔續接，詳見 [original-auctions.md](original-auctions.md)。音樂來源與 fallback 規則詳見 [original-audio.md](original-audio.md)；移動呈現與目前 0.16 秒的重製版結果動畫詳見 [movement-presentation.md](movement-presentation.md)。

部分經濟參數與地產破產分配仍屬暫定，部分卡片／工具的原作精確細節、特殊人物、其他企業服務、小遊戲、原作鏡頭、步態與交通工具動畫仍有已知 fallback 或 Unknown。這些狀態記錄於本頁，後續只在擁有者指定範圍內處理；[Issue #1](https://github.com/nurockplayer/richman4-remake/issues/1) 的完成條件已由上述 release acceptance 通過，進入關閉流程。
