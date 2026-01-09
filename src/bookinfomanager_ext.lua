---
--- BookInfoManager extensions for Kobo kepub files.
--- Integrates with CoverBrowser plugin to display book metadata and covers.

local BookInfoDatabase = require("src/lib/bookinfo_database")
local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local RenderImage = require("ui/renderimage")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local BookInfoManagerExt = {}

---
--- Builds a bookinfo table compatible with CoverBrowser.
--- @param filepath string: Virtual file path.
--- @param metadata table: Book metadata from Kobo database.
--- @param real_path string: Real file path on filesystem.
--- @return table: Bookinfo structure.
local function buildBookInfo(filepath, metadata, real_path)
    local directory, filename = util.splitFilePathName(filepath)
    local file_attr = lfs.attributes(real_path)

    return {
        directory = directory,
        filename = filename,
        filesize = file_attr and file_attr.size or (metadata.file and metadata.file.size),
        filemtime = file_attr and file_attr.modification or 0,
        in_progress = 0,
        unsupported = nil,
        cover_fetched = "Y",
        has_meta = "Y",
        has_cover = nil,
        cover_sizetag = nil,
        ignore_meta = nil,
        ignore_cover = nil,
        title = metadata.title,
        authors = metadata.author,
        series = metadata.series,
        series_index = metadata.number and tonumber(metadata.number),
        language = metadata.language,
        keywords = metadata.categories and table.concat(metadata.categories, ", "),
        description = nil,
        pages = nil,
    }
end

---
--- Initializes the BookInfoManagerExt module.
--- @param virtual_library table: Virtual library instance.
function BookInfoManagerExt:init(virtual_library)
    self.virtual_library = virtual_library
    self.original_methods = {}
    self.db_location = DataStorage:getSettingsDir() .. "/bookinfo_cache.sqlite3"
end

---
--- Applies monkey patches to BookInfoManager.
--- Patches getBookInfo and extractBookInfo for virtual kepub files.
--- @param BookInfoManager table: BookInfoManager module to patch.
function BookInfoManagerExt:apply(BookInfoManager)
    if not self.virtual_library:isActive() then
        logger.info("KoboPlugin: Kobo plugin not active, skipping BookInfoManager patches")
        return
    end

    logger.info("KoboPlugin: Applying BookInfoManager monkey patches for Kobo kepub integration")

    self.original_methods.getBookInfo = BookInfoManager.getBookInfo
    BookInfoManager.getBookInfo = function(bim_self, filepath, get_cover)
        logger.dbg("KoboPlugin: getting book info for", filepath)

        if not self.virtual_library:isVirtualPath(filepath) then
            return self.original_methods.getBookInfo(bim_self, filepath, get_cover)
        end

        local cached = self.original_methods.getBookInfo(bim_self, filepath, get_cover)
        if cached then
            logger.dbg("KoboPlugin: Cache hit for virtual book:", filepath)
        end

        return cached
    end

    self.original_methods.extractBookInfo = BookInfoManager.extractBookInfo
    BookInfoManager.extractBookInfo = function(bim_self, filepath, cover_specs)
        logger.dbg("KoboPlugin: extracting book info for", filepath)

        if not self.virtual_library:isVirtualPath(filepath) then
            return self.original_methods.extractBookInfo(bim_self, filepath, cover_specs)
        end

        local bookinfo = self:getVirtualBookInfo(filepath, cover_specs ~= nil)

        if not bookinfo then
            logger.warn("KoboPlugin: Failed to get metadata for virtual book:", filepath)

            return nil
        end

        bookinfo.in_progress = 0
        bookinfo.cover_fetched = "Y"

        self:writeBookInfoToDatabase(filepath, bookinfo)

        logger.dbg("KoboPlugin: Successfully extracted metadata for virtual book:", filepath)

        return bookinfo
    end
end

---
--- Gets book info for virtual kepub file from Kobo metadata.
--- Extracts cover to sidecar directory if needed and loads it.
--- @param filepath string: Virtual file path.
--- @param get_cover boolean: Whether to load cover image.
--- @return table|nil: Bookinfo structure, or nil on error.
function BookInfoManagerExt:getVirtualBookInfo(filepath, get_cover)
    local metadata = self.virtual_library:getMetadata(filepath)
    if not metadata then
        return nil
    end

    local real_path = self.virtual_library:getRealPath(filepath)
    if not real_path then
        return nil
    end

    local bookinfo = buildBookInfo(filepath, metadata, real_path)

    if get_cover then
        local book_id = metadata.book_id
        local is_encrypted = self.virtual_library.parser:isBookEncrypted(book_id)

        self.virtual_library.parser:extractCoverToSidecar(book_id, real_path, is_encrypted)

        local sidecar_dir = DocSettings:getSidecarDir(real_path)
        local cover_path = sidecar_dir .. "/cover.jpg"

        local attr = lfs.attributes(cover_path, "mode")
        if attr == "file" then
            local cover_bb = RenderImage:renderImageFile(cover_path, false)
            if cover_bb then
                bookinfo.has_cover = "Y"
                bookinfo.cover_bb = cover_bb
                bookinfo.cover_w = cover_bb:getWidth()
                bookinfo.cover_h = cover_bb:getHeight()
                bookinfo.cover_sizetag = string.format("%dx%d", bookinfo.cover_w, bookinfo.cover_h)
                bookinfo.cover_fetched = "Y"
            else
                logger.dbg("KoboPlugin: Could not render cover image:", cover_path)
            end
        else
            logger.dbg("KoboPlugin: No cover found in sidecar:", cover_path)
        end
    end

    return bookinfo
end

---
--- Writes bookinfo to BookInfoManager's database cache.
--- Follows the exact same pattern as the original BookInfoManager:extractBookInfo.
--- Compresses cover image using zstd before storing in database.
--- @param filepath string: Virtual file path.
--- @param bookinfo table: Bookinfo table with metadata and cover.
function BookInfoManagerExt:writeBookInfoToDatabase(filepath, bookinfo)
    local success = BookInfoDatabase:writeBookInfo(self.db_location, filepath, bookinfo)

    if not success then
        logger.warn("KoboPlugin: Failed to write bookinfo to database for:", filepath)
    end
end

---
--- Removes all monkey patches and restores original methods.
--- @param BookInfoManager table: BookInfoManager module to restore.
function BookInfoManagerExt:unapply(BookInfoManager)
    logger.info("KoboPlugin: Removing BookInfoManager monkey patches")

    for method_name, original_method in pairs(self.original_methods) do
        BookInfoManager[method_name] = original_method
    end

    self.original_methods = {}
end

return BookInfoManagerExt
