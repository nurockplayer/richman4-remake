# 公司分紅與銀行利息報表

#137 對應 #102 的 S17／S18。既有結算核心仍負責金額、日期、存款、破產與 RNG；
`monthly_statements.gd` 只封裝核心已計算的數字，透過 `monthly_statement` 事件
交給 presenter。畫面不計算股利，也不再次結算。

## 原作依據

擁有者授權來源的 `rich4_ui_stock.asm`，函式 `0042ba97`，使用 Panel76 chunk0。
公司按股票索引排列，存活玩家依序占欄，保留本月盈餘、各玩家實際分紅及合計。
未持股公司的盈餘仍顯示，核心不因此清零。表格 logical size 為 592×432，
位於 640×480 黑底的 (24,24)；來源滑鼠左右鍵放開可關閉，分紅表預設三秒後繼續。

`rich4.asm` 的 `00439bfa`／`004380d5` 使用 Panel25；背景、行員、帳戶卡片與
角色來自同版資源。報表顯示計息前存款、實際利息，貸款中的玩家顯示紅色「貸款中」。
來源日期入口在 `rich4_player_core_actions.asm`：十五日分紅，跨月後顯示銀行報表。
LGKouDi 的 article52／53 已直接檢視，作為畫面結構的交叉參考；裁切圖片不作座標權威。
Game／MultiverseJourney 各自綁定 Panel25 的 83 chunks 與 Panel76 的 1 chunk。

本次採來源可核對的報表姿勢，利息頁由滑鼠左右鍵放開繼續。完整旁白、姿勢動畫、
月度排名後續段落仍未驗證；沒有以猜測的旁白秒數自動關閉。素材 logical metadata
與實際 texture 尺寸分離，原圖與衍生快取不進入 public repo。

## 資料與介面生命週期

分紅資料在帳務預檢通過後、盈餘清零及破產前複製，保留原本參與結算的玩家。
利息資料保留計息前餘額；各帳戶實際入帳後才填入已支付利息。被拒絕的結算不發送
成功報表。事件沿用既有 JSON 結構，未增加存檔版本或核心待處理階段。

`source_monthly_controller.gd` 只接收 host action 前後可證明的新事件，沿用既有
event-log overlap 檢查，並防止同一 action 重複交付。一般 refresh、讀檔或新局不掃描
歷史報表。佇列在移動或其他既有呈現完成後顯示，阻擋下一個操作、AI 與存讀檔；
關閉只推進介面。延期 callback 受 game ownership／generation 保護。若分紅令對局
結束，先顯示分紅報表，再顯示最終結算 overlay。

## 驗證狀態

- 核心 immutable `b77d4f6`：有效日期／帳務 fixtures，32 checks／4 failures／0 setup failures；
  `5780931` 後為 51／0。涵蓋正負分紅、未持股、帳務上限拒絕、月底貸款／零利息、JSON 與重複讀取。
- Controller／MainUI 首次 RED 分別為 1／1、3／1，屬於缺少新元件／接線的 availability RED；
  完整互動斷言留在同一測試，不能把尚未執行的分支冒稱為已重現的行為失敗。
- 最終分紅覆蓋順序 immutable `be158b7`：有效四人虧損 fixture，在實際 MainUI 搭配報表 test double
  重現 7／1，修正後 headless／native 7／0。Controller 的獨立佇列測試 headless／native 19／0。
- 本批已跑既有公司金融 36、貸款 132、日期設定流程 213、公司存檔 200、movement extraction 36，
  以及銀行 MainUI 25、title UI 31、save menu UI 48，均通過。報表實際 renderer、完整 MainUI
  與 actual-catalog 測試仍須於完成接線後更新這裡，不能套用 test-double 的結果。

原生 SubViewport 不等於普通 OS 輸入；逐幕原版對照、獨立審查與目前套件 gate 均另行驗收。
本文件不宣稱 S17／S18 或 Mission 完成。
