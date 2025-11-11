---
-- Reading State Synchronization for Kobo Kepub files.
-- Syncs reading progress between KOReader and Kobo SQLite database based on last read date.

local logger = require("logger")
local ReadHistory = require("readhistory")
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local _ = require("gettext")
local T = require("ffi/util").template
local ffiUtil = require("ffi/util")
local DocSettings = require("docsettings")
local Trapper = require("ui/trapper")
local KoboStateReader = require("lib/kobo_state_reader")
local KoboStateWriter = require("lib/kobo_state_writer")
local SyncDecisionMaker = require("lib/sync_decision_maker")
local BookList = require("ui/widget/booklist")

local ReadingStateSync = {}

---
-- Extracts book ID from virtual path.
-- @param virtual_path string: Virtual path in format KOBO_VIRTUAL://BOOKID/filename.
-- @return string|nil: Book ID if extracted successfully.
local function extractBookIdFromVirtualPath(virtual_path)
    if not virtual_path or not virtual_path:match("^KOBO_VIRTUAL://") then
        return nil
    end

    local book_id = virtual_path:match("^KOBO_VIRTUAL://([A-Z0-9]+)/")
    if book_id then
        logger.dbg("KoboPlugin: Extracted book ID from virtual path:", book_id)
    end

    return book_id
end

---
-- Extracts book ID from doc_path in doc_settings.
-- @param doc_settings table: Document settings instance.
-- @return string|nil: Book ID if extracted successfully.
local function extractBookIdFromDocPath(doc_settings)
    if not doc_settings or not doc_settings.data or not doc_settings.data.doc_path then
        return nil
    end

    local doc_path = doc_settings.data.doc_path
    local book_id = doc_path:match("/([A-Z0-9]+)$") or doc_path:match("/([A-Z0-9]+)/")

    if book_id then
        logger.dbg("KoboPlugin: Extracted book ID from doc_path:", book_id, "from path:", doc_path)
        return book_id
    end

    return extractBookIdFromVirtualPath(doc_path)
end

---
-- Creates a new ReadingStateSync instance.
-- @param metadata_parser table: MetadataParser instance for accessing book metadata.
-- @return table: A new ReadingStateSync instance.
function ReadingStateSync:new(metadata_parser)
    local o = {
        metadata_parser = metadata_parser,
        enabled = false,
        plugin = nil,
        sync_direction = nil,
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

---
-- Sets plugin instance and sync direction constants.
-- @param plugin table: Main plugin instance with settings.
-- @param sync_direction table: SYNC_DIRECTION constants.
function ReadingStateSync:setPlugin(plugin, sync_direction)
    self.plugin = plugin
    self.sync_direction = sync_direction
end

---
-- Checks if reading state sync is enabled.
-- @return boolean: True if sync is enabled.
function ReadingStateSync:isEnabled()
    return self.enabled
end

---
-- Extracts book ID from various path formats.
-- Handles virtual paths, Kobo paths, and doc_settings data.
-- @param virtual_path string|nil: Virtual path to check.
-- @param doc_settings table|nil: Document settings instance.
-- @return string|nil: Book ID if extraction succeeds.
function ReadingStateSync:extractBookId(virtual_path, doc_settings)
    if not virtual_path and not doc_settings then
        return nil
    end

    local book_id = extractBookIdFromVirtualPath(virtual_path)
    if book_id then
        return book_id
    end

    book_id = extractBookIdFromDocPath(doc_settings)
    if book_id then
        return book_id
    end

    logger.dbg("KoboPlugin: Could not extract book ID from paths")
    return nil
end

---
-- Gets book title from various sources.
-- @param book_id string: Book ContentID.
-- @param doc_settings table: Document settings instance.
-- @return string: Book title, or "Unknown Book" if not found.
function ReadingStateSync:getBookTitle(book_id, doc_settings)
    local title = doc_settings and doc_settings:readSetting("title")
    if title and title ~= "" then
        return title
    end

    if not self.metadata_parser then
        return "Unknown Book"
    end

    local book_meta = self.metadata_parser:getBookMetadata(book_id)
    if book_meta and book_meta.title and book_meta.title ~= "" then
        return book_meta.title
    end

    logger.dbg("KoboPlugin: Could not determine book title for book ID:", book_id)
    return "Unknown Book"
end

---
-- Sets whether reading state sync is enabled.
-- @param enabled boolean: True to enable sync.
function ReadingStateSync:setEnabled(enabled)
    self.enabled = enabled
    logger.info("KoboPlugin: Reading state sync", enabled and "enabled" or "disabled")
end

---
-- Checks if automatic sync is enabled.
-- @return boolean: True if auto-sync is enabled.
function ReadingStateSync:isAutomaticSyncEnabled()
    if not self.enabled or not self.plugin then
        return false
    end

    return self.plugin.settings.enable_auto_sync == true
end

---
-- Evaluates whether a sync should proceed based on user settings.
-- Executes the provided callback function if sync is approved.
-- @param is_pull_from_kobo boolean: True if pulling FROM Kobo, false if pushing TO Kobo.
-- @param is_newer boolean: True if source is newer, false if older.
-- @param sync_fn function: Callback to execute if sync is approved.
-- @param sync_details table: Optional details for user prompt (book_title, percent, timestamps).
-- @return boolean: True if sync was executed, false if denied.
function ReadingStateSync:syncIfApproved(is_pull_from_kobo, is_newer, sync_fn, sync_details)
    logger.dbg(
        "KoboPlugin: Evaluating sync approval:",
        is_pull_from_kobo and "FROM Kobo" or "TO Kobo",
        is_newer and "newer" or "older"
    )

    if not self.plugin or not self.sync_direction then
        logger.warn("KoboPlugin: Sync settings not configured, denying sync")
        return false
    end

    return SyncDecisionMaker.syncIfApproved(
        self.plugin,
        self.sync_direction,
        is_pull_from_kobo,
        is_newer,
        sync_fn,
        sync_details
    )
end

---
-- Reads Kobo reading state from SQLite database.
-- @param book_id string: Book ContentID.
-- @return table|nil: State table with percent_read, timestamp, status, kobo_status.
function ReadingStateSync:readKoboState(book_id)
    local db_path = self.metadata_parser:getDatabasePath()
    if not db_path then
        return nil
    end

    return KoboStateReader.read(db_path, book_id)
end

---
-- Writes KOReader reading state to Kobo SQLite database.
-- @param book_id string: Book ContentID.
-- @param percent_read number: Progress percentage (0-100).
-- @param timestamp number: Unix timestamp of last read.
-- @param status string: KOReader status string.
-- @return boolean: True if write succeeded.
function ReadingStateSync:writeKoboState(book_id, percent_read, timestamp, status)
    local db_path = self.metadata_parser:getDatabasePath()
    if not db_path then
        return false
    end

    return KoboStateWriter.write(db_path, book_id, percent_read, timestamp, status)
end

---
-- Sync reading state from Kobo to KOReader (when opening virtual library).
-- Winner is whoever was read more recently.
-- Note: Does NOT sync if Kobo ReadStatus is 0 (unopened), but KOReader can sync back to Kobo.
-- @param book_id string: Book ContentID.
-- @param doc_settings table: Document settings instance.
-- @return boolean: True if sync was performed.
function ReadingStateSync:syncFromKobo(book_id, doc_settings)
    if not self:isEnabled() then
        return false
    end

    local kobo_state = self:readKoboState(book_id)

    if not kobo_state or not kobo_state.percent_read then
        return false
    end

    if kobo_state.kobo_status == 0 then
        logger.dbg("KoboPlugin: Skipping sync FROM Kobo - book unopened (ReadStatus = 0) for:", book_id)
        return false
    end

    local kr_timestamp = self:getTimestampFromHistory(doc_settings)

    if kobo_state.timestamp <= kr_timestamp then
        logger.dbg(
            "KoboPlugin: KOReader is more recent, keeping KOReader value:",
            "KOReader:",
            kr_timestamp,
            "vs Kobo:",
            kobo_state.timestamp
        )
        return false
    end

    return self:applyKoboStateToKOReader(kobo_state, doc_settings, kr_timestamp)
end

---
-- Gets timestamp from ReadHistory for a document.
-- @param doc_settings table: Document settings instance.
-- @return number: Timestamp from ReadHistory, or 0 if not found.
function ReadingStateSync:getTimestampFromHistory(doc_settings)
    local doc_path = doc_settings:getPath()

    if not doc_path then
        return 0
    end

    for _, entry in ipairs(ReadHistory.hist) do
        if entry.file and entry.file == doc_path then
            return entry.time or 0
        end
    end

    return 0
end

---
-- Applies Kobo state to KOReader settings.
-- @param kobo_state table: Kobo reading state.
-- @param doc_settings table: Document settings instance.
-- @param kr_timestamp number: KOReader timestamp for logging.
-- @return boolean: True if state was applied.
function ReadingStateSync:applyKoboStateToKOReader(kobo_state, doc_settings, kr_timestamp)
    local kobo_percent = kobo_state.percent_read / 100.0

    logger.info(
        "KoboPlugin: Syncing FROM Kobo - Kobo is more recent:",
        "Kobo timestamp:",
        kobo_state.timestamp,
        "vs KOReader:",
        kr_timestamp
    )

    doc_settings:saveSetting("percent_finished", kobo_percent)
    doc_settings:saveSetting("last_percent", kobo_percent)

    local summary = doc_settings:readSetting("summary") or {}
    summary.status = kobo_state.status

    if kobo_state.percent_read >= 100 then
        summary.status = "complete"
        logger.info("KoboPlugin: Marked book as complete (100% read in Kobo)")
    end

    doc_settings:saveSetting("summary", summary)

    return true
end

---
-- Sync reading state from KOReader to Kobo (when closing document).
-- Always syncs to update timestamp to current time.
-- @param book_id string: Book ContentID.
-- @param doc_settings table: Document settings instance.
-- @return boolean: True if write succeeded.
function ReadingStateSync:syncToKobo(book_id, doc_settings)
    if not self:isEnabled() then
        return false
    end

    local kr_percent = doc_settings:readSetting("percent_finished") or 0
    local kobo_percent = math.floor(kr_percent * 100)
    local summary = doc_settings:readSetting("summary") or {}
    local kr_status = summary.status or "reading"
    local current_timestamp = os.time()

    logger.info(
        "KoboPlugin: Syncing TO Kobo - writing KOReader progress:",
        string.format("%.2f%%", kr_percent * 100),
        "with current timestamp:",
        current_timestamp,
        "status:",
        kr_status
    )

    return self:writeKoboState(book_id, kobo_percent, current_timestamp, kr_status)
end

---
-- Gets KOReader timestamp from ReadHistory.
-- @param doc_path string: Document path to look up.
-- @return number: Timestamp from ReadHistory, or 0 if not found.
local function getKOReaderTimestampFromHistory(doc_path)
    if not doc_path then
        logger.warn("KoboPlugin: doc_path is nil, cannot look up ReadHistory")
        return 0
    end

    logger.dbg("KoboPlugin: Looking for doc_path in ReadHistory:", doc_path)

    local book_id_from_virtual = nil

    if doc_path:match("^KOBO_VIRTUAL://") then
        book_id_from_virtual = doc_path:match("^KOBO_VIRTUAL://([A-Z0-9]+)/")
        logger.dbg("KoboPlugin: Extracted book ID from virtual path:", book_id_from_virtual)
    end

    for _, entry in ipairs(ReadHistory.hist) do
        if not entry.file then
            goto continue
        end

        logger.dbg("KoboPlugin: Comparing with history entry:", entry.file)

        if entry.file == doc_path then
            local timestamp = entry.time or 0
            logger.dbg("KoboPlugin: Found matching history entry (exact path) with timestamp:", timestamp)
            return timestamp
        end

        if book_id_from_virtual and entry.file:match(book_id_from_virtual) then
            local timestamp = entry.time or 0
            logger.dbg("KoboPlugin: Found matching history entry (book ID match) with timestamp:", timestamp)
            return timestamp
        end

        ::continue::
    end

    logger.dbg("KoboPlugin: No matching history entry found for:", doc_path)
    return 0
end

---
-- Gets validated KOReader timestamp, accounting for sidecar existence.
--
-- IMPORTANT: Check if sidecar file exists before trusting ReadHistory timestamp.
-- Without a sidecar (.sdr) file, there's no actual reading progress in KOReader.
-- ReadHistory entry without sidecar is unreliable - could be from:
--   - After a reset that deleted the .sdr file
-- Therefore, if no sidecar exists, ignore ReadHistory and set timestamp to 0.
-- @param doc_path string: Document path.
-- @return number: Valid timestamp, or 0 if no sidecar exists.
local function getValidatedKOReaderTimestamp(doc_path)
    local kr_timestamp = getKOReaderTimestampFromHistory(doc_path)

    if kr_timestamp == 0 then
        return 0
    end

    local has_sidecar = DocSettings:hasSidecarFile(doc_path)

    if not has_sidecar then
        logger.dbg(
            "KoboPlugin: ReadHistory entry exists but no sidecar file found - ignoring ReadHistory timestamp.",
            "This ensures PULL from Kobo when KOReader has no valid reading progress."
        )
        return 0
    end

    return kr_timestamp
end

---
-- Executes sync FROM Kobo to KOReader (PULL scenario).
-- @param book_id string: Book ContentID.
-- @param doc_settings table: Document settings instance.
-- @param kobo_state table: Kobo reading state.
-- @param kr_percent number: KOReader progress (0-1).
-- @param kr_timestamp number: KOReader timestamp.
-- @return boolean: True if sync was completed.
function ReadingStateSync:executePullFromKobo(book_id, doc_settings, kobo_state, kr_percent, kr_timestamp)
    logger.info(
        "KoboPlugin: Kobo is more recent - PULL scenario:",
        "Kobo:",
        kobo_state.percent_read,
        "% (",
        kobo_state.timestamp,
        ")",
        "KOReader:",
        kr_percent * 100,
        "% (",
        kr_timestamp,
        ")"
    )

    if kobo_state.kobo_status == 0 and kobo_state.percent_read == 0 then
        logger.info("KoboPlugin: Skipping sync for unopened book:", book_id, "- ReadStatus=0 with no progress")
        return false
    end

    local sync_details = {
        book_title = self:getBookTitle(book_id, doc_settings),
        source_percent = kobo_state.percent_read,
        dest_percent = kr_percent * 100,
        source_time = kobo_state.timestamp,
        dest_time = kr_timestamp,
    }

    local sync_completed = false

    self:syncIfApproved(true, true, function()
        local kobo_percent = kobo_state.percent_read / 100.0
        logger.info("KoboPlugin: Syncing FROM Kobo (PULL) - applying newer Kobo state to KOReader")
        doc_settings:saveSetting("percent_finished", kobo_percent)
        doc_settings:saveSetting("last_percent", kobo_percent)

        local summary = doc_settings:readSetting("summary") or {}
        summary.status = kobo_state.status

        if kobo_state.percent_read >= 100 then
            summary.status = "complete"
            logger.info("KoboPlugin: Marked book as complete (100% read in Kobo)")
        end

        doc_settings:saveSetting("summary", summary)
        doc_settings:flush()

        sync_completed = true
    end, sync_details)

    return sync_completed
end

---
-- Executes sync FROM KOReader to Kobo (PUSH scenario).
-- Only proceeds if KOReader has a recorded timestamp.
-- Note: kr_timestamp will be 0 if no sidecar exists (checked earlier),
-- so this only executes when KOReader has valid reading progress.
-- @param book_id string: Book ContentID.
-- @param doc_settings table: Document settings instance.
-- @param kobo_state table: Kobo reading state.
-- @param kr_percent number: KOReader progress (0-1).
-- @param kr_timestamp number: KOReader timestamp.
-- @return boolean: True if sync was completed.
function ReadingStateSync:executePushToKobo(book_id, doc_settings, kobo_state, kr_percent, kr_timestamp)
    logger.info(
        "KoboPlugin: KOReader is more recent - PUSH scenario:",
        "KOReader:",
        kr_percent * 100,
        "% (",
        kr_timestamp,
        ")",
        "Kobo:",
        kobo_state.percent_read,
        "% (",
        kobo_state.timestamp,
        ")"
    )

    if kr_timestamp == 0 then
        return false
    end

    local sync_details = {
        book_title = self:getBookTitle(book_id, doc_settings),
        source_percent = kr_percent * 100,
        dest_percent = kobo_state.percent_read,
        source_time = kr_timestamp,
        dest_time = kobo_state.timestamp,
    }

    local sync_completed = false

    self:syncIfApproved(false, true, function()
        local summary = doc_settings:readSetting("summary") or {}
        local kr_status = summary.status or "reading"
        local current_timestamp = os.time()

        logger.info("KoboPlugin: Syncing TO Kobo (PUSH) - applying newer KOReader state to Kobo")
        self:writeKoboState(book_id, kr_percent * 100, current_timestamp, kr_status)
        sync_completed = true
    end, sync_details)

    return sync_completed
end

---
-- Bidirectional sync - used when showing virtual library.
-- Winner is whoever was read more recently.
-- Uses syncIfApproved callback pattern for all sync decisions.
-- @param book_id string: Book ContentID.
-- @param doc_settings table: Document settings instance.
-- @return boolean: True if sync was performed.
function ReadingStateSync:syncBidirectional(book_id, doc_settings)
    if not self:isEnabled() then
        return false
    end

    local kobo_state = self:readKoboState(book_id)

    if not kobo_state then
        logger.dbg("KoboPlugin: syncBidirectional - no kobo_state found for book:", book_id)
        return false
    end

    local kr_percent = doc_settings:readSetting("percent_finished") or 0
    local doc_path = doc_settings.data and doc_settings.data.doc_path
    local kr_timestamp = getValidatedKOReaderTimestamp(doc_path)

    local summary = doc_settings:readSetting("summary") or {}
    local kr_status = summary.status

    if SyncDecisionMaker.areBothSidesComplete(kobo_state, kr_percent, kr_status) then
        logger.dbg(
            "KoboPlugin: Both sides marked as complete, skipping sync for book:",
            book_id,
            "Kobo:",
            kobo_state.percent_read,
            "% (",
            kobo_state.timestamp,
            "), KOReader:",
            kr_percent * 100,
            "% (",
            kr_timestamp,
            ")"
        )

        return false
    end

    if kobo_state.timestamp > kr_timestamp then
        return self:executePullFromKobo(book_id, doc_settings, kobo_state, kr_percent, kr_timestamp)
    end

    return self:executePushToKobo(book_id, doc_settings, kobo_state, kr_percent, kr_timestamp)
end

---
-- Sync all accessible books in the library (manually triggered).
-- Wraps execution in Trapper for UI interaction and progress display.
-- @return number: Number of books successfully synced.
function ReadingStateSync:syncAllBooksManual()
    if not self:isEnabled() then
        logger.warn("KoboPlugin: Sync is disabled, cannot sync all books")
        return 0
    end

    local result = 0

    Trapper:wrap(function()
        result = self:syncAllBooks()
    end)

    return result
end

---
-- Syncs a single book during manual sync operation.
-- @param book table: Book info with id and filepath.
-- @return boolean: True if sync was successful.
function ReadingStateSync:syncBook(book)
    if not book.filepath then
        return false
    end

    local doc_settings = DocSettings:open(book.filepath)

    if not doc_settings then
        return false
    end

    return self:syncBidirectional(book.id, doc_settings)
end

---
-- Invalidates book metadata caches and broadcasts refresh events.
function ReadingStateSync:invalidateMetadataCaches()
    logger.info("KoboPlugin: Invalidating all book metadata caches after sync")

    BookList.book_info_cache = {}

    UIManager:broadcastEvent(Event:new("BookMetadataChanged"))
    UIManager:broadcastEvent(Event:new("InvalidateMetadataCache"))
end

---
-- Displays sync completion message to user.
-- @param synced_count number: Number of books synced.
function ReadingStateSync:showSyncCompletionMessage(synced_count)
    ffiUtil.sleep(2)
    Trapper:info(T(_("Synced %1 books"), synced_count))
    ffiUtil.sleep(2)
    Trapper:clear()
end

---
-- Internal: Sync all accessible books (should be called from within Trapper:wrap context).
-- @return number: Number of books successfully synced.
function ReadingStateSync:syncAllBooks()
    if not self:isEnabled() then
        logger.warn("KoboPlugin: Sync is disabled, cannot sync all books")
        return 0
    end

    local accessible_books = self.metadata_parser:getAccessibleBooks()

    logger.info("KoboPlugin: Starting manual sync for", #accessible_books, "accessible books")

    Trapper:setPausedText(_("Do you want to abort sync?"), _("Abort"), _("Continue"))

    local go_on = Trapper:info(_("Scanning books..."))

    if not go_on then
        logger.info("KoboPlugin: Manual sync cancelled by user")
        return 0
    end

    local synced_count = 0

    for i, book in ipairs(accessible_books) do
        go_on = Trapper:info(T(_("Syncing: %1 / %2"), i, #accessible_books))

        if not go_on then
            logger.info("KoboPlugin: Manual sync aborted by user at book", i, "of", #accessible_books)
            Trapper:clear()
            return synced_count
        end

        if self:syncBook(book) then
            synced_count = synced_count + 1
        end
    end

    logger.info("KoboPlugin: Manual sync completed -", synced_count, "books synced out of", #accessible_books)

    if synced_count > 0 then
        self:invalidateMetadataCaches()
    end

    self:showSyncCompletionMessage(synced_count)

    return synced_count
end

return ReadingStateSync
