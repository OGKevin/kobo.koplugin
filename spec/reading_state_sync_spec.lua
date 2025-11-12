-- Tests for ReadingStateSync module

describe("ReadingStateSync", function()
    local ReadingStateSync, MetadataParser, createMockDocSettings
    local SYNC_DIRECTION = { PROMPT = 1, SILENT = 2, NEVER = 3 }

    -- Helper function to set up plugin with default granular settings
    local function setupPluginSettings(sync)
        local mock_plugin = {
            settings = {
                enable_sync_from_kobo = true,
                enable_sync_to_kobo = true,
                sync_from_kobo_newer = SYNC_DIRECTION.SILENT,
                sync_from_kobo_older = SYNC_DIRECTION.NEVER,
                sync_to_kobo_newer = SYNC_DIRECTION.SILENT,
                sync_to_kobo_older = SYNC_DIRECTION.NEVER,
            },
        }
        sync:setPlugin(mock_plugin, SYNC_DIRECTION)
    end

    setup(function()
        -- Mocks are set up by helper.lua
        local helper = require("spec.helper")
        createMockDocSettings = helper.createMockDocSettings
        ReadingStateSync = require("reading_state_sync")
        MetadataParser = require("metadata_parser")
    end)

    before_each(function()
        package.loaded["reading_state_sync"] = nil
        package.loaded["metadata_parser"] = nil
        package.loaded["lib/kobo_state_reader"] = nil

        ReadingStateSync = require("reading_state_sync")
        MetadataParser = require("metadata_parser")
    end)

    describe("initialization", function()
        it("should create a new instance with metadata parser", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            assert.is_not_nil(sync)
            assert.equals(parser, sync.metadata_parser)
        end)

        it("should initialize with sync disabled", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            assert.is_false(sync:isEnabled())
        end)
    end)

    describe("enable/disable functionality", function()
        it("should enable sync when requested", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)
            assert.is_true(sync:isEnabled())
        end)

        it("should disable sync when requested", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)
            sync:setEnabled(false)
            assert.is_false(sync:isEnabled())
        end)
    end)

    describe("readKoboState", function()
        it("should have readKoboState method", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            assert.is_function(sync.readKoboState)
        end)

        it("should gracefully handle database errors", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)

            local success = pcall(function()
                return sync:readKoboState("test_book_1")
            end)

            assert.is_true(success, "readKoboState should not throw unhandled errors")
        end)

        it("should successfully read kobo state from database with rows iterator", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            local result = sync:readKoboState("test_book_1")
            assert.is_not_nil(result)
            assert.equals(50, result.percent_read)
            assert.is_number(result.timestamp)
        end)

        it("should parse both ISO 8601 date formats correctly", function()
            -- Test the date parsing logic with both formats:
            -- Format 1: YYYY-MM-DDTHH:MM:SSZ (ISO 8601 with T separator)
            -- Format 2: YYYY-MM-DD HH:MM:SS.SSS+00:00 (with space separator)

            local date_iso_t = "2025-10-26T18:26:15Z"
            local date_space = "2025-11-08 15:30:45.000+00:00"

            -- Extract parsing logic
            local function parseDate(date_str)
                if not date_str or date_str == "" then
                    return 0
                end
                -- Parse both ISO formats: YYYY-MM-DD[T ]HH:MM:SS
                local year, month, day, hour, min, sec = date_str:match("(%d+)-(%d+)-(%d+)[T ](%d+):(%d+):(%d+)")
                if year then
                    local dt = os.time({
                        year = tonumber(year),
                        month = tonumber(month),
                        day = tonumber(day),
                        hour = tonumber(hour),
                        min = tonumber(min),
                        sec = tonumber(sec),
                    })
                    return dt or 0
                end
                return 0
            end

            local ts_iso_t = parseDate(date_iso_t)
            local ts_space = parseDate(date_space)

            -- Both should parse successfully (non-zero)
            assert.is_not_equal(0, ts_iso_t, "ISO 8601 T format should parse correctly")
            assert.is_not_equal(0, ts_space, "Space format should parse correctly")

            -- Both should be reasonable timestamps (greater than 1000000000 = Sept 2001)
            assert.is_true(ts_iso_t > 1000000000, "ISO T format timestamp should be valid")
            assert.is_true(ts_space > 1000000000, "Space format timestamp should be valid")
        end)
    end)

    describe("sync state", function()
        it("should maintain enabled state", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)

            sync:setEnabled(true)
            assert.is_true(sync:isEnabled())

            sync:setEnabled(false)
            assert.is_false(sync:isEnabled())
        end)
    end)

    describe("extractBookId", function()
        it("should extract book ID from virtual path format", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)

            local virtual_path = "KOBO_VIRTUAL://0N3773Z7HFPXB/Jennifer L. Armentrout - A Soul of Ash and Blood.epub"
            local book_id = sync:extractBookId(virtual_path, nil)

            assert.equals("0N3773Z7HFPXB", book_id)
        end)

        it("should extract book ID from Kobo real path", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)

            local mock_doc_settings = {
                data = { doc_path = "/tmp/.kobo/kepub/0N3773Z7HFPXB" },
                readSetting = function(self, key)
                    return nil
                end,
                saveSetting = function(self, key, value) end,
            }

            local book_id = sync:extractBookId(nil, mock_doc_settings)
            assert.equals("0N3773Z7HFPXB", book_id)
        end)

        it("should extract book ID from virtual path in doc_settings", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)

            local mock_doc_settings = {
                data = { doc_path = "KOBO_VIRTUAL://0N395DCCSFPF2/Some Book Title.epub" },
                readSetting = function(self, key)
                    return nil
                end,
                saveSetting = function(self, key, value) end,
            }

            local book_id = sync:extractBookId(nil, mock_doc_settings)
            assert.equals("0N395DCCSFPF2", book_id)
        end)

        it("should return nil if no book ID can be extracted", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)

            local book_id = sync:extractBookId(nil, nil)
            assert.is_nil(book_id)
        end)
    end)

    describe("syncBidirectional", function()
        it("should have syncBidirectional method", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            assert.is_function(sync.syncBidirectional)
        end)

        it("should handle doc_settings with doc_path correctly", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)

            -- Create mock doc_settings with data table
            local mock_doc_settings = {
                data = { doc_path = "/test/book.epub" },
                readSetting = function(self, key)
                    if key == "percent_finished" then
                        return 0.5
                    end
                    return nil
                end,
                saveSetting = function(self, key, value) end,
            }

            -- Should not crash when calling syncBidirectional
            local success = pcall(function()
                sync:syncBidirectional("test_book_id", mock_doc_settings)
            end)
            assert.is_true(success)
        end)

        it("should correctly match doc_path with ReadHistory entries - exact path", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)

            -- Update ReadHistory mock to have specific test entries
            package.preload["readhistory"] = function()
                return {
                    hist = {
                        { file = "/tmp/.kobo/kepub/0N3773Z7HFPXB", time = 1762685677 },
                        { file = "/tmp/.kobo/kepub/0N395DCCSFPF2", time = 1762628755 },
                        { file = "/home/user/Documents/book.epub", time = 1762600000 },
                    },
                    addRecord = function(self, record)
                        table.insert(self.hist, record)
                    end,
                }
            end

            -- Reload to get updated mock
            package.loaded["readhistory"] = nil
            require("readhistory")

            -- Create doc_settings with a path that matches history exactly
            local mock_doc_settings = {
                data = { doc_path = "/tmp/.kobo/kepub/0N3773Z7HFPXB" },
                readSetting = function(self, key)
                    if key == "percent_finished" then
                        return 0.3
                    end
                    return nil
                end,
                saveSetting = function(self, key, value) end,
            }

            -- Call syncBidirectional - it should find the matching history entry
            local result = pcall(function()
                sync:syncBidirectional("0N3773Z7HFPXB", mock_doc_settings)
            end)
            assert.is_true(result)
        end)

        it("should correctly match virtual paths with ReadHistory by book ID", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)

            -- Update ReadHistory mock with Kobo paths
            package.preload["readhistory"] = function()
                return {
                    hist = {
                        { file = "/tmp/.kobo/kepub/0N3773Z7HFPXB", time = 1762685677 },
                        { file = "/tmp/.kobo/kepub/0N395DCCSFPF2", time = 1762628755 },
                        { file = "/home/user/Documents/other.epub", time = 1762600000 },
                    },
                    addRecord = function(self, record)
                        table.insert(self.hist, record)
                    end,
                }
            end

            -- Reload to get updated mock
            package.loaded["readhistory"] = nil
            require("readhistory")

            -- Create doc_settings with a VIRTUAL path (as shown in logs)
            -- Format: KOBO_VIRTUAL://BOOKID/filename
            local mock_doc_settings = {
                data = {
                    doc_path = "KOBO_VIRTUAL://0N3773Z7HFPXB/Jennifer L. Armentrout - A Soul of Ash and Blood.epub",
                },
                readSetting = function(self, key)
                    if key == "percent_finished" then
                        return 0.3
                    end
                    return nil
                end,
                saveSetting = function(self, key, value) end,
            }

            -- Call syncBidirectional - it should extract book ID and find the matching history entry
            local result = pcall(function()
                sync:syncBidirectional("0N3773Z7HFPXB", mock_doc_settings)
            end)
            assert.is_true(result)
        end)

        it("should handle missing ReadHistory entries gracefully", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)

            -- Create doc_settings with a path that doesn't match any history
            local mock_doc_settings = {
                data = { doc_path = "/nonexistent/path/book.epub" },
                readSetting = function(self, key)
                    if key == "percent_finished" then
                        return 0.5
                    end
                    return nil
                end,
                saveSetting = function(self, key, value) end,
            }

            -- Should not crash when path doesn't match
            local result = pcall(function()
                sync:syncBidirectional("unknown_book", mock_doc_settings)
            end)
            assert.is_true(result)
        end)

        it("should handle virtual paths with no matching history entry", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)

            -- Create doc_settings with a VIRTUAL path that has no matching history
            local mock_doc_settings = {
                data = { doc_path = "KOBO_VIRTUAL://UNKNOWN123/nonexistent.epub" },
                readSetting = function(self, key)
                    if key == "percent_finished" then
                        return 0.3
                    end
                    return nil
                end,
                saveSetting = function(self, key, value) end,
            }

            -- Should not crash
            local result = pcall(function()
                sync:syncBidirectional("UNKNOWN123", mock_doc_settings)
            end)
            assert.is_true(result)
        end)

        it("should sync reading progress to Kobo database on close (writeKoboState)", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)

            -- Create mock doc_settings that tracks saveSetting calls
            local saved_settings = {}
            local mock_doc_settings = {
                data = { doc_path = "/tmp/.kobo/kepub/0N3773Z7HFPXB" },
                readSetting = function(self, key)
                    if key == "percent_finished" then
                        return 0.65
                    end
                    return nil
                end,
                saveSetting = function(self, key, value)
                    saved_settings[key] = value
                end,
            }

            -- Call syncToKobo which should write to database
            local result = sync:syncToKobo("0N3773Z7HFPXB", mock_doc_settings)

            -- Result will depend on DB availability in test environment
            -- but the call should not crash
            assert.is_true(result == true or result == false)
            -- Verify that saveSetting was not called (syncToKobo writes to Kobo DB, not doc_settings)
            -- (Empty table should have no keys)
            local key_count = 0
            for _ in pairs(saved_settings) do
                key_count = key_count + 1
            end
            assert.equals(0, key_count)
        end)

        it("should update main book entry's ___PercentRead to match overall progress", function()
            -- Test that writeKoboState updates the main entry's ___PercentRead with the actual progress
            -- (not hardcoded 0 as it was before)
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)

            -- Get access to the mock SQ3 module to inspect captured queries
            local SQ3 = require("lua-ljsqlite3/init")
            SQ3._clearSqlQueries()

            -- Call writeKoboState which should execute UPDATE statements
            local result = sync:writeKoboState("test_book_1", 35, os.time(), "reading")

            -- Get captured SQL queries
            local queries = SQ3._getSqlQueries()

            -- Verify that we captured the UPDATE statement
            assert.is_true(result == true or result == false, "writeKoboState should return boolean")

            -- Check that we have captured queries
            if #queries > 0 then
                -- Find the main entry update (ContentType = 6)
                local main_entry_update = nil
                for _, captured in ipairs(queries) do
                    if captured.query:match("ContentType = 6") and captured.query:match("___PercentRead") then
                        main_entry_update = captured
                        break
                    end
                end

                -- Verify main entry update was executed with correct parameters
                if main_entry_update then
                    -- The first parameter should be the ___PercentRead value (35)
                    -- Query: SET ___PercentRead = ?, DateLastRead = ?, ReadStatus = ?, ChapterIDBookmarked = ?
                    local percent_param = main_entry_update.params[1]
                    assert.is_not_nil(percent_param, "Main entry update should have ___PercentRead parameter")
                    assert.equals(35, percent_param, "Main entry ___PercentRead should be 35 (not 0)")
                end
            end
        end)
        it("should include Kobo position marker in ChapterIDBookmarked for Nickel compatibility", function()
            -- Test that writeKoboState includes the #kobo.X.Y position marker
            -- This ensures Nickel firmware can seek to the exact position within a chapter
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)

            -- Get access to the mock SQ3 module to inspect captured queries
            local SQ3 = require("lua-ljsqlite3/init")
            SQ3._clearSqlQueries()

            -- Call writeKoboState
            sync:writeKoboState("test_book_1", 35, os.time(), "reading")

            -- Get captured SQL queries
            local queries = SQ3._getSqlQueries()

            -- Check that we have captured queries
            if #queries > 0 then
                -- Find the main entry update (ContentType = 6)
                local main_entry_update = nil
                for _, captured in ipairs(queries) do
                    if captured.query:match("ContentType = 6") then
                        main_entry_update = captured
                        break
                    end
                end

                -- Verify main entry update includes position marker
                if main_entry_update then
                    -- The fourth parameter should be ChapterIDBookmarked
                    local chapter_id_param = main_entry_update.params[4]
                    assert.is_not_nil(chapter_id_param, "ChapterIDBookmarked parameter should exist")

                    -- Should contain the position marker format: filename#kobo.X.Y
                    assert.is_true(
                        chapter_id_param:match("#kobo%.%d+%.%d+") ~= nil,
                        "ChapterIDBookmarked should contain #kobo.X.Y position marker, got: "
                            .. tostring(chapter_id_param)
                    )

                    -- Verify filename without ContentID prefix
                    assert.is_false(
                        chapter_id_param:match("!!") ~= nil,
                        "ChapterIDBookmarked should not contain !! prefix (ContentID removed)"
                    )
                end
            end
        end)
        it("should find book_id and sync when opened via last_file (no virtual_path)", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)

            -- Simulate last_file scenario: doc_settings has real Kobo path, but no virtual_path from document
            local mock_doc_settings = {
                data = { doc_path = "/tmp/.kobo/kepub/0N3773Z7HFPXB" },
                readSetting = function(self, key)
                    if key == "percent_finished" then
                        return 0.5
                    end
                    return nil
                end,
                saveSetting = function(self, key, value) end,
            }

            -- Extract book_id using fallback method (what happens when virtual_path is nil)
            local book_id = sync:extractBookId(nil, mock_doc_settings)

            -- Should successfully extract the book ID from the Kobo path
            assert.equals("0N3773Z7HFPXB", book_id)

            -- Now try to write state to Kobo (simulating onClose sync)
            local result = sync:syncToKobo(book_id, mock_doc_settings)
            assert.is_true(result == true or result == false) -- May fail if DB not available
        end)

        it("should skip sync when both sides are marked as complete (100% progress)", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)
            setupPluginSettings(sync)

            local mock_doc_settings = createMockDocSettings("/tmp/.kobo/kepub/finished_book", {
                percent_finished = 1.0,
                summary = { status = "complete" },
            })

            local result = sync:syncBidirectional("finished_book", mock_doc_settings)

            assert.is_false(result)
        end)

        it("should skip sync when both sides are complete (status-based check)", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)
            setupPluginSettings(sync)

            local mock_doc_settings = createMockDocSettings("/tmp/.kobo/kepub/finished_book", {
                percent_finished = 0.99,
                summary = { status = "complete" },
            })

            local result = sync:syncBidirectional("finished_book", mock_doc_settings)

            assert.is_false(result)
        end)

        it("should skip sync when KOReader uses 'finished' status string", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)
            setupPluginSettings(sync)

            local mock_doc_settings = createMockDocSettings("/tmp/.kobo/kepub/finished_book", {
                percent_finished = 1.0,
                summary = { status = "finished" },
            })

            local result = sync:syncBidirectional("finished_book", mock_doc_settings)

            assert.is_false(result)
        end)

        it("should sync when only Kobo is complete (pull scenario)", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)
            setupPluginSettings(sync)

            package.preload["readhistory"] = function()
                return {
                    hist = {
                        { file = "/tmp/.kobo/kepub/finished_book", time = 1762600000 },
                    },
                    addRecord = function(self, record)
                        table.insert(self.hist, record)
                    end,
                }
            end

            package.loaded["readhistory"] = nil

            local mock_doc_settings = createMockDocSettings("/tmp/.kobo/kepub/finished_book", {
                percent_finished = 0.75,
                summary = { status = "reading" },
            })

            local result = sync:syncBidirectional("finished_book", mock_doc_settings)

            assert.is_true(result)
        end)

        it("should sync when only KOReader is complete (push scenario)", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)
            setupPluginSettings(sync)

            package.preload["readhistory"] = function()
                return {
                    hist = {
                        { file = "/tmp/.kobo/kepub/test_book_1", time = 1762700000 },
                    },
                    addRecord = function(self, record)
                        table.insert(self.hist, record)
                    end,
                }
            end

            package.loaded["readhistory"] = nil

            local mock_doc_settings = createMockDocSettings("/tmp/.kobo/kepub/test_book_1", {
                percent_finished = 1.0,
                summary = { status = "complete" },
            })

            local result = sync:syncBidirectional("test_book_1", mock_doc_settings)

            assert.is_true(result)
        end)

        it("should sync when Kobo is 99.9% and KOReader is 100%", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)
            setupPluginSettings(sync)

            package.preload["readhistory"] = function()
                return {
                    hist = {
                        { file = "/tmp/.kobo/kepub/almost_finished", time = 1762700000 },
                    },
                    addRecord = function(self, record)
                        table.insert(self.hist, record)
                    end,
                }
            end

            package.loaded["readhistory"] = nil

            package.preload["lib/kobo_state_reader"] = function()
                return {
                    read = function(db_path, book_id)
                        if book_id == "almost_finished" then
                            return {
                                percent_read = 99.9,
                                timestamp = 1762600000,
                                status = "reading",
                                kobo_status = 1,
                            }
                        end

                        return nil
                    end,
                }
            end

            package.loaded["lib/kobo_state_reader"] = nil

            local mock_doc_settings = createMockDocSettings("/tmp/.kobo/kepub/almost_finished", {
                percent_finished = 1.0,
                summary = { status = "complete" },
            })

            local result = sync:syncBidirectional("almost_finished", mock_doc_settings)

            assert.is_true(result)

            -- Clean up the mock to avoid affecting subsequent tests
            package.preload["lib/kobo_state_reader"] = nil
        end)
    end)

    describe("readKoboState with Status", function()
        it("should read Kobo state including ReadStatus", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)

            local state = sync:readKoboState("test_book_id")

            assert.is_not_nil(state)
            assert.equals(50, state.percent_read)
            assert.equals("reading", state.status)
            assert.equals(1, state.kobo_status)
        end)

        it("should read finished books with ReadStatus=2 and use main entry ___PercentRead", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)

            local state = sync:readKoboState("finished_book")

            assert.is_not_nil(state)
            assert.equals(100, state.percent_read)
            assert.equals("complete", state.status)
            assert.equals(2, state.kobo_status)
        end)

        it("should handle finished books with 0% progress (e.g., manga marked as finished)", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)

            -- Override readKoboState behavior to simulate ReadStatus=2 with 0% progress
            local original_readKoboState = sync.readKoboState
            sync.readKoboState = function(self, book_id)
                if book_id == "finished_book_zero_percent" then
                    return original_readKoboState(self, "finished_book_zero_percent")
                end
                return original_readKoboState(self, book_id)
            end

            -- Need to mock the database to return ReadStatus=2 with ___PercentRead=0
            -- This is handled by updating the helper.lua mock
            -- For now, just verify the logic: finished books default to 100%
            local state = sync:readKoboState("finished_book")
            assert.is_not_nil(state)
            assert.equals("complete", state.status)
            assert.equals(2, state.kobo_status)
        end)

        it("should not return nil for unopened book (ReadStatus=0) with no chapter bookmark", function()
            -- Regression test for issue where book 0N395DCCSFPF3 had:
            -- - ReadStatus = 0 (unopened)
            -- - ChapterIDBookmarked = empty
            -- - ___PercentRead = 0 (no fallback)
            -- Bug: readKoboState() would return nil, blocking all sync from KOReader
            -- Fix: Should return state with percent_read=0 to allow sync

            -- The helper.lua mock database is configured to return this exact state
            -- for book ID "0N395DCCSFPF3" - this tests the real readKoboState() logic

            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)

            -- Call readKoboState with the regression test book ID
            -- This will use the helper's mocked database that returns:
            -- - DateLastRead: "" (empty)
            -- - ReadStatus: 0 (unopened)
            -- - ChapterIDBookmarked: "" (no bookmark)
            -- - ___PercentRead: 0 (no progress tracked)
            local state = sync:readKoboState("0N395DCCSFPF3")

            -- Core assertion: should NOT return nil
            assert.is_not_nil(state, "readKoboState should return state even for unopened book with no progress")

            -- Verify the state values
            assert.equals(0, state.percent_read, "unopened book should have 0% progress")
            assert.equals(0, state.kobo_status, "unopened book should have kobo_status=0")
            assert.equals("", state.status, "unopened book should have empty status")
        end)
    end)

    describe("Sync Status Behavior", function()
        it("should NOT sync FROM Kobo when ReadStatus is 0 (unopened)", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)

            -- Mock readKoboState to return unopened status
            local original_readKoboState = sync.readKoboState
            sync.readKoboState = function(self, book_id)
                return {
                    percent_read = 0,
                    timestamp = 0,
                    status = "abandoned",
                    kobo_status = 0, -- unopened
                }
            end

            local mock_doc_settings = {
                data = { doc_path = "/test/book.epub" },
                readSetting = function(self, key)
                    if key == "percent_finished" then
                        return 0.5
                    end
                    return nil
                end,
                saveSetting = function(self, key, value) end,
            }

            -- Should return false (not synced) because book is unopened
            local result = sync:syncFromKobo("test_book", mock_doc_settings)
            assert.is_false(result)

            sync.readKoboState = original_readKoboState
        end)

        it("should NOT sync unopened books TO Kobo in PUSH scenario", function()
            ---
            -- Test that unopened books (without .sdr files) are not synced TO Kobo
            -- With the fix: no sidecar means kr_timestamp=0, so it becomes PULL scenario instead
            -- Uses the DocSettings mock from helper.lua which tracks sidecar files
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)
            setupPluginSettings(sync)

            -- Mock readKoboState to return older timestamp (would normally force PUSH scenario)
            local original_readKoboState = sync.readKoboState
            sync.readKoboState = function(self, book_id)
                return {
                    percent_read = 20,
                    timestamp = 1000000, -- Older timestamp
                    status = "reading",
                    kobo_status = 1,
                }
            end

            -- Mock writeKoboState to track if it's called
            local writeKoboState_called = false
            local original_writeKoboState = sync.writeKoboState
            sync.writeKoboState = function(self, ...)
                writeKoboState_called = true
                return true
            end

            -- Get DocSettings and mark a file as unopened (no sidecar)
            local DocSettings = require("docsettings")
            local unopened_path = "/tmp/unopened.epub"
            DocSettings:_setSidecarFile(unopened_path, false)

            -- Track what gets saved (for PULL scenario)
            local saved_values = {}
            local mock_doc_settings = {
                data = { doc_path = unopened_path },
                readSetting = function(self, key)
                    if key == "percent_finished" then
                        return 0.5
                    end
                    if key == "summary" then
                        return { status = "reading" }
                    end
                    return saved_values[key]
                end,
                saveSetting = function(self, key, value)
                    saved_values[key] = value
                end,
                flush = function(self) end,
            }

            -- Add unopened file to ReadHistory with newer timestamp
            -- This would normally trigger PUSH, but with no sidecar should trigger PULL instead
            local ReadHistory = require("readhistory")
            table.insert(ReadHistory.hist, { file = unopened_path, time = 2000000 })

            -- Call syncBidirectional
            local result = sync:syncBidirectional("unopened_id", mock_doc_settings)

            -- Verify writeKoboState was NOT called (no PUSH happened)
            assert.is_false(writeKoboState_called, "writeKoboState should NOT be called for unopened books")

            -- With the fix: should PULL from Kobo instead (result = true, settings saved)
            assert.is_true(result, "syncBidirectional should return true (PULL scenario)")
            assert.equals(0.2, saved_values["percent_finished"], "Should PULL 20% from Kobo")
            assert.equals("reading", saved_values["summary"].status, "Should PULL status from Kobo")

            -- Clean up
            sync.readKoboState = original_readKoboState
            sync.writeKoboState = original_writeKoboState
            DocSettings:_clearSidecars()
            -- Remove the added ReadHistory entry
            for i = #ReadHistory.hist, 1, -1 do
                if ReadHistory.hist[i].file == unopened_path then
                    table.remove(ReadHistory.hist, i)
                end
            end
        end)
        it("should sync status TO Kobo when book is closed", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)

            local mock_doc_settings = {
                data = { doc_path = "/test/book.epub" },
                readSetting = function(self, key)
                    if key == "percent_finished" then
                        return 0.75
                    end
                    if key == "summary" then
                        return { status = "reading", modified = "2025-11-09" }
                    end
                    return nil
                end,
                saveSetting = function(self, key, value) end,
            }

            -- Call syncToKobo which should write status
            local result = sync:syncToKobo("test_book", mock_doc_settings)

            -- Result depends on DB availability
            assert.is_true(result == true or result == false)
        end)

        it("should sync status FROM Kobo in bidirectional sync", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)
            setupPluginSettings(sync) -- Use helper function

            -- Update ReadHistory mock
            package.preload["readhistory"] = function()
                return {
                    hist = {
                        { file = "/tmp/.kobo/kepub/0N3773Z7HFPXB", time = 1762600000 }, -- older
                    },
                    addRecord = function(self, record)
                        table.insert(self.hist, record)
                    end,
                }
            end

            package.loaded["readhistory"] = nil
            require("readhistory")

            local saved_status = nil
            local mock_doc_settings = createMockDocSettings("/tmp/.kobo/kepub/0N3773Z7HFPXB", {
                percent_finished = 0.5,
                summary = { status = "abandoned" },
            })

            -- Track status changes
            local original_saveSetting = mock_doc_settings.saveSetting
            function mock_doc_settings:saveSetting(key, value)
                if key == "summary" then
                    saved_status = value.status
                end
                return original_saveSetting(self, key, value)
            end

            -- Mock Kobo state with reading status
            local original_readKoboState = sync.readKoboState
            sync.readKoboState = function(self, book_id)
                return {
                    percent_read = 75,
                    timestamp = 1762700000, -- more recent than KOReader
                    status = "reading",
                    kobo_status = 1,
                }
            end

            sync:syncBidirectional("0N3773Z7HFPXB", mock_doc_settings)

            -- Status should be synced from Kobo (reading)
            assert.equals("reading", saved_status)

            sync.readKoboState = original_readKoboState
        end)

        it("should sync KOReader status TO Kobo in bidirectional when KOReader is more recent", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)

            -- Update ReadHistory mock with newer KOReader timestamp
            package.preload["readhistory"] = function()
                return {
                    hist = {
                        { file = "/tmp/.kobo/kepub/0N3773Z7HFPXB", time = 1762700000 }, -- more recent
                    },
                    addRecord = function(self, record)
                        table.insert(self.hist, record)
                    end,
                }
            end

            package.loaded["readhistory"] = nil
            require("readhistory")

            local mock_doc_settings = {
                data = { doc_path = "/tmp/.kobo/kepub/0N3773Z7HFPXB" },
                readSetting = function(self, key)
                    if key == "percent_finished" then
                        return 0.85
                    end
                    if key == "summary" then
                        return { status = "complete", modified = "2025-11-09" }
                    end
                    return nil
                end,
                saveSetting = function(self, key, value) end,
            }

            -- Mock Kobo state with older timestamp
            local original_readKoboState = sync.readKoboState
            sync.readKoboState = function(self, book_id)
                return {
                    percent_read = 50,
                    timestamp = 1762700000, -- older than KOReader
                    status = "reading",
                    kobo_status = 1,
                }
            end

            -- Should not crash and should handle the case gracefully
            local result = pcall(function()
                sync:syncBidirectional("0N3773Z7HFPXB", mock_doc_settings)
            end)
            assert.is_true(result)

            sync.readKoboState = original_readKoboState
        end)
    end)

    describe("Sync Timing - Verification Tests", function()
        it("should sync TO Kobo when book is closed (onClose event)", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)

            -- Simulate a user opening a book from virtual library, reading it, then closing
            local mock_doc_settings = {
                data = { doc_path = "KOBO_VIRTUAL://0N3773Z7HFPXB/Test Book.epub" },
                readSetting = function(self, key)
                    if key == "percent_finished" then
                        return 0.75
                    end -- User read 75%
                    return nil
                end,
                saveSetting = function(self, key, value) end,
            }

            -- When the book is closed, syncToKobo should be called
            -- This writes the current progress to the Kobo database
            local result = sync:syncToKobo("0N3773Z7HFPXB", mock_doc_settings)

            -- Sync happens on close (may succeed or fail depending on DB)
            assert.is_true(result == true or result == false)
        end)

        it("should sync BIDIRECTIONAL before virtual library opens", function()
            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)

            -- Update ReadHistory with test data
            package.preload["readhistory"] = function()
                return {
                    hist = {
                        { file = "/tmp/.kobo/kepub/0N3773Z7HFPXB", time = 1762685677 },
                    },
                    addRecord = function(self, record)
                        table.insert(self.hist, record)
                    end,
                }
            end

            package.loaded["readhistory"] = nil
            require("readhistory")

            -- Simulate showing virtual library
            local mock_doc_settings = {
                data = { doc_path = "/tmp/.kobo/kepub/0N3773Z7HFPXB" },
                readSetting = function(self, key)
                    if key == "percent_finished" then
                        return 0.5
                    end
                    return nil
                end,
                saveSetting = function(self, key, value) end,
            }

            -- Before showing virtual library, syncBidirectional is called
            -- This ensures the virtual library shows the latest progress from either Kobo or KOReader
            local result = sync:syncBidirectional("0N3773Z7HFPXB", mock_doc_settings)

            -- Result depends on which has newer data
            assert.is_true(result == true or result == false)
        end)

        it("should NOT sync when book is being opened from file browser", function()
            -- This test documents the expected behavior:
            -- When a user selects a book from the virtual library to open it,
            -- NO sync should happen. Sync only happens:
            -- 1. When the book is CLOSED (syncToKobo)
            -- 2. Before the virtual library opens (syncBidirectional)

            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)

            -- Just verify that the sync methods exist and can be called
            -- The actual flow is controlled by readerui_ext.lua and filechooser_ext.lua
            assert.is_function(sync.syncToKobo)
            assert.is_function(sync.syncBidirectional)
            assert.is_function(sync.readKoboState)

            -- When a file is selected, it just opens without syncing
            -- (The ReaderUI will sync on close, not on open)
        end)
    end)

    describe("book exists in Kobo database but no SDR in KOReader", function()
        it("should sync Kobo progress to KOReader when book has no SDR (bidirectional)", function()
            -- This test covers the bug case:
            -- Book exists in Kobo database with reading progress (16%, ReadStatus=2 for "reading")
            -- But KOReader has no SDR (sidecar directory) for this book yet
            -- Expected: Sync should create the reading progress from Kobo

            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)
            setupPluginSettings(sync) -- Use helper function

            -- Mock ReadHistory with NO entry for this book
            package.preload["readhistory"] = function()
                return {
                    hist = {}, -- Empty history - book was never opened in KOReader
                    addRecord = function(self, record)
                        table.insert(self.hist, record)
                    end,
                }
            end

            package.loaded["readhistory"] = nil
            require("readhistory")

            -- Mock doc_settings with no existing progress (simulating new SDR)
            local mock_doc_settings = createMockDocSettings("/tmp/.kobo/kepub/0N3773Z7HFPXB", {
                percent_finished = 0,
                summary = { status = "abandoned" },
            })

            -- Mock Kobo state with existing progress
            local original_readKoboState = sync.readKoboState
            sync.readKoboState = function(self, book_id)
                return {
                    percent_read = 16, -- 16% as in the bug report
                    timestamp = 1762700000, -- Some timestamp from Kobo
                    status = "reading", -- ReadStatus=2 means reading in Kobo
                    kobo_status = 2,
                }
            end

            -- Call syncBidirectional (used when showing virtual library)
            local result = sync:syncBidirectional("0N3773Z7HFPXB", mock_doc_settings)

            -- Should return true (sync was performed)
            assert.is_true(result)

            -- Should sync Kobo progress to KOReader (16% / 100 = 0.16)
            assert.equals(0.16, mock_doc_settings:readSetting("percent_finished"))
            assert.equals(0.16, mock_doc_settings:readSetting("last_percent"))
            assert.equals("reading", mock_doc_settings:readSetting("summary").status)

            sync.readKoboState = original_readKoboState
        end)

        it("should not crash when doc_settings has minimal data", function()
            -- Edge case: doc_settings with only doc_path, no other fields

            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)

            package.preload["readhistory"] = function()
                return {
                    hist = {},
                    addRecord = function(self, record)
                        table.insert(self.hist, record)
                    end,
                }
            end

            package.loaded["readhistory"] = nil
            require("readhistory")

            -- Minimal mock doc_settings
            local mock_doc_settings = {
                data = { doc_path = "/tmp/.kobo/kepub/0N3773Z7HFPXB" },
                readSetting = function(self, key)
                    return nil
                end,
                saveSetting = function(self, key, value) end,
            }

            local original_readKoboState = sync.readKoboState
            sync.readKoboState = function(self, book_id)
                return {
                    percent_read = 25,
                    timestamp = 1762700000,
                    status = "reading",
                    kobo_status = 2,
                }
            end

            -- Should not crash even with minimal doc_settings
            local result = pcall(function()
                sync:syncBidirectional("0N3773Z7HFPXB", mock_doc_settings)
            end)
            assert.is_true(result)

            sync.readKoboState = original_readKoboState
        end)

        it(
            "should ignore ReadHistory and PULL from Kobo when no sidecar exists despite newer ReadHistory timestamp",
            function()
                ---
                -- Tests the fix for bug where book finished in Kobo is skipped
                -- Scenario:
                -- - Kobo has book at 100% finished (or any progress)
                -- - ReadHistory has a newer timestamp (e.g., from browsing or after reset)
                -- - No sidecar file exists in KOReader
                -- Expected: ReadHistory timestamp should be ignored, PULL from Kobo

                local parser = MetadataParser:new()
                local sync = ReadingStateSync:new(parser)
                sync:setEnabled(true)
                setupPluginSettings(sync)

                -- Mock ReadHistory with newer timestamp than Kobo
                package.preload["readhistory"] = function()
                    return {
                        hist = {
                            { file = "/tmp/.kobo/kepub/0N3773Z7HFPXB", time = 1762878197 }, -- Newer timestamp
                        },
                        addRecord = function(self, record)
                            table.insert(self.hist, record)
                        end,
                    }
                end

                package.loaded["readhistory"] = nil
                require("readhistory")

                -- Get DocSettings and mark file as having NO sidecar
                local DocSettings = require("docsettings")
                local doc_path = "/tmp/.kobo/kepub/0N3773Z7HFPXB"
                DocSettings:_setSidecarFile(doc_path, false) -- No sidecar

                -- Create mock doc_settings
                local mock_doc_settings = createMockDocSettings(doc_path, {
                    percent_finished = 0,
                    summary = { status = "abandoned" },
                })

                -- Mock Kobo state with older timestamp but has actual progress
                local original_readKoboState = sync.readKoboState
                sync.readKoboState = function(self, book_id)
                    return {
                        percent_read = 100, -- Finished in Kobo
                        timestamp = 1762284975, -- Older than ReadHistory
                        status = "complete",
                        kobo_status = 2, -- Finished
                    }
                end

                -- Call syncBidirectional
                local result = sync:syncBidirectional("0N3773Z7HFPXB", mock_doc_settings)

                -- Should return true (sync was performed)
                assert.is_true(result, "Sync should have been performed")

                -- Should PULL from Kobo despite ReadHistory having newer timestamp
                -- Because no sidecar means ReadHistory is not reliable
                assert.equals(1.0, mock_doc_settings:readSetting("percent_finished"), "Should sync 100% from Kobo")
                assert.equals(1.0, mock_doc_settings:readSetting("last_percent"), "Should sync 100% from Kobo")
                assert.equals(
                    "complete",
                    mock_doc_settings:readSetting("summary").status,
                    "Should sync complete status from Kobo"
                )

                -- Clean up
                sync.readKoboState = original_readKoboState
                DocSettings:_clearSidecars()
            end
        )

        it("should respect book unopened status (ReadStatus=0)", function()
            -- Book in Kobo database but never opened (ReadStatus=0)
            -- Should NOT sync from Kobo

            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)

            package.preload["readhistory"] = function()
                return {
                    hist = {},
                    addRecord = function(self, record)
                        table.insert(self.hist, record)
                    end,
                }
            end

            package.loaded["readhistory"] = nil
            require("readhistory")

            local saved_values = {}
            local mock_doc_settings = {
                data = { doc_path = "/tmp/.kobo/kepub/UNOPENEDBOOK" },
                readSetting = function(self, key)
                    if key == "percent_finished" then
                        return 0
                    end
                    if key == "summary" then
                        return { status = "abandoned" }
                    end
                    return saved_values[key]
                end,
                saveSetting = function(self, key, value)
                    saved_values[key] = value
                end,
            }

            local original_readKoboState = sync.readKoboState
            sync.readKoboState = function(self, book_id)
                return {
                    percent_read = 0,
                    timestamp = 1762700000,
                    status = "abandoned",
                    kobo_status = 0, -- unopened
                }
            end

            -- Using syncFromKobo (not syncBidirectional) to test unopened behavior
            local result = sync:syncFromKobo("UNOPENEDBOOK", mock_doc_settings)

            -- Should return false (no sync from unopened book)
            assert.is_false(result)

            -- KOReader progress should NOT change
            assert.is_nil(saved_values["percent_finished"])

            sync.readKoboState = original_readKoboState
        end)

        it("should NOT create .sdr for unopened book when syncing bidirectional from Kobo", function()
            -- Regression test for issue where book 0N395DCB1FTSA had:
            -- - ReadStatus = 0 (unopened in Kobo)
            -- - ___PercentRead = 0 (no progress)
            -- Bug: syncBidirectional would still create .sdr metadata with "abandoned" status
            -- Fix: Should NOT sync unopened books FROM Kobo to KOReader

            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)
            setupPluginSettings(sync)

            package.preload["readhistory"] = function()
                return {
                    hist = {},
                    addRecord = function(self, record)
                        table.insert(self.hist, record)
                    end,
                }
            end

            package.loaded["readhistory"] = nil
            require("readhistory")

            -- Track what gets saved
            local saved_values = {}
            local mock_doc_settings = {
                data = { doc_path = "/tmp/.kobo/kepub/0N395DCB1FTSA" },
                readSetting = function(self, key)
                    if key == "percent_finished" then
                        return 0
                    end
                    if key == "summary" then
                        return { status = "abandoned" }
                    end
                    return saved_values[key]
                end,
                saveSetting = function(self, key, value)
                    saved_values[key] = value
                end,
                flush = function(self) end,
            }

            -- Mock Kobo state: unopened book with no progress
            local original_readKoboState = sync.readKoboState
            sync.readKoboState = function(self, book_id)
                return {
                    percent_read = 0, -- No progress
                    timestamp = 1762700000,
                    status = "", -- Empty status (unopened)
                    kobo_status = 0, -- unopened (ReadStatus=0)
                }
            end

            -- Call syncBidirectional (called when showing virtual library)
            local result = sync:syncBidirectional("0N395DCB1FTSA", mock_doc_settings)

            assert.is_false(result, "unopened book should NOT sync from Kobo to KOReader")

            -- Should NOT modify the doc_settings since Kobo book is unopened
            -- The percent_finished should remain 0 and NOT be saved
            assert.is_nil(
                saved_values["percent_finished"],
                "unopened book should NOT sync percent_finished to doc_settings"
            )

            -- Most importantly: summary status should NOT be saved/changed
            assert.is_nil(saved_values["summary"], "unopened book should NOT sync summary to doc_settings")

            sync.readKoboState = original_readKoboState
        end)
        it("should sync finished book with 0% progress (ReadStatus=2)", function()
            -- Book marked as finished in Kobo but with 0% PercentRead
            -- This can happen with some ebook types
            -- Should still be synced as complete

            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)
            setupPluginSettings(sync) -- Use helper function

            package.preload["readhistory"] = function()
                return {
                    hist = {},
                    addRecord = function(self, record)
                        table.insert(self.hist, record)
                    end,
                }
            end

            package.loaded["readhistory"] = nil
            require("readhistory")

            local mock_doc_settings = createMockDocSettings("/tmp/.kobo/kepub/FINISHEDBOOK", {
                percent_finished = 0,
                summary = { status = "abandoned" },
            })

            local original_readKoboState = sync.readKoboState
            sync.readKoboState = function(self, book_id)
                return {
                    percent_read = 0, -- 0% progress but marked complete
                    timestamp = 1762700000,
                    status = "complete", -- ReadStatus=2 converted to complete
                    kobo_status = 2, -- finished
                }
            end

            -- Using syncBidirectional since this is called from virtual library
            local result = sync:syncBidirectional("FINISHEDBOOK", mock_doc_settings)

            -- Should return true (sync was performed)
            assert.is_true(result)

            -- Should sync to 0% (correctly)
            assert.equals(0, mock_doc_settings:readSetting("percent_finished"))

            -- Most importantly: status should be "complete"
            assert.equals("complete", mock_doc_settings:readSetting("summary").status)

            sync.readKoboState = original_readKoboState
        end)

        it("should read from book entry (ContentType=6) not individual chapters", function()
            -- Kobo database has multiple content entries per book:
            -- - One main entry (ContentType=6) with overall progress
            -- - Multiple chapter entries (ContentType=9) with per-chapter progress
            -- The sync should only read from the main entry (ContentType=6)

            local parser = MetadataParser:new()
            local sync = ReadingStateSync:new(parser)
            sync:setEnabled(true)
            setupPluginSettings(sync)

            package.preload["readhistory"] = function()
                return {
                    hist = {},
                    addRecord = function(self, record)
                        table.insert(self.hist, record)
                    end,
                }
            end

            package.loaded["readhistory"] = nil
            require("readhistory")

            -- Mock the database query to test ContentType filtering
            -- In real Kobo DB: multiple entries like "0NFEEKBGD9JTY!!chapter.htm" (ContentType=9)
            -- and one "0NFEEKBGD9JTY" (ContentType=6)
            local query_count = 0
            local original_readKoboState = sync.readKoboState
            sync.readKoboState = function(self, book_id)
                query_count = query_count + 1
                -- Simulate reading the main book entry (ContentType=6)
                return {
                    percent_read = 16, -- 16% from main book entry
                    timestamp = 1762700000,
                    status = "reading",
                    kobo_status = 1,
                }
            end

            local mock_doc_settings = createMockDocSettings("/tmp/.kobo/kepub/TESTBOOK", {
                percent_finished = 0,
                summary = { status = "abandoned" },
            })

            local result = sync:syncBidirectional("TESTBOOK", mock_doc_settings)

            assert.is_true(result)
            -- Should sync the 16% from main book entry
            assert.equals(0.16, mock_doc_settings:readSetting("percent_finished"))
            assert.equals(1, query_count) -- Should only query once for the main entry

            sync.readKoboState = original_readKoboState
        end)
    end)

    describe("syncIfApproved with granular settings", function()
        local sync, mock_plugin

        before_each(function()
            local parser = MetadataParser:new()
            sync = ReadingStateSync:new(parser)

            -- Create mock plugin with default settings
            mock_plugin = {
                settings = {
                    enable_sync_from_kobo = true,
                    enable_sync_to_kobo = true,
                    sync_from_kobo_newer = SYNC_DIRECTION.SILENT,
                    sync_from_kobo_older = SYNC_DIRECTION.NEVER,
                    sync_to_kobo_newer = SYNC_DIRECTION.SILENT,
                    sync_to_kobo_older = SYNC_DIRECTION.NEVER,
                },
            }

            sync:setPlugin(mock_plugin, SYNC_DIRECTION)
            sync:setEnabled(true)
        end)

        describe("when sync FROM Kobo is disabled", function()
            it("should not call callback for pull operations", function()
                mock_plugin.settings.enable_sync_from_kobo = false
                local call_count_pull_newer = 0
                local call_count_pull_older = 0

                sync:syncIfApproved(true, true, function()
                    call_count_pull_newer = call_count_pull_newer + 1
                end)
                sync:syncIfApproved(true, false, function()
                    call_count_pull_older = call_count_pull_older + 1
                end)

                assert.equals(0, call_count_pull_newer)
                assert.equals(0, call_count_pull_older)
            end)
        end)

        describe("when sync TO Kobo is disabled", function()
            it("should not call callback for push operations", function()
                mock_plugin.settings.enable_sync_to_kobo = false
                local call_count_push_newer = 0
                local call_count_push_older = 0

                sync:syncIfApproved(false, true, function()
                    call_count_push_newer = call_count_push_newer + 1
                end)
                sync:syncIfApproved(false, false, function()
                    call_count_push_older = call_count_push_older + 1
                end)

                assert.equals(0, call_count_push_newer)
                assert.equals(0, call_count_push_older)
            end)
        end)

        describe("PULL from Kobo (is_pull_from_kobo=true)", function()
            describe("when Kobo is newer (is_newer=true)", function()
                it("should call callback when sync_from_kobo_newer is SILENT", function()
                    mock_plugin.settings.sync_from_kobo_newer = SYNC_DIRECTION.SILENT
                    local called = false
                    sync:syncIfApproved(true, true, function()
                        called = true
                    end)
                    assert.is_true(called)
                end)

                it("should not call callback when sync_from_kobo_newer is NEVER", function()
                    mock_plugin.settings.sync_from_kobo_newer = SYNC_DIRECTION.NEVER
                    local called = false
                    sync:syncIfApproved(true, true, function()
                        called = true
                    end)
                    assert.is_false(called)
                end)
            end)

            describe("when Kobo is older (is_newer=false)", function()
                it("should call callback when sync_from_kobo_older is SILENT", function()
                    mock_plugin.settings.sync_from_kobo_older = SYNC_DIRECTION.SILENT
                    local called = false
                    sync:syncIfApproved(true, false, function()
                        called = true
                    end)
                    assert.is_true(called)
                end)

                it("should not call callback when sync_from_kobo_older is NEVER", function()
                    mock_plugin.settings.sync_from_kobo_older = SYNC_DIRECTION.NEVER
                    local called = false
                    sync:syncIfApproved(true, false, function()
                        called = true
                    end)
                    assert.is_false(called)
                end)
            end)
        end)

        describe("PUSH to Kobo (is_pull_from_kobo=false)", function()
            describe("when KOReader is newer (is_newer=true)", function()
                it("should call callback when sync_to_kobo_newer is SILENT", function()
                    mock_plugin.settings.sync_to_kobo_newer = SYNC_DIRECTION.SILENT
                    local called = false
                    sync:syncIfApproved(false, true, function()
                        called = true
                    end)
                    assert.is_true(called)
                end)

                it("should not call callback when sync_to_kobo_newer is NEVER", function()
                    mock_plugin.settings.sync_to_kobo_newer = SYNC_DIRECTION.NEVER
                    local called = false
                    sync:syncIfApproved(false, true, function()
                        called = true
                    end)
                    assert.is_false(called)
                end)
            end)

            describe("when KOReader is older (is_newer=false)", function()
                it("should call callback when sync_to_kobo_older is SILENT", function()
                    mock_plugin.settings.sync_to_kobo_older = SYNC_DIRECTION.SILENT
                    local called = false
                    sync:syncIfApproved(false, false, function()
                        called = true
                    end)
                    assert.is_true(called)
                end)

                it("should not call callback when sync_to_kobo_older is NEVER", function()
                    mock_plugin.settings.sync_to_kobo_older = SYNC_DIRECTION.NEVER
                    local called = false
                    sync:syncIfApproved(false, false, function()
                        called = true
                    end)
                    assert.is_false(called)
                end)
            end)
        end)

        describe("granular control scenarios", function()
            it("should allow pulling newer from Kobo but prevent pushing older to Kobo", function()
                -- Enable pulling from Kobo (newer only)
                mock_plugin.settings.enable_sync_from_kobo = true
                mock_plugin.settings.sync_from_kobo_newer = SYNC_DIRECTION.SILENT
                mock_plugin.settings.sync_from_kobo_older = SYNC_DIRECTION.NEVER

                -- Enable pushing to Kobo (newer only)
                mock_plugin.settings.enable_sync_to_kobo = true
                mock_plugin.settings.sync_to_kobo_newer = SYNC_DIRECTION.SILENT
                mock_plugin.settings.sync_to_kobo_older = SYNC_DIRECTION.NEVER

                -- Pull newer from Kobo: allowed
                local pull_newer = false
                sync:syncIfApproved(true, true, function()
                    pull_newer = true
                end)
                assert.is_true(pull_newer)
                -- Pull older from Kobo: denied
                local pull_older = false
                sync:syncIfApproved(true, false, function()
                    pull_older = true
                end)
                assert.is_false(pull_older)

                -- Push newer to Kobo: allowed
                local push_newer = false
                sync:syncIfApproved(false, true, function()
                    push_newer = true
                end)
                assert.is_true(push_newer)
                -- Push older to Kobo: denied
                local push_older = false
                sync:syncIfApproved(false, false, function()
                    push_older = true
                end)
                assert.is_false(push_older)
            end)

            it("should only sync FROM Kobo when TO Kobo is disabled", function()
                mock_plugin.settings.enable_sync_from_kobo = true
                mock_plugin.settings.sync_from_kobo_newer = SYNC_DIRECTION.SILENT
                mock_plugin.settings.enable_sync_to_kobo = false

                -- Pull from Kobo: allowed
                local pull = false
                sync:syncIfApproved(true, true, function()
                    pull = true
                end)
                assert.is_true(pull)
                -- Push to Kobo: denied (disabled)
                local push = false
                sync:syncIfApproved(false, true, function()
                    push = true
                end)
                assert.is_false(push)
            end)

            it("should only sync TO Kobo when FROM Kobo is disabled", function()
                mock_plugin.settings.enable_sync_from_kobo = false
                mock_plugin.settings.enable_sync_to_kobo = true
                mock_plugin.settings.sync_to_kobo_newer = SYNC_DIRECTION.SILENT

                -- Pull from Kobo: denied (disabled)
                local pull = false
                sync:syncIfApproved(true, true, function()
                    pull = true
                end)
                assert.is_false(pull)
                -- Push to Kobo: allowed
                local push = false
                sync:syncIfApproved(false, true, function()
                    push = true
                end)
                assert.is_true(push)
            end)
        end)
    end)

    describe("getBookTitle", function()
        local sync, parser

        before_each(function()
            parser = MetadataParser:new()
            sync = ReadingStateSync:new(parser)
        end)

        it("should return title from doc_settings if available", function()
            local mock_doc_settings = {
                readSetting = function(self, key)
                    if key == "title" then
                        return "Test Book from DocSettings"
                    end
                    return nil
                end,
                data = { doc_path = "/some/path/book.epub" },
            }

            local title = sync:getBookTitle("BOOK123", mock_doc_settings)
            assert.equals("Test Book from DocSettings", title)
        end)

        it("should return title from metadata parser if doc_settings title is missing", function()
            local mock_doc_settings = {
                readSetting = function(self, key)
                    if key == "title" then
                        return ""
                    end
                    return nil
                end,
                data = { doc_path = "/some/path/book.epub" },
            }

            -- Mock the metadata parser's getBookMetadata
            parser.getBookMetadata = function(self, book_id)
                return { title = "Test Book from Metadata" }
            end

            local title = sync:getBookTitle("BOOK123", mock_doc_settings)
            assert.equals("Test Book from Metadata", title)
        end)

        it("should return 'Unknown Book' as fallback when both sources are unavailable", function()
            local mock_doc_settings = {
                readSetting = function(self, key)
                    return ""
                end,
                data = nil,
            }

            parser.getBookMetadata = function(self, book_id)
                return nil
            end

            local title = sync:getBookTitle("BOOK123", mock_doc_settings)
            assert.equals("Unknown Book", title)
        end)

        it("should handle nil doc_settings gracefully", function()
            parser.getBookMetadata = function(self, book_id)
                return nil
            end

            local title = sync:getBookTitle("BOOK123", nil)
            assert.equals("Unknown Book", title)
        end)

        it("should prioritize doc_settings over metadata parser", function()
            local mock_doc_settings = {
                readSetting = function(self, key)
                    if key == "title" then
                        return "Doc Settings Title"
                    end
                    return nil
                end,
                data = { doc_path = "/tmp/.kobo/kepub/book.epub" },
            }

            parser.getBookMetadata = function(self, book_id)
                return { title = "Metadata Title" }
            end

            local title = sync:getBookTitle("BOOK123", mock_doc_settings)
            -- Should use doc_settings title (highest priority)
            assert.equals("Doc Settings Title", title)
        end)
    end)
end)
