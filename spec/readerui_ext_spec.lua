-- Tests for ReaderUIExt module

describe("ReaderUIExt", function()
    local ReaderUIExt

    setup(function()
        -- Mock BookList before loading ReaderUIExt
        package.preload["ui/widget/booklist"] = function()
            return {
                book_info_cache = {},
                setBookInfoCacheProperty = function(path, key, value) end,
            }
        end

        helper = require("spec.helper")
        ReaderUIExt = require("src.readerui_ext")
    end)

    before_each(function()
        package.loaded["src.readerui_ext"] = nil
        ReaderUIExt = require("src.readerui_ext")
    end)

    describe("performAutoSyncIfEnabled (via onClose patch)", function()
        local function createMockVirtualLibrary(is_active)
            return {
                isActive = function()
                    return is_active
                end,
                isVirtualPath = function(self, path)
                    return path and path:match("^KOBO_VIRTUAL://")
                end,
                getBookId = function(self, virtual_path)
                    if not virtual_path then
                        return nil
                    end

                    return virtual_path:match("^KOBO_VIRTUAL://([A-Z0-9]+)/")
                end,
            }
        end

        local function createMockReadingStateSync(is_enabled, auto_sync_enabled, kobo_state, sync_called_tracker)
            return {
                isEnabled = function()
                    return is_enabled
                end,
                isAutomaticSyncEnabled = function()
                    return auto_sync_enabled
                end,
                readKoboState = function(self, book_id)
                    return kobo_state
                end,
                syncIfApproved = function(self, is_pull_from_kobo, is_newer, sync_fn, sync_details)
                    if sync_called_tracker then
                        sync_called_tracker.was_called = true
                        sync_called_tracker.is_pull_from_kobo = is_pull_from_kobo
                        sync_called_tracker.is_newer = is_newer
                        sync_called_tracker.sync_details = sync_details
                    end

                    if sync_fn then
                        sync_fn()
                    end
                end,
                syncToKobo = function(self, book_id, doc_settings)
                    if sync_called_tracker then
                        sync_called_tracker.sync_to_kobo_called = true
                    end

                    return true
                end,
                getBookTitle = function(self, book_id, doc_settings)
                    return "Test Book"
                end,
                extractBookId = function(self, virtual_path, doc_settings)
                    return nil
                end,
            }
        end

        local function createMockDocSettings(percent_finished, status)
            return {
                data = { doc_path = "KOBO_VIRTUAL://TESTBOOK1/test.epub" },
                readSetting = function(self, key)
                    if key == "percent_finished" then
                        return percent_finished
                    end

                    if key == "summary" then
                        return { status = status }
                    end

                    return nil
                end,
            }
        end

        local function createMockReaderUI()
            return {
                showFileManager = function(self, file, selected_files)
                    return true
                end,
                onClose = function(self, full_refresh) end,
            }
        end

        it("should skip sync when both KOReader and Kobo are marked as complete (100%)", function()
            local sync_tracker = { was_called = false, sync_to_kobo_called = false }
            local kobo_state = {
                status = "complete",
                percent_read = 100,
                timestamp = os.time() - 1000,
            }
            local mock_sync = createMockReadingStateSync(true, true, kobo_state, sync_tracker)
            local mock_vlib = createMockVirtualLibrary(true)

            local ext = ReaderUIExt:new()
            ext:init(mock_vlib, mock_sync)

            local mock_reader_ui = createMockReaderUI()
            ext:apply(mock_reader_ui)

            local mock_doc_settings = createMockDocSettings(1.0, "complete")
            local reader_self = {
                document = { virtual_path = "KOBO_VIRTUAL://TESTBOOK1/test.epub" },
                doc_settings = mock_doc_settings,
            }

            mock_reader_ui.onClose(reader_self, false)

            assert.is_false(sync_tracker.was_called)
            assert.is_false(sync_tracker.sync_to_kobo_called)
        end)

        it("should skip sync when both are complete (KOReader at 80% with status='complete')", function()
            local sync_tracker = { was_called = false, sync_to_kobo_called = false }
            local kobo_state = {
                status = "complete",
                percent_read = 100,
                timestamp = os.time() - 1000,
            }
            local mock_sync = createMockReadingStateSync(true, true, kobo_state, sync_tracker)
            local mock_vlib = createMockVirtualLibrary(true)

            local ext = ReaderUIExt:new()
            ext:init(mock_vlib, mock_sync)

            local mock_reader_ui = createMockReaderUI()
            ext:apply(mock_reader_ui)

            local mock_doc_settings = createMockDocSettings(0.8, "complete")
            local reader_self = {
                document = { virtual_path = "KOBO_VIRTUAL://TESTBOOK1/test.epub" },
                doc_settings = mock_doc_settings,
            }

            mock_reader_ui.onClose(reader_self, false)

            assert.is_false(sync_tracker.was_called)
            assert.is_false(sync_tracker.sync_to_kobo_called)
        end)

        it("should skip sync when both are complete (status='finished')", function()
            local sync_tracker = { was_called = false, sync_to_kobo_called = false }
            local kobo_state = {
                status = "complete",
                percent_read = 100,
                timestamp = os.time() - 1000,
            }
            local mock_sync = createMockReadingStateSync(true, true, kobo_state, sync_tracker)
            local mock_vlib = createMockVirtualLibrary(true)

            local ext = ReaderUIExt:new()
            ext:init(mock_vlib, mock_sync)

            local mock_reader_ui = createMockReaderUI()
            ext:apply(mock_reader_ui)

            local mock_doc_settings = createMockDocSettings(0.99, "finished")
            local reader_self = {
                document = { virtual_path = "KOBO_VIRTUAL://TESTBOOK1/test.epub" },
                doc_settings = mock_doc_settings,
            }

            mock_reader_ui.onClose(reader_self, false)

            assert.is_false(sync_tracker.was_called)
            assert.is_false(sync_tracker.sync_to_kobo_called)
        end)

        it("should sync when KOReader is complete but Kobo is not", function()
            local sync_tracker = { was_called = false, sync_to_kobo_called = false }
            local kobo_state = {
                status = "reading",
                percent_read = 50,
                timestamp = os.time() - 1000,
            }
            local mock_sync = createMockReadingStateSync(true, true, kobo_state, sync_tracker)
            local mock_vlib = createMockVirtualLibrary(true)

            local ext = ReaderUIExt:new()
            ext:init(mock_vlib, mock_sync)

            local mock_reader_ui = createMockReaderUI()
            ext:apply(mock_reader_ui)

            local mock_doc_settings = createMockDocSettings(1.0, "complete")
            local reader_self = {
                document = { virtual_path = "KOBO_VIRTUAL://TESTBOOK1/test.epub" },
                doc_settings = mock_doc_settings,
            }

            mock_reader_ui.onClose(reader_self, false)

            assert.is_true(sync_tracker.was_called)
            assert.is_true(sync_tracker.sync_to_kobo_called)
            assert.is_false(sync_tracker.is_pull_from_kobo)
            assert.is_true(sync_tracker.is_newer)
        end)

        it("should sync when neither side is complete", function()
            local sync_tracker = { was_called = false, sync_to_kobo_called = false }
            local kobo_state = {
                status = "reading",
                percent_read = 50,
                timestamp = os.time() - 1000,
            }
            local mock_sync = createMockReadingStateSync(true, true, kobo_state, sync_tracker)
            local mock_vlib = createMockVirtualLibrary(true)

            local ext = ReaderUIExt:new()
            ext:init(mock_vlib, mock_sync)

            local mock_reader_ui = createMockReaderUI()
            ext:apply(mock_reader_ui)

            local mock_doc_settings = createMockDocSettings(0.6, "reading")
            local reader_self = {
                document = { virtual_path = "KOBO_VIRTUAL://TESTBOOK1/test.epub" },
                doc_settings = mock_doc_settings,
            }

            mock_reader_ui.onClose(reader_self, false)

            assert.is_true(sync_tracker.was_called)
            assert.is_true(sync_tracker.sync_to_kobo_called)
        end)

        it("should not sync when auto-sync is disabled", function()
            local sync_tracker = { was_called = false, sync_to_kobo_called = false }
            local kobo_state = {
                status = "reading",
                percent_read = 50,
                timestamp = os.time() - 1000,
            }
            local mock_sync = createMockReadingStateSync(true, false, kobo_state, sync_tracker)
            local mock_vlib = createMockVirtualLibrary(true)

            local ext = ReaderUIExt:new()
            ext:init(mock_vlib, mock_sync)

            local mock_reader_ui = createMockReaderUI()
            ext:apply(mock_reader_ui)

            local mock_doc_settings = createMockDocSettings(0.6, "reading")
            local reader_self = {
                document = { virtual_path = "KOBO_VIRTUAL://TESTBOOK1/test.epub" },
                doc_settings = mock_doc_settings,
            }

            mock_reader_ui.onClose(reader_self, false)

            assert.is_false(sync_tracker.was_called)
            assert.is_false(sync_tracker.sync_to_kobo_called)
        end)

        it("should not sync when kobo_state is nil", function()
            local sync_tracker = { was_called = false, sync_to_kobo_called = false }
            local mock_sync = createMockReadingStateSync(true, true, nil, sync_tracker)
            local mock_vlib = createMockVirtualLibrary(true)

            local ext = ReaderUIExt:new()
            ext:init(mock_vlib, mock_sync)

            local mock_reader_ui = createMockReaderUI()
            ext:apply(mock_reader_ui)

            local mock_doc_settings = createMockDocSettings(0.6, "reading")
            local reader_self = {
                document = { virtual_path = "KOBO_VIRTUAL://TESTBOOK1/test.epub" },
                doc_settings = mock_doc_settings,
            }

            mock_reader_ui.onClose(reader_self, false)

            assert.is_false(sync_tracker.was_called)
            assert.is_false(sync_tracker.sync_to_kobo_called)
        end)
    end)

    describe("initialization", function()
        it("should create a new instance", function()
            local ext = ReaderUIExt:new()
            assert.is_not_nil(ext)
        end)

        it("should initialize with virtual library and reading state sync", function()
            local mock_vlib = {
                isActive = function()
                    return true
                end,
            }
            local mock_sync = {
                isEnabled = function()
                    return true
                end,
            }

            local ext = ReaderUIExt:new()
            ext:init(mock_vlib, mock_sync)

            assert.equals(mock_vlib, ext.virtual_library)
            assert.equals(mock_sync, ext.reading_state_sync)
            assert.is_table(ext.original_methods)
        end)
    end)
end)
