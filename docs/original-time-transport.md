# 時光機與傳送機

Issue #81 接通研究所來源工具 ID10「時光機」與 ID11「傳送機」。這兩項效果只在具備
`supports_original_research` 且啟用 `original_research` 的圖形地圖新局（v12 或後續 v13）啟用；
舊存檔不因程式更新而改變規則，也沒有新增
存檔版本。研究所產品的解鎖與生產規則見[研究所建設與生產](original-research.md)。

## 傳送機

傳送機在目前玩家的 `await_roll` 階段使用。核心提供唯讀的兩段選擇查詢：

```text
transport_targets(target_kind: String) -> Array
transport_destinations(target_kind: String, target_id: int) -> Array
```

公開效果入口仍是既有的 `choose_action("use_tool", params)`：

```text
{
  "tool_id": "傳送機",
  "target_kind": "property|facility|player|god",
  "target_id": int,
  "destination_id": int,
  "cancel": bool,
}
```

目標與目的地會在消耗工具前以嚴格型別和目前世界狀態重新檢查；取消或拒絕不改變存檔、
隨機數或供給。成功只消耗一個傳送機，並保留目前玩家的行動階段。

| 目標 | 可傳送內容與目的地 | 成功後的處理 |
| --- | --- | --- |
| 住宅 | 有屋主或有建物的住宅，目的地是另一間無主、零級、非連鎖空住宅 | 移動屋主、等級與連鎖標記；清空來源，保留節點身分、價格與狀態，重算租金／價值與持有清單 |
| 設施 | 以 `source_object_id` 合併多入口；目的地是另一項無主、零級、類型 0 設施 | 跨所有入口移動屋主、等級與設施類型；各來源物件的價格、狀態與研究欄位留在原址 |
| 玩家 | 存活且不在拘留狀態的玩家，目的地是不同的合法道路節點 | 更新位置與方向，並同步附身神明；不執行落地、租金、購地、事件、碰撞、研究倒數或炸彈倒數 |
| 神明 | 附身神明以其玩家為目標；未附身神明以自身節點為目標 | 附身神明移動玩家與位置；未附身神明只移動節點。目的地排除玩家、道路物件與其他未附身神明 |

玩家傳送的方向使用目前 `previous_position` 到 `position` 的向量，在目的地選擇最接近的
反向相鄰節點；分數相同時採最小節點 ID。沒有可用方向時採合法相鄰節點的第一個值，
不另造 facing 欄位。多名玩家共用道路節點仍沿用既有狀態模型。

## 時光機

時光機只能由目前的人類玩家在 `await_roll` 使用。唯讀查詢
`time_machine_status() -> Dictionary` 回傳 `available: bool` 與顯示給玩家的 `message`，
UI 在沒有可用錨點時停用按鈕並說明原因。公開入口為：

```text
choose_action("use_tool", {"tool_id": "時光機", "cancel": bool})
```

每位人類玩家各有一個只存在記憶體的錨點。錨點在實際人類圖形移動前、所有拒絕／狀態／
停留檢查完成後擷取，並涵蓋當時合法的整個世界；不會為 AI 或沒有移動的停留／跳過回合
擷取。自身使用傳送機，或以目前玩家附身的神明作為目標時，也在傳送機消耗前擷取，因此可以
回到傳送前的位置與背包。

錨點不在 `state`、`to_dict()` 或 `to_json()` 中。新局、`from_dict` 與磁碟讀檔都從沒有錨點
開始；讀檔保留已持有的工具，但玩家須先完成一次正常移動。此設計不宣稱跨存檔延續錨點。

還原流程會先檢查目前與錨點中的玩家身分、時光機，以及完整 staged 存檔是否合法，成功後
才一次提交。還原消耗一個錨點中的時光機，保留目前隨機數作為後續延續點，不回捲也不額外
抽取；錨點本身則替換成扣除工具後的世界，使重複使用不能補回工具。被捨棄的未來錨點會
一併清除。任何拒絕均不消耗工具、不寫事件、不改變隨機數。

## 保真度邊界與驗證

傳送機的原始目標選擇、玩家方向、附身神明與設施多入口規則依 owner-authorized 原版
研究及現有來源核對接入；時光機錨點的序列化生命週期、隨機數回捲與重複使用細節在來源中
未完全確定，因此採上述明確的 bounded fallback。原始執行檔、反組譯輸出與素材不放進
public code repo。

此切片的本機 acceptance 為：

```sh
godot --headless --path . --script tests/time_transport_flow.gd
godot --headless --path . --script tests/time_transport_save.gd
godot --headless --path . --script tests/time_transport_ui.gd
```

完整回歸由 `bash tools/check.sh` 執行同三個檢查；測試涵蓋四類目標、空目的地與多入口
設施、研究狀態位置、方向與無落地傳送、AI、自身傳送後還原、讀檔錨點遺失、隨機數延續、
工具供給守恆、重複還原及拒絕操作的原子性。
