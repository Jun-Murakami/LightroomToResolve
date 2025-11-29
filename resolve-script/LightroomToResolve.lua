local json = (function()
    local json = {}

    local escape_map = {
        ['"']  = '\\"',
        ["\\"] = "\\\\",
        ["/"]  = "\\/",
        ["\b"] = "\\b",
        ["\f"] = "\\f",
        ["\n"] = "\\n",
        ["\r"] = "\\r",
        ["\t"] = "\\t",
    }

    local function escape_char(c)
        return escape_map[c] or string.format("\\u%04x", c:byte())
    end

    local function encode(value, stack)
        local t = type(value)
        if t == "nil" then
            return "null"
        elseif t == "number" then
            return string.format("%.17g", value)
        elseif t == "boolean" then
            return tostring(value)
        elseif t == "string" then
            return '"' .. value:gsub('[%z\1-\31\\"]', escape_char) .. '"'
        elseif t == "table" then
            if stack[value] then
                error("json.encode: circular reference detected")
            end
            stack[value] = true

            local isArray = true
            local idx = 1
            for k, _ in pairs(value) do
                if k ~= idx then
                    isArray = false
                    break
                end
                idx = idx + 1
            end

            local items = {}
            if isArray then
                for i = 1, #value do
                    items[i] = encode(value[i], stack)
                end
                stack[value] = nil
                return "[" .. table.concat(items, ",") .. "]"
            else
                for k, v in pairs(value) do
                    local keyType = type(k)
                    if keyType ~= "string" and keyType ~= "number" then
                        error("json.encode: invalid key type " .. keyType)
                    end
                    table.insert(items, encode(tostring(k), stack) .. ":" .. encode(v, stack))
                end
                stack[value] = nil
                return "{" .. table.concat(items, ",") .. "}"
            end
        else
            error("json.encode: unsupported type " .. t)
        end
        error("json.decode: unterminated string")
    end

    function json.encode(value)
        return encode(value, {})
    end

    local function skip_ws(str, idx)
        local len = #str
        while idx <= len do
            local c = str:sub(idx, idx)
            if not (c == " " or c == "\t" or c == "\n" or c == "\r") then
                break
            end
            idx = idx + 1
        end
        return idx
    end

    local function parse_literal(str, idx, literal, value)
        if str:sub(idx, idx + #literal - 1) == literal then
            return value, idx + #literal
        end
        error("json.decode: invalid literal at position " .. idx)
    end

    local function parse_number(str, idx)
        local num = str:match("^%-?%d+%.?%d*[eE]?[+%-]?%d*", idx)
        if not num then
            error("json.decode: invalid number at position " .. idx)
        end
        return tonumber(num), idx + #num
    end

    local function unicode_to_utf8(code)
        if code <= 0x7F then
            return string.char(code)
        elseif code <= 0x7FF then
            return string.char(0xC0 + math.floor(code / 0x40), 0x80 + (code % 0x40))
        elseif code <= 0xFFFF then
            return string.char(
                0xE0 + math.floor(code / 0x1000),
                0x80 + (math.floor(code / 0x40) % 0x40),
                0x80 + (code % 0x40)
            )
        else
            return string.char(
                0xF0 + math.floor(code / 0x40000),
                0x80 + (math.floor(code / 0x1000) % 0x40),
                0x80 + (math.floor(code / 0x40) % 0x40),
                0x80 + (code % 0x40)
            )
        end
    end

    local function parse_string(str, idx)
        idx = idx + 1
        local res = {}
        local len = #str
        while idx <= len do
            local c = str:sub(idx, idx)
            if c == '"' then
                return table.concat(res), idx + 1
            elseif c == "\\" then
                local esc = str:sub(idx + 1, idx + 1)
                if esc == "u" then
                    local hex = str:sub(idx + 2, idx + 5)
                    local code = tonumber(hex, 16)
                    if not code then
                        error("json.decode: invalid unicode escape at position " .. idx)
                    end
                    res[#res + 1] = unicode_to_utf8(code)
                    idx = idx + 6
                else
                    local map = { ['"']='"', ["\\"]="\\", ["/"]="/", b="\b", f="\f", n="\n", r="\r", t="\t" }
                    local translated = map[esc]
                    if not translated then
                        error("json.decode: invalid escape char at position " .. idx)
                    end
                    res[#res + 1] = translated
                    idx = idx + 2
                end
            else
                res[#res + 1] = c
                idx = idx + 1
            end
        end
    end

    local function parse_array(str, idx)
        idx = idx + 1
        local res = {}
        idx = skip_ws(str, idx)
        if str:sub(idx, idx) == "]" then
            return res, idx + 1
        end
        while true do
            local val
            val, idx = json.parse(str, idx)
            res[#res + 1] = val
            idx = skip_ws(str, idx)
            local c = str:sub(idx, idx)
            if c == "]" then
                return res, idx + 1
            elseif c ~= "," then
                error("json.decode: expected ',' or ']' at position " .. idx)
            end
            idx = skip_ws(str, idx + 1)
        end
    end

    local function parse_object(str, idx)
        idx = idx + 1
        local res = {}
        idx = skip_ws(str, idx)
        if str:sub(idx, idx) == "}" then
            return res, idx + 1
        end
        while true do
            if str:sub(idx, idx) ~= '"' then
                error("json.decode: expected string key at position " .. idx)
            end
            local key
            key, idx = parse_string(str, idx)
            idx = skip_ws(str, idx)
            if str:sub(idx, idx) ~= ":" then
                error("json.decode: expected ':' at position " .. idx)
            end
            idx = skip_ws(str, idx + 1)
            local val
            val, idx = json.parse(str, idx)
            res[key] = val
            idx = skip_ws(str, idx)
            local c = str:sub(idx, idx)
            if c == "}" then
                return res, idx + 1
            elseif c ~= "," then
                error("json.decode: expected ',' or '}' at position " .. idx)
            end
            idx = skip_ws(str, idx + 1)
        end
    end

    function json.parse(str, idx)
        idx = skip_ws(str, idx or 1)
        local c = str:sub(idx, idx)
        if c == "{" then
            return parse_object(str, idx)
        elseif c == "[" then
            return parse_array(str, idx)
        elseif c == '"' then
            return parse_string(str, idx)
        elseif c == "-" or c:match("%d") then
            return parse_number(str, idx)
        elseif c == "t" then
            return parse_literal(str, idx, "true", true)
        elseif c == "f" then
            return parse_literal(str, idx, "false", false)
        elseif c == "n" then
            return parse_literal(str, idx, "null", nil)
        else
            error("json.decode: unexpected character '" .. c .. "' at position " .. idx)
        end
    end

    function json.decode(str)
        local value, idx = json.parse(str, 1)
        idx = skip_ws(str, idx)
        if idx <= #str then
            error("json.decode: trailing data at position " .. idx)
        end
        return value
    end

    return json
end)()

local IS_WINDOWS = package.config:sub(1,1) == "\\"
local PATH_SEP = IS_WINDOWS and "\\" or "/"

local function log(message)
    print(string.format("[LightroomToResolve] %s", message))
end

local function join_paths(...)
    local parts = {...}
    return table.concat(parts, PATH_SEP)
end

local function ensure_dir(path)
    if IS_WINDOWS then
        os.execute('cmd /c if not exist "' .. path .. '" mkdir "' .. path .. '" >nul 2>&1')
    else
        os.execute('mkdir -p "' .. path .. '" >/dev/null 2>&1')
    end
end

local function get_base_dir()
    if IS_WINDOWS then
        local appdata = os.getenv("APPDATA")
        if appdata and appdata ~= "" then
            return join_paths(appdata, "LightroomToResolve")
        end
    else
        local home = os.getenv("HOME")
        if home and home ~= "" then
            return join_paths(home, "Library", "Application Support", "LightroomToResolve")
        end
    end
    -- fallback to current directory
    return "LightroomToResolve"
end

local function get_queue_dirs()
    local base = get_base_dir()
    local queue = join_paths(base, "queue")
    local processed = join_paths(base, "processed")
    ensure_dir(queue)
    ensure_dir(processed)
    return queue, processed
end

local function quote_path(path)
    return '"' .. path:gsub('"', '\\"') .. '"'
end

local function get_file_mtime(path)
    if IS_WINDOWS then
        local escaped = path:gsub("'", "''")
        local command = string.format("powershell -NoProfile -Command \"(Get-Item -LiteralPath '%s').LastWriteTimeUtc.ToFileTimeUtc()\"", escaped)
        local handle = io.popen(command)
        if not handle then
            return 0
        end
        local output = handle:read("*a")
        handle:close()
        return tonumber(output) or 0
    else
        local command = string.format("stat -f %%m %s", quote_path(path))
        local handle = io.popen(command)
        if not handle then
            return 0
        end
        local output = handle:read("*a")
        handle:close()
        return tonumber(output) or 0
    end
end

local function list_directory(path)
    local files = {}
    local command
    if IS_WINDOWS then
        command = 'cmd /c dir /b "' .. path .. '"'
    else
        command = 'ls -1 "' .. path .. '"'
    end
    local handle = io.popen(command)
    if not handle then
        return files
    end
    for entry in handle:lines() do
        table.insert(files, entry)
    end
    handle:close()
    return files
end

local function read_file(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

local function move_file(src, dest)
    os.remove(dest)
    os.rename(src, dest)
end

local function get_resolve()
    if type(Resolve) ~= "function" then
        log("Resolve() API is not available in this environment.")
        return nil
    end
    local status, resolve = pcall(Resolve)
    if not status or not resolve then
        log("Failed to connect to Resolve.")
        return nil
    end
    return resolve
end

local function find_dng_converter()
    if IS_WINDOWS then
        local potentials = {
            "C:\\Program Files\\Adobe\\Adobe DNG Converter\\Adobe DNG Converter.exe",
            "C:\\Program Files (x86)\\Adobe\\Adobe DNG Converter\\Adobe DNG Converter.exe",
        }
        for _, path in ipairs(potentials) do
            local file = io.open(path, "r")
            if file then
                file:close()
                return path
            end
        end
    else
        local path = "/Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter"
        local file = io.open(path, "r")
        if file then
            file:close()
            return path
        end
    end
    return nil
end

local function convert_to_dng(raw_path, converter_path)
    local file = io.open(raw_path, "r")
    if not file then
        log("RAW file not found: " .. raw_path)
        return nil
    end
    file:close()

    local source_dir = raw_path:match("^(.*" .. PATH_SEP .. ")") or raw_path:gsub("[^" .. PATH_SEP .. "]+$", "")
    if source_dir == "" then
        source_dir = "."
    end
    
    -- Remove trailing separator for DNG Converter to avoid escaping issues on Windows
    if IS_WINDOWS and source_dir:sub(-1) == PATH_SEP then
        source_dir = source_dir:sub(1, -2)
    end

    local base_name = raw_path:match("([^" .. PATH_SEP .. "]+)%.%w+$") or "output"
    local expected_dng = source_dir .. PATH_SEP .. base_name .. ".dng"
    local final_dng = source_dir .. PATH_SEP .. base_name .. "_2d.dng"

    os.remove(expected_dng)
    os.remove(final_dng)

    local command
    if IS_WINDOWS then
        -- Windows often handles quotes better without the outer wrapper in os.execute depending on Lua version
        -- The previous fix added double quotes which might be confusing cmd.exe when combined with redirection
        command = string.format('"%s" -c -d "%s" "%s"', converter_path, source_dir, raw_path)
    else
        command = string.format('"%s" -c -d "%s" "%s"', converter_path, source_dir, raw_path)
    end

    log("Converting RAW via Adobe DNG Converter: " .. raw_path)
    log("Command: " .. command)
    
    -- Capture stderr to a temporary file
    local temp_err_file
    if IS_WINDOWS then
        local temp_dir = os.getenv("TEMP") or os.getenv("TMP") or "."
        temp_err_file = temp_dir .. "\\dng_err_" .. os.time() .. ".txt"
    else
        temp_err_file = "/tmp/dng_err_" .. os.time() .. ".txt"
    end
    
    local full_command
    if IS_WINDOWS then
        -- Explicitly wrap in cmd /C to handle redirection and quotes reliably
        full_command = 'cmd /C " ' .. command .. ' 2> ' .. quote_path(temp_err_file) .. ' "'
    else
        full_command = command .. " 2> " .. quote_path(temp_err_file)
    end
    
    local result = os.execute(full_command)
    local success = (result == 0) or (result == true)
    
    -- Read error output
    local error_output = ""
    local err_file = io.open(temp_err_file, "r")
    if err_file then
        error_output = err_file:read("*a") or ""
        err_file:close()
    end
    
    -- Clean up temp file
    os.remove(temp_err_file)
    
    if not success then
        log("DNG Converter failed for " .. raw_path)
        if error_output and error_output ~= "" then
            -- Clean up error output for logging
            local clean_err = error_output:gsub("\n", " "):gsub("\r", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
            if clean_err ~= "" then
                log("  Error: " .. clean_err)
            end
        end
        if not error_output or error_output == "" then
            log("  No error output captured. Check if DNG Converter is installed correctly.")
        end
        return nil
    end
    
    -- Log warnings even on success
    if error_output and error_output ~= "" then
        local clean_warn = error_output:gsub("\n", " "):gsub("\r", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        if clean_warn ~= "" then
            log("  Warning: " .. clean_warn)
        end
    end

    local function rename_if_exists(old_path, new_path)
        local f = io.open(old_path, "r")
        if f then
            f:close()
            os.remove(new_path)
            os.rename(old_path, new_path)
            return true
        end
        return false
    end

    if rename_if_exists(expected_dng, final_dng) then
        return final_dng
    end
    local f = io.open(final_dng, "r")
    if f then
        f:close()
        return final_dng
    end
    log("DNG output not found for " .. raw_path)
    return nil
end

local function ensure_project(resolve)
    local project_manager = resolve:GetProjectManager()
    if not project_manager then
        log("Failed to get Project Manager.")
        return nil
    end
    local project = project_manager:GetCurrentProject()
    if not project then
        log("No project is currently open.")
        return nil
    end
    return project
end

local function get_or_create_bin(media_pool, start_folder, relative_path)
    local current = start_folder
    local parts = {}
    for part in string.gmatch(relative_path, "[^/]+") do
        table.insert(parts, part)
    end
    for _, part in ipairs(parts) do
        local found = nil
        for _, child in ipairs(current:GetSubFolderList()) do
            if child:GetName() == part then
                found = child
                break
            end
        end
        if found then
            current = found
        else
            local new_folder = media_pool:AddSubFolder(current, part)
            if not new_folder then
                error("Failed to create folder: " .. part)
            end
            current = new_folder
        end
    end
    return current
end

local SKIP_EXTS = {
    [".jpg"]=true, [".jpeg"]=true, [".png"]=true,
    [".tif"]=true, [".tiff"]=true, [".psd"]=true,
    [".mp4"]=true, [".mov"]=true,
}

local function normalize_path(path)
    if IS_WINDOWS then
        local normalized = path:gsub("^\\\\%?\\", "")
        normalized = normalized:gsub("/", "\\")
        return normalized
    end
    return path
end

local function normalize_key(path)
    if IS_WINDOWS then
        return path:lower()
    end
    return path
end

local function set_map(map, path, value)
    if not path or path == "" then
        return
    end
    map[normalize_key(path)] = value
end

local function get_map(map, path)
    if not path or path == "" then
        return nil
    end
    return map[normalize_key(path)]
end

local function filename_lower(path)
    local base = path:match("([^" .. PATH_SEP .. "]+)$") or path
    return base:lower()
end

local function file_exists(path)
    if not path or path == "" then
        return false
    end
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function apply_grade_from_drx(timeline_item, drx_path)
    if not timeline_item or not drx_path then
        return false, "missing parameters"
    end

    local graph = timeline_item.GetNodeGraph and timeline_item:GetNodeGraph()
    if not graph or not graph.ApplyGradeFromDRX then
        return false, "node graph unavailable"
    end

    local ok, result = pcall(function()
        return graph:ApplyGradeFromDRX(drx_path, 0)
    end)

    if not ok then
        return false, result
    end

    if not result then
        return false, "ApplyGradeFromDRX returned false"
    end

    return true
end

local function find_timeline_by_name(project, name)
    if not project or not name or name == "" then
        return nil
    end

    -- Try direct lookup first (available in Resolve 18+)
    if project.GetTimelineByName then
        local found = project:GetTimelineByName(name)
        if found then
            return found
        end
    end

    -- Fallback: iterate all timelines and compare names
    local total = project.GetTimelineCount and project:GetTimelineCount() or 0
    for idx = 1, total do
        local timeline = project:GetTimelineByIndex(idx)
        if timeline and timeline.GetName and timeline:GetName() == name then
            return timeline
        end
    end

    return nil
end

local function process_job(job_path, resolve)
    log("Processing " .. job_path)
    local content = read_file(job_path)
    if not content then
        log("Failed to read job file.")
        return false
    end

    local ok, job = pcall(json.decode, content)
    if not ok or type(job) ~= "table" then
        log("Invalid JSON payload: " .. tostring(job))
        return false
    end

    local drx_grade_path = job.drxGradePath
    if drx_grade_path and drx_grade_path ~= "" then
        drx_grade_path = normalize_path(drx_grade_path)
        if file_exists(drx_grade_path) then
            log("DRX grade will be applied: " .. drx_grade_path)
        else
            -- Windows の Unicode パスなどでは Lua の io.open が失敗する場合があるので、チェックに失敗しても続行する
            log("WARNING: Could not verify DRX file on disk (continuing anyway): " .. tostring(drx_grade_path))
        end
    end

    local project = ensure_project(resolve)
    if not project then
        return false
    end
    local media_pool = project:GetMediaPool()

    local source_type = job.sourceType or "TIFF"
    -- TIFF は Lightroom 側で回転を焼き込んでいるため Resolve での回転処理を抑制するフラグ
    local allow_orientation_adjust = (source_type ~= "TIFF")
    local job_files = job.files or {}
    local input_files = {}
    local is_vertical_map = {}
    local orientation_map = {}

    for _, item in ipairs(job_files) do
        if type(item) == "table" then
            local path = normalize_path(item.path or "")
            if path ~= "" then
                table.insert(input_files, path)
                if item.isVertical then
                    set_map(is_vertical_map, path, true)
                end
                if allow_orientation_adjust and item.orientation then
                    set_map(orientation_map, path, item.orientation)
                end
            end
        elseif type(item) == "string" then
            local path = normalize_path(item)
            table.insert(input_files, path)
        end
    end

    if #input_files == 0 then
        log("No files listed in job.")
        return false
    end

    -- Set up bins
    local root_folder = media_pool:GetRootFolder()
    media_pool:SetCurrentFolder(root_folder)

    local collections_root = nil
    for _, child in ipairs(root_folder:GetSubFolderList()) do
        if child:GetName() == "Collections" then
            collections_root = child
            break
        end
    end
    if not collections_root then
        collections_root = media_pool:AddSubFolder(root_folder, "Collections")
    end
    local bin_path = job.binPath or "Lightroom Import"
    local timeline_bin = get_or_create_bin(media_pool, collections_root, bin_path)

    -- Source Photos root
    local source_root = nil
    for _, child in ipairs(root_folder:GetSubFolderList()) do
        if child:GetName() == "Source Photos" then
            source_root = child
            break
        end
    end
    if not source_root then
        source_root = media_pool:AddSubFolder(root_folder, "Source Photos")
    end

    local first_parent = "Imported"
    if #input_files > 0 then
        local dir = input_files[1]:match("^(.*" .. PATH_SEP .. ")")
        if dir then
            dir = dir:gsub(PATH_SEP .. "$", "")
            local name = dir:match("([^" .. PATH_SEP .. "]+)$")
            if name and name ~= "" then
                first_parent = name
            end
        end
    end

    media_pool:SetCurrentFolder(source_root)
    local source_bin = nil
    for _, child in ipairs(source_root:GetSubFolderList()) do
        if child:GetName() == first_parent then
            source_bin = child
            break
        end
    end
    if not source_bin then
        source_bin = media_pool:AddSubFolder(source_root, first_parent)
    end
    media_pool:SetCurrentFolder(source_bin)

    local import_files = {}
    if source_type == "RAW" then
        local converter = find_dng_converter()
        if not converter then
            log("Adobe DNG Converter not found. Cannot process RAW files.")
            return false
        end
        for _, path in ipairs(input_files) do
            local ext = path:match("%.([^%.]+)$")
            ext = ext and ("." .. ext:lower()) or ""
            if SKIP_EXTS[ext] then
                log("Skipping non-RAW file in RAW job: " .. path)
            else
                local dng_path = convert_to_dng(path, converter)
                if dng_path then
                    dng_path = normalize_path(dng_path)
                    table.insert(import_files, dng_path)
                    if get_map(is_vertical_map, path) then
                        set_map(is_vertical_map, dng_path, true)
                    end
                    if allow_orientation_adjust then
                        local orientation_value = get_map(orientation_map, path)
                        if orientation_value then
                            set_map(orientation_map, dng_path, orientation_value)
                        end
                    end
                else
                    log("Skipping " .. path .. " due to conversion failure")
                end
            end
        end
    else
        import_files = input_files
    end

    if #import_files == 0 then
        log("No files to import.")
        return false
    end

    local imported = media_pool:ImportMedia(import_files)
    if not imported or #imported == 0 then
        log("ImportMedia returned empty list (or failed).")
        return false
    end

    local timelines_created = 0
    for _, clip in ipairs(imported) do
        media_pool:SetCurrentFolder(timeline_bin)
        local clip_path = normalize_path(clip:GetClipProperty("File Path"))
        local is_vertical = get_map(is_vertical_map, clip_path) or false
        if not is_vertical then
            local basename = clip_path and filename_lower(clip_path)
            if basename then
                for path, flag in pairs(is_vertical_map) do
                    if filename_lower(path) == basename then
                        is_vertical = flag
                        break
                    end
                end
            end
        end

        local res_str = clip:GetClipProperty("Resolution") or "1920x1080"
        local clip_w, clip_h = res_str:match("^(%d+)%s*x%s*(%d+)$")
        clip_w = tonumber(clip_w) or 1920
        clip_h = tonumber(clip_h) or 1080

        local tl_w, tl_h
        if is_vertical then
            tl_w = math.min(clip_w, clip_h)
            tl_h = math.max(clip_w, clip_h)
        else
            tl_w = math.max(clip_w, clip_h)
            tl_h = math.min(clip_w, clip_h)
        end

        local clip_name = clip:GetName()
        local base_name = clip_name:gsub("%.%w+$", "")
        -- Remove _2d suffix if present
        base_name = base_name:gsub("_2d$", "")

        -- 既存タイムラインがあれば削除してから作成（上書き）
        local existing_timeline = find_timeline_by_name(project, base_name)
        if existing_timeline then
            log("Timeline already exists. Deleting: " .. base_name)
            local deleted = media_pool:DeleteTimelines({ existing_timeline })
            if deleted then
                log(" -> Deleted existing timeline: " .. base_name)
            else
                log(" -> Failed to delete timeline: " .. base_name)
                -- Rename existing timeline to avoid name collision, then continue
                if existing_timeline.SetName then
                    local fallback_name = string.format("%s (old %s)", base_name, os.date("%H%M%S"))
                    local renamed = existing_timeline:SetName(fallback_name)
                    if renamed then
                        log(" -> Renamed existing timeline to: " .. fallback_name)
                    else
                        log(" -> Failed to rename existing timeline, new timeline creation may still fail.")
                    end
                end
            end
        end

        local new_timeline = media_pool:CreateEmptyTimeline(base_name)

        if new_timeline then
            timelines_created = timelines_created + 1
            log("Created timeline: " .. new_timeline:GetName())

            new_timeline:SetSetting("useCustomSettings", "1")
            new_timeline:SetSetting("timelineResolutionWidth", tostring(tl_w))
            new_timeline:SetSetting("timelineResolutionHeight", tostring(tl_h))
            new_timeline:SetSetting("timelineOutputResolutionWidth", tostring(tl_w))
            new_timeline:SetSetting("timelineOutputResolutionHeight", tostring(tl_h))

            media_pool:AppendToTimeline(clip)

            local items = new_timeline:GetItemListInTrack("video", 1)
            if items and #items > 0 then
                local item = items[1]
                if allow_orientation_adjust then
                    local orientation = get_map(orientation_map, clip_path)
                    if not orientation and clip_path then
                        local basename = filename_lower(clip_path)
                        if basename then
                            for path, value in pairs(orientation_map) do
                                if filename_lower(path) == basename then
                                    orientation = value
                                    break
                                end
                            end
                        end
                    end

                    local rotation_angle = 0.0
                    if orientation == "BC" then
                        rotation_angle = -90.0
                    elseif orientation == "DA" then
                        rotation_angle = 90.0
                    elseif orientation == "CD" then
                        rotation_angle = 180.0
                    elseif is_vertical and tl_w < tl_h and clip_w > clip_h then
                        rotation_angle = -90.0
                    end

                    if rotation_angle ~= 0.0 then
                        item:SetProperty("RotationAngle", rotation_angle)
                        log(string.format(" -> Applied rotation: %.1f", rotation_angle))
                        local scale_factor = math.max(clip_w, clip_h) / math.min(clip_w, clip_h)
                        item:SetProperty("ZoomX", scale_factor)
                        item:SetProperty("ZoomY", scale_factor)
                        log(string.format(" -> Applied Zoom: %.3f", scale_factor))
                    end
                else
                    -- TIFF では Lightroom 側で正しい向きにレンダリング済みのため、Resolve 上での回転補正を明示的にスキップ
                    log(" -> Skipped rotation adjustments for TIFF source.")
                end

                if drx_grade_path then
                    local applied, err = apply_grade_from_drx(item, drx_grade_path)
                    if applied then
                        log(" -> Applied DRX grade: " .. drx_grade_path)
                    else
                        log(" -> Failed to apply DRX grade: " .. tostring(err))
                    end
                end
            end
            log(string.format(" -> Set resolution to %dx%d", tl_w, tl_h))
        else
            log("Failed to create timeline for " .. clip_name)
        end
    end

    if timelines_created > 0 then
        return true
    end
    log("No timelines were created.")
    return false
end

local function main()
    local queue_dir, processed_dir = get_queue_dirs()
    local resolve = get_resolve()
    if not resolve then
        return
    end

    local entries = list_directory(queue_dir)
    local jobs = {}
    for _, name in ipairs(entries) do
        if name:match("%.json$") then
            local full_path = join_paths(queue_dir, name)
            table.insert(jobs, { name = name, path = full_path, mtime = get_file_mtime(full_path) })
        end
    end

    table.sort(jobs, function(a, b)
        if a.mtime == b.mtime then
            return a.name < b.name
        end
        return a.mtime < b.mtime
    end)

    if #jobs == 0 then
        log("Queue is empty.")
        return
    end

    for _, job in ipairs(jobs) do
        local ok, result = pcall(process_job, job.path, resolve)
        if ok and result then
            local dest = join_paths(processed_dir, job.name)
            move_file(job.path, dest)
            log("Job completed: " .. job.name)
        elseif ok then
            log("Job failed: " .. job.name)
        else
            log("Error processing " .. job.name .. ": " .. tostring(result))
        end
    end
end

main()

