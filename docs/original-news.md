# 新聞事件

本批接通來源地圖 `event_code=2` 的新聞落點；經過不抽選。命運（event 3）另見[命運契約](original-fate.md)。來源節點的物件類型仍優先決定住宅／設施等行為，不讓新聞覆蓋既有物件。

## 來源與差異

規則依 owner-authorized 原版 PE 與既有位址級反組譯交叉核對：36 個新聞 handler 表、候選檢查與游標循環、金流／土地／公司與股票欄位，以及 preview／apply 分界。這是靜態來源證據，未宣稱原版 runtime golden trace。原始二進位、反組譯及原圖不放進 public code repo。

目前接通 32 個可映射的效果，涵蓋釋放／延長休養、土地價格與建物損害、地主／持股獎勵、三類稅款、行人／車輛停留、銀行拒貸／利息、股票事件及公司獲利。以下四個 ID 保留於候選排列，抽選時明確跳過：

| ID | 尚未接通範圍 |
| --- | --- |
| 4 | 外星事件的範圍損害 helper |
| 7 | 公共土地拍賣與互動 |
| 20 | 颱風的範圍損害 |
| 29 | 公司負責人的入獄與狀態卡回應 |

未支援與沒有相容目標的候選都跳過，每次最多掃描 36 個；不把跳過記成效果成功。ID15 的來源 gate 可能因已建設施通過，但可靠 handler 目標是已建住宅；本版要求實際住宅目標存在，以免沒有可作用對象時無界搜尋。

使用現有 Godot RNG，在首次新聞落點惰性洗牌一次，往後循環相同排列。這保留 deterministic continuation，但初始化時機與亂數值不等同原版新局初始化／libc rand。新聞結果以依實際效果撰寫的繁體中文呈現，結果視窗停留2.4秒；未宣稱原版逐字文案、新聞原畫、完整媒體時序、音效與動畫已還原。

## 存檔與整合

optional `news` 保存 `order`、`cursor`、`draw_count` 與已完成的 `last`。每次有界抽選增加一次 draw_count；選中後先固定目標與金額，再同步套用。UI 只呈現已完成的結果，存讀不再抽選、扣款或套用效果。沒有新增 save version 或舊開發玩法分支；舊來源 type0/event2 的 unsupported 節點在讀入時做單一結構 migration。

拒貸使用 optional player `loan_block_days`。每次自己的 incoming admission 倒數，1→128→0；128 視為已解除，只阻擋1..127。原始 loan gate 對 release marker 的精確處理未確認，採此明確映射。禁貸期間仍可存提款。

土地／設施沿既有 canonical mutation 與 alias 規則；稅款先計算所有適用金額，再依既有金流逐人處理，對局結束即停止。目前行動者若在新聞中破產，完成新聞結算後最多交接一次。公司新聞使用 `stock_index` 尋找連動股票，`monthly_profit`／`cumulative_profit` 與 `stock_value` 分開處理；設置 event 後即時刷新連動檔的現價、當日 history 與 index。

地價漲跌先截斷乘積，再保留來源無號 16 位元欄位；住宅同名群與設施別名使用同一規則。ID21 只損害選中的來源物件，ID18 才擴及同名住宅；設施降到零級時一併清除臨時狀態。ID8–10 的現金獎勵不扣銀行準備金。ID35 的股票事件碼若迴繞成0，仍更新公司獲利，但保留原股價、history 與 index。

## 驗證入口

- `tests/news_flow.gd`：抽選與效果契約。
- `tests/news_eligibility.gd`：沒有地產或持股時跳過相應候選。
- `tests/news_price_and_rewards.gd`：地價欄位邊界、現金獎勵記帳、單棟損害與公司事件碼迴繞。
- `tests/news_save.gd`：optional 資料、拒貸 counter、結構 migration 及 JSON continuation。
- `tests/graph_flow.gd`：新聞節點分類、落點與經過行為。
- `tests/news_public_tax.gd`：實際擲骰／選路落點的全體稅款、行動者破產與單次交接。
- `tests/news_ui.gd`：實際結果視窗、關閉、重新整理及存讀不重做效果。
- `tests/news_bank_ui.gd`：拒貸期限、貸款操作及仍可使用的存提款。
- `tools/news_source_smoke.gd -- <existing-catalog>`：兩張來源地圖的實際遙控骰子／路線選擇新聞落點與 bounded AI continuation。

實際 RED／GREEN、原生視窗與最終審查證據記於 #54／#55，這份說明不代替驗收紀錄。
