-- Kobo Kepub Metadata Parser
-- Parses /mnt/onboard/.kobo/KoboReader.sqlite database

local SQ3 = require("lua-ljsqlite3/init")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local MetadataParser = {}

---
-- Creates a new MetadataParser instance.
-- Initializes with empty metadata cache and no database path.
-- @return table: A new MetadataParser instance.
function MetadataParser:new()
    local o = {
        metadata = nil,
        db_path = nil,
        last_mtime = nil,
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

---
-- Gets the base Kobo library path.
-- Checks KOBO_LIBRARY_PATH environment variable first for development/testing,
-- otherwise returns the default Kobo device path /mnt/onboard/.kobo.
-- Environment variable value has /kepub suffix stripped if present.
-- @return string: The Kobo library base path.
function MetadataParser:getKoboPath()
    local env_path = os.getenv("KOBO_LIBRARY_PATH")
    if env_path and env_path ~= "" then
        local base_path = env_path:gsub("/kepub$", "")
        logger.info("KoboPlugin: Using KOBO_PATH from environment:", base_path)
        return base_path
    end

    return "/mnt/onboard/.kobo"
end

---
-- Gets the path to the KoboReader.sqlite database file.
-- Result is cached in self.db_path after first call.
-- @return string: Full path to KoboReader.sqlite.
function MetadataParser:getDatabasePath()
    if not self.db_path then
        local kobo_path = self:getKoboPath()
        self.db_path = kobo_path .. "/KoboReader.sqlite"
        logger.dbg("KoboPlugin: Constructed database path:", self.db_path)
    end
    return self.db_path
end

---
-- Gets the kepub directory path where book files are stored.
-- @return string: Full path to the kepub directory.
function MetadataParser:getKepubPath()
    local kepub_path = self:getKoboPath() .. "/kepub"
    logger.dbg("KoboPlugin: Kepub directory path:", kepub_path)
    return kepub_path
end

---
-- Checks whether cached metadata needs to be reloaded from database.
-- Reload is needed when: metadata is nil, last_mtime is nil,
-- database file disappeared but we had cached data, or database
-- modification time is newer than our cached version.
-- @return boolean: True if metadata should be reloaded.
function MetadataParser:needsReload()
    local db_path = self:getDatabasePath()
    local attr = lfs.attributes(db_path)

    if not attr then
        return self.metadata ~= nil
    end

    if not self.metadata then
        return true
    end

    if not self.last_mtime then
        return true
    end

    return attr.modification > self.last_mtime
end

---
-- Gets the SQL query for fetching book metadata from KoboReader.sqlite.
-- Query selects books (ContentType = 6) with kepub-style IDs.
-- Excludes file:// prefixed paths and UUID-style IDs (containing dashes).
-- Kepub IDs are alphanumeric strings like 0N3773Z6SFV9Z.
-- @return string: SQL query string.
local function getBookMetadataQuery()
    return [[
        SELECT ContentID, Title, Attribution, Publisher, Series, SeriesNumber, ___PercentRead
        FROM content
        WHERE ContentType = 6
        AND ContentID NOT LIKE 'file://%'
        AND ContentID NOT LIKE '%-%'
    ]]
end

---
-- Creates a metadata entry from a database row.
-- Handles empty/nil values with appropriate defaults.
-- Title and author default to "Unknown" if empty.
-- Percent read defaults to 0 if nil.
-- @param row table: Database row with columns [ContentID, Title, Attribution, Publisher, Series, SeriesNumber, ___PercentRead].
-- @return table: Metadata entry with normalized fields.
local function createMetadataEntry(row)
    local content_id = row[1]
    local title = row[2]
    local author = row[3]
    local publisher = row[4]
    local series = row[5]
    local series_number = row[6]
    local percent_read = tonumber(row[7]) or 0

    return {
        book_id = content_id,
        title = title ~= "" and title or "Unknown",
        author = author ~= "" and author or "Unknown",
        publisher = publisher,
        series = series,
        series_number = series_number,
        percent_read = percent_read,
    }
end

---
-- Opens the database and prepares the metadata query statement.
-- @param db_path string: Path to the KoboReader.sqlite database.
-- @return table|nil: Database connection object.
-- @return table|nil: Prepared statement object.
local function openDatabaseAndPrepareQuery(db_path)
    local conn = SQ3.open(db_path)
    if not conn then
        logger.err("KoboPlugin: Failed to open Kobo database:", db_path)
        return nil, nil
    end

    local stmt = conn:prepare(getBookMetadataQuery())
    if not stmt then
        logger.err("KoboPlugin: Failed to prepare query")
        conn:close()
        return nil, nil
    end

    return conn, stmt
end

---
-- Parses book metadata rows from the database statement.
-- Creates metadata entries for each row and counts the total.
-- @param stmt table: Prepared database statement.
-- @return table: Metadata table keyed by book ContentID.
-- @return number: Count of books parsed.
local function parseBookRows(stmt)
    local metadata = {}
    local book_count = 0

    for row in stmt:rows() do
        local content_id = row[1]
        metadata[content_id] = createMetadataEntry(row)
        book_count = book_count + 1
    end

    return metadata, book_count
end

---
-- Parses the KoboReader.sqlite database to extract book metadata.
-- Returns empty table if database is missing or cannot be opened.
-- Updates self.metadata and self.last_mtime on success.
-- @return table: Metadata table keyed by book ContentID, or empty table on failure.
function MetadataParser:parseMetadata()
    local db_path = self:getDatabasePath()

    logger.dbg("KoboPlugin: Using database path:", db_path)

    local attr = lfs.attributes(db_path)
    if not attr then
        logger.warn("KoboPlugin: Kobo database not found at:", db_path)
        self.metadata = {}
        return self.metadata
    end

    logger.dbg("KoboPlugin: Database found, size:", attr.size, "bytes")

    local conn, stmt = openDatabaseAndPrepareQuery(db_path)
    if not conn then
        self.metadata = {}
        return self.metadata
    end

    logger.dbg("KoboPlugin: Executing query...")

    local metadata, book_count = parseBookRows(stmt)

    stmt:close()
    conn:close()

    self.metadata = metadata
    self.last_mtime = attr.modification

    logger.info("KoboPlugin: Loaded metadata for", book_count, "kepub books from SQLite database")
    return self.metadata
end

---
-- Gets the metadata cache, reloading from database if stale.
-- Automatically calls parseMetadata if needsReload returns true.
-- @return table: Metadata table keyed by book ContentID, never nil.
function MetadataParser:getMetadata()
    if self:needsReload() then
        self:parseMetadata()
    end
    return self.metadata or {}
end

---
-- Gets metadata for a specific book by its ContentID.
-- @param book_id string: The book's ContentID.
-- @return table|nil: Metadata table for the book, or nil if not found.
function MetadataParser:getBookMetadata(book_id)
    local metadata = self:getMetadata()
    return metadata[book_id]
end

---
-- Gets a list of all book ContentIDs in the metadata cache.
-- @return table: Array of ContentID strings.
function MetadataParser:getBookIds()
    local metadata = self:getMetadata()
    local ids = {}
    for id, _ in pairs(metadata) do
        table.insert(ids, id)
    end
    return ids
end

---
-- Gets the total count of books in the metadata cache.
-- @return number: Number of books.
function MetadataParser:getBookCount()
    local count = 0
    for _ in pairs(self:getMetadata()) do
        count = count + 1
    end
    return count
end

---
-- Gets the full filesystem path for a kepub book file.
-- Kepub files are stored as /path/to/kepub/{ContentID} without extension.
-- The ContentID from the database IS the filename.
-- Verifies the file exists and is a regular file before returning the path.
-- @param book_id string: The book's ContentID.
-- @return string|nil: Full path to the book file, or nil if not found or not a file.
function MetadataParser:getBookFilePath(book_id)
    local kepub_path = self:getKepubPath()
    local filepath = kepub_path .. "/" .. book_id

    logger.dbg("KoboPlugin: Checking book file path:", filepath)

    local attr = lfs.attributes(filepath, "mode")
    if attr == "file" then
        logger.dbg("KoboPlugin: Book file found:", book_id)
        return filepath
    end

    logger.dbg("KoboPlugin: Book file NOT found:", book_id, "at", filepath)
    return nil
end

---
-- Gets the path to a book's thumbnail preview image.
-- Does not verify that the thumbnail actually exists.
-- @param book_id string: The book's ContentID.
-- @return string: Path to the thumbnail PNG file.
function MetadataParser:getThumbnailPath(book_id)
    local kepub_path = self:getKepubPath()
    return kepub_path .. "/.thumbnail-previews/" .. book_id .. ".png"
end

---
-- Checks if a book file exists and is accessible as a regular file.
-- @param book_id string: The book's ContentID.
-- @return boolean: True if the book file exists and is accessible.
function MetadataParser:isBookAccessible(book_id)
    local filepath = self:getBookFilePath(book_id)
    if not filepath then
        logger.dbg("KoboPlugin: Book NOT accessible (file not found):", book_id)
        return false
    end

    local attr = lfs.attributes(filepath, "mode")
    local accessible = attr == "file"
    logger.dbg("KoboPlugin: Book accessibility check:", book_id, "->", accessible and "ACCESSIBLE" or "NOT ACCESSIBLE")
    return accessible
end

---
-- Reads the first 4 bytes of a file to check for ZIP/EPUB signature.
-- EPUB files are ZIP archives starting with PK\x03\x04.
-- @param filepath string: Full path to the file.
-- @return boolean: True if file has valid ZIP signature (PK\x03\x04).
local function hasValidZipSignature(filepath)
    local file = io.open(filepath, "rb")
    if not file then
        return false
    end

    local header = file:read(4)
    file:close()

    if not header or #header < 4 then
        return false
    end

    local pk_signature = header:byte(1) == 0x50 and header:byte(2) == 0x4B
    local zip_signature = header:byte(3) == 0x03 and header:byte(4) == 0x04

    return pk_signature and zip_signature
end

---
-- Checks if a book file is likely encrypted or corrupted.
-- Uses basic heuristic: checks for valid ZIP/EPUB signature (PK\x03\x04).
-- Missing files or files without proper ZIP signature are considered encrypted.
-- @param book_id string: The book's ContentID.
-- @return boolean: True if the book appears to be encrypted or inaccessible.
function MetadataParser:isBookEncrypted(book_id)
    local filepath = self:getBookFilePath(book_id)
    if not filepath then
        return true
    end

    return not hasValidZipSignature(filepath)
end

---
-- Creates an accessible book entry with all relevant paths.
-- @param book_id string: The book's ContentID.
-- @param book_meta table: Metadata table for the book.
-- @return table: Accessible book entry with id, metadata, filepath, and thumbnail.
local function createAccessibleBookEntry(book_id, book_meta, filepath, thumbnail_path)
    return {
        id = book_id,
        metadata = book_meta,
        filepath = filepath,
        thumbnail = thumbnail_path,
    }
end

---
-- Filters the metadata cache to return only accessible, unencrypted books.
-- Checks each book's accessibility and encryption status.
-- Logs statistics about accessible, encrypted, and missing books.
-- @return table: Array of accessible book entries, each containing id, metadata, filepath, and thumbnail.
function MetadataParser:getAccessibleBooks()
    local accessible = {}
    local metadata = self:getMetadata()

    logger.dbg("KoboPlugin: Checking accessibility for", self:getBookCount(), "books")

    local accessible_count = 0
    local encrypted_count = 0
    local missing_count = 0

    for book_id, book_meta in pairs(metadata) do
        local accessible = self:isBookAccessible(book_id)
        if not accessible then
            missing_count = missing_count + 1
        end

        if accessible and self:isBookEncrypted(book_id) then
            encrypted_count = encrypted_count + 1
            logger.dbg("KoboPlugin: Book is encrypted:", book_id, book_meta.title)
        end

        if accessible and not self:isBookEncrypted(book_id) then
            local filepath = self:getBookFilePath(book_id)
            local thumbnail = self:getThumbnailPath(book_id)
            local entry = createAccessibleBookEntry(book_id, book_meta, filepath, thumbnail)
            table.insert(accessible, entry)
            accessible_count = accessible_count + 1
        end
    end

    logger.info(
        "KoboPlugin: Accessible books:",
        accessible_count,
        "Encrypted:",
        encrypted_count,
        "Missing:",
        missing_count
    )

    return accessible
end

---
-- Clears the metadata cache, forcing a reload on next access.
-- Resets both the metadata table and the last modification time.
function MetadataParser:clearCache()
    self.metadata = nil
    self.last_mtime = nil
end

return MetadataParser
