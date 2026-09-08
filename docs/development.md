# 開發與本機打包

使用 Godot **4.7.2 stable**，不需要瀏覽器、Node.js 或第三方 Python 套件。Python 工具使用標準函式庫；可以透過 `uv run --no-project --python 3.12` 執行。

```sh
godot --editor --path .
bash tools/check.sh
python3 tools/install_templates.py
bash tools/package_macos.sh
```

`install_templates.py` 下載官方匯出模板並核對固定 SHA-512，僅安裝 macOS 模板。Godot 可由 [官方 4.7.2 發行頁](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable) 取得。`GODOT_BIN` 可指定執行檔。

macOS 打包輸出 `build/Richman4.zip` 與新的 `build/package.XXXXXX/*.app`，採本機 ad-hoc 簽章。打包腳本先執行驗證，再匯出並驗證簽章。這是私人本機版本，尚無 Developer ID 公證。

原版資料與衍生快取禁止提交。匯入方式見 [assets.md](assets.md)。沒有本機素材時仍應可執行，但測試棋盤不代表已還原原版地圖；差異見 [fidelity.md](fidelity.md)。
