--[[----------------------------------------------------------------------------
ExportToResolveTiff.lua
Export selected photos as TIFF (with edits applied) and send to Resolve.
------------------------------------------------------------------------------]]

local LrTasks = import "LrTasks"
local LrDialogs = import "LrDialogs"
local LrApplication = import "LrApplication"
local LrExportSession = import "LrExportSession"
local LrPathUtils = import "LrPathUtils"
local LrFileUtils = import "LrFileUtils"
local LrPrefs = import "LrPrefs"
local LrProgressScope = import "LrProgressScope"

local ResolveUtils = require "ResolveUtils"

-- Main export function
LrTasks.startAsyncTask(function()
    local catalog = LrApplication.activeCatalog()
    local selectedPhotos = catalog:getTargetPhotos()
    
    if #selectedPhotos == 0 then
        LrDialogs.message("No Photos Selected", "Please select one or more photos to export.")
        return
    end
    
    local prefs = LrPrefs.prefsForPlugin()
    local exportFolder = prefs.exportFolder
    
    -- Ensure export folder exists
    if not LrFileUtils.exists(exportFolder) then
        LrFileUtils.createAllDirectories(exportFolder)
    end
    
    -- Progress scope
    local progressScope = LrProgressScope({
        title = "Exporting to Resolve (TIFF)",
        functionContext = context,
    })
    
    -- Export settings for TIFF
    local exportSettings = {
        LR_export_destinationType = "sourceFolder",
        LR_export_useSubfolder = false,
        
        LR_format = "TIFF",
        LR_export_colorSpace = "sRGB",
        LR_export_bitDepth = 16,
        LR_tiff_compressionMethod = "compressionMethod_None",
        
        LR_size_doConstrain = false,
        LR_outputSharpeningOn = false,
        
        LR_metadata_keywordOptions = "lightroomHierarchical",
        LR_embeddedMetadataOption = "all",
        LR_removeLocationMetadata = false,
        
        LR_reimportExportedPhoto = false,
        LR_renamingTokensOn = true,
        LR_tokens = "{{image_name}}_2d",
        
        LR_collisionHandling = "overwrite",
    }
    
    -- Create export session
    local exportSession = LrExportSession({
        photosToExport = selectedPhotos,
        exportSettings = exportSettings,
    })
    
    -- Track exported files
    local exportedFiles = {}
    local binPath = "Lightroom Import" -- Default
    
    -- Get collection path from first photo for bin hierarchy
    if #selectedPhotos > 0 then
        binPath = ResolveUtils.getCollectionPath(selectedPhotos[1])
    end
    
    -- Perform export
    for i, rendition in exportSession:renditions() do
        progressScope:setPortionComplete(i - 1, #selectedPhotos)
        progressScope:setCaption("Exporting " .. i .. " of " .. #selectedPhotos)
        
        local success, pathOrMessage = rendition:waitForRender()
        
        if success then
            -- Get orientation
            local photo = rendition.photo
            local dims = photo:getRawMetadata("dimensions")
            local isVertical = false
            
            -- Simple vertical detection: width < height
            if dims and dims.width < dims.height then
                isVertical = true
            end
            
            table.insert(exportedFiles, {
                path = pathOrMessage,
                name = LrPathUtils.leafName(pathOrMessage),
                isVertical = isVertical,
                -- TIFF は Lightroom 側で回転が焼き込まれているため orientation を渡さない
            })
        else
            LrDialogs.message("Export Error", "Failed to export: " .. tostring(pathOrMessage))
        end
        
        if progressScope:isCanceled() then
            break
        end
    end
    
    progressScope:done()
    
    -- Write queue job
    if #exportedFiles > 0 then
        local drxGradePath = prefs.drxGradePath
        if drxGradePath and drxGradePath ~= "" and not LrFileUtils.exists(drxGradePath) then
            ResolveUtils.log("Configured DRX file not found, skipping: " .. tostring(drxGradePath))
            drxGradePath = nil
        end

        -- Extract just paths for 'files' array in job if structure requires it, 
        -- but updated ResolveUtils.writeJobFile can handle objects if we update it.
        -- Current ResolveUtils expects simple path list or object list?
        -- Looking at ResolveUtils.lua, it iterates param.filePaths and makes objects.
        -- We should update ResolveUtils to accept file objects directly.
        
        local fileList = {}
        for _, f in ipairs(exportedFiles) do
            table.insert(fileList, f.path)
        end
        
        -- For now, pass paths. We need to update ResolveUtils to pass metadata.
        -- Let's update ResolveUtils.writeJobFile to take full objects.
        
        local jobPath = ResolveUtils.writeJobFile({
            files = exportedFiles, -- Passing objects: {path, name, isVertical}
            binPath = binPath,
            timelineName = "Lightroom TIFF " .. os.date("%Y%m%d-%H%M"),
            sourceType = "TIFF",
            drxGradePath = drxGradePath,
        })
        if jobPath then
            local triggered = ResolveUtils.triggerScript()
            if not triggered then
                ResolveUtils.notifyJobCreated(jobPath)
            else
                LrDialogs.message("Sent to Resolve", "Import process completed.\nCheck the Media Pool in DaVinci Resolve.", "info")
            end
        else
            LrDialogs.message("Queue Error", "Failed to enqueue Resolve job.")
        end
    else
        LrDialogs.message("Export Failed", "No photos were exported successfully.")
    end
end)
