--[[----------------------------------------------------------------------------
ResolveUtils.lua
Utility functions for DaVinci Resolve integration.
------------------------------------------------------------------------------]]

local LrDialogs = import "LrDialogs"
local LrPathUtils = import "LrPathUtils"
local LrFileUtils = import "LrFileUtils"
local LrUUID = import "LrUUID"

local ResolveUtils = {}

-- Get the collection path for a photo (for creating bin hierarchy)
function ResolveUtils.getCollectionPath(photo)
    local containingCollections = photo:getContainedCollections()
    
    if containingCollections and #containingCollections > 0 then
        -- Get the first collection the photo belongs to
        local collection = containingCollections[1]
        local path = collection:getName()
        
        -- Walk up the hierarchy
        local parent = collection:getParent()
        while parent do
            path = parent:getName() .. "/" .. path
            parent = parent:getParent()
        end
        
        return path
    end
    
    -- Default path if no collection
    return "Lightroom Import"
end

local function getBaseDataDir()
    local appData = LrPathUtils.getStandardFilePath("appData")

    -- Lightroom の appData は通常 .../Adobe/Lightroom なので、2階層上に戻って共通ルートを得る
    local sharedRoot = appData
    if appData then
        local parent = LrPathUtils.parent(appData)
        if parent then
            local grandParent = LrPathUtils.parent(parent)
            sharedRoot = grandParent or parent
        end
    end

    if not sharedRoot or sharedRoot == "" then
        sharedRoot = appData or LrPathUtils.getStandardFilePath("documents")
    end

    local base = LrPathUtils.child(sharedRoot, "LightroomToResolve")
    LrFileUtils.createAllDirectories(base)
    return base
end

function ResolveUtils.getQueueDir()
    local base = getBaseDataDir()
    local queueDir = LrPathUtils.child(base, "queue")
    LrFileUtils.createAllDirectories(queueDir)
    return queueDir
end

local function isArray(tbl)
    local count = 0
    for k, _ in pairs(tbl) do
        if type(k) ~= "number" then
            return false
        end
        count = count + 1
    end
    return count == #tbl
end

local function escapeString(str)
    str = str:gsub("\\", "\\\\")
    str = str:gsub('"', '\\"')
    str = str:gsub("\n", "\\n")
    str = str:gsub("\r", "\\r")
    str = str:gsub("\t", "\\t")
    return '"' .. str .. '"'
end

local function encodeJson(value)
    local valueType = type(value)
    if valueType == "string" then
        return escapeString(value)
    elseif valueType == "number" or valueType == "boolean" then
        return tostring(value)
    elseif value == nil then
        return "null"
    elseif valueType == "table" then
        if isArray(value) then
            local parts = {}
            for i, item in ipairs(value) do
                parts[i] = encodeJson(item)
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, v in pairs(value) do
                table.insert(parts, escapeString(k) .. ":" .. encodeJson(v))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

function ResolveUtils.writeJobFile(params)
    local queueDir = ResolveUtils.getQueueDir()
    local jobId = LrUUID.generateUUID()
    local filename = string.format("job-%s.json", jobId)
    local path = LrPathUtils.child(queueDir, filename)

    local jobData = {
        id = jobId,
        version = 1,
        createdAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        binPath = params.binPath or "Lightroom Import",
        timelineName = params.timelineName,
        sourceType = params.sourceType,
        collectionPath = params.collectionPath or {},
        files = params.files or {},
        notes = params.notes,
    }

    local file = io.open(path, "w")
    if not file then
        return nil
    end
    file:write(encodeJson(jobData))
    file:close()
    return path
end

function ResolveUtils.log(message)
    local base = getBaseDataDir()
    local logPath = LrPathUtils.child(base, "plugin.log")
    local file = io.open(logPath, "a")
    if file then
        file:write(string.format("[%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), message))
        file:close()
    end
end

function ResolveUtils.notifyJobCreated(jobPath)
    LrDialogs.message(
        "Queued for Resolve",
        "Run Resolve and open the script in Workspace > Scripts > Edit > LightroomToResolve \n\n" .. jobPath,
        "info"
    )
end

function ResolveUtils.getPowershellPath()
    if WIN_ENV then
        return "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
    elseif MAC_ENV then
        return "/usr/bin/env pwsh"
    else
        return "/usr/bin/env pwsh"
    end
end

return ResolveUtils
