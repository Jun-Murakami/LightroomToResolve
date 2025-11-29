--[[----------------------------------------------------------------------------
InitPlugin.lua
Plugin initialization for Send to Resolve.
------------------------------------------------------------------------------]]

local LrPathUtils = import "LrPathUtils"
local LrFileUtils = import "LrFileUtils"
local LrPrefs = import "LrPrefs"

-- プラットフォーム検出: WIN_ENVとMAC_ENVを定義
-- パスの区切り文字や標準ファイルパスの形式でプラットフォームを検出
-- Windowsではパスに`\`が含まれ、macOSでは`/`が使用される
local homePath = LrPathUtils.getStandardFilePath("home") or ""
local WIN_ENV = (homePath:match("^[A-Za-z]:\\") ~= nil)  -- Windows形式: C:\Users\...
local MAC_ENV = not WIN_ENV  -- WindowsでなければmacOSと仮定

-- Get plugin preferences
local prefs = LrPrefs.prefsForPlugin()

-- Initialize default settings if not set
if prefs.exportFolder == nil then
    -- Default to a subfolder in user's Pictures folder
    prefs.exportFolder = LrPathUtils.child(LrPathUtils.getStandardFilePath("pictures"), "LightroomToResolve")
end

if prefs.tauriAppPath == nil then
    -- Default path for the Tauri app
    if WIN_ENV then
        prefs.tauriAppPath = LrPathUtils.child(
            LrPathUtils.getStandardFilePath("appData"),
            "Lightroom to Resolve\\Lightroom to Resolve.exe"
        )
    else
        prefs.tauriAppPath = "/Applications/Lightroom to Resolve.app"
    end
end

-- Ensure export folder exists
if not LrFileUtils.exists(prefs.exportFolder) then
    LrFileUtils.createAllDirectories(prefs.exportFolder)
end

return {
    -- No action needed
}

