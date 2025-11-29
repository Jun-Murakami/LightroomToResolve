--[[----------------------------------------------------------------------------
Info.lua
Lightroom plugin Info file for Send to Resolve.

This plugin exports selected photos to DaVinci Resolve via TIFF or DNG format.
------------------------------------------------------------------------------]]

return {
    LrSdkVersion = 9.0,
    LrSdkMinimumVersion = 6.0,
    
    LrToolkitIdentifier = "com.conta.sendtoresolve",
    LrPluginName = "Send to Resolve",
    
    LrInitPlugin = "InitPlugin.lua",
    LrPluginInfoProvider = "PluginManager.lua",
    
    LrExportMenuItems = {
        {
            title = "Send to Resolve (TIFF/Edited)",
            file = "ExportToResolveTiff.lua",
            enabledWhen = "photosSelected",
        },
        {
            title = "Send to Resolve (DNG/Raw)",
            file = "ExportToResolveDng.lua",
            enabledWhen = "photosSelected",
        },
    },
    
    LrPluginInfoUrl = "https://jun-murakami.com",
    
    VERSION = { major = 0, minor = 1, revision = 0, build = 0 },
}

