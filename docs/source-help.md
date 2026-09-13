# 原版遊戲說明

#192 在 current main 上重新接入 #102 的原版說明視窗；它不是舊有 stacked PR #140 的
合併路徑，也不改動月結、銀行、存檔、RNG、AI 或地圖行為。

## 範圍與來源

說明從棋盤工具列進入，維持來源形狀的 400×400 三欄視窗，置於 640×480 logical
canvas 的 `(120,40)`。同版內容分成八個分類、共 99 個主題；可選分類／主題、翻閱
主題列表及正文，並以 source-backed 的鍵盤 PageUp／PageDown 翻頁。右鍵放開會關閉
並回到原棋局。

內容與圖像不會進入 public repository。私有 bundle 的兩版內容分別驗證；loader 不會
在缺失、版別不符、格式不合法或雜湊不符時借用另一版文字。缺少內容或圖像會明示，
但視窗仍可正常關閉，不會捏造手冊內容。

來源契約沿用 #139／PR #140 的 `rich4_ui_help.asm` entry、renderer、callback 與 tables，
以及 `help.mkf`：12 個 resource chunks 構成視窗；分類 topic 數為
`1/6/12/3/16/18/30/13`。每個 topic 保留 source payload 與分頁 payload 的 digest。
`export_original_help.py` 只接受同版 `help.mkf`，`package_help.py` 只將已驗證的小型
bundle 放入 package；二者都不需要無關的 map 或完整原始素材樹。

## Runtime 邊界

`original_help.gd` 依序從 `RICHMAN4_HELP_MANIFEST`、已封裝 app 的
`Contents/Resources/Original/help/manifest.json` 與開發用
`.local/original-help/manifest.json` 載入。內容與 index 設有限制，並在每次使用時回傳
獨立複本。

Controller 持有同一個 game ownership，關閉 callback 受 generation 保護；新局或讀入
另一棋局會取消舊視窗。視窗開啟時，MainUI 阻擋底層遊戲操作、AI、其他 modal、存讀檔
及新局入口；關閉後恢復工具列。閱讀／取消不應改變 state、gameplay ledger 或 RNG。

## 目前 qualification 狀態

歷史 #140 的測試與來源研究只作設計證據。#192 必須在其 exact candidate HEAD 重新取得
focused loader/controller/presenter/MainUI、兩版私有內容 provenance、ordinary package/native
navigation/close/return、unavailable no-soft-lock、state/RNG invariance、source/remake rendered
comparison、hosted Verify 與 fresh independent review。這個文件不宣稱 #102、#167、#99 或
Mission #1 已完成。
