# 移動與結果呈現

[Issue #60](https://github.com/nurockplayer/richman4-remake/issues/60) 將 action-scoped 移動判讀放在 `movement_presentation.gd`。GameState 同步完成操作；MainUI 擷取前後 snapshot，BoardView 以每格0.16秒呈現既定路線，動畫不修改 simulation、存檔或 RNG。

一般逐格紀錄是 `move`；選路本身使用 `route_chosen`，同樣代表已走過一條 edge。只取該次操作可證明的新增事件；log截斷重疊有歧義、legacy聚合、瞬移、狀態或對局結束時採直接顯示結果。一般refresh不重播。地產所有權／建設造成的來源record變更不算換圖；幾何與來源身份另行核對。

動畫期間暫停操作與AI；完成後才顯示分岔、落點效果及下一回合。新局／讀檔取消呈現並提高generation，舊完成回呼與AI timer不能覆寫新局。存檔仍保存已完成的simulation結果。

角色沿既有八方向站姿轉向：下0、右下1、右2、右上3、上4、左上5、左6、左下7。映射依已核對的來源方向表與目前平面座標；沒有原版runtime逐幀比對的宣稱。步態、車身動畫與其他未確認resource mapping仍採站姿移動fallback，不新增decode或完整素材副本。

新聞／命運的已完成結果預設顯示2.4／1.6秒後關閉，也可手動提早關閉。每次新結果及新局／讀檔取消都使舊timer失效；這些是結果呈現時間，simulation的preview/apply仍同步，並非重現原版所有媒體時序。

驗證使用 `movement_presentation`、`movement_ui`、`movement_continuation`、`news_timing`、`fate_timing` tests，以及既有news/fate UI回歸。真實UI基準17/5 RED→20/0、continuation8/2→0、兩個timer各13/6→0；早期helper單獨交付的missing-module parse failure不是行為RED。native來源素材及AI連續操作證據記在active PR。
