-- Kobo Kepub Virtual Library
-- Manages virtual filesystem for kepub books

local BD = require("ui/bidi")
local Device = require("device")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local VirtualLibrary = {}

VirtualLibrary.VIRTUAL_LIBRARY_NAME = "Kobo Library"
VirtualLibrary.VIRTUAL_PATH_PREFIX = "KOBO_VIRTUAL://"

---
-- Creates a new VirtualLibrary instance.
-- Initializes path mapping tables for virtual-to-real path conversion.
-- @param metadata_parser table: MetadataParser instance for accessing book metadata.
-- @return table: A new VirtualLibrary instance.
function VirtualLibrary:new(metadata_parser)
    local o = {
        parser = metadata_parser,
        virtual_to_real = {},
        real_to_virtual = {},
        book_id_to_virtual = {},
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

---
-- Checks if the virtual library should be active.
-- Active when KOBO_LIBRARY_PATH environment variable is set (dev mode)
-- or when running on a Kobo device.
-- @return boolean: True if virtual library should be active.
function VirtualLibrary:isActive()
    local env_path = os.getenv("KOBO_LIBRARY_PATH")
    if env_path and env_path ~= "" then
        return true
    end

    return Device:isKobo()
end

---
-- Sanitizes a string for use in a filename.
-- Replaces filesystem-unsafe characters with underscores.
-- @param text string: Text to sanitize.
-- @return string: Sanitized text safe for filenames.
local function sanitizeForFilename(text)
    return text:gsub('[/\\:*?"<>|]', "_")
end

---
-- Generates a virtual file path for a book.
-- Creates a path in the format: KOBO_VIRTUAL://BOOK_ID/Author - Title.epub
-- Sanitizes author and title to be filesystem-safe.
-- @param book_id string: The book's ContentID.
-- @param metadata table: Book metadata containing title and author.
-- @return string: Virtual path for the book.
function VirtualLibrary:generateVirtualPath(book_id, metadata)
    local title = metadata.title or "Unknown"
    local author = metadata.author or "Unknown"

    local safe_title = sanitizeForFilename(title)
    local safe_author = sanitizeForFilename(author)

    local filename = string.format("%s - %s.epub", safe_author, safe_title)
    local virtual_path = self.VIRTUAL_PATH_PREFIX .. book_id .. "/" .. filename

    return virtual_path
end

---
-- Builds bidirectional mappings between virtual and real file paths.
-- Clears existing mappings and rebuilds from accessible books.
-- Creates three mapping tables: virtual_to_real, real_to_virtual, book_id_to_virtual.
function VirtualLibrary:buildPathMappings()
    self.virtual_to_real = {}
    self.real_to_virtual = {}
    self.book_id_to_virtual = {}

    local accessible_books = self.parser:getAccessibleBooks()

    for _, book in ipairs(accessible_books) do
        local virtual_path = self:generateVirtualPath(book.id, book.metadata)

        self.virtual_to_real[virtual_path] = book.filepath
        self.real_to_virtual[book.filepath] = virtual_path
        self.book_id_to_virtual[book.id] = virtual_path
    end

    logger.dbg("KoboPlugin: Built path mappings for", #accessible_books, "books")
end

---
-- Refreshes the path mappings by clearing caches and rebuilding.
-- Should be called when metadata may have changed.
function VirtualLibrary:refresh()
    self.parser:clearCache()
    self:buildPathMappings()
end

---
-- Checks if a path is a virtual library path.
-- @param path string: Path to check.
-- @return boolean: True if path starts with VIRTUAL_PATH_PREFIX.
function VirtualLibrary:isVirtualPath(path)
    if not path then
        return false
    end

    return path:sub(1, #self.VIRTUAL_PATH_PREFIX) == self.VIRTUAL_PATH_PREFIX
end

---
-- Converts a virtual path to its real filesystem path.
-- Returns the path unchanged if it's not a virtual path.
-- @param virtual_path string: Virtual path to convert.
-- @return string|nil: Real filesystem path, or original path if not virtual, or nil if mapping not found.
function VirtualLibrary:getRealPath(virtual_path)
    if not self:isVirtualPath(virtual_path) then
        return virtual_path
    end

    return self.virtual_to_real[virtual_path]
end

---
-- Gets the virtual path corresponding to a real filesystem path.
-- @param real_path string: Real filesystem path.
-- @return string|nil: Virtual path, or nil if not mapped.
function VirtualLibrary:getVirtualPath(real_path)
    return self.real_to_virtual[real_path]
end

---
-- Extracts the book ContentID from a virtual path.
-- Virtual paths have the format: KOBO_VIRTUAL://BOOK_ID/filename.epub
-- @param virtual_path string: Virtual path to parse.
-- @return string|nil: Book ContentID, or nil if not a virtual path.
function VirtualLibrary:getBookId(virtual_path)
    if not self:isVirtualPath(virtual_path) then
        return nil
    end

    local book_id = virtual_path:match(self.VIRTUAL_PATH_PREFIX .. "([^/]+)/")
    return book_id
end

---
-- Gets metadata for a book by its virtual path.
-- @param virtual_path string: Virtual path of the book.
-- @return table|nil: Book metadata, or nil if book not found.
function VirtualLibrary:getMetadata(virtual_path)
    local book_id = self:getBookId(virtual_path)
    if not book_id then
        return nil
    end

    return self.parser:getBookMetadata(book_id)
end

---
-- Creates a file chooser entry for a single book.
-- Includes display text, file attributes, and Kobo-specific metadata.
-- @param book table: Accessible book entry with id, metadata, and filepath.
-- @param virtual_path string: Virtual path for this book.
-- @return table: File chooser entry with all required fields.
local function createBookEntry(book, virtual_path)
    local metadata = book.metadata
    local filename = virtual_path:match("/([^/]+)$")

    local file_attr = lfs.attributes(book.filepath)
    local file_size = file_attr and file_attr.size or (metadata.file and metadata.file.size) or 0

    return {
        text = filename,
        path = virtual_path,
        is_file = true,
        bidi_wrap_func = BD.filename,
        attr = {
            mode = "file",
            size = file_size,
            modification = file_attr and file_attr.modification or 0,
        },
        mandatory = util.getFriendlySize(file_size),
        kobo_book_id = book.id,
        kobo_real_path = book.filepath,
        kobo_metadata = metadata,
    }
end

---
-- Sorts book entries alphabetically by display text.
-- @param entries table: Array of book entries to sort in-place.
local function sortBookEntries(entries)
    table.sort(entries, function(a, b)
        return a.text < b.text
    end)
end

---
-- Gets all virtual book entries for the file chooser.
-- Creates formatted entries for each accessible book with file attributes
-- and Kobo-specific metadata. Entries are sorted alphabetically by title.
-- @return table: Array of file chooser entry tables.
function VirtualLibrary:getBookEntries()
    local entries = {}
    local accessible_books = self.parser:getAccessibleBooks()

    for _, book in ipairs(accessible_books) do
        local virtual_path = self:generateVirtualPath(book.id, book.metadata)
        local entry = createBookEntry(book, virtual_path)
        table.insert(entries, entry)
    end

    sortBookEntries(entries)

    return entries
end

---
-- Creates a virtual folder entry for the file chooser.
-- Represents the Kobo Library as a browsable folder.
-- @param parent_path string: Path to the parent directory.
-- @return table: Folder entry for the virtual library.
function VirtualLibrary:createVirtualFolderEntry(parent_path)
    return {
        text = self.VIRTUAL_LIBRARY_NAME .. "/",
        path = parent_path .. "/" .. self.VIRTUAL_LIBRARY_NAME,
        is_kobo_virtual_folder = true,
        bidi_wrap_func = BD.directory,
    }
end

---
-- Gets the thumbnail path for a book by its virtual path.
-- @param virtual_path string: Virtual path of the book.
-- @return string|nil: Path to the thumbnail PNG file, or nil if book not found.
function VirtualLibrary:getThumbnailPath(virtual_path)
    local book_id = self:getBookId(virtual_path)
    if not book_id then
        return nil
    end

    return self.parser:getThumbnailPath(book_id)
end

return VirtualLibrary
