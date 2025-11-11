-- User patch to add separator to last menu item in filemanager_settings
-- This provides visual separation for plugin-added menu items
-- Priority: 2

local logger = require("logger")

-- Patch FileManagerMenu to add separator to start_with menu item
local function patchFileManagerMenu()
    local ok, FileManagerMenu = pcall(require, "apps/filemanager/filemanagermenu")
    if not ok then
        logger.warn("KoboPlugin: Could not load FileManagerMenu for patching")
        return
    end

    -- Save original getStartWithMenuTable
    local original_getStartWithMenuTable = FileManagerMenu.getStartWithMenuTable

    -- Override to add separator
    function FileManagerMenu:getStartWithMenuTable()
        local menu_table = original_getStartWithMenuTable(self)
        -- Add separator to visually separate from plugin items below
        menu_table.separator = true
        return menu_table
    end

    logger.info("KoboPlugin: Added separator to filemanager_settings menu")
end

-- Apply patch
patchFileManagerMenu()

return true
