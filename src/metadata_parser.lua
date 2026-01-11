-- Kobo Kepub Metadata Parser
-- Parses /mnt/onboard/.kobo/KoboReader.sqlite database

local CacheManager = require("src/lib/drm/cache_manager")
local CoverExtractor = require("src/lib/drm/cover_extractor")
local DocumentRegistry = require("document/documentregistry")
local KoboKDRM = require("src/lib/drm/kobo_kdrm")
local SQ3 = require("lua-ljsqlite3/init")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local MetadataParser = {}

---
--- Creates a new MetadataParser instance.
--- Initializes with empty metadata cache and no database path.
--- @return table: A new MetadataParser instance.
function MetadataParser:new()
    local o = {
        metadata = nil,
        db_path = nil,
        last_mtime = nil,
        accessible_books = nil,
        plugin = nil,
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

---
--- Sets the plugin instance for accessing settings.
--- @param plugin table: The KoboPlugin instance.
function MetadataParser:setPlugin(plugin)
    self.plugin = plugin
end

---
--- Gets the base Kobo library path.
--- Checks KOBO_LIBRARY_PATH environment variable first for development/testing,
--- otherwise returns the default Kobo device path /mnt/onboard/.kobo.
--- Environment variable value has /kepub suffix stripped if present.
--- @return string: The Kobo library base path.
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
--- Gets the path to the KoboReader.sqlite database file.
--- Result is cached in self.db_path after first call.
--- @return string: Full path to KoboReader.sqlite.
function MetadataParser:getDatabasePath()
    if not self.db_path then
        local kobo_path = self:getKoboPath()
        self.db_path = kobo_path .. "/KoboReader.sqlite"
        logger.dbg("KoboPlugin: Constructed database path:", self.db_path)
    end
    return self.db_path
end

---
--- Gets the kepub directory path where book files are stored.
--- @return string: Full path to the kepub directory.
function MetadataParser:getKepubPath()
    local kepub_path = self:getKoboPath() .. "/kepub"
    logger.dbg("KoboPlugin: Kepub directory path:", kepub_path)
    return kepub_path
end

---
--- Checks whether cached metadata needs to be reloaded from database.
--- Reload is needed when: metadata is nil, last_mtime is nil,
--- database file disappeared but we had cached data, or database
--- modification time is newer than our cached version.
--- @return boolean: True if metadata should be reloaded.
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
--- Checks whether cached accessible books need to be reloaded.
--- Reload is needed when: accessible_books is nil, or when metadata needs reload.
--- @return boolean: True if accessible books cache should be reloaded.
function MetadataParser:needsAccessibleBooksReload()
    return self.accessible_books == nil or self:needsReload()
end

---
--- Gets the SQL query for fetching book metadata from KoboReader.sqlite.
--- Query selects all books (ContentType = 6) from the content table.
--- Excludes file:// prefixed paths, they are excluded because these are sideloaded files not stored in kepub directory.
--- @return string: SQL query string.
local function getBookMetadataQuery()
    return [[
        SELECT ContentID, Title, Attribution, Publisher, Series, SeriesNumber, ___PercentRead
        FROM content
        WHERE ContentType = 6
        AND ContentID NOT LIKE 'file://%'
    ]]
end

---
--- Creates a metadata entry from a database row.
--- Handles empty/nil values with appropriate defaults.
--- Title and author default to "Unknown" if empty.
--- Percent read defaults to 0 if nil.
--- @param row table: Database row with columns [ContentID, Title, Attribution, Publisher, Series, SeriesNumber, ___PercentRead].
--- @return table: Metadata entry with normalized fields.
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
--- Opens the database and prepares the metadata query statement.
--- @param db_path string: Path to the KoboReader.sqlite database.
--- @return table|nil: Database connection object.
--- @return table|nil: Prepared statement object.
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
--- Parses book metadata rows from the database statement.
--- Creates metadata entries for each row and counts the total.
--- @param stmt table: Prepared database statement.
--- @return table: Metadata table keyed by book ContentID.
--- @return number: Count of books parsed.
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
--- Parses the KoboReader.sqlite database to extract book metadata.
--- Returns empty table if database is missing or cannot be opened.
--- Updates self.metadata and self.last_mtime on success.
--- @return table: Metadata table keyed by book ContentID, or empty table on failure.
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
    if not conn or not stmt then
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
--- Gets the metadata cache, reloading from database if stale.
--- Automatically calls parseMetadata if needsReload returns true.
--- @return table: Metadata table keyed by book ContentID, never nil.
function MetadataParser:getMetadata()
    if self:needsReload() then
        self:parseMetadata()
    end
    return self.metadata or {}
end

---
--- Gets metadata for a specific book by its ContentID.
--- @param book_id string: The book's ContentID.
--- @return table|nil: Metadata table for the book, or nil if not found.
function MetadataParser:getBookMetadata(book_id)
    local metadata = self:getMetadata()
    return metadata[book_id]
end

---
--- Gets a list of all book ContentIDs in the metadata cache.
--- @return table: Array of ContentID strings.
function MetadataParser:getBookIds()
    local metadata = self:getMetadata()
    local ids = {}
    for id, _ in pairs(metadata) do
        table.insert(ids, id)
    end
    return ids
end

---
--- Gets the total count of books in the metadata cache.
--- @return number: Number of books.
function MetadataParser:getBookCount()
    local count = 0
    for _ in pairs(self:getMetadata()) do
        count = count + 1
    end
    return count
end

---
--- Gets the full filesystem path for a kepub book file.
--- Kepub files are stored as /path/to/kepub/{ContentID} without extension.
--- The ContentID from the database IS the filename.
--- Verifies the file exists and is a regular file before returning the path.
--- @param book_id string: The book's ContentID.
--- @return string|nil: Full path to the book file, or nil if not found or not a file.
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
--- Gets the path to a book's thumbnail preview image.
--- Does not verify that the thumbnail actually exists.
--- @param book_id string: The book's ContentID.
--- @return string: Path to the thumbnail PNG file.
function MetadataParser:getThumbnailPath(book_id)
    local kepub_path = self:getKepubPath()
    return kepub_path .. "/.thumbnail-previews/" .. book_id .. ".png"
end

---
--- Checks if a book file exists and is accessible as a regular file.
--- @param book_id string: The book's ContentID.
--- @return boolean: True if the book file exists and is accessible.
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
--- Checks if a book is DRM-encrypted by querying the content_keys table.
--- Books with entries in content_keys are KDRM-encrypted by Kobo.
--- Books without entries are not encrypted (sideloaded DRM-free books).
--- This is a fast O(1) database lookup using an indexed query.
--- @param book_id string: The book's ContentID.
--- @param db_conn table|nil: Optional database connection to reuse. If not provided, opens and closes a new connection.
--- @return boolean: True if the book has KDRM encryption (content keys exist).
function MetadataParser:isBookEncrypted(book_id, db_conn)
    logger.dbg("MetadataParser: checking if book is encrypted", book_id)

    if not book_id then
        logger.dbg("MetadataParser: book_id is missing, assuming not encrypted")

        return false
    end

    local owns_connection = false

    if not db_conn then
        if not self.db_path then
            logger.dbg("MetadataParser: no database path set, assuming not encrypted")

            return false
        end

        db_conn = SQ3.open(self.db_path)
        if not db_conn then
            logger.dbg("MetadataParser: could not open database, assuming not encrypted")

            return false
        end
        owns_connection = true
    end

    local stmt = db_conn:prepare("SELECT 1 FROM content_keys WHERE volumeId = ? LIMIT 1")
    if not stmt then
        if owns_connection then
            db_conn:close()
        end
        logger.dbg("MetadataParser: could not prepare query, assuming not encrypted")

        return false
    end

    stmt:bind(book_id)
    local has_keys = stmt:step() ~= nil
    stmt:close()

    if owns_connection then
        db_conn:close()
    end

    if has_keys then
        logger.dbg("MetadataParser: book has content keys (KDRM encrypted)", book_id)

        return has_keys
    end

    logger.dbg("MetadataParser: book has no content keys (not encrypted)", book_id)

    return has_keys
end

---
--- Creates an accessible book entry with all relevant paths.
--- @param book_id string: The book's ContentID.
--- @param book_meta table: Metadata table for the book.
--- @return table: Accessible book entry with id, metadata, filepath, and thumbnail.
local function createAccessibleBookEntry(book_id, book_meta, filepath, thumbnail_path)
    return {
        id = book_id,
        metadata = book_meta,
        filepath = filepath,
        thumbnail = thumbnail_path,
    }
end

---
--- Scans the kepub directory and returns a list of file basenames (book IDs).
--- Skips hidden files and directories.
--- @return table: Array of book ID strings found in kepub directory.
function MetadataParser:scanKepubDirectory()
    local kepub_path = self:getKepubPath()
    local book_ids = {}

    local attr = lfs.attributes(kepub_path)
    if not attr or attr.mode ~= "directory" then
        logger.warn("KoboPlugin: Kepub directory not found or not a directory:", kepub_path)
        return book_ids
    end

    for entry in lfs.dir(kepub_path) do
        if entry ~= "." and entry ~= ".." and not entry:match("^%.") then
            local filepath = kepub_path .. "/" .. entry
            local entry_attr = lfs.attributes(filepath, "mode")
            if entry_attr == "file" then
                table.insert(book_ids, entry)
            end
        end
    end

    logger.dbg("KoboPlugin: Found", #book_ids, "files in kepub directory")
    return book_ids
end

---
--- Check if DRM decryption is enabled in settings.
--- @return boolean: True if DRM decryption is enabled
function MetadataParser:isDrmDecryptionEnabled()
    if not self.plugin then
        return false
    end

    return self.plugin.settings.enable_drm_decryption == true
end

---
--- Get the cache directory for decrypted books from settings.
--- @return string: Cache directory path
function MetadataParser:getDrmCacheDir()
    if not self.plugin then
        return nil
    end

    return self.plugin.settings.drm_cache_dir
end

---
--- Extracts cover image to book's sidecar directory.
--- Handles both encrypted and unencrypted books transparently.
--- For encrypted books: decrypts only the cover file from the EPUB.
--- For unencrypted books: extracts cover normally from the EPUB.
--- Saves the cover as "cover.jpg" in the book's .sdr directory so KOReader can find it.
--- @param book_id string: Book ContentID
--- @param book_path string: Full path to the book file
--- @param is_encrypted boolean: Whether the book is DRM-encrypted
--- @return boolean: True if successful, false otherwise
function MetadataParser:extractCoverToSidecar(book_id, book_path, is_encrypted)
    local DocSettings = require("docsettings")
    local util = require("util")

    local sidecar_dir = DocSettings:getSidecarDir(book_path)
    local cover_path = sidecar_dir .. "/cover.jpg"

    local attr = lfs.attributes(cover_path)
    if attr and attr.mode == "file" then
        logger.dbg("KoboPlugin: Cover already exists in sidecar:", cover_path)

        return true
    end

    util.makePath(sidecar_dir)

    if is_encrypted then
        local kobo_dir = self:getKoboPath()
        local db_path = self:getDatabasePath()
        local input_path = kobo_dir .. "/kepub/" .. book_id

        local success, err = CoverExtractor:extractCover(book_id, input_path, cover_path, kobo_dir, db_path, KoboKDRM)
        if not success then
            logger.warn("KoboPlugin: Failed to extract cover from encrypted book", book_id, ":", err)

            return false
        end

        logger.info("KoboPlugin: Successfully extracted cover from encrypted book to sidecar:", cover_path)
        return true
    end

    local doc = DocumentRegistry:openDocument(book_path)
    if not doc then
        logger.warn("KoboPlugin: Failed to open document for cover extraction:", book_path)

        return false
    end

    local cover_bb = doc:getCoverPageImage()
    doc:close()

    if not cover_bb then
        logger.warn("KoboPlugin: Document has no cover image:", book_path)

        return false
    end

    cover_bb:writeToFile(cover_path, "JPEG")
    cover_bb:free()

    logger.info("KoboPlugin: Successfully extracted cover from unencrypted book to sidecar:", cover_path)

    return true
end

---
--- Filters the metadata cache to return only accessible books.
--- Scans kepub directory to find files, checks encryption status.
--- For encrypted books: checks cache and optionally extracts covers (lazy).
--- Logs statistics about accessible, encrypted, and missing books.
---
--- Due to the way how KOReader works, an empty temporary file is created for files that sitll
--- need to be decrypted.
---
--- @return table: Array of accessible book entries, each containing id, metadata, filepath, and thumbnail.
local function _buildAccessibleBooks(self)
    local accessible = {}

    local all_metadata = self:getMetadata()

    local book_ids = self:scanKepubDirectory()
    if #book_ids == 0 then
        logger.info("KoboPlugin: Accessible books: 0 Encrypted: 0 Missing: 0")

        return accessible
    end

    logger.dbg("KoboPlugin: Checking accessibility for", #book_ids, "files")

    local accessible_count = 0
    local encrypted_count = 0
    local no_metadata_count = 0

    local drm_enabled = self:isDrmDecryptionEnabled()
    local cache_dir = self:getDrmCacheDir()

    if drm_enabled then
        logger.info("KoboPlugin: DRM decryption is enabled")
    end

    local db_conn = nil
    if self.db_path then
        db_conn = SQ3.open(self.db_path)
        if not db_conn then
            logger.warn(
                "KoboPlugin: Failed to open database for encryption checks, will use fallback per-book connections"
            )
        end
    end

    for _, book_id in ipairs(book_ids) do
        local encrypted = self:isBookEncrypted(book_id, db_conn)

        if encrypted then
            encrypted_count = encrypted_count + 1
            logger.dbg("KoboPlugin: Book is encrypted:", book_id)
        end

        local book_meta = all_metadata[book_id]

        if not book_meta then
            no_metadata_count = no_metadata_count + 1
            logger.dbg("KoboPlugin: No metadata found in database for book:", book_id)
        end

        if book_meta then
            local filepath

            if encrypted and drm_enabled then
                local cached_path = CacheManager:ensureCachePath(book_id, cache_dir)

                filepath = cached_path
                logger.dbg("KoboPlugin: Using cached decrypted book:", filepath)
            else
                filepath = self:getBookFilePath(book_id)
            end

            if filepath and not (encrypted and not drm_enabled) then
                local entry = createAccessibleBookEntry(book_id, book_meta, filepath, nil)

                entry.is_encrypted = encrypted
                table.insert(accessible, entry)
                accessible_count = accessible_count + 1
            end
        end
    end

    if db_conn then
        db_conn:close()
    end

    logger.info(
        "KoboPlugin: Accessible books:",
        accessible_count,
        "Encrypted:",
        encrypted_count,
        "Missing metadata:",
        no_metadata_count
    )

    return accessible
end

---
--- Gets the accessible books cache, reloading from disk if stale.
--- Automatically calls _buildAccessibleBooks if needsAccessibleBooksReload returns true.
--- @return table: Array of accessible book entries, never nil.
function MetadataParser:getAccessibleBooks()
    if self:needsAccessibleBooksReload() then
        self.accessible_books = _buildAccessibleBooks(self)
    end

    return self.accessible_books or {}
end

---
--- Clears the metadata cache, forcing a reload on next access.
--- Resets both the metadata table and the last modification time.
--- Also clears the accessible books cache.
function MetadataParser:clearCache()
    self.metadata = nil
    self.last_mtime = nil
    self.accessible_books = nil
end

return MetadataParser
