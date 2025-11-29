--[[----------------------------------------------------------------------------
ResolveUtils.lua
Utility functions for DaVinci Resolve integration.
------------------------------------------------------------------------------]]

local LrDialogs = import "LrDialogs"
local LrPathUtils = import "LrPathUtils"
local LrFileUtils = import "LrFileUtils"
local LrUUID = import "LrUUID"
local LrTasks = import "LrTasks"

-- プラットフォーム検出: WIN_ENVとMAC_ENVを定義
-- パスの区切り文字や標準ファイルパスの形式でプラットフォームを検出
-- Windowsではパスに`\`が含まれ、macOSでは`/`が使用される
local homePath = LrPathUtils.getStandardFilePath("home") or ""
local WIN_ENV = (homePath:match("^[A-Za-z]:\\") ~= nil)  -- Windows形式: C:\Users\...
local MAC_ENV = not WIN_ENV  -- WindowsでなければmacOSと仮定

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

local function shellEscapePath(path)
    -- シェルのダブルクォート内でのエスケープを行う
    -- 既にダブルクォートが含まれている場合はバックスラッシュでエスケープ
    path = path:gsub('"', '\\"')
    return '"' .. path .. '"'
end

local function getScriptLogPath()
    local base = getBaseDataDir()
    return LrPathUtils.child(base, "fuscript-output.log")
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

    if params.drxGradePath and params.drxGradePath ~= "" then
        jobData.drxGradePath = params.drxGradePath
    end

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
        "Could not trigger Resolve automatically.\n\nPlease execute 'Workspace > Scripts > Edit > LightroomToResolve' in DaVinci Resolve.",
        "info"
    )
end

-- Check if DaVinci Resolve is running
function ResolveUtils.isResolveRunning()
    if WIN_ENV then
        -- Windows: tasklistコマンドでResolve.exeプロセスを検索
        local cmd = 'tasklist /FI "IMAGENAME eq Resolve.exe" /NH'
        local handle = io.popen(cmd)
        if not handle then return false end
        local content = handle:read("*a")
        handle:close()
        return content and content:match("Resolve.exe") ~= nil
    else
        -- macOS: 複数の方法でResolveプロセスを検出
        -- 方法1: pgrep -f でプロセスコマンドラインに"DaVinci Resolve"が含まれるか確認
        local cmd1 = 'pgrep -f "DaVinci Resolve"'
        local handle1 = io.popen(cmd1)
        if handle1 then
            local content1 = handle1:read("*a")
            handle1:close()
            if content1 and content1:match("%S") then
                return true
            end
        end
        
        -- 方法2: psコマンドで"DaVinci Resolve"を含むプロセスを検索
        local cmd2 = 'ps aux | grep -i "[Dd]aVinci [Rr]esolve" | grep -v grep'
        local handle2 = io.popen(cmd2)
        if handle2 then
            local content2 = handle2:read("*a")
            handle2:close()
            if content2 and content2:match("DaVinci Resolve") then
                return true
            end
        end
        
        -- 方法3: pgrep -i で大文字小文字を無視して"resolve"を検索（最後の手段）
        local cmd3 = 'pgrep -i resolve | head -1'
        local handle3 = io.popen(cmd3)
        if handle3 then
            local content3 = handle3:read("*a")
            handle3:close()
            if content3 and content3:match("%S") then
                -- さらに確認: プロセス名が実際にResolve関連かチェック
                local pid = content3:match("(%S+)")
                if pid then
                    local cmd4 = string.format('ps -p %s -o comm= 2>/dev/null', pid)
                    local handle4 = io.popen(cmd4)
                    if handle4 then
                        local procName = handle4:read("*a")
                        handle4:close()
                        if procName and (procName:match("[Rr]esolve") or procName:match("[Dd]aVinci")) then
                            return true
                        end
                    end
                end
            end
        end
        
        return false
    end
end

function ResolveUtils.triggerScript()
    -- First, check if Resolve is running
    local isRunning = ResolveUtils.isResolveRunning()
    ResolveUtils.log("Checking if Resolve is running: " .. tostring(isRunning))
    if not isRunning then
        ResolveUtils.log("DaVinci Resolve is not running.")
        return false
    end
    ResolveUtils.log("DaVinci Resolve is running. Proceeding to trigger script.")

    local isWindows = (WIN_ENV == true)
    local fuscriptPath = nil
    local scriptPath = nil

    if isWindows then
        fuscriptPath = "C:\\Program Files\\Blackmagic Design\\DaVinci Resolve\\fuscript.exe"
        -- Assume standard AppData path for the installed script
        local appData = LrPathUtils.getStandardFilePath("appData")
        if appData then
             -- appData is usually "C:\Users\User\AppData\Roaming\Adobe\Lightroom"
             -- We need "C:\Users\User\AppData\Roaming"
             local roaming = LrPathUtils.parent(LrPathUtils.parent(appData))
             scriptPath = LrPathUtils.child(roaming, "Blackmagic Design\\DaVinci Resolve\\Support\\Fusion\\Scripts\\Edit\\LightroomToResolve.lua")
        end
    else
        -- macOS: 複数の可能なパスを試す（Resolve実行ファイルは除外）
        local possiblePaths = {
            "/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/MacOS/fuscript",
            "/Applications/DaVinci Resolve.app/Contents/MacOS/fuscript",
            "/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Resources/fuscript",
            "/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/fuscript",
            "/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/Executables/fuscript",
        }
        
        fuscriptPath = nil
        for _, path in ipairs(possiblePaths) do
            ResolveUtils.log("Checking for fuscript at: " .. path)
            local f = io.open(path, "r")
            if f then
                f:close()
                if LrPathUtils.leafName(path) == "fuscript" then
                    fuscriptPath = path
                    ResolveUtils.log("Found fuscript at: " .. path)
                    break
                else
                    ResolveUtils.log("Ignoring non-fuscript file: " .. path)
                end
            else
                ResolveUtils.log("fuscript not found at: " .. path)
            end
        end
        
        -- 見つからない場合は、findコマンドで検索を試みる
        if not fuscriptPath then
            ResolveUtils.log("fuscript not found in standard locations, searching with find...")
            local findCmd = 'find "/Applications" -name "fuscript" -type f 2>/dev/null | head -1'
            local handle = io.popen(findCmd)
            if handle then
                local foundPath = handle:read("*l")
                handle:close()
                if foundPath and foundPath ~= "" then
                    foundPath = foundPath:gsub("%s+$", "")  -- 行末の改行のみ削除
                    if LrPathUtils.leafName(foundPath) == "fuscript" then
                        fuscriptPath = foundPath
                        ResolveUtils.log("Found fuscript via find: " .. fuscriptPath)
                    else
                        ResolveUtils.log("find result is not fuscript: " .. foundPath)
                    end
                else
                    ResolveUtils.log("find command did not find fuscript")
                end
            else
                ResolveUtils.log("Failed to execute find command")
            end
        end
        
        -- それでも見つからない場合は、DaVinci Resolveアプリケーションのパスを確認
        if not fuscriptPath then
            ResolveUtils.log("Trying to locate DaVinci Resolve application...")
            local resolveAppPaths = {
                "/Applications/DaVinci Resolve/DaVinci Resolve.app",
                "/Applications/DaVinci Resolve.app",
            }
            for _, appPath in ipairs(resolveAppPaths) do
                local macosPath = LrPathUtils.child(appPath, "Contents/MacOS")
                if LrFileUtils.exists(macosPath) then
                    ResolveUtils.log("Found DaVinci Resolve app at: " .. appPath)
                    -- MacOSディレクトリ内のファイルをリスト
                    local listCmd = string.format('ls "%s" 2>/dev/null', macosPath)
                    local handle = io.popen(listCmd)
                    if handle then
                        local content = handle:read("*a")
                        handle:close()
                        ResolveUtils.log("Contents of MacOS directory: " .. content)
                        -- fuscriptという名前のファイルのみを探す（Resolveは除外）
                        if content:match("fuscript") then
                            local candidate = LrPathUtils.child(macosPath, "fuscript")
                            local fc = io.open(candidate, "r")
                            if fc then
                                fc:close()
                                fuscriptPath = candidate
                                ResolveUtils.log("Found fuscript in MacOS directory: " .. fuscriptPath)
                                break
                            end
                        end
                    end
                end
            end
        end
        
        local home = LrPathUtils.getStandardFilePath("home")
        if home then
            scriptPath = LrPathUtils.child(home, "Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Edit/LightroomToResolve.lua")
        end
    end

    if not scriptPath or not LrFileUtils.exists(scriptPath) then
        ResolveUtils.log("Script not found at: " .. tostring(scriptPath))
        return false
    end

    -- fuscriptが見つからない場合、osascriptを使用してResolveのスクリプトを実行
    if not fuscriptPath then
        ResolveUtils.log("fuscript not found, trying osascript method")
        -- osascriptを使用してResolveのスクリプトを実行
        -- ただし、これはResolveのUIに依存するため、確実ではない
        -- スクリプトパスをエスケープ
        local escapedScript = scriptPath:gsub("'", "'\\''")
        local appleScript = string.format(
            'tell application "DaVinci Resolve" to activate\n' ..
            'tell application "System Events"\n' ..
            '  tell process "DaVinci Resolve"\n' ..
            '    keystroke "l" using {command down, option down}\n' ..
            '  end tell\n' ..
            'end tell'
        )
        -- より直接的な方法: osascriptでスクリプトを実行
        -- ただし、ResolveのスクリプトAPIは外部からの直接実行をサポートしていない可能性がある
        -- そのため、キューに入れるだけにして、ユーザーに手動実行を促す
        ResolveUtils.log("fuscript not found, script will be queued for manual execution")
        return false
    end

    local cmd = ""
    local exitCode = nil
    if isWindows then
        -- Windows: wrap in quotes
        cmd = string.format('""%s" "%s""', fuscriptPath, scriptPath)
        -- Use cmd /c to execute and capture exit code
        exitCode = LrTasks.execute("cmd.exe /c " .. cmd)
    else
        -- macOS: シェル経由で実行し、出力をログファイルにリダイレクト
        local escapedFuscript = shellEscapePath(fuscriptPath)
        local escapedScript = shellEscapePath(scriptPath)
        local logPath = getScriptLogPath()
        local escapedLogPath = shellEscapePath(logPath)
        cmd = string.format('%s %s >> %s 2>&1', escapedFuscript, escapedScript, escapedLogPath)
        exitCode = LrTasks.execute(cmd)
        ResolveUtils.log("fuscript output redirected to: " .. logPath)
    end

    ResolveUtils.log(string.format("Triggered Resolve script (exitCode=%s): %s", tostring(exitCode), cmd))
    return true
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
