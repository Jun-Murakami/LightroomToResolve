# LightroomToResolve

Lightroom Classic で選んだ写真を、ワンクリックで DaVinci Resolve に送り込み、解像度に合わせたタイムラインを自動作成するツールです。縦位置 / RAW / TIFF をサポートします。

---

This tool allows you to send photos selected in Lightroom Classic to DaVinci Resolve and automatically create a timeline with the appropriate resolution. It supports vertical position / RAW / TIFF.

## 必須ソフト (Required Software)

- Adobe Lightroom Classic 6 or later
- DaVinci Resolve(tested with Studio only)
- Adobe DNG Converter (required for RAW to DNG conversion)
  https://helpx.adobe.com/jp/camera-raw/using/adobe-dng-converter.html

## インストール（Windows） (Installation (Windows))

1. `install_windows.bat` をダブルクリック。
2. Lightroom プラグインと Resolve スクリプトが以下にコピーされます。
   - `%APPDATA%\Adobe\Lightroom\Modules\SendToResolve.lrplugin`
   - `%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Edit\LightroomToResolve.lua`
3. Lightroom / Resolve を再起動。

---

1. Run `install_windows.bat` by double-clicking.
2. The Lightroom plugin and Resolve script will be copied to the following locations.
   - `%APPDATA%\Adobe\Lightroom\Modules\SendToResolve.lrplugin`
   - `%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Edit\LightroomToResolve.lua`
3. Restart Lightroom / Resolve.

## インストール（macOS） (Installation (macOS))

`.pkg`インストーラーを起動して実行してください。
Run the `.pkg` installer.

## 使い方 (Usage)

1. Lightroom で写真を選択し、**ファイル → プラグインエクストラ → Send to Resolve (TIFF/Edited または DNG/Raw)** を実行。（メニューが表示されない場合、プラグインマネージャーを開きプラグインが有効になっているか確認してください。）
2. Resolve が起動しプロジェクトが開かれていれば、スクリプトが自動で走り、写真がメディアプール＆タイムラインに追加されます。DNG/Raw の場合は自動的に元ソースから DNG Converter で.dng ファイルに変換され読み込まれます。
3. もし自動起動しない場合は、Resolve の **Workspace → Scripts → LightroomToResolve** を手動実行してください。

---

1. Select photos in Lightroom and run **File → Plugin Extras → Send to Resolve (TIFF/Edited or DNG/Raw)**. (If the menu is not displayed, open the Plugin Manager and check if the plugin is enabled.)
2. Resolve will start and open a project if it is already running. The script will run automatically and the photos will be added to the media pool & timeline. For DNG/Raw, the source file will be automatically converted to a .dng file using Adobe DNG Converter and loaded.
3. If the script does not start automatically, run **Workspace → Scripts → LightroomToResolve** manually.

## DRX グレードの自動適用（任意） (Optional: Automatic DRX Grade Application)

1. Lightroom の **ファイル → プラグインマネージャー** を開き、`Send to Resolve` を選択。
2. 設定セクションの「適用する DRX ファイル」で `Browse…` をクリックし、Resolve で使いたい `.drx` ファイルを指定します。
3. 以降、Lightroom からジョブを送ると Resolve のタイムライン作成後に同じグレードが全クリップへ自動反映されます（DRX が未設定・または見つからない場合はスキップされます）。

---

1. Open the **File → Plugin Manager** in Lightroom and select `Send to Resolve`.
2. In the Settings section, click `Browse…` in the "DRX to apply" field and select the `.drx` file you want to use in Resolve.
3. From then on, when you send a job from Lightroom, the same grade will be automatically applied to all clips after the Resolve timeline is created (skipped if DRX is not set or not found).

## License

[MIT License](LICENSE)
