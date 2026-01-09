---
--- Database writer for BookInfoManager cache.
--- Writes book metadata and covers to BookInfoManager's SQLite cache,
--- following the exact same schema and compression as the original implementation.
---
local SQ3 = require("lua-ljsqlite3/init")
local logger = require("logger")
local util = require("util")
local zstd = require("ffi/zstd")

local BookInfoDatabase = {}

---
--- Column set matching BookInfoManager's BOOKINFO_COLS_SET.
--- Must be in exact same order as the original implementation.
local BOOKINFO_COLS_SET = {
    "directory",
    "filename",
    "filesize",
    "filemtime",
    "in_progress",
    "unsupported",
    "cover_fetched",
    "has_meta",
    "has_cover",
    "cover_sizetag",
    "ignore_meta",
    "ignore_cover",
    "pages",
    "title",
    "authors",
    "series",
    "series_index",
    "language",
    "keywords",
    "description",
    "cover_w",
    "cover_h",
    "cover_bb_type",
    "cover_bb_stride",
    "cover_bb_data",
}

---
--- Builds the INSERT OR REPLACE SQL statement.
--- @return string: SQL statement for inserting/updating bookinfo.
local function buildInsertSql()
    local placeholders = {}
    for _ = 1, #BOOKINFO_COLS_SET do
        table.insert(placeholders, "?")
    end

    return "INSERT OR REPLACE INTO bookinfo "
        .. "("
        .. table.concat(BOOKINFO_COLS_SET, ",")
        .. ") "
        .. "VALUES ("
        .. table.concat(placeholders, ",")
        .. ");"
end

---
--- Creates a database row table from bookinfo, compressing cover if present.
--- Follows exact same logic as BookInfoManager:extractBookInfo.
--- @param filepath string: Virtual file path.
--- @param bookinfo table: Bookinfo table with metadata and cover.
--- @return table: Database row ready for INSERT.
local function buildDatabaseRow(filepath, bookinfo)
    local directory, filename = util.splitFilePathName(filepath)

    local dbrow = {
        directory = directory,
        filename = filename,
        filesize = bookinfo.filesize,
        filemtime = bookinfo.filemtime,
        in_progress = bookinfo.in_progress or 0,
        unsupported = bookinfo.unsupported,
        cover_fetched = bookinfo.cover_fetched,
        has_meta = bookinfo.has_meta,
        has_cover = bookinfo.has_cover,
        cover_sizetag = bookinfo.cover_sizetag,
        ignore_meta = bookinfo.ignore_meta,
        ignore_cover = bookinfo.ignore_cover,
        pages = bookinfo.pages,
        title = bookinfo.title,
        authors = bookinfo.authors,
        series = bookinfo.series,
        series_index = bookinfo.series_index,
        language = bookinfo.language,
        keywords = bookinfo.keywords,
        description = bookinfo.description,
    }

    -- Compress cover data if present, following exact same logic as original
    if bookinfo.cover_bb then
        local cover_bb = bookinfo.cover_bb

        dbrow.cover_w = cover_bb.w
        dbrow.cover_h = cover_bb.h
        dbrow.cover_bb_type = cover_bb:getType()
        dbrow.cover_bb_stride = tonumber(cover_bb.stride)

        local cover_size = cover_bb.stride * cover_bb.h
        local cover_zst_ptr, cover_zst_size = zstd.zstd_compress(cover_bb.data, cover_size)
        dbrow.cover_bb_data = SQ3.blob(cover_zst_ptr, cover_zst_size)

        logger.dbg(
            "KoboPlugin: cover for",
            filename,
            "size",
            cover_bb.w,
            "x",
            cover_bb.h,
            ", compressed from",
            tonumber(cover_size),
            "to",
            tonumber(cover_zst_size)
        )
    else
        dbrow.cover_w = nil
        dbrow.cover_h = nil
        dbrow.cover_bb_type = nil
        dbrow.cover_bb_stride = nil
        dbrow.cover_bb_data = nil
    end

    return dbrow
end

---
--- Writes bookinfo to BookInfoManager's database.
--- Opens connection, prepares statement, binds values, and commits.
--- Follows exact same pattern as BookInfoManager:extractBookInfo lines 564-568.
--- @param db_location string: Path to bookinfo_cache.sqlite3.
--- @param filepath string: Virtual file path.
--- @param bookinfo table: Bookinfo table with metadata and cover.
--- @return boolean: True on success, false on failure.
function BookInfoDatabase:writeBookInfo(db_location, filepath, bookinfo)
    logger.dbg("KoboPlugin: Writing bookinfo to database:", filepath)

    local db_conn = SQ3.open(db_location)
    if not db_conn then
        logger.err("KoboPlugin: Failed to open BookInfoManager database:", db_location)
        return false
    end

    db_conn:set_busy_timeout(5000)

    local insert_sql = buildInsertSql()
    local stmt = db_conn:prepare(insert_sql)
    if not stmt then
        logger.err("KoboPlugin: Failed to prepare INSERT statement")
        db_conn:close()
        return false
    end

    local dbrow = buildDatabaseRow(filepath, bookinfo)

    -- Bind all columns in order, following exact same pattern as original (line 564-566)
    for num, col in ipairs(BOOKINFO_COLS_SET) do
        stmt:bind1(num, dbrow[col])
    end

    local ok = pcall(function()
        stmt:step()
    end)

    stmt:clearbind():reset()
    db_conn:close()

    if not ok then
        logger.err("KoboPlugin: Failed to execute INSERT statement for:", filepath)
        return false
    end

    logger.dbg("KoboPlugin: Successfully wrote bookinfo to database:", filepath)
    return true
end

return BookInfoDatabase
