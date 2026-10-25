# 開發與本機打包

使用 Godot **4.7.2 stable**，不需要瀏覽器、Node.js 或第三方 Python 套件。Python 工具使用標準函式庫；可以透過 `uv run --no-project --python 3.12` 執行。

```sh
godot --editor --path .
bash tools/check.sh
python3 tools/install_templates.py
bash tools/package_macos.sh
```

`install_templates.py` 下載官方匯出模板並核對固定 SHA-512，僅安裝 macOS 模板。Godot 可由 [官方 4.7.2 發行頁](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable) 取得。`GODOT_BIN` 可指定執行檔。

`tools/check.sh` 會把 `RICHMAN4_USER_ROOT` 指向一個執行結束即刪除的暫存目錄，所有執行期寫入根（存檔檔位、自動存檔、舊版存檔、系統選項、熱鍵、`audio.cfg`）都落在其中，測試永遠不碰擁有者 `user://` 下的真實資料。手動跑單一測試時比照：

```sh
RICHMAN4_USER_ROOT="$(mktemp -d)" godot --headless --path . --script tests/save_slots.gd
```

macOS 打包輸出 `build/Richman4.zip` 與新的 `build/package.XXXXXX/*.app`，採本機 ad-hoc 簽章。打包腳本先執行驗證，再匯出並驗證簽章。這是私人本機版本，尚無 Developer ID 公證。

這個 public code repo 不放未確認公開分發權的第三方原版資料，也不追蹤可重建的衍生快取。擁有者可先依 [assets.md](assets.md) 從 private Git/LFS source 取回原始資料，再在 `.local/` 產生匯入結果。沒有素材時仍應可執行，但測試棋盤不代表已還原原版地圖；差異見 [fidelity.md](fidelity.md)。

## THIN 與 FULL 工作樹

一般 Codex worktree 預設是 **THIN**：只保留程式碼與小型測試所需資料，不因 agent isolation 複製完整原版素材、衍生 PNG、Godot import cache 或 export bundle。需要完整素材／渲染／打包驗證時，優先使用擁有者的 `~/Developer/richman4-remake` 作為單一 **FULL** validation lane。

任何新 FULL materialization 前先執行：

```sh
bash tools/disk_guard.sh --operation "Richman4 FULL validation"
```

預設低於 20 GiB 會警告，不應再建立第二個 FULL lane；低於 10 GiB 直接 fail closed（私有素材約 1 GiB，加上 clone、Godot import 與打包暫存仍遠低於此），不再新增大型素材 checkout／完整 Godot validation cache。只有擁有者明確接受風險時才可用 `RICHMAN4_ALLOW_LOW_DISK=1` 覆寫 hard stop。門檻可用 `RICHMAN4_DISK_WARN_GIB` 與 `RICHMAN4_DISK_HARD_MIN_GIB` 調整。

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

## 完整私人 release-candidate 套件

`tools/package_rc.sh` 是建置私人 RC 的唯一指令。它在同一次執行中：

1. 以 `tools/disk_guard.sh` 檢查磁碟，再用 `tools/bootstrap_private_assets.sh` 驗證（或取回）固定 revision 的 private source；預設共用 cache 是 `/Volumes/KIOXIA/richman4-cache`。
2. 從 private source 匯出所有執行期可載入的衍生素材到 ignored `.local/`：地圖 catalog（`import_original.py`）、場景／角色／UI 圖（`decode_original_ground.py`，含 `Panel` 的銀行、商店、庫存、彩券、SALE、股票、月結、信託與小遊戲資源）以及說明內容（`export_original_help.py`）。
3. 呼叫 `tools/package_macos.sh`，把 catalog、場景 manifest、說明 manifest 與 `Media/Music` 放進 `.app/Contents/Resources/Original/`，並執行 `tools/check.sh`。
4. 以 `tools/rc_art_report.gd` 對封裝後的 `Contents/Resources/Original` 做 headless 煙霧測試：逐一檢查各 presenter 的素材 key 是否載入到真實 texture；任何缺圖都會讓建置失敗。
5. 把 `Richman4-private.zip` 複製到 `<cache>/rc/Richman4-rc1-<short-sha>.zip`，同時寫出 `.sha256`；worktree 的 `build/` 與暫存目錄在結束時刪除。

```sh
orb-test --heavy --host -- bash tools/package_rc.sh
```

`RICHMAN4_CACHE_ROOT` 可換共用 cache，`RICHMAN4_RC_OUTPUT_DIR` 可換輸出目錄，`RICHMAN4_RC_SKIP_EXPORT=1` 會重用既有 `.local/` 匯出。`.local/rc-art-report.txt` 保留最後一次煙霧測試的 presenter → found/fallback 清單。原始素材、衍生 PNG 與 RC zip 都不得提交或推送。
