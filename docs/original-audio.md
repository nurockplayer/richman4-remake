# 原版音樂

`OriginalAudio` 只從檔案系統讀取 Ogg 音樂，不把原版音檔放進 public code repo 或
`res://`。遊戲啟動時依序嘗試：使用者曾選取且仍有效的資料夾、macOS app 內的
`Contents/Resources/Original/audio`，以及開發環境 bootstrap 建立的
`.local/private-assets/source/dfw4cskzl_136622`。每個來源都必須包含
`Media/Music/`；找不到有效來源時保留靜音遊戲，其他功能不受影響。

使用「音樂設定」選取原版遊戲資料夾後，路徑、開關與音量會保存到
`user://audio.cfg`。有效的自訂資料夾優先於隨 app 的音樂；失效時會自動回到隨包或
開發來源。播放順序目前是檔名字典序循環，尚未宣稱等同原版逐地圖選曲、混音、音效
或角色語音；這些對應仍是 Unknown。

私人 macOS 打包必須明確指定既有 verified private checkout：

```sh
RICHMAN4_AUDIO_ASSETS=/path/to/verified-assets \
  bash tools/package_macos.sh
```

腳本會先以 `config/private-assets.json` 及 `tools/verify_private_assets.py` 驗證固定
commit、manifest、檔案大小與 SHA-256，再由 `tools/package_music.py` 只複製
`Media/Music` 下的 `.ogg` 檔到 app 內，並寫入 `manifest.json`。該套件 manifest
保留來源 revision、來源 manifest SHA-256、檔案數、總大小與每個音檔的 SHA-256；
驗證失敗、Git LFS pointer、路徑逃逸、符號連結或空的音樂目錄都會在複製前停止。
沒有設定 `RICHMAN4_AUDIO_ASSETS` 時，打包流程不會取回或加入任何原版音檔。

合成 fixture 驗證來源優先順序、無素材 fallback，以及套件的 Ogg 篩選、manifest
hash、tamper、LFS pointer、符號連結與路徑逃逸拒絕。完整私人 export 仍只在唯一
FULL validation lane 進行；此分支不提交原版音檔。

## 原作曲目對應

來源 `rich4.exe`（MultiverseJourney）`47e773` 是 25 項曲目表，順序即 CD 音軌 02–26，也就是 Steam 版 `Media/Music/track02.ogg`–`track26.ogg`（`tracklen.nfo` 的長度吻合：02–09 為 112–185 秒，10–26 為 16–78 秒）。光碟版附同表的 MIDI 檔。

- 地圖曲：表 0–7（RICH08、RICH16–22，音軌 02–09）。`454d91(0)` 換下一首並以 `& 7` 回繞；`454d91(n)` 指定第 n 首；`415965` 以 `1` 從第一首開始。`OriginalAudio.next_track()` 在 25 首的來源曲庫只循環這 8 首，其他曲庫照舊循環全部。
- 場景短曲：表 8–24（MIDI01–16，音軌 10–26）。`4549cf(n)` 播第 n 段（`0x8000` 旗標略過保存目前地圖曲），`454bcc` 播完後從頭重播原地圖曲。`OriginalAudio.play_cue(n)` 對應此行為。
- 已接入（MainUI 依事件紀錄觸發，讀檔只建立基準不重播）：魔法屋 `433b1e` n=7、監獄入口 `43d38e` n=15、醫院入口 `43ea3a` n=16、月底結算 `439e99` n=9。
- 尚未對應的 `4549cf` 呼叫點（呼叫位置：n）：`4026fd`：0、`402a94`：0、`40711f`：1|0x8000、`407771`：6|0x8000、`40cf88`：2、`40d1cd`：5、`4109da`：選項預覽、`41539c`：12、`415597`：11、`4157cc`：10、`42ecf6`：6、`431644`：6、`4317a9`：8、`4338a0`：7、`43674f`：4、`4369e2`：4、`43c6cc`：5、`4525a3`：日期相關|0x8000。`46cb06` 低四位是「特殊曲剩餘天數」，`41cf67` 換日時歸零後恢復地圖曲。
