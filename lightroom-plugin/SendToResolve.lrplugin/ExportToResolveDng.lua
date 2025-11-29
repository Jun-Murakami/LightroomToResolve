--[[----------------------------------------------------------------------------
ExportToResolveDng.lua
Export selected photos as DNG (raw conversion) and send to Resolve.
Uses Adobe DNG Converter for raw files.
------------------------------------------------------------------------------]]

local LrTasks = import "LrTasks"
local LrDialogs = import "LrDialogs"
local LrApplication = import "LrApplication"
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
    
    -- Progress scope
    local progressScope = LrProgressScope({
        title = "Queuing for Resolve (RAW)",
        functionContext = context,
    })
    
    -- Track files
    local exportedFiles = {}
    local binPath = "Lightroom Import" -- Default
    
    -- Get collection path from first photo for bin hierarchy
    if #selectedPhotos > 0 then
        binPath = ResolveUtils.getCollectionPath(selectedPhotos[1])
    end
    
    -- Process each photo
    for i, photo in ipairs(selectedPhotos) do
        progressScope:setPortionComplete(i - 1, #selectedPhotos)
        progressScope:setCaption("Processing " .. i .. " of " .. #selectedPhotos)
        
        if progressScope:isCanceled() then
            break
        end
        
        local fileFormat = photo:getRawMetadata("fileFormat")
        if fileFormat ~= "RAW" and fileFormat ~= "DNG" then
            LrDialogs.message(
                "Skipped Non-RAW File",
                "Skipping file as it is not RAW or DNG format:\n" .. photo:getFormattedMetadata("fileName") .. "\n\nUse 'Send to Resolve (TIFF/Edited)' for non-raw files.",
                "warning"
            )
        else
            local rawPath = photo:getRawMetadata("path")
            local dims = photo:getRawMetadata("dimensions")
            local orientation = photo:getRawMetadata("orientation")
            local isVertical = false
            if dims and dims.width < dims.height then
                isVertical = true
            end
            
            table.insert(exportedFiles, {
                path = rawPath,
                name = LrPathUtils.leafName(rawPath),
                isVertical = isVertical,
                orientation = orientation
            })
        end
    end
    
    progressScope:done()
    
    -- Write queue job
    if #exportedFiles > 0 then
        local jobPath = ResolveUtils.writeJobFile({
            files = exportedFiles,
            binPath = binPath,
            timelineName = "Lightroom RAW " .. os.date("%Y%m%d-%H%M"),
            sourceType = "RAW", 
        })
        if jobPath then
            ResolveUtils.notifyJobCreated(jobPath)
        else
            LrDialogs.message("Queue Error", "Failed to enqueue Resolve job.")
        end
    else
        LrDialogs.message("Export Failed", "No photos found.")
    end
end)
