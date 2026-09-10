# 銀行／提款機來源畫面 presenter

`RichmanSourceBankPanel` 是 S11–S13 的純 UI presenter。它接收 host 提供的
view model，負責來源座標內的選取、金額輸入與畫面回饋；不持有帳務、存檔或
亂數，也不直接呼叫遊戲核心。父層收到確認訊號後，仍須重新查詢核心並更新
view model。

## View model

呼叫 `set_view_model(model: Dictionary)` 時，元件會深拷貝字典。支援的欄位是：

| 欄位 | 用途 |
| --- | --- |
| `edition` | `Game` 或 `MultiverseJourney` 的來源版別；接受小寫、`MJ` 等別名；`front`／`rear` 不是 edition |
| `entry_mode` | `atm` 顯示提款機，`loan` 一律先顯示 Panel23 前台 |
| `allowed_actions` | 正式允許的 action 陣列，或 action→bool 字典 |
| `action_limits` | 正式 action→非負整數上限；元件不自行推算額度 |
| `cash`, `deposit`, `loan`, `due_date` | 無來源圖時的 fallback 資訊；原版 art 模式不加畫常駐餘額標籤 |
| `special_principal`, `other_deposits` | 後台特殊融資摘要的 host 數值 |
| `can_special` | 銀行主席 gate；不是 `true` 時特殊融資控制保持停用 |

未知模式、錯誤型別、負數、非整數或非有限上限會被拒絕或停用，缺少數值顯示
為 `—`，不以預設餘額冒充資料。`view_model()` 可取得另一份深拷貝供測試。

## 來源座標

元件的 logical size 與輸出視窗大小分離；父層可把整個控制項縮放或放到棋盤上，
不應用目前 PNG 的 pixel 尺寸推算 gameplay 或命中區。

| 畫面 | logical size／位置 | 控制項來源矩形 |
| --- | --- | --- |
| Panel24 ATM | `320×338`，棋盤上的 `(60,71)` 由父層定位 | 提款 `(57,49,80,41)`、存款 `(139,49,80,41)`、EXIT `(221,49,43,41)` |
| ATM 金額 | 同上 | 金額條 `(53,137,215,29)`；數字按鍵 x=`58/97/136`、y=`211/230/249/268`、`33×17`；MAX `(183,233,49,25)`；ENTER `(175,260,57,25)` |
| Panel23 前台 | `640×480` | 申請貸款 `(282,324,126,42)`、償還貸款 `(470,326,120,40)`、EXIT `(548,431,80,40)` |
| Panel23 後台 | `640×480` | 週轉現金／歸還款項 `(11,305,114,40)`／`(11,362,114,40)`；EXIT `(11,419,80,40)` |
| Panel21 calculator | `128×192`，疊在銀行場景 `(256,144)` | MAX `(8,63,49,25)`、ENTER `(64,63,57,25)`；C／0／退格 x=`8/48/88`、y=`95`，數字列 y=`119/143/167`、`33×17` |

`loan` 的前台／後台是同一流程內的 scene state，不由 `edition` 或
`allowed_actions` 推導。`can_special=true` 時，前台才建立 owner-only 透明入口
`(268,51,323,222)`；點擊後才進入後台。非主席前台可綁定 Panel23 chunk1，來源偏移
`(62,198)` 以 `(320,240)` 為 anchor，畫在 `(258,42)`。後台綁定 chunk2 與 chunk20
summary；chunk20 放在 `(10,125)`。後台 EXIT 回到前台，前台 EXIT 才發出 `closed()`。
刷新 view model 時，仍有效的後台 scene 會保留；`can_special` 被撤銷則立即回前台。

後台的三組文字保留來源中心 x=`78`、y=`147/195/243`，對應金額右界 x=`128`、
y=`163/211/259`。`週轉現金` 是原版文字；正式 action 是
`take_special_finance`，其 accounting 語意由核心決定為增加 `deposit`，元件不
把標籤改成現代化名稱。

`set_visuals(accessor)` 接受 keyed `Dictionary`、`Callable`，或提供
`ui(edition, archive, resource, chunk)` 與 `texture(frame)` 的 resolver。前者可用
`Game.Panel24`、`Game.Panel23.front`、`Game.Panel23.rear`、`Game.Panel23.chunk1`、
`Game.Panel23.chunk20`、`Game.Panel21` 等 key；後者會查詢 Panel24／23／21 的指定
chunk。來源圖存在時，按鈕是透明 hit target，只有原版動態 labels 疊在來源 art 上；缺少主圖時
才保留來源座標 fallback controls。Panel22 沒有視覺資源，因此不會建立或假造 Panel22
圖像。原圖、匯出器與 full cache 由父層另行接入。

## Signals 與操作

元件只在明確確認且輸入通過 host limit 時發出
`action_requested(action: String, amount: int)`。action 使用核心名稱：
`withdraw`、`deposit`、`take_loan`、`repay_loan`、`take_special_finance`、
`repay_special_finance`。選取提款／存款或貸款按鈕本身不會送出 action；MAX、金額條、
數字鍵、清除、退格與鍵盤數字也只改 presenter 狀態。

空白、零、負數、含空白、非數字、非整數與超過上限的輸入不會發出 action 訊號。
來源模式保留 source amount display／停用確認；fallback 模式另顯示文字錯誤。
ATM 的提款在左、存款在右，且 MAX 只填入該 action 的 host 上限。
貸款／特殊融資按鈕會開啟獨立 Panel21 calculator；calculator 的取消只返回目前銀行
scene。ATM 與 calculator 只有在自身可見時才攔截鍵盤事件。銀行前台 EXIT 或沒有選取
金額時的 Escape 才發出 `closed()`；後台 EXIT 只返回前台，由父層決定返回上一個流程。

## 驗證

```sh
godot --headless --path . --script tests/source_bank_panel.gd
```

測試以 SubViewport `push_input` 驗證鍵盤／滑鼠事件，以及按鈕事件、上限與 gate、三種
scene、calculator 取消、source chunk 組合和 host dictionary 不變。來源圖層以高對比
texture 做像素檢查；Godot dummy headless renderer 會明確 SKIP 該像素段，需在可渲染的
native lane 重跑。這些測試證明 Godot 控制項事件邊界，不宣稱作業系統實體輸入、原生
視窗時序、原版素材完整匯入或畫面相似度已驗收；來源動畫時序的微小不確定性仍依契約
記錄，待父層素材／MainUI 接線後另做整合與視覺審查。

## 實際原圖修正與界線

原版 art 模式隱藏 fallback HSlider、LineEdit 與泛用常駐說明，避免滑桿圓點或重複字樣
覆蓋來源圖。ATM 使用 Panel24 chunks19–28 的數字，末位 `(244,101)`，步距20；
chunk4 的百分比列在 `(58,139)`，寬度依34階比例裁切。Calculator 使用 Panel21
chunks16–25 的數字，末位 `(107,11)`，步距12；百分比列 `(10,42,108,12)` 的點擊採原版
34個 threshold 對應 `floor(limit * index / 33)`，繪製採 `threshold[floor(amount * 33 / limit)]`，
零金額另顯示全空。先畫 empty chunk1，再從 source background0 複製 filled prefix。MAX、ENTER、C、0、退格與數字鍵
的 pressed art 分別使用 Panel21 chunks2–15。ATM 使用 Panel24 chunks1–18。

前台動態貸款文字中心 `(345,345)`／`(530,345)`，26px 黑色；主席入口文字中心
`(492,245)`，14px 灰色。後台按鈕以 chunks16–19 組成，摘要金額保留 `$` 與千分位，
下方「特別融資」中心 `(443,427)`、26px 黑色。元件使用目前可用的中文字型；
原作 GDI 字型筆畫與場景動畫／對話出現時序尚未宣稱完全一致。

測試-only `828567d` 先取得 `Source bank visual checks: 218, failures: 174`，
修正後同一份測試為264/0（條件式後續檢查在節點存在時才執行）。人工對照仍看到
fallback 滑桿圓點，`427df44` 只增加禁止該圖層的檢查，在當時未提交的修正工作樹
得到266/2；隱藏滑桿後266/0。原有 bank presenter74項與原生像素76項保持不變。
`tools/check.sh` 執行 presenter 與 visual 兩套測試。

以 pinned 私有素材、隔離 SubViewport 拍攝 Game／MultiverseJourney 的提款機、前台、
後台、非主席前台及 calculator，並與原版 article22–24／來源繪製座標比對。
這些影像只支持元件構圖方向；MainUI 入口、帳務後續、原生實體輸入與目前 package
仍需另外驗收，不能將此元件或 headless 全綠視為 S11–S13 完整 PASS。

新的獨立審查指出 Panel21 線性比例與來源 threshold 不同，以及按鍵 `0→1` 在一位數
額度下會因前導零被錯判超額。Root 核對實際 chunk0／1 後也修正百分比列的填色方向。
不變 tests-only `1f906a3`：headless20/18、native68/60 合格 RED；修正後20/0、68/0。
原生 pixel case 使用來源相同的 filled-background／empty-strip 結構，分別檢查
0／1／1700／3300 金額的左側實心、右側空白與離散寬度，沒有使用自訂全綠 baseline。
ATM／calculator 的實際滑鼠按鍵還驗證重複零仍是一個0，接續1並ENTER可正確送出1；
既有嚴格 amount parser、外部 malformed-input 拒絕和所有266／74 assertions保留。
