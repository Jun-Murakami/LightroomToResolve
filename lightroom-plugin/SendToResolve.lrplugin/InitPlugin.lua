--[[----------------------------------------------------------------------------
InitPlugin.lua
Plugin initialization for Send to Resolve.
------------------------------------------------------------------------------]]

local LrPathUtils = import "LrPathUtils"
local LrFileUtils = import "LrFileUtils"
local LrPrefs = import "LrPrefs"

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

