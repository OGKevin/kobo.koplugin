---
-- Patch ReaderUI:showReader to handle virtual library paths.
-- This allows virtual library books to be opened from the file browser.

local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local ShowReaderExt = {
    name = "showreader_ext",
    original_showReader = nil,
}

---
-- Shows an error message to the user.
-- @param message string: Translated error message template.
-- @param path string: File path to display in the message.
local function showErrorMessage(message, path)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local BD = require("ui/bidi")
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local T = require("ffi/util").template
    local _ = require("gettext")

    UIManager:show(InfoMessage:new({
        text = T(_(message), BD.filepath(filemanagerutil.abbreviate(path))),
    }))
end

---
-- Extracts the book ID from a virtual library path.
-- @param file string: Virtual library path.
-- @return string|nil: Book ID if extracted successfully, nil otherwise.
local function extractBookId(file)
    return file:match("^/kobo%-library/([^/]+)/")
end

---
-- Checks if the given file is a virtual library path.
-- @param file string|nil: File path to check.
-- @return boolean: True if the file is a virtual library path.
local function isVirtualLibraryPath(file)
    return file and file:match("^/kobo%-library/") ~= nil
end

---
-- Validates that a real file exists on the filesystem.
-- @param real_file string: Path to the real file.
-- @return boolean: True if the file exists and is a regular file.
local function validateRealFileExists(real_file)
    return lfs.attributes(real_file, "mode") == "file"
end

---
-- Handles opening a book from a virtual library path.
-- Resolves the virtual path to the real file and delegates to original showReader.
-- @param reader_self table: ReaderUI instance.
-- @param file string: Virtual library path.
-- @param provider string|nil: Document provider.
-- @param seamless boolean|nil: Whether to open seamlessly.
-- @param is_provider_forced boolean|nil: Whether provider is forced.
-- @param virtual_library table: Virtual library instance.
-- @param original_showReader function: Original showReader function.
-- @return any: Result from original showReader, or nil on error.
local function handleVirtualLibraryPath(
    reader_self,
    file,
    provider,
    seamless,
    is_provider_forced,
    virtual_library,
    original_showReader
)
    logger.info("KoboPlugin: Detected virtual library path:", file)

    local book_id = extractBookId(file)
    if not book_id then
        logger.err("KoboPlugin: Failed to extract book_id from virtual path:", file)
        showErrorMessage("Invalid virtual library path: %1", file)
        return
    end

    local real_file = virtual_library.parser:getBookFilePath(book_id)
    if not real_file then
        logger.err("KoboPlugin: Virtual library book not found:", book_id)
        showErrorMessage("Virtual library book not found: %1", file)
        return
    end

    if not validateRealFileExists(real_file) then
        logger.err("KoboPlugin: Real file does not exist:", real_file)
        showErrorMessage("Book file does not exist: %1", real_file)
        return
    end

    logger.info("KoboPlugin: Redirecting virtual path to real file:", real_file)
    return original_showReader(reader_self, real_file, provider, seamless, is_provider_forced)
end

---
-- Initializes the ShowReaderExt module with the plugin instance.
-- @param plugin table: Main plugin instance.
function ShowReaderExt:init(plugin)
    self.plugin = plugin
    self.virtual_library = plugin.virtual_library
end

---
-- Applies the ReaderUI:showReader monkey patch.
-- Intercepts showReader calls to resolve virtual library paths to real files.
function ShowReaderExt:apply()
    local ReaderUI = require("apps/reader/readerui")

    if not self.original_showReader then
        self.original_showReader = ReaderUI.showReader
    end

    local virtual_library = self.virtual_library
    local original_showReader = self.original_showReader

    ReaderUI.showReader = function(reader_self, file, provider, seamless, is_provider_forced)
        logger.dbg("KoboPlugin: showReader called with file:", file)

        if not isVirtualLibraryPath(file) then
            return original_showReader(reader_self, file, provider, seamless, is_provider_forced)
        end

        return handleVirtualLibraryPath(
            reader_self,
            file,
            provider,
            seamless,
            is_provider_forced,
            virtual_library,
            original_showReader
        )
    end

    logger.info("KoboPlugin: Patched ReaderUI:showReader to handle virtual library paths")
end

---
-- Restores the original ReaderUI:showReader method on plugin exit.
function ShowReaderExt:onExit()
    if not self.original_showReader then
        return
    end

    local ReaderUI = require("apps/reader/readerui")
    ReaderUI.showReader = self.original_showReader
    logger.info("KoboPlugin: Restored original ReaderUI:showReader")
end

return ShowReaderExt
