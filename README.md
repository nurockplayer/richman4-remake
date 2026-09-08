# richman4-remake

以 Godot 高忠實度重製《大富翁4》，供擁有者私人遊玩。目標是原作本身的規則、內容、操作與節奏，不是精神續作或通用桌遊引擎。

macOS / Apple Silicon 是第一個交付平台，最終提供可直接啟動的獨立 `.app`；同時保留未來移植 Windows / Linux 的能力。

產品使命與完成條件見 [Issue #1](https://github.com/nurockplayer/richman4-remake/issues/1)。代理工作規則見 [AGENTS.md](AGENTS.md)。

原版素材與衍生素材快取不納入版本控制或遠端上傳；需要時從擁有者有權使用的本機來源匯入。

## 開發

使用 Godot 4.7.2 stable 開啟 `project.godot`，或執行 `godot --path .`。
測試使用 `bash tools/check.sh`；macOS 匯出、模板安裝與本機依賴見 [開發說明](docs/development.md)。

可玩程度與尚未還原內容見 [fidelity 記錄](docs/fidelity.md)；原版素材只透過 [本機匯入流程](docs/assets.md) 使用。
