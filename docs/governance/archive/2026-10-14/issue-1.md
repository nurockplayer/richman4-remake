> **2026-09-26 owner routing amendment:** [#200](https://github.com/nurockplayer/richman4-remake/issues/200) is the current model-routing/serial-execution authority. It supersedes older Terra/DeepSeek/Astra-lead/Oracle-only role text only where conflicting; this Issue's product scope and acceptance contract remain authoritative. GPT-6 Sol leads, GPT-6 Luna implements, Oracle + Ego-lite independently review exact final HEAD, and Astra is advisory escalation for architecture/difficult blockers.

## Mission

高忠實度重製《大富翁4》，供擁有者私人遊玩。現代化的是實作，不是遊戲設計；不是精神續作、泛用 Monopoly clone 或桌遊平台。

## Authority

- **#1**：Mission、硬性約束、目前 phase 與 Done criteria。**#1 comments 只保留歷史，不是 live state；恢復工作時不要掃 comments 找目前進度。**
- **#52**：唯一 current development handoff；只更新 Issue body，不用 comments 累積日誌。
- **`AGENTS.md`**：agent 工作方式與操作規則。
- **active Issue / PR**：目前功能範圍、實作、RED/GREEN、來源研究與 review evidence。
- **#28**：Astra engineering reflection／retrospective，不是 status 或驗收來源。

## Constraints

### Delivery

- **使用 Godot。** 做成可直接啟動的獨立桌面遊戲，不依賴瀏覽器或開發環境。
- macOS / Apple Silicon 是第一個交付平台，同時保留未來移植 Windows / Linux 的能力。
- simulation、存檔與 RNG 應可測試／重現；runtime 與《大富翁4》內容合理分離，但不要為了泛用而過度抽象。

### Fidelity

- 以原版可觀察到的規則、內容、操作、節奏與細節為 reference；**目標是玩家可感知的 90–95% 還原度與完整可玩性，不是完美考古。**
- 未知、低影響、低機率或證據不足的細節預設不是 blocker。限制研究成本，記錄 uncertainty／合理 fallback 後繼續；不要為了「找更多差異」主動擴大 scope。
- 若正常實作／驗證已可靠觀察到原作的不合理、過時、矛盾、疑似 bug 或技術限制遺留行為，不要只因為不合理就擅自現代化。必要時記到 `docs/original-oddities.md`；只有已知原作行為妨礙正常遊玩、無法可靠重現或撞到硬性約束時，才採最小必要偏離並記錄理由。
- polish / RC 階段只追可重現、玩家可感知的差異或既定 acceptance failure；不要因新發現重新擴張 release scope。
- 原版低解析 raster 可作 reference 與早期可玩素材，但 **source texture pixel dimensions、遊戲／UI logical coordinates 與實體輸出解析度必須解耦**；不得讓目前原圖尺寸成為 gameplay、hitbox、layout 或存檔格式的硬依賴。高解析素材應可逐項替換而不重寫邏輯；canonical logical resolution 未確認前不得猜數字寫死。

### Architecture and saves

- **架構採棘輪，不在 #1 收口期啟動大型重構。** 新功能若有自然且可獨立驗收的 domain／UI 邊界，優先抽成小 module，避免繼續實質膨脹 `game/core/game_state.gd` 與 `game/ui/main_ui.gd`；既有穩定程式只在碰到相關區域或 correctness 需要時順手收斂。
- 當核心玩法大致完成、active PR 重心轉為 UI／animation／audio／polish 時，做一次 bounded architecture reassessment，優先評估 `main_ui.gd`；不要為整潔提前開大型 deferred refactor。
- **停止新增尚未正式 release 的舊開發存檔 gameplay-semantics 永久相容負擔。** 保留 deterministic simulation、固定 seed、save/load、JSON continuation 等除錯能力；舊開發存檔優先做低成本 migration，成本不成比例時可明確不相容。不要為清理既有相容碼而中斷功能，但從現在起不要再擴張這類 compatibility branches。

### Agent routing

- `AGENTS.md` 是 live agent-routing / execution authority；#1 只保留方向與硬性邊界。
- 可安全隔離的 bounded routine implementation、tests、exploration、mechanical work，預設委派給外部 `~/.local/bin/deepseek-worker`；相近小工作盡量 batch 成可獨立驗收的工作包。
- 明確使用 `printf '%s\n' "$TASK" | ~/.local/bin/deepseek-worker` 呼叫；**不要用 native `spawn_agent` 召喚 DeepSeek**。
- architecture、模糊需求、跨模組整合、shared-writer 變更與 final verification 保留給 parent／Astra。
- **Astra token conservation：Astra 繼續帶主線，但目前優先節省 token，不追求最快完工。** 採低頻、長批次、event-driven 的節奏；可等待就使用長等待（現行至少 180 秒），不要頻繁 polling、重讀既有歷史、重複狀態敘述或為了小變更反覆跑 broad/full regression。把清楚、可隔離的實作／測試／素材整理盡量 batch 後委派給 `~/.local/bin/deepseek-worker`；Astra 自己集中在 shared integration、來源／需求仲裁、跨模組判斷與必要的 milestone verification。寧可慢慢推進，也不要為維持 activity 或回報頻率燃燒 token；#52 只在實質 checkpoint 更新。
- 不得 overlapping writes；DeepSeek 失敗、loop 或品質不足就收回／升級，不要反覆重試。

### Assets

- public code repo 不放沒有合法公開分發權的第三方原版素材。
- owner-authorized canonical source 固定為 private GitHub repo **`nurockplayer/richman4-remake-assets` + Git LFS**。fresh clone 必須能透過 manifest/bootstrap 取得並驗證 pinned asset revision；不得用 Dropbox、Google Drive、iCloud Drive 或其他同步資料夾取代 canonical source。本機原版安裝可作匯入／驗證來源，但不得是唯一 source of truth。

### Validation

- **Use layered testing; default to the cheapest sufficient level.** local change 用 static/focused；feature batch 後跑 affected subsystem；PR／merge 前跑 integration smoke；只有 cross-cutting/core/schema/save/asset-pipeline 或 milestone 才跑 full regression。
- full-asset / full-corpus validation 是例外，不是 routine regression；沒有新證據不要升級或重跑更廣的 suite。
- 同一失敗重複 2 次仍沒有新的有效資訊時，停止盲跑，重新判斷並改用最便宜、最能區分問題的測試。
- 若出現**無頭模式測試通過、原生圖形模式失敗**，視為獨立的執行邊界問題；不要靠反覆重跑完整原生流程碰運氣。
- 優先記錄最小必要的事件與狀態邊界（例如焦點、視窗／彈窗通知、待處理狀態、階段、呼叫路徑）；可行時先縮成可重現的小型測試，再修改正式程式。
- 正式程式修正與測試工具修正要分開證明；只修改測試工具，不能當作產品問題已修復。
- 依賴焦點、視窗／彈窗生命週期、真實輸入或畫面更新時序的功能，合併前需要一次原生模式驗證；已找到的原生模式限定問題應保留最小回歸案例，避免下次重新跑完整流程才發現。
- **功能／打包 PASS 不等於原版呈現 PASS。** #99 指定的核心畫面須提供同版原作與實際重製畫面的對照、必要操作證據及獨立視覺審查；現代 dashboard/debug shell 不可作為高忠實度交付。截圖存在或自訂 baseline 全綠不構成還原度驗收。
- 正常啟動／新局必須驗證實際 catalog 與能力路徑，不得只用注入完整能力的測試 fixture 證明玩家能取得原版內容。

## Current phase — fidelity acceptance reopened

2026-09-10 擁有者實際開啟主棋盤與股市後，退回高忠實度驗收。**Mission 尚未完成；不是只剩 cosmetic polish。** 修復範圍與逐幕 gate 由 **#99** 定義；先處理 **#100** 的三股簡化市場／成品能力路徑，再完成 **#101** 的主棋盤與股市可玩呈現，第一段通過獨立審查後才進 **#102** 其餘畫面。#98 的安全重新開局、銀行金額與 tooltip 修正保留並協調同一 UI writer。

#89 保留 `159aeb036a71194badc564a2064e750655bd7484` 的歷史 macOS 打包、對局、存讀檔與素材驗證成果；不再作為整個高忠實度 Mission 完成的充分證據。不要刪除或否定已取得的有效工程證據，也不要未查實就認定只需換皮。擁有者截圖對應的實際 executable／catalog／save 身分仍須由 #100 核對。

#52 仍是唯一 current handoff；#28 仍只保留 reflection。詳細修復規格不重複堆進 #1；各 child PR 不得自動關閉 Mission，完整 gate 後交 Steward 驗收。

## Done

以下已勾項目代表 #89 的歷史基線證據；修復後變動的邊界仍須在對應版本重新驗證。

- [x] Apple Silicon Mac 上可直接啟動打包後的 `.app`。
- [x] 可以開新局、正常操作、與 AI 完整玩完一局、結算並重新開局。
- [x] 存檔／讀檔可靠，必要的遊戲行為可重現。
- [ ] 主要《大富翁4》系統與內容在正常成品入口實際可達，#100 的簡化市場差異已釐清與修復。
- [x] 乾淨 checkout 可以重現 build、test、package 與必要的本機素材匯入流程。
- [ ] #99 範圍內的原版 UI／資訊結構／操作呈現有逐幕對照與獨立驗收，不以開發 shell 冒充完成。
- [ ] 修復版整合原生流程與 exact-HEAD evidence 通過，Steward 核可關閉 #1。