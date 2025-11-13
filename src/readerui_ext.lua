---
-- ReaderUI extensions for Kobo kepub files.
-- Patches ReaderUI to navigate back to virtual library after closing kepub files.

local SyncDecisionMaker = require("src.lib.sync_decision_maker")
local logger = require("logger")

local ReaderUIExt = {}

---
-- Creates a new ReaderUIExt instance.
-- @return table: A new ReaderUIExt instance.
function ReaderUIExt:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self
    return o
end

---
-- Updates BookList cache with final reading progress.
-- @param virtual_path string: Virtual library path.
-- @param doc_settings table: Document settings instance.
local function updateBookListCache(virtual_path, doc_settings)
    if not doc_settings then
        return
    end

    local percent_finished = doc_settings:readSetting("percent_finished")
    if not percent_finished then
        return
    end

    local BookList = require("ui/widget/booklist")
    logger.dbg(
        "KoboPlugin: Updating BookList cache for virtual path:",
        virtual_path,
        "percent:",
        percent_finished * 100
    )
    BookList.setBookInfoCacheProperty(virtual_path, "percent_finished", percent_finished)
end

---
-- Prepares sync details for reading state synchronization.
-- @param kr_percent number: KOReader progress percentage.
-- @param kr_timestamp number: KOReader timestamp.
-- @param kobo_state table: Kobo reading state.
-- @param book_id string: Kobo book ID.
-- @param doc_settings table: Document settings instance.
-- @param reading_state_sync table: Reading state sync instance.
-- @return table: Sync details structure.
local function prepareSyncDetails(kr_percent, kr_timestamp, kobo_state, book_id, doc_settings, reading_state_sync)
    return {
        book_title = reading_state_sync:getBookTitle(book_id, doc_settings),
        source_percent = kr_percent * 100,
        dest_percent = kobo_state.percent_read,
        source_time = kr_timestamp,
        dest_time = kobo_state.timestamp,
    }
end

---
-- Performs sync to Kobo if auto-sync is enabled and user approves.
-- @param book_id string: Kobo book ID.
-- @param doc_settings table: Document settings instance.
-- @param reading_state_sync table: Reading state sync instance.
local function performAutoSyncIfEnabled(book_id, doc_settings, reading_state_sync)
    if not reading_state_sync or not reading_state_sync:isAutomaticSyncEnabled() then
        return
    end

    logger.info("KoboPlugin: Evaluating auto-sync for closing book:", book_id)

    local kr_percent = doc_settings:readSetting("percent_finished") or 0
    local kr_timestamp = os.time()
    local kobo_state = reading_state_sync:readKoboState(book_id)

    if not kobo_state then
        return
    end

    local summary = doc_settings:readSetting("summary") or {}
    local kr_status = summary.status

    if SyncDecisionMaker.areBothSidesComplete(kobo_state, kr_percent, kr_status) then
        logger.info(
            "KoboPlugin: Both sides marked as complete, skipping auto-sync for book:",
            book_id,
            "Kobo:",
            kobo_state.percent_read,
            "%, KOReader:",
            kr_percent * 100,
            "%"
        )

        return
    end

    local is_koreader_newer = true
    local sync_details =
        prepareSyncDetails(kr_percent, kr_timestamp, kobo_state, book_id, doc_settings, reading_state_sync)

    reading_state_sync:syncIfApproved(false, is_koreader_newer, function()
        logger.info("KoboPlugin: Syncing closing book to Kobo:", book_id)
        reading_state_sync:syncToKobo(book_id, doc_settings)
    end, sync_details)
end

---
-- Attempts to extract book_id from doc_settings as fallback.
-- @param virtual_path string|nil: Virtual library path.
-- @param doc_settings table: Document settings instance.
-- @param reading_state_sync table: Reading state sync instance.
-- @return string|nil: Book ID if extraction succeeds.
local function extractBookIdFallback(virtual_path, doc_settings, reading_state_sync)
    if not reading_state_sync or not reading_state_sync:isEnabled() then
        return nil
    end

    if not reading_state_sync:isAutomaticSyncEnabled() then
        return nil
    end

    local book_id = reading_state_sync:extractBookId(virtual_path, doc_settings)
    if book_id then
        logger.info("KoboPlugin: Extracted book_id from doc_settings for last_file sync:", book_id)
    end

    return book_id
end

---
-- Initializes the ReaderUIExt module.
-- @param virtual_library table: Virtual library instance.
-- @param reading_state_sync table: Reading state sync instance.
function ReaderUIExt:init(virtual_library, reading_state_sync)
    self.virtual_library = virtual_library
    self.reading_state_sync = reading_state_sync
    self.original_methods = {}
end

---
-- Applies monkey patches to ReaderUI.
-- Patches showFileManager and onClose for virtual kepub navigation and sync.
-- @param ReaderUI table: ReaderUI module to patch.
function ReaderUIExt:apply(ReaderUI)
    if not self.virtual_library:isActive() then
        logger.info("KoboPlugin: Kobo plugin not active, skipping ReaderUI patches")
        return
    end

    logger.info("KoboPlugin: Applying ReaderUI monkey patches for Kobo kepub navigation")

    self.original_methods.showFileManager = ReaderUI.showFileManager
    ReaderUI.showFileManager = function(reader_self, file, selected_files)
        if not file or not self.virtual_library:isVirtualPath(file) then
            return self.original_methods.showFileManager(reader_self, file, selected_files)
        end

        logger.info("KoboPlugin: Navigating to virtual library for virtual path:", file)
        return self.original_methods.showFileManager(reader_self, file, selected_files)
    end

    self.original_methods.onClose = ReaderUI.onClose
    ReaderUI.onClose = function(reader_self, full_refresh)
        local virtual_path = reader_self.document and reader_self.document.virtual_path
        local book_id = virtual_path and self.virtual_library:getBookId(virtual_path)

        self.original_methods.onClose(reader_self, full_refresh)

        if virtual_path and reader_self.doc_settings then
            updateBookListCache(virtual_path, reader_self.doc_settings)

            if book_id then
                performAutoSyncIfEnabled(book_id, reader_self.doc_settings, self.reading_state_sync)
            end
        end

        if not book_id and reader_self.doc_settings then
            book_id = extractBookIdFallback(virtual_path, reader_self.doc_settings, self.reading_state_sync)
            if book_id then
                performAutoSyncIfEnabled(book_id, reader_self.doc_settings, self.reading_state_sync)
            end
        end
    end
end

---
-- Removes all monkey patches and restores original methods.
-- @param ReaderUI table: ReaderUI module to restore.
function ReaderUIExt:unapply(ReaderUI)
    logger.info("KoboPlugin: Removing ReaderUI monkey patches")

    for method_name, original_method in pairs(self.original_methods) do
        ReaderUI[method_name] = original_method
    end

    self.original_methods = {}
end

return ReaderUIExt
