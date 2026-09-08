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

這個 public code repo 不放未確認公開分發權的第三方原版資料，也不追蹤可重建的衍生快取。擁有者可先依 [assets.md](assets.md) 從 private Git/LFS source 取回原始資料，再在 `.local/` 產生匯入結果。沒有素材時仍應可執行，但測試棋盤不代表已還原原版地圖；差異見 [fidelity.md](fidelity.md)。

## THIN 與 FULL 工作樹

一般 Codex worktree 預設是 **THIN**：只保留程式碼與小型測試所需資料，不因 agent isolation 複製完整原版素材、衍生 PNG、Godot import cache 或 export bundle。需要完整素材／渲染／打包驗證時，優先使用擁有者的 `~/Developer/richman4-remake` 作為單一 **FULL** validation lane。

任何新 FULL materialization 前先執行：

```sh
bash tools/disk_guard.sh --operation "Richman4 FULL validation"
```

預設低於 60 GiB 會警告，不應再建立第二個 FULL lane；低於 25 GiB 會 fail closed。只有擁有者明確接受風險時才可用 `RICHMAN4_ALLOW_LOW_DISK=1` 覆寫 hard stop。門檻可用 `RICHMAN4_DISK_WARN_GIB` 與 `RICHMAN4_DISK_HARD_MIN_GIB` 調整。

`.godot/`、`.local/imported-original/`、`.local/original-scenes/`、`build/`、`dist/` 與 test results 都是可重建 cache。FULL worktree 退役後應回收，不把它們當成需要長期保存的開發 authority。

## 私人素材 bootstrap

重新 clone 後，擁有者可用自己的 GitHub credentials 取回 public binding 所指定的 private asset revision：

```sh
bash tools/bootstrap_private_assets.sh
asset_source="$PWD/.local/private-assets/source/dfw4cskzl_136622"
```

bootstrap 不再把 Git LFS checkout 複製到每個 worktree。預設 canonical 本機 cache 是：

```text
~/Library/Caches/richman4-remake/private-assets/<pinned-revision>/
```

目前 worktree 的 `.local/private-assets` 只是一個指向該 verified cache 的 symlink。同一部機器上的其他 worktree 執行相同 bootstrap 時會重新驗證並直接 reuse；只有該 pinned revision 尚未 materialize 時才會執行 LFS download，且下載前會通過 `tools/disk_guard.sh`。

若 cache root 必須放在其他 volume，可設定：

```sh
RICHMAN4_CACHE_ROOT=/Volumes/FastSSD/richman4-cache \
  bash tools/bootstrap_private_assets.sh
```

bootstrap 會檢查 Git LFS、固定 commit、manifest SHA-256 與每個來源檔案；缺少 private repo credentials 時會停止並顯示存取錯誤，不會改用舊機器路徑或其他同步服務。既有 shared cache 若驗證失敗也不會被自動覆寫。

只有 FULL lane 需要建立衍生素材：

```sh
python3 tools/import_original.py \
  --source "$asset_source" \
  --output .local/imported-original \
  --extract-map-payloads
python3 tools/decode_original_ground.py \
  --source "$asset_source" \
  --output .local/original-scenes
```

這些 catalog、PNG 與其他 derived outputs 仍是可丟棄 cache；ordinary THIN worktree 不應重建它們。

## 原版地圖的私人套件

先完成 private asset bootstrap 或使用擁有者本機資料匯入，再指定 catalog 打包：

```sh
python3 tools/import_original.py --source /path/to/dfw4cskzl_136622 --output .local/imported-original
RICHMAN4_MAP_CATALOG="$PWD/.local/imported-original/maps/catalog.json" bash tools/package_macos.sh
```

腳本會先驗證 catalog，再將它放入 `.app/Contents/Resources/Original/maps/catalog.json`，重新簽章並輸出 `build/Richman4-private.zip`。這個私人套件含衍生地圖資料，只留本機。未指定 catalog 的 `build/Richman4.zip` 仍不含原版資料。遊戲可從封裝路徑自行載入地圖，不必保留開發工作樹。
