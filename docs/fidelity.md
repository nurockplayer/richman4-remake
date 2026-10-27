# 保真度狀態

本頁把兩種證據分開記錄：一種是擁有者授權的原作位元組、解析結果、反組譯與說明書頁面，另一種是 Godot 重製版目前的執行時行為。兩者都不能單獨推出「與原作完全相同」或一個保真度百分比。

2026-09-10 擁有者退回主棋盤與股市的呈現驗收。[#1](https://github.com/nurockplayer/richman4-remake/issues/1) 已重新開啟，Mission 尚未完成；[#99](https://github.com/nurockplayer/richman4-remake/issues/99) 要求完整原版玩家畫面與操作流程的逐幕比較及獨立審查。先修復 #100 的成品能力入口，再驗收 #101 主棋盤／股市及 #102 其餘畫面。目前沒有任何畫面在這次修復階段取得最終呈現 PASS。即時進度以 #52 body 為準。

目前發行來源是 [`159aeb0`](https://github.com/nurockplayer/richman4-remake/commit/159aeb036a71194badc564a2064e750655bd7484)。[Issue #89](https://github.com/nurockplayer/richman4-remake/issues/89) 的最終 release acceptance 已通過：在 ARM64 M2 Pro 上以 plain packaged app 完成一名人類手動擲骰／選路、三名 AI 持續循環的新局；另完成四名 AI 的 30 日／120 次操作 settlement，最終由沙隆巴斯於第 121 回合獲勝。驗收也通過磁碟存檔／讀檔／再存檔相等、production JSON encoding equality、重開、音樂 next-track，以及正常退出且沒有 engine errors；套件不依賴開發用素材路徑、`audio.cfg` 或環境變數。產物已移至 `/Users/tachikoma/Applications/大富翁 4 · 城市棋局.app` 並通過 codesign，擁有者存檔已逐位元還原，`audio.cfg` 恢復原先不存在的狀態，暫時移開的開發素材目錄也已還原。

這是重製版套件與流程的 release 證據，不是原作等價證明。目前沒有原作執行檔在同一環境下的可重現 golden trace，也沒有量測出的保真度百分比；原作規則、媒體映射、鏡頭與操作節奏仍須以對應來源或可重現觀察逐項核對。

## 逐畫面保真度

本表在 2026-10-26 JST 以 main 的程式與文件核對，一行一個玩家可見畫面；測試檔名是 `tests/` 下的實際檔案。素材狀態用語：

- **exported+bound**：公開的 export／prepare 工具能產生該素材，執行時由私有 scene manifest 的 `ui.<edition>.<archive>.resources["<resource>"].chunks["<chunk>"]` 綁定（載入器見 `game/platform/original_visuals.gd`）。沒有私有 manifest 的公開 checkout 一律走 fallback；本欄描述私有 manifest 已安裝時的狀態。
- **placeholder**：沒有可用原作素材時，以來源座標繪製的可操作替代，不冒充原作。
- **none**：沒有原作素材，使用重製版 UI。
- **UNKNOWN**：未核對，不推定。

| 畫面 | 原作素材（exported+bound／placeholder／none）與 manifest key／檔案 | 行為（符合原作／已知偏離） | 測試檔 | 未結案 follow-up |
| --- | --- | --- | --- | --- |
| 標題 Title | exported+bound：`ui.<edition>.Data.1`（chunk 0 背景；2／4／6／8／10 hover；Game／MJ 各自綁定），由 `tools/original_ui_assets.py` 匯出 | 符合來源 640×480 構圖、來源 hit region、hover chunk 與左鍵按下即送意圖；版本標籤 `V3.11` 另繪。實體 OS 輸入與目前套件入口未驗（#204） | `tests/source_title_panel.gd`, `tests/source_title_ui.gd` | 實體滑鼠／鍵盤與 EXIT 離開流程在候選套件上驗收 |
| 新局設定 Setup | exported+bound：`ui.<edition>.jump.4`（Game）／`.jump.8`（MJ）atlas、`ui.<edition>.Data.2` 肖像、`ui.<edition>.jump.5–40`／`9–44` 角色車輛預覽 | 符合來源 frame 幾何、肖像點選順序、車輛預覽與 stage／edition 傳遞；缺同版地圖時該列停用。偏離：缺私有 atlas 時顯示角色名文字版，不冒充原作 | `tests/source_setup_ui.gd`, `tests/source_setup_interaction.gd`, `tests/source_setup_factory.gd`, `tests/setup_controls.gd`, `tests/setup_ui.gd` | 實體輸入；缺地圖時仍保留 legacy 新局 popup fallback |
| 主棋盤 Board | exported+bound：私有 scene manifest 的 `maps[].image`、`house_sprites`、`scenery_sprites`、`road_sprites`、`characters`，加上 `ui.<edition>.jump.0–3`（Game）／`0–7`（MJ）底圖；缺 manifest 時顯示明確 fallback 路網 | 符合來源節點、座標、鄰接與八方向站姿。偏離：平面 2D 鏡頭與 0.16 秒移動呈現，沒有原作透視／旋轉鏡頭、步態與交通工具動畫 | `tests/map_ui.gd`, `tests/map_loader.gd`, `tests/movement_ui.gd`, `tests/movement_presentation.gd`, `tests/board_camera.gd`, `tests/scene_visuals.gd` | 原作鏡頭、步態與設施升級圖像（#99） |
| HUD／工具列 | exported+bound：`ui.<edition>.Panel.0`（200×280 HUD）、`ui.<edition>.Panel.1`（439×40 工具列與圖示）、`ui.<edition>.Data.2` 肖像 | 符合來源 HUD／工具列幾何與 tab 行為。偏離：文字使用 Godot 字型，Windows 字型 raster 未核對 | `tests/main_hud_ui.gd`, `tests/ui_flow.gd`, `tests/source_view_modes_main_ui.gd` | 字型 raster；#204 實體滑鼠可達性 |
| 小地圖／日曆／三種檢視 | exported+bound：日曆 `ui.<edition>.Panel.2` chunks 0–3／4–7／8／11；小地圖沒有專用原作 bitmap，使用棋盤 scene 圖縮放 | 符合來源 view 0／1／2 幾何、TAB 循環、日曆閏年（含 2100）與日／月樣式。偏離：小地圖不是原作小地圖素材，無地區節慶；日／月樣式只是 runtime 呈現狀態 | `tests/source_view_modes.gd`, `tests/source_view_modes_main_ui.gd`, `tests/source_calendar_panel.gd`, `tests/source_calendar_input.gd`, `tests/source_calendar_main_ui.gd`, `tests/source_calendar_sunday.gd`, `tests/calendar.gd`, `tests/board_camera.gd` | 原作小地圖素材／投影比對 |
| 回合控制與提示（GO／YES／NO、選路、購買／升級、付款與陷阱提示） | placeholder：以來源座標重繪的選擇框與 picker（`game/ui/game_shell.gd` 常數），沒有原作 tile bitmap；工具列圖示仍來自 `ui.<edition>.Panel.1` | 符合來源選項位置與 `await_roll`／`await_route`／`await_action` gate。偏離：顏色與字型為重製，非原作 tile；提示文字用 Godot 字型 | `tests/main_hud_ui.gd`, `tests/ui_flow.gd`, `tests/movement_ui.gd`, `tests/trap_ui.gd`, `tests/sleep_cards_modal.gd`, `tests/financial_ui.gd`, `tests/ui_full_match_soak.gd` | 來源選擇框／picker tile 素材 |
| 股市 Stock | exported+bound：`ui.<edition>.Panel.75` chunks 0–6（六欄價格、七欄持股、公司資訊、走勢圖） | 符合來源欄位構圖與 12 股買賣入口。偏離：走勢與字型為重製，未逐像素比對；owner 已退回舊 dashboard 呈現 | `tests/market_entry_ui.gd`, `tests/market_entry_active_presentation.gd`, `tests/stock_presentation.gd`, `tests/stock_accounting.gd`, `tests/stock_popup_mode_ui.gd`, `tests/company_market.gd` | 股市畫面視覺驗收（#1 指定 board／HUD／stock 需原作導向呈現） |
| 銀行 ATM／貸款／特殊金融 | none：Panel23／24（ATM／銀行）與 Panel21（金額盤）沒有公開 exporter；執行時接受私有 overlay，否則顯示 art-free 可操作 fallback。特殊金融付款選擇是 Godot `financial_presentation.gd` popup | 符合 ATM 前／後景、存提、借還、貸款與免費／查稅付款選擇的流程與金額限制。偏離：沒有原作銀行／ATM 素材，付款 popup 為重製 UI | `tests/source_bank_panel.gd`, `tests/source_bank_controller.gd`, `tests/source_bank_ui.gd`, `tests/source_bank_visit.gd`, `tests/source_loans.gd`, `tests/source_bank_visual.gd`, `tests/source_bank_amount_regressions.gd`, `tests/source_bank_modal.gd`, `tests/source_bank_controller_host.gd`, `tests/financial_ui.gd`, `tests/special_finance.gd` | 匯出 Panel23／24／21 或讓 #99 接受 placeholder；付款 popup 素材 |
| 月報（股利／利息） | exported+bound：`ui.<edition>.Panel.76`（分紅表）、`ui.<edition>.Panel.25`（利息報表、行員與帳戶卡） | 符合 15 日分紅、月底利息、排在 news／銀行 modal 之後，以及關閉不重算。偏離：旁白、姿勢動畫與精確節奏未還原；原生 focus gate 仍 HOLD | `tests/monthly_statements.gd`, `tests/source_monthly_panel.gd`, `tests/source_monthly_controller.gd`, `tests/source_monthly_ui.gd`, `tests/source_monthly_focus.gd`, `tests/source_monthly_money.gd`, `tests/source_monthly_lifecycle.gd`, `tests/source_monthly_deferred.gd`, `tests/source_monthly_final.gd`, `tests/source_monthly_rendering.gd`, `tests/source_monthly_catalog.gd` | 原生 focus HOLD；完整旁白／動畫 |
| 樂透 Lottery | exported+bound：私有 lottery overlay 的 Panel14／16／17 動畫與 Panel12／13／15（`tools/prepare_lottery_assets.py`）；缺 manifest 時同名 placeholder 矩形與文字 | 符合 01–36、1,000 現金購買、共用 jackpot、15 日先分紅後開獎。偏離：購買先結算再顯示、語音節奏簡化、已售格用暗化近似 | `tests/source_lottery_panel.gd`, `tests/source_lottery_controller.gd`, `tests/source_lottery_ui.gd`, `tests/source_lottery_core.gd`, `tests/source_lottery_rules.gd`, `tests/source_lottery_admission.gd`, `tests/source_lottery_settlement.gd`, `tests/source_lottery_save.gd`, `tests/source_lottery_bankruptcy.gd`, `tests/source_lottery_game_over.gd`, `tests/source_lottery_public_purchase.gd` | 整幕視覺與語音節奏；creditor -1 的費用流向仍缺口 |
| 小遊戲（七彩氣球／企鵝挖寶／喜從天降） | exported+bound：私有 minigame manifest 的 Panel78–111 與 Data485／526（`tools/prepare_minigame_assets.py`）；缺 manifest 時明確 fallback | 符合三款來源模型、tick 期限、命中框與 AI／託管 shortcut。偏離：不 warp OS 游標、精確首繪與音效未核對，活動中不可存檔 | `tests/source_minigame_models.gd`, `tests/source_minigame_panel.gd`, `tests/source_minigame_controller.gd`, `tests/source_minigame_ai_runner.gd`, `tests/source_minigame_balloon_recovery.gd`, `tests/source_minigame_main_ui.gd`, `tests/source_minigame_save.gd`, `tests/source_minigame_source_reclaim.gd`, `tests/source_minigame_unknown_kind.gd`, `tests/source_minigame_bomb_mapping_native.gd` | 實體輸入與原作 runtime timing；All36 |
| 商店 Shop | exported+bound：私有 Panel10 slice（`tools/prepare_source_shop.py`）；缺圖顯示「來源畫面素材未載入」 | 符合有限次商店、加權卡攤、單品買賣與贈品 1.5 秒 gate。偏離：套件整合與實體輸入未驗 | `tests/source_shop_core.gd`, `tests/source_shop_panel.gd`, `tests/source_shop_ui.gd`, `tests/source_shop_catalog.gd`, `tests/source_shop_lifecycle.gd`, `tests/test_source_shop_assets.py` | 套件整合與實體輸入 |
| 背包 Inventory | exported+bound：私有 Panel11 chunks 0–16、車輛 15／16（`tools/prepare_inventory_assets.py`）；缺圖保留可讀 fallback | 符合持有順序／重複、工具 1–13、機車汽車 command 14 與共享供給。偏離：Windows 字型 raster 未核對，按下位移為近似 | `tests/source_inventory_panel.gd`, `tests/source_inventory_ui.gd`, `tests/source_inventory_catalog.gd`, `tests/source_inventory_lifecycle.gd`, `tests/inventory_ui.gd`, `tests/inventory_flow.gd`, `tests/inventory_runtime.gd` | S22 target／reaction 外觀；套件 |
| SALE 佈告板 | 部分 exported+bound：私有 Panel73／74 overlay（`tools/prepare_source_sale.py`）與 YES／NO frames Data399／440；board portrait 仍是 placeholder，`source_art_available()` 回 false | 符合七格報價、四類清單、全額現金入賣方存款與無 escrow。偏離：地產顯示格式、細節排版與頭像未完成 | `tests/source_sale_rules.gd`, `tests/source_sale_panel.gd`, `tests/source_sale_controller.gd`, `tests/source_sale_catalog.gd`, `tests/source_sale_stock_cost.gd`, `tests/stock_accounting.gd`, `tests/test_source_sale_assets.py` | 頭像與細節構圖、兩版 native 1x／2x 比對、實體輸入 |
| 說明 Help | exported+bound：私有 help bundle 的 `help.0` frame 與 icons（`tools/export_original_help.py`／`tools/package_help.py`）；文字 bundle 私有 | 符合 400×400 三欄、8 分類 99 主題、PageUp／PageDown 翻頁、右鍵關閉與阻擋底層。偏離：精確字型 raster 與語音未核對 | `tests/source_help_panel.gd`, `tests/source_help_controller.gd`, `tests/source_help_ui.gd`, `tests/original_help.gd` | 套件導覽與 source／remake rendered comparison（#192） |
| 選項／日期／熱鍵／託管 | exported+bound：`ui.<edition>.Data.3`（一般選項、日期、熱鍵）、`ui.<edition>.Panel.77`（託管 18 chunks） | 符合六欄設定持久化、標題 OPTION 與遊戲中「系」、日期子視窗成為下一局起始日、28 欄熱鍵與託管比例。偏離：音效引擎、動畫切場與視窗模式尚無 runtime consumer，完整 S35 未完成 | `tests/source_options_panel.gd`, `tests/source_options_main_ui.gd`, `tests/source_options_rendering.gd`, `tests/source_preferences.gd`, `tests/system_settings.gd`, `tests/source_date_panel.gd`, `tests/source_date_rendering.gd`, `tests/source_date_hint_layout.gd`, `tests/source_hotkeys_panel.gd`, `tests/source_hotkeys_focus.gd`, `tests/source_hotkeys_pixels.gd`, `tests/source_hotkeys_rendering.gd`, `tests/system_hotkeys.gd`, `tests/source_trustee_dialog.gd`, `tests/source_trustee_ui.gd`, `tests/source_trustee_source_layout.gd`, `tests/trustee_core.gd`, `tests/trustee_consumers.gd`, `tests/trustee_preferences.gd` | 其餘 S35 consumer；實體 OS focus 熱鍵 |
| 存讀檔選單 Save／Load | exported+bound：`ui.<edition>.Data.479`（Game）／`.520`（MJ）全 chunks、Loading `ui.<edition>.Data.560`／`.601`、肖像 `ui.<edition>.Data.2` | 符合 hover 選列、左鍵按下直接啟用、右鍵取消與無頁尾。偏離：覆寫確認與 legacy continue 是已接受的資料安全偏離，Escape 是平台 fallback | `tests/source_save_panel.gd`, `tests/source_save_menu_ui.gd`, `tests/save_slots.gd`, `tests/save_shapes.gd`, `tests/save_slots_concurrency.gd`, `tests/ui_flow.gd` | S34 實體輸入與 Loading 原生呈現 |
| 自動存檔 Autosave | none：沒有專用畫面；AUTO 列沿用 `ui.<edition>.Data.479`／`.520`，失敗對話框是一般 Godot dialog | 符合每日 checkpoint、pending 月報／modal 完成後才寫入、row 0 AUTO 身分與 Retry／Skip。偏離：錯誤對話框外觀未驗收；終局不寫 AUTO | `tests/source_autosave.gd`, `tests/source_autosave_ui.gd`, `tests/save_slots_autosave.gd` | 原作風格錯誤對話框；native focus |
| 結算 Settlement | placeholder：`game/ui/main_ui.gd` 的 `SettlementOverlay`，HUD 紙張框式版面（#248） | 顯示勝者、結束原因（day_limit／wealth_target／calendar_limit／最後存活／全員破產）與依總資產排序的完整名次；重新開局／返回標題／結束程式；終局停用投降、不寫 AUTO。偏離：沒有原作結算畫面可比對 | `tests/match_settlement_ui.gd`, `tests/save_relaunch.gd`, `tests/ui_full_match_soak.gd`, `tests/surrender_ui.gd` | 原作結算素材；#204 完整對局 |
| 新聞／命運彈窗 | none：`game/ui/news_panel.gd`、`game/ui/fate_panel.gd` 的 Godot `PopupPanel` | 符合顯示已套用的抽取結果、自動關閉（2.4 秒／1.6 秒）與關閉不改 state 或 RNG。偏離：沒有原作新聞／命運畫面、旁白或音效 | `tests/news_ui.gd`, `tests/news_flow.gd`, `tests/news_timing.gd`, `tests/news_eligibility.gd`, `tests/news_save.gd`, `tests/news_save_limits.gd`, `tests/news_public_tax.gd`, `tests/news_bank_ui.gd`, `tests/fate_ui.gd`, `tests/fate_flow.gd`, `tests/fate_timing.gd`, `tests/fate_save.gd`, `tests/fate_graph.gd`, `tests/fate_state_contract.gd`, `tests/fate_contract_regressions.gd`, `tests/fate_public_charge.gd` | 原作新聞／命運呈現（#99） |
| 卡片／道具、拍賣與目標選擇 modal | none：`game/ui/main_ui.gd` 的 Godot Control／PopupPanel，以及 `auction_presentation.gd`、`theft_picker.gd`、`transport_picker.gd` 等 | 偏離：卡片／道具效果、拍賣出價與搶奪／傳送／工程車目標都由重製 modal 選取，再由 core 驗證；沒有原作卡面、拍賣或目標選擇素材，逐項流程未做原作比對 | `tests/building_card_ui.gd`, `tests/property_card_ui.gd`, `tests/god_card_ui.gd`, `tests/gods_ui.gd`, `tests/hazard_ui.gd`, `tests/status_ui.gd`, `tests/trap_ui.gd`, `tests/sleep_cards_ui.gd`, `tests/auctions_ui.gd`, `tests/theft_ui.gd`, `tests/time_transport_ui.gd`, `tests/engineering_vehicle_ui.gd`, `tests/remodel_ui.gd`, `tests/research_ui.gd`, `tests/missiles_ui.gd` | 卡面／拍賣／目標選擇的原作素材與逐幕比對 |

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
| 其他內容資源 | 壓縮解碼已驗證；資源語意部分核對 | 兩個版本全部 878 筆壓縮資源的解碼位元組已與研究用 C oracle 逐筆比對一致；Panel 樣本亦已輸出 SPR/SMP 與 PNG，見 [image-format.md](image-format.md)。這不代表所有像素色彩、透明、資源組合／用途、音訊或語音均已核對。 |
| 音樂與音效 | 曲目表與部分場景已對照原作；其餘未核對 | 來源 `rich4.exe` 曲目表 `47e773`：CD 音軌 02–09（RICH08、RICH16–22）為 8 首地圖曲，由 `454d91` 依序循環；音軌 10–26（MIDI01–16，含 14-1／14-2）為 17 段場景短曲，由 `4549cf` 播一次後從頭恢復地圖曲（`454bcc`）。已接入魔法屋、監獄／醫院入口、月底結算的短曲；其餘 4549cf 呼叫點（見 `docs/original-audio.md`）、混音曲線、音效與語音仍是 Unknown。 |
| UI、動畫與操作節奏 | 部分接入；原作差異未量化 | 逐畫面狀態見上表；Board 目前以平面地圖、八方向站姿移動與既定路線呈現，沒有宣稱原版步態、交通工具動畫、原作 timing、透視或旋轉鏡頭已還原。缺素材時仍保留可操作路網 fallback。 |
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

UI 素材的來源與打包邊界見 [original-ui-assets.md](original-ui-assets.md)；各畫面的規則、來源反組譯與已知偏離見 `docs/source-*.md`。沒有列在該頁 bounded UI slice 的 Panel（例如銀行 Panel23／24、金額盤 Panel21）目前沒有公開 exporter，必須先在私有 manifest 提供，否則照上表走 placeholder／none。

## 目前可操作的重製版本

Godot 桌面版本已具備 2–4 人新局、固定 seed、擲骰／買地／逐次加蓋、租金與破產、AI 接手、銀行／股票、已接入的卡片與道具效果、存讀檔、結算重開，以及隨 app 附帶的音樂。上述可操作範圍已納入 [Issue #89](https://github.com/nurockplayer/richman4-remake/issues/89) 的 release acceptance；它描述重製版行為，不等同原版 golden trace。

原版 catalog 已接入選圖、座標路網、分岔選路與地圖身分存檔；沒有本機 catalog 時顯示明確標示的 40 格測試棋盤。住宅採來源地價、建屋成本及六級租金表；路口允許玩家選方向，AI 只走原始鄰接邊。經過卡片／點數／銀行格有對應處理，其他尚未還原的特殊格顯示「待還原」。

各系統的來源證據與驗證範圍見 [calendar-and-setup.md](calendar-and-setup.md)、[original-scenes.md](original-scenes.md)、[original-inventory.md](original-inventory.md)、[original-facilities.md](original-facilities.md)、[original-companies.md](original-companies.md)、[original-gods.md](original-gods.md)、[original-statuses.md](original-statuses.md)、[original-road-hazards.md](original-road-hazards.md)、[original-property-cards.md](original-property-cards.md)、[original-remodel.md](original-remodel.md)、[original-research.md](original-research.md)、[original-time-transport.md](original-time-transport.md)、[original-engineering-vehicle.md](original-engineering-vehicle.md)、[original-theft.md](original-theft.md)、[original-auctions.md](original-auctions.md)、[original-financial-cards.md](original-financial-cards.md)、[movement-presentation.md](movement-presentation.md) 與 [original-audio.md](original-audio.md)。這些文件描述重製版規則與已量測的行為，不代表原作 golden trace；逐畫面缺口集中在 #99，v1.0 發行條件與 RC playtest 見 #1、#204 與 [rc-playtest.md](rc-playtest.md)。
