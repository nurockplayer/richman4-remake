# 卡片、道具與點券

`game/content/original_inventory.gd` 保存兩版共同的 30 張卡片與 13 種道具目錄。
每筆包含原作名稱、1 起算 source ID、初始共享供給量、點券價格及尚未解釋的兩個原始旗標。
既有五種卡片的短名稱 ID 保留，避免僅因顯示名稱改動破壞舊存檔。

## 來源與驗證

直接讀取擁有者本機的兩版 `rich4.exe`，每筆 8 bytes：32-bit 名稱指標，
+4 初始供給量、+5 點券價格、+6／+7 旗標。名稱指標依 PE section 轉為 file offset，
CP950 解碼；Game 卡片表位於 file offset `0x7c152`，道具表 `0x7c242`；
MultiverseJourney 分別 `0x7e3f2`、`0x7e4e2`。Godot 載入目錄後輸出 JSON，
逐筆與兩版二進位表比較 source ID／名稱／供給／價格／旗標：兩版各 43 筆完全相同。

原作說明書 PDF 第 11 頁記載卡片容量 15 張、每類道具最多 9 個。
初始供給並非個人容量：前八種道具的共享供給為 10，後五種為 0；研究道具取得方式另由
原作流程決定，不能僅以表中的 0 推論道具不存在。

研究 repository `mytbk/rich4` commit `54ff26750e7e7f585da6fe68c4e8972cd22ed509`
用於定位資料與流程，再回查擁有者二進位；不複製其 GPL C／ASM 實作。
所有原版執行檔、反組譯輸出及圖像均留本機，不隨程式碼提交。

目錄資料並不代表每張卡片、每種道具的效果已完成。可用時機、共享供給的變動、目標限制、
商店交易與效果必須由 runtime 明確接入；未實作效果不得回報成功或消耗物品。

## 已接入的生命週期核心

`game/core/inventory_rules.gd` 提供一個不依賴遊戲狀態的可重現規則層。呼叫端持有並傳入共享
供給與玩家容器：

```text
supply = {
  "cards": {"均富": 1, ...},
  "tools": {"機器娃娃": 10, ..., "核子飛彈": 0}
}
player_cards = ["均富", "停留"]
player_tools = {"路障": 2}
```

`new_supply()` 依目錄建立完整的卡片與道具供給；`empty_tools()` 建立空的稀疏道具字典。
`initialize_player(player, supply)` 與 `initialize_players(players, supply)` 保留玩家其他欄位，
並把卡片清空、點數設為 0，再各發一個來源 ID 1、2、3、4、8、9 的道具。來源 ID 1–8 的
有限共享供給會按玩家數量扣除；研究道具 ID 9–13 不共用供給上限。初始化會先檢查全部需求，
供給不足時不改動任何玩家或供給。

`grant_card(supply, player_cards, card_id)` 從有限卡片池扣一張並加入玩家；玩家已有 15 張時，
會退回背包中第一張最低點券價格卡片，再把新卡加到陣列尾端。同價時先退回玩家陣列中較早出現
的卡片。`consume_card(supply, player_cards, card_id)` 移除玩家持有的卡片並歸還共享池。
`draw_card(supply, rng)` 是低階的抽取／保留操作：按剩餘供給加權、扣除一張並回傳卡片 ID，
但不寫入玩家背包。需要將抽卡交給玩家時，使用 `receive_random_card(supply, player_cards, rng)`；
它在一個 staged transaction 中完成加權抽取、扣池、滿 15 張時的驅逐與加入，不能再接著呼叫
`grant_card`。

`grant_tool` 與 `consume_tool` 支援正整數數量；每種道具的玩家持有量最多 9。來源 ID 1–8
的發放會扣除共享池，使用後歸還；研究道具 ID 9–13 的發放與使用不改動共享池。數量、ID、
供給或背包格式不合法，以及容量或供給不足時，操作不會部分套用。

`quote_buy(kind, id, quantity)` 回傳目錄標價乘數量；`quote_sale` 則先計算總標價，再截去
`total * 0.9` 的小數。`buy_price`、`sale_price` 是相同計算的短別名；無效項目或數量回傳
`-1`。卡片 ID 與道具 ID 以目錄中的短中文字串為 canonical key，方法也接受 1 起算的
`source_id` 作為查詢／操作輸入。

這一層只處理供給、背包、抽取、容量與點券報價；卡片／道具效果、可用時機、目標選擇、商店
現金／點券結算、存檔版本與 UI 仍由後續 runtime 接入。

## 生命週期驗證依據

兩版執行檔的本機反組譯在 `mj-original-disasm.txt` 的 `4412ae` 路徑以卡片表的價格欄位
（每筆 8 bytes 的 `+5`）尋找第一張最低價卡片；研究程式碼曾標示的 `+7` 回傳位置不是這個
驅逐比較值。MultiverseJourney 的 `406de7` 初始化路徑呼叫來源 ID 1、2、3、4、8、9 的
道具接收；兩版玩家 profile 的點數欄位（`+48`）初始為 0。卡片商店 routine `42d145` 與
道具商店 routine `42d1b2` 使用 `0x464364`／`0x46436c` 的 0.9 常數；Game 版對應
`42c54d`／`42c5b3` 與 `0x462350`／`0x462358`。以上只記錄本機執行檔的觀察結果，沒有
複製研究 repository 的 GPL C／ASM 實作。
