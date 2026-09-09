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
