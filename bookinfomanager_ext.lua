---
-- BookInfoManager extensions for Kobo kepub files.
-- Integrates with CoverBrowser plugin to display book metadata and covers.

local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")

local BookInfoManagerExt = {}

---
-- Builds a bookinfo table compatible with CoverBrowser.
-- @param filepath string: Virtual file path.
-- @param metadata table: Book metadata from Kobo database.
-- @param real_path string: Real file path on filesystem.
-- @return table: Bookinfo structure.
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
        cover_fetched = nil,
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
-- Loads and attaches cover image to bookinfo.
-- @param bookinfo table: Bookinfo structure to modify.
-- @param thumbnail_path string: Path to Kobo thumbnail file.
local function attachCoverImage(bookinfo, thumbnail_path)
    if not thumbnail_path or lfs.attributes(thumbnail_path, "mode") ~= "file" then
        return
    end

    local RenderImage = require("ui/renderimage")
    local cover_bb = RenderImage:renderImageFile(thumbnail_path, false)
    if not cover_bb then
        return
    end

    bookinfo.has_cover = "Y"
    bookinfo.cover_bb = cover_bb
    bookinfo.cover_w = cover_bb:getWidth()
    bookinfo.cover_h = cover_bb:getHeight()
    bookinfo.cover_sizetag = string.format("%dx%d", bookinfo.cover_w, bookinfo.cover_h)
    bookinfo.cover_fetched = "Y"
end

---
-- Initializes the BookInfoManagerExt module.
-- @param virtual_library table: Virtual library instance.
function BookInfoManagerExt:init(virtual_library)
    self.virtual_library = virtual_library
    self.original_methods = {}
end

---
-- Applies monkey patches to BookInfoManager.
-- Patches getBookInfo and extractBookInfo for virtual kepub files.
-- @param BookInfoManager table: BookInfoManager module to patch.
function BookInfoManagerExt:apply(BookInfoManager)
    if not self.virtual_library:isActive() then
        logger.info("KoboPlugin: Kobo plugin not active, skipping BookInfoManager patches")
        return
    end

    logger.info("KoboPlugin: Applying BookInfoManager monkey patches for Kobo kepub integration")

    self.original_methods.getBookInfo = BookInfoManager.getBookInfo
    BookInfoManager.getBookInfo = function(bim_self, filepath, get_cover)
        if not self.virtual_library:isVirtualPath(filepath) then
            return self.original_methods.getBookInfo(bim_self, filepath, get_cover)
        end

        return self:getVirtualBookInfo(filepath, get_cover)
    end

    self.original_methods.extractBookInfo = BookInfoManager.extractBookInfo
    BookInfoManager.extractBookInfo = function(bim_self, filepath, cover_specs)
        if not self.virtual_library:isVirtualPath(filepath) then
            return self.original_methods.extractBookInfo(bim_self, filepath, cover_specs)
        end

        local real_path = self.virtual_library:getRealPath(filepath)
        if not real_path then
            return false
        end

        return self.original_methods.extractBookInfo(bim_self, real_path, cover_specs)
    end
end

---
-- Gets book info for virtual kepub file from Kobo metadata.
-- @param filepath string: Virtual file path.
-- @param get_cover boolean: Whether to load cover image.
-- @return table|nil: Bookinfo structure, or nil on error.
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
        local thumbnail_path = self.virtual_library:getThumbnailPath(filepath)
        attachCoverImage(bookinfo, thumbnail_path)
    end

    return bookinfo
end

---
-- Removes all monkey patches and restores original methods.
-- @param BookInfoManager table: BookInfoManager module to restore.
function BookInfoManagerExt:unapply(BookInfoManager)
    logger.info("KoboPlugin: Removing BookInfoManager monkey patches")

    for method_name, original_method in pairs(self.original_methods) do
        BookInfoManager[method_name] = original_method
    end

    self.original_methods = {}
end

return BookInfoManagerExt
