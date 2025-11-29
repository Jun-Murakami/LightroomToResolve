--[[----------------------------------------------------------------------------
PluginManager.lua
Provides the Lightroom Plug-in Manager UI for Send to Resolve.
------------------------------------------------------------------------------]]

local LrView = import "LrView"
local LrDialogs = import "LrDialogs"
local LrPrefs = import "LrPrefs"
local LrFileUtils = import "LrFileUtils"

local bind = LrView.bind
local viewFactory = LrView.osFactory()
local prefs = LrPrefs.prefsForPlugin()

local PluginManager = {}

local function normalizePath(path)
    if path == nil or path == "" then
        return nil
    end
    return path
end

local function buildStatusText(path)
    if path == nil or path == "" then
        return "Not configured. Specify a .drx file if you want to auto-apply a grade."
    elseif LrFileUtils.exists(path) then
        return "Selected: " .. path
    else
        return "⚠️ File not found: " .. path
    end
end

function PluginManager.sectionsForTopOfDialog(_, propertyTable)
    propertyTable.drxGradePath = propertyTable.drxGradePath or prefs.drxGradePath or ""
    propertyTable.drxStatusMessage = propertyTable.drxStatusMessage or buildStatusText(propertyTable.drxGradePath)

    if not propertyTable._drxObserverAdded then
        propertyTable:addObserver("drxGradePath", function()
            prefs.drxGradePath = normalizePath(propertyTable.drxGradePath)
            propertyTable.drxStatusMessage = buildStatusText(propertyTable.drxGradePath)
        end)
        propertyTable._drxObserverAdded = true
    end

    local function chooseDrx()
        local result = LrDialogs.runOpenPanel({
            title = "Select DRX file",
            prompt = "Select",
            canChooseFiles = true,
            canChooseDirectories = false,
            allowsMultipleSelection = false,
            fileTypes = { "drx", "DRX" },
        })

        if result and #result > 0 then
            propertyTable.drxGradePath = result[1]
        end
    end

    local function clearDrx()
        propertyTable.drxGradePath = ""
    end

    return {
        {
            title = "DaVinci Resolve Grade Settings",
            viewFactory:column({
                spacing = viewFactory:control_spacing(),
                viewFactory:row({
                    viewFactory:static_text({
                        title = "DRX to apply",
                        width_in_chars = 20,
                    }),
                    viewFactory:edit_field({
                        bind_to_object = propertyTable,
                        value = bind("drxGradePath"),
                        width_in_chars = 50,
                        truncate = "middle",
                        tooltip = "Path to the PowerGrade (.drx) file to apply in DaVinci Resolve",
                    }),
                }),
                viewFactory:row({
                    spacing = viewFactory:control_spacing(),
                    viewFactory:push_button({
                        title = "Browse…",
                        action = chooseDrx,
                    }),
                    viewFactory:push_button({
                        title = "Clear",
                        action = clearDrx,
                    }),
                }),
                viewFactory:static_text({
                    bind_to_object = propertyTable,
                    title = bind("drxStatusMessage"),
                    wrap = true,
                    width_in_chars = 80,
                }),
                viewFactory:static_text({
                    title = "When set, the selected DRX grade will be applied automatically after the Resolve timeline is created.",
                    wrap = true,
                    width_in_chars = 80,
                }),
            }),
        },
    }
end

return PluginManager

