-- Helper to dynamically extract Dispatcher actions from KOReader runtime.
-- Mirrors the approach used by httpinspector.koplugin.

local M = {}

local _ = require("gettext")
local util = require("util")

local _dispatcher_actions_cache

---
--- Get all dispatcher actions grouped by category.
--- Uses debug.getupvalue to extract settingsList and dispatcher_menu_order from Dispatcher.
---
--- @return table|nil Array of actions organized by category, with section titles (strings) interspersed.
---        Each action is a table with fields: event, title, args, toggle, category, dispatcher_id, etc.
---        Returns nil and error message if extraction fails.
function M.get_dispatcher_actions_ordered()
    if _dispatcher_actions_cache then
        return _dispatcher_actions_cache
    end

    local ok_debug = pcall(function()
        return debug
    end)
    if not ok_debug then
        return nil
    end

    local ok, Dispatcher = pcall(require, "dispatcher")
    if not ok or not Dispatcher then
        return nil
    end

    local settings, order

    -- Check if Dispatcher.init exists and is a function
    if type(Dispatcher.init) == "function" then
        local n = 1
        while true do
            local name, value = debug.getupvalue(Dispatcher.init, n)

            if not name then
                break
            end

            if name == "settingsList" then
                settings = value

                break
            end

            n = n + 1
        end
    end

    -- Check if Dispatcher.registerAction exists and is a function
    if type(Dispatcher.registerAction) == "function" then
        local n = 1
        while true do
            local name, value = debug.getupvalue(Dispatcher.registerAction, n)

            if not name then
                break
            end

            if name == "dispatcher_menu_order" then
                order = value

                break
            end

            n = n + 1
        end
    end

    if not settings or not order then
        return nil
    end

    local section_list = {
        { "general", _("General") },
        { "device", _("Device") },
        { "screen", _("Screen and lights") },
        { "filemanager", _("File browser") },
        { "reader", _("Reader") },
        { "rolling", _("Reflowable documents") },
        { "paging", _("Fixed layout documents") },
    }

    local actions = {}

    for _, section in ipairs(section_list) do
        table.insert(actions, section[2])

        local section_key = section[1]

        for _, k in ipairs(order) do
            if settings[k] and settings[k][section_key] == true then
                local t = util.tableDeepCopy(settings[k])

                t.dispatcher_id = k
                table.insert(actions, t)
            end
        end
    end

    _dispatcher_actions_cache = actions

    return actions
end

--- Clear the cached actions (useful for testing or refreshing after plugins add new actions).
function M.clear_cache()
    _dispatcher_actions_cache = nil
end

return M
