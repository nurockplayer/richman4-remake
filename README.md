# richman4-remake

以 Godot 高忠實度重製《大富翁4》，供擁有者私人遊玩。目標是原作本身的規則、內容、操作與節奏，不是精神續作或通用桌遊引擎。

macOS / Apple Silicon 是第一個交付平台，最終提供可直接啟動的獨立 `.app`；同時保留未來移植 Windows / Linux 的能力。

產品使命與完成條件見 [Issue #1](https://github.com/nurockplayer/richman4-remake/issues/1)。代理工作規則見 [AGENTS.md](AGENTS.md)。

素材策略以「重新 clone 後可重建完整開發環境」為目標。這個程式 repo 是公開的，因此沒有合法公開分發權的第三方原版素材不直接放在這裡；本專案指定的 owner-authorized canonical source 是 private Git/LFS repo `nurockplayer/richman4-remake-assets`。`config/private-assets.json` 與 `tools/bootstrap_private_assets.sh` 會鎖定並驗證其 asset revision，原版本機安裝只作相容的匯入來源，不是唯一 source of truth。

## 開發

使用 Godot 4.7.2 stable 開啟 `project.godot`，或執行 `godot --path .`。
測試使用 `bash tools/check.sh`；macOS 匯出、模板安裝與本機依賴見 [開發說明](docs/development.md)。

可玩程度與尚未還原內容見 [fidelity 記錄](docs/fidelity.md)；素材來源、匯入與可重建性見 [資產說明](docs/assets.md)。
