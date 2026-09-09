# 命運事件

本批契約見 [Issue #56](https://github.com/nurockplayer/richman4-remake/issues/56)。來源 graph `event_code=3` 落點觸發命運，經過不抽選；住宅與設施物件分類優先。效果由小型 domain module 管理，UI 只展示 simulation 已決定的結果。

## 範圍與來源

37 個候選循環使用一次洗牌的排列；每次最多掃描37個，沒有相容目標則跳過。本批接通0、1、4、10–31、33–36，共29個候選。10–16按交通方式重新映射，工程車不符合這些交通候選。33–36僅適用原版Game四張圖，分別入獄3、5、7、9天。

來源是 owner-authorized 原版 PE、既有位址級反組譯與 companion C-like 摘要。核對範圍含命運 dispatcher、traffic remap、god gate、住宅與金流 mutation、status helper 及神明附身的 signed16 delta table。這些是靜態證據，並非原版runtime逐值golden trace；原始程式、二進位與素材不放進public repo。

收入直接加玩家現金，不扣銀行準備金；費用沿既有現金／存款／破產處理。存款分配直接做玩家間deposit轉移，銀行現金與總存款不變。住宅處分只影響抽中的自有住宅，房屋拆除保留土地所有權；空地出售才清除所有權。神明修飾使用已建模的附身效果，不猜尚未建模的基礎buff。

## 已知差異

以下候選保留在排列中並明確跳過，不記為成功事件：

| ID | 未完成的 adapter |
| --- | --- |
| 2、3 | 強制借款與raw銀行拒貸counter |
| 5 | 選卡與玩家間卡片轉移 |
| 6、7 | 離場旅行、返回及路線生命週期 |
| 8、9 | 特殊售股的來源記帳分支 |
| 32 | 全部卡片／道具及active vehicle出售換點 |

狀態事件先處理免罪卡；嫁禍卡採同步fallback，導向ID最小的其他存活玩家，不遞迴防禦。原版human可選對象，AI策略也未逐值重現。沒有其他玩家時直接承受且不消耗嫁禍。這項選擇是明記的互動差異，不借用陷害卡的pending response語義。

第一次命運落點才以Godot RNG洗牌；原版初始化時機與libc rand序列不同。preview及apply同步完成，未重現1600ms等候、原畫與音效；繁體中文摘要依實際效果撰寫，沒有原版逐字文案承諾。一般費用的其他來源保險helper與未建模buff仍有差異。

## 存檔與驗證

optional `fate={order,cursor,draw_count,last}` 保存抽選與已完成結果；last含原候選、remap ID、map slot、玩家、目標、變更、摘要、applied／blocked、原額度／天數與gate結果。UI關閉、重新整理及存讀不抽選或重新套用。舊type0/event3的unsupported道路可做一次kind migration；不增加save version或舊開發玩法分支。

驗證入口為`tests/fate_flow.gd`、`tests/fate_save.gd`、`tests/fate_graph.gd`、`tests/fate_public_charge.gd`與`tests/fate_ui.gd`。`tools/fate_source_smoke.gd -- <existing-catalog>`沿兩張來源圖實際擲骰／選路並作bounded JSON AI續玩，不建立素材副本。實際RED／GREEN、native與審查紀錄保留於active PR；這份範圍文件本身不是完成驗收。
