# richman4-remake

以現代實作高忠實度重建《大富翁4》，供擁有者私人遊玩。目標是原作本身的規則、內容、操作與節奏，不是精神續作或通用桌遊引擎。

## 開發入口

[Issue #1：自治開發主票](https://github.com/nurockplayer/richman4-remake/issues/1) 是目標、授權與驗收依據；目前進度以該票的 canonical handoff 及其連結的實作 Issue／PR 為準。代理從 [AGENTS.md](AGENTS.md) 開始。

Astra Medium 負責研究、設計、拆票、驗收、審查及合併；Luna 預設實作。擁有者不參與例行開發管理。**本專案使用 Godot 開發。**

## 交付目標

macOS／Apple Silicon 是第一個交付平台，最終可直接啟動獨立 `.app`；同時保留未來移植 Windows／Linux 的能力。Runtime 與遊戲內容合理分離；優先可玩性及還原度，不過度泛化。

本 repo 與 Tachiko Fortune／Formosa 獨立。原版素材及衍生素材快取不納入版本控制或自動上傳；預留從擁有者有權使用的本機安裝匯入的路徑，缺少素材時明確列出還原差異。

## 目前狀態

尚在任務／流程 bootstrap，沒有遊戲實作、可執行檔或已驗證的建置指令。第一個可操作切片完成後，應在此提供真實的建置、測試、啟動與素材匯入說明，並移除此暫存狀態。
