# Richman4 → Tachiko：第一個資料鏡像

Scope authority: #168。M0 準備 #169；M1 試點 #170；上游 nurockplayer/tachiko-work#366。
不是 Mission #1 或 S21 驗收。

## 決定與版本

現在做 **Mirror → Verify**，不做 runtime cutover。既有 Richman4 程式與 pinned private
資料仍是遊戲資料來源；Tachiko 專案只是候選鏡像。禁止雙向同步、全量重構與新通用平台。

| 身分 | 固定值 |
| --- | --- |
| 盤點來源 / active product | `608a821edb2f5f779f499a375d5dcbbe11d23cde` |
| prep PR base / checked main | `b447d0b6b12b1e7b5b0fa6becfdf00f1365f920c` |
| 首域來源 | `game/content/original_inventory.gd` |
| 該檔案 Git blob（兩個版本相同） | `2d36b62f5cd32a0581d6195d87368fdb158c52ba` |
| 該檔案 SHA-256 / bytes | `8e6e99429f1b5281e7397e635adb0873d3095cad2d8c502576c3370a34cdcf24` / 2905 |
| 已讀 Tachiko Work main | `6900e975112576585fd9360f12d9fcf8b36ba466` |

Prep 直接從 main 分支，不帶入尚未接受的 stacked S21。來源 hash 改變時先記錄 drift、
重做窄範圍對照，不能悄悄更新 oracle。這些 pins 不是產品相容性或安全簽章承諾。

Tachiko 既有入口：`examples/game-balance/README.md`、`CONTRIBUTING.md`、
`docs/governance/project-governance.md`。上游 #17 / #332 定義 engine-adapter 邊界；
#119 是現有 game-balance workflow。重用 Rust semantic authority、`.roproj`、
validation、semantic diff、export；不創造另一個 `.ro` 格式、formula engine 或 SDK。
`tachiko-sheet` UI 不必先完成，也不為本試點修改 Sheet MVP。

## 已查閱入口與下一輪盤點

下表是有來源的入口地圖，不是全檔案／所有欄位完整稽核。只有第一列已逐筆固定。
其他列必須補 actual-catalog reachability、欄位、引用與測試後，才選為下一個遷移域。

| 域 | 已確認的入口／定位 | 現在處置 |
| --- | --- | --- |
| Cards / tools | `game/content/original_inventory.gd` 全文 | 首個 43-record pilot |
| 角色 / setup | `game/core/game_state.gd`: `SETUP_CHARACTER_NAMES`, `SETUP_*` | 可盤點；AI ratios 不等於純顯示資料 |
| 地圖 / 地產 | `game_state.gd`: `OriginalMaps`, `RUNTIME_MAP_SCHEMA`, `PROPERTY_SPECS` | actual imported catalog 與 provisional fallback 分開；不搬完整原圖 |
| 設施 / 研究 | `game_state.gd`: `FACILITY_*`, `RESEARCH_*` | 靜態內容和支付／效果契約分離 |
| 股票 / 公司 | `game_state.gd`: `OriginalStockMarket`, `StockAccounting`, `STOCK_*` | 不把舊三股 fallback 當十二股正式市場；numeric semantics 延後 |
| News / fate | `game_state.gd`: `NewsEvents`, `FateEvents` | metadata 可候選；事件抽樣與執行留 Godot |
| Gods / NPC | `game_state.gd`: `OriginalGods`, `DISMISS_GOD_IDS` | 名錄和效果／附身狀態分開 |
| 商店 / SALE | `game_state.gd`: `SourceShop`, `SourceSale` | 只盤點可引用資料；不碰 #165 owner |
| 銀行 / 月結 | `game_state.gd`: `MONTHLY_*`, `SourceLoans`, `BankVisit` | 金額、float32、rounding、creditor callback 不是先搬公式的理由 |
| Calendar / rules | `game_state.gd`: `GameCalendar`, `RULESET_ID`, version constants | 先分參數、能力門檻與歷史相容分支，不凍結整個模型 |
| UI text / asset refs | #1 / #29、`config/private-assets.json`、`docs/assets.md` | 再逐 UI 消費點盤點；受限原文與 binaries 保持 private |
| Simulation / saves / UI | #1 / #52 / #167；shared core / MainUI | 非本輪搬移資料；原生 audit 獨立繼續 |

## Pilot 欄位契約

來源已公開的 30 cards、13 tools；不是全效果實作或原作完整資料 PASS。

| 現有意義 | 候選 Tachiko 欄位 | 比對要求 |
| --- | --- | --- |
| category | 分開 card/tool schemas | 避免兩類 `source_id=1` 相撞 |
| legacy `id` | Text `legacy_id` | 原樣保留，不改現有 save / effect keys |
| displayed `name` | Text `display_name` | 與 identity 分開；不可當 opaque ID |
| `source_id` | Number `source_id` | 原本 category-local 1-based index；輸出按此排序 |
| `initial_supply` | Number `initial_supply` | 非負整數；五種 tool 的 0 必須保留 |
| `price` | Number `point_price` | 點數，不是現金；不帶入載具 cash cost |
| `source_flags[0..1]` | 兩個 Number 欄位 | 保留位置與原值；不推論新 capability |
| capacities | 兩個 Number 設定 | card 15；每類 tool 9 |

以上只是 consumer fixture 的 mapping，不擴充 Tachiko Core 型別。
使用既有 opaque semantic IDs；初次映射後持久保存，重新匯出／改名不重生 ID。
Source ID 與可改的 human key 都不能替代 semantic ID。映射 provenance 放 consumer-side
manifest，不自行把 Git SHA 當 Tachiko semantic revision。

Rust 負責既有型別、reference、calculation、canonical validation；consumer adapter 負責
本遊戲的非負整數／範圍、點數單位、category-local ID、行序和 loss gate。
本域數值可精確表示為小整數；從 Rust Number 投影時先檢查 finite / integer / range，
再輸出 JSON integer，禁止四捨五入。不要宣稱 Rust 核心已驗證 adapter 自行檢查的條件。
財務或公式移植另案評估，不能由此推論 float32 行為相同。

## Acceptance seed 與命令

`tests/tachiko_mirror/oracle.json` 是固定測試資料，不是新的遊戲 runtime wire。
`check_catalog.py` 只讀取／比對；它不產生 Tachiko 專案、不執行語意、不證明輸出來源。
依既有工具鏈使用 Python 3.10+；無新增依賴或 lockfile。以下在 prep checkout root 執行：

```sh
uv run --no-project --offline python tests/tachiko_mirror/check_catalog.py \
  --self-test --source game/content/original_inventory.gd

# 此唯讀 driver 不建立 Game、不需原作素材，也不占用 #167 實體視窗。
# 使用專案既有 Godot 4.7.2；不要為本票更換 engine/toolchain。
evidence=$(mktemp -d "${TMPDIR:-/tmp}/richman4-tachiko.XXXXXX")
godot --headless --path "$PWD" \
  --script tests/tachiko_mirror/source_oracle.gd > "$evidence/godot.log" 2>&1 && \
uv run --no-project --offline python tests/tachiko_mirror/check_catalog.py \
  --source game/content/original_inventory.gd --godot-log "$evidence/godot.log"
```

M1 adapter 另行實作並提供其實際命令，不在這份準備虛構 CLI。完成後，將真正
Tachiko validated export 正規化為 checker 接受的相同 view，再執行：

```sh
uv run --no-project --offline python tests/tachiko_mirror/check_catalog.py \
  --projection "$evidence/roundtrip-1.json" \
  --repeat "$evidence/roundtrip-2.json" \
  --edited-projection "$evidence/edited.json"
```

Normalized view 的根只有 `card_capacity`, `tool_capacity_per_type`, `cards`, `tools`。
每個 record 正好是既有 `cards()` / `tools()` 公開回傳的欄位；見 source driver。
Object key 順序不是語意，但同一版 adapter 兩次獨立 fresh export 的完整 bytes 必須相同。
不得複製第一次檔案冒充第二次生成；不得直接輸出 oracle 冒充 Rust roundtrip。

`edited.json` 的唯一變更是 tool 路障 point price **30 → 31**。這是隔離候選，
不更改原鏡像或遊戲。必須經真實 Tachiko typed edit、semantic diff、save/reopen、export；
checker 驗內容，reviewer 另驗上述 provenance。不要手改 `.roproj` internals 製造證據。

## M1 必要證據（seed 不替代整包驗收）

| Gate | 需要的實際證据 |
| --- | --- |
| Source qualification | exact checkout + source blob + Godot 成功 exit + public-method oracle |
| Real mirror | 43 筆經 Rust validate/materialize/export；記錄採用 CLI revision/build |
| No-op roundtrip | full-field equality；兩次 fresh output bytes；重新開啟語意一致 |
| Stable identities | 保存 opaque ID mapping，重複 export / candidate edit / reopen 不變 |
| Valid edit | 路障 30→31；真實 semantic diff 只改該值；所有其他欄位與兩個 capacity 不變 |
| Invalid input | duplicate/missing ID、wrong type、fraction、negative supply、unknown field 不被 silent drop/coerce；無有效成品發布 |
| Preservation | 來源與已有目的地前後 hash 不變；衝突目的地明確失敗；錯誤不留下可用 partial output |
| Provenance | Richman4 / Tachiko / adapter pins、來源與projection hashes、exact commands；不含 secrets / owner saves |
| No gameplay change | 只 consumer tooling；沒有 runtime/core/MainUI/save/AI/payment / default-loader diff |
| Independent review | 同時審查 mapping、oracle、validation responsibility 與真實 Rust 呼叫證據 |

Invalid-input gate 要直接測 candidate importer/exporter，不是只讓 checker 拒絕壞 JSON。
對 schema 本身可接受但 consumer 不允許的值，歸類為 consumer diagnostic。
Baseline 缺工具／缺 adapter 是 PRECONDITION_UNMET，不是 behavioral RED。

## 已完成／未完成

本準備已在獨立環境執行 **26 harness self-tests / 0 failures**；2905-byte public source
轉錄與 Git blob 完全一致，43 rows / capacities static qualification 通過。
這些測試包含反例以檢驗 checker，不是已發現或修復 26 個遊戲問題。

尚未執行：Godot driver、真正 Tachiko CLI / `.roproj` 往返、consumer adapter、
人類 authoring / save-reopen 證據、獨立 review、hosted repo gates。不能標成已搬遷或 PASS。
準備環境沒有 Godot / Tachiko binary，container 無法直接存取 GitHub；來源經授權
GitHub connector 讀取並在本機按 blob hash 核對。没有修改使用者的 Mac 或執行中的 session。

## 接手與後續

Terra 先接 #169 的資格驗證與 review，再依 #168 的 M1 child scope 進行。
Routine mapping / tests 用外部 `~/.local/bin/deepseek-worker`；shared integration 不委派。
兩次同失敗沒新資訊就改定位，不重跑全庫／原作考古。

若既有 Tachiko 缺足以完成試點的能力，先提交最小 missing seam 與 evidence 到上游
tracking Issue，按上游 Ready/Accepted 規則處理，不能趁機改 Core 或建立 plugin framework。
資料試點不關閉 #1/#167，不接手 #165，不改 native audit 排程。

M1 通過後只提出下一個資料域；runtime cutover、Hot Reload、遊戲存檔 content pin、
rollback 與全流程 fixed-seed parity 仍需另外的明確授權。
