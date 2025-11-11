---
-- FileChooser extensions for Kobo virtual library.
-- Monkey patches FileChooser to show virtual Kobo library.

local logger = require("logger")

local FileChooserExt = {}

---
-- Checks if a path matches the kepub directory.
-- @param path string: Path to check.
-- @param kepub_dir string: Kepub directory path.
-- @return boolean: True if path is within kepub directory.
local function isKepubDirectoryPath(path, kepub_dir)
    if not path or not kepub_dir then
        return false
    end

    local escaped_kepub_dir = kepub_dir:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    return path:match("^" .. escaped_kepub_dir) ~= nil
end

---
-- Finds the insertion position for virtual folder in item table.
-- Skips past "go up" and "long-press" navigation entries.
-- @param item_table table: File chooser item table.
-- @return number: Position to insert virtual folder.
local function findVirtualFolderInsertPosition(item_table)
    for i, item in ipairs(item_table) do
        if not item.is_go_up and not item.path:match("/%.$") then
            return i
        end
    end

    return #item_table + 1
end

---
-- Checks if we should add the virtual folder at this path.
-- Only adds at root or home directory.
-- @param path string: Current path.
-- @return boolean: True if virtual folder should be added.
local function shouldAddVirtualFolder(path)
    if path == "/" then
        return true
    end

    local home_dir = G_reader_settings:readSetting("home_dir")
    return home_dir and path == home_dir
end

---
-- Performs automatic reading state sync on first virtual library open.
-- Uses session flag to prevent duplicate syncs.
-- @param reading_state_sync table: Reading state sync instance.
local function performAutomaticSync(reading_state_sync)
    if not reading_state_sync or not reading_state_sync:isEnabled() then
        return
    end

    if not reading_state_sync:isAutomaticSyncEnabled() then
        return
    end

    local SessionFlags = require("session_flags")
    if SessionFlags:isFlagSet("virtual_library_synced") then
        return
    end

    SessionFlags:setFlag("virtual_library_synced")
    logger.info("KoboPlugin: Performing automatic sync on virtual library open")

    local Trapper = require("ui/trapper")
    Trapper:wrap(function()
        reading_state_sync:syncAllBooks()
    end)
end

---
-- Shows error message when no books are found in virtual library.
local function showNoBookMessage()
    local InfoMessage = require("ui/widget/infomessage")
    local UIManager = require("ui/uimanager")
    UIManager:show(InfoMessage:new({
        text = "No accessible books found in Kobo library.\n\n"
            .. "Books may be encrypted or the library may be empty.",
        timeout = 3,
    }))
end

---
-- Creates a "back" navigation entry for the virtual library.
-- @return table: Navigation entry that returns to home directory.
local function createBackEntry()
    local Device = require("device")
    local home_dir = G_reader_settings:readSetting("home_dir") or Device.home_dir or "/"
    return {
        text = "⬆ ../",
        path = home_dir,
        is_go_up = true,
    }
end

---
-- Initializes the FileChooserExt module.
-- @param virtual_library table: Virtual library instance.
-- @param reading_state_sync table: Reading state sync instance.
function FileChooserExt:init(virtual_library, reading_state_sync)
    self.virtual_library = virtual_library
    self.reading_state_sync = reading_state_sync
    self.original_methods = {}
end

---
-- Applies monkey patches to FileChooser.
-- Patches init, changeToPath, refreshPath, genItemTable, and onMenuSelect.
-- @param FileChooser table: FileChooser module to patch.
function FileChooserExt:apply(FileChooser)
    if not self.virtual_library:isActive() then
        logger.info("KoboPlugin: Kobo plugin not active, skipping FileChooser patches")
        return
    end

    logger.info("KoboPlugin: Applying FileChooser monkey patches for Kobo virtual library")

    self.original_methods.init = FileChooser.init
    FileChooser.init = function(fc_self)
        self.original_methods.init(fc_self)

        local kepub_dir = self.virtual_library.parser:getKepubPath()
        if not isKepubDirectoryPath(fc_self.path, kepub_dir) then
            return
        end

        logger.info("KoboPlugin: FileChooser initialized with kepub path, showing virtual library instead")
        fc_self:showKoboVirtualLibrary()
    end

    self.original_methods.changeToPath = FileChooser.changeToPath
    FileChooser.changeToPath = function(fc_self, new_path, ...)
        local kepub_dir = self.virtual_library.parser:getKepubPath()
        if not isKepubDirectoryPath(new_path, kepub_dir) then
            return self.original_methods.changeToPath(fc_self, new_path, ...)
        end

        logger.info("KoboPlugin: Intercepting navigation to real kepub directory:", new_path, "-> virtual library")
        fc_self:showKoboVirtualLibrary()
    end

    self.original_methods.refreshPath = FileChooser.refreshPath
    FileChooser.refreshPath = function(fc_self)
        if not fc_self.path or not fc_self.path:lower():match("^kobo_virtual://") then
            return self.original_methods.refreshPath(fc_self)
        end

        logger.info("KoboPlugin: Refreshing virtual library via refreshPath")
        fc_self:showKoboVirtualLibrary()
    end

    self.original_methods.genItemTable = FileChooser.genItemTable
    FileChooser.genItemTable = function(fc_self, dirs, files, path)
        local item_table = self.original_methods.genItemTable(fc_self, dirs, files, path)

        if not shouldAddVirtualFolder(path) then
            return item_table
        end

        local insert_pos = findVirtualFolderInsertPosition(item_table)
        local virtual_folder = self.virtual_library:createVirtualFolderEntry(path)
        table.insert(item_table, insert_pos, virtual_folder)

        return item_table
    end

    self.original_methods.onMenuSelect = FileChooser.onMenuSelect
    FileChooser.onMenuSelect = function(fc_self, item)
        if item.is_kobo_virtual_folder then
            fc_self:showKoboVirtualLibrary()
            return true
        end

        if fc_self.path and fc_self.path:lower():match("^kobo_virtual://") and item.is_go_up then
            logger.dbg("KoboPlugin: Going back from virtual library to:", item.path)
            fc_self:changeToPath(item.path)
            return true
        end

        return self.original_methods.onMenuSelect(fc_self, item)
    end

    FileChooser.showKoboVirtualLibrary = function(fc_self)
        fc_self.path = "KOBO_VIRTUAL://"
        logger.info("KoboPlugin: Switching FileChooser to virtual library path")

        self.virtual_library:buildPathMappings()
        performAutomaticSync(self.reading_state_sync)

        local book_entries = self.virtual_library:getBookEntries()
        if #book_entries == 0 then
            showNoBookMessage()
            return
        end

        table.insert(book_entries, 1, createBackEntry())
        fc_self:switchItemTable(nil, book_entries, 1, nil, "Kobo Library")
    end
end

---
-- Removes all monkey patches and restores original methods.
-- @param FileChooser table: FileChooser module to restore.
function FileChooserExt:unapply(FileChooser)
    logger.info("KoboPlugin: Removing FileChooser monkey patches")

    for method_name, original_method in pairs(self.original_methods) do
        FileChooser[method_name] = original_method
    end

    FileChooser.showKoboVirtualLibrary = nil
    self.original_methods = {}
end

return FileChooserExt
