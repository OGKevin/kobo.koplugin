-- Test helper module that provides mock dependencies for all test files
-- This module sets up package.preload mocks before any tests require actual modules

-- Adjust package path to find plugin modules
package.path = package.path .. ";./plugins/kobo.koplugin/?.lua"

-- Mock gettext module
if not package.preload["gettext"] then
    package.preload["gettext"] = function()
        return function(text)
            return text -- Just return the text as-is for tests
        end
    end
end

-- Mock logger module
if not package.preload["logger"] then
    package.preload["logger"] = function()
        return {
            info = function(...) end,
            dbg = function(...) end,
            warn = function(...) end,
            err = function(...) end,
        }
    end
end

-- Mock ui/bidi module
if not package.preload["ui/bidi"] then
    package.preload["ui/bidi"] = function()
        return {
            isolateWords = function(text)
                return text
            end,
            getParagraphDirection = function(text)
                return "L"
            end,
        }
    end
end

-- Mock device module
if not package.preload["device"] then
    package.preload["device"] = function()
        local Device = {}
        function Device:isKobo()
            return os.getenv("KOBO_LIBRARY_PATH") and true or false
        end
        return Device
    end
end

-- Mock util module
if not package.preload["util"] then
    package.preload["util"] = function()
        return {
            template = function(template, vars)
                local result = template
                for k, v in pairs(vars) do
                    result = result:gsub("{" .. k .. "}", tostring(v))
                end
                return result
            end,
        }
    end
end

-- Mock ffi/util module (used for T() template function)
if not package.preload["ffi/util"] then
    package.preload["ffi/util"] = function()
        return {
            template = function(template, vars)
                local result = template
                if vars then
                    for k, v in pairs(vars) do
                        result = result:gsub("{" .. k .. "}", tostring(v))
                    end
                end
                return result
            end,
        }
    end
end

-- Mock libs/libkoreader-lfs module
if not package.preload["libs/libkoreader-lfs"] then
    package.preload["libs/libkoreader-lfs"] = function()
        -- Track file states for testing
        local file_states = {}

        local lfs = {
            ---
            -- Check if a path exists.
            -- @param path string: The file path.
            -- @return boolean: True if path exists.
            path_exists = function(path)
                if file_states[path] ~= nil then
                    return file_states[path].exists
                end
                return true
            end,

            ---
            -- Check if a path is a file.
            -- @param path string: The file path.
            -- @return boolean: True if path is a file.
            path_is_file = function(path)
                if file_states[path] ~= nil then
                    return file_states[path].is_file
                end
                return true
            end,

            ---
            -- Check if a path is a directory.
            -- @param path string: The file path.
            -- @return boolean: True if path is a directory.
            path_is_dir = function(path)
                if file_states[path] ~= nil then
                    return file_states[path].is_dir
                end
                return false
            end,

            ---
            -- Get directory/file attributes.
            -- @param path string: The file path.
            -- @param attr_name string|nil: Optional specific attribute name.
            -- @return table|string|nil: Attributes table or specific attribute value.
            dir_attributes = function(path, attr_name)
                local default_attrs = { size = 100, mode = "file" }
                if file_states[path] ~= nil then
                    local attrs = file_states[path].attributes or default_attrs
                    if attr_name then
                        return attrs[attr_name]
                    end
                    return attrs
                end
                if attr_name then
                    return default_attrs[attr_name]
                end
                return default_attrs
            end,

            ---
            -- Get file attributes (alias for dir_attributes).
            -- @param path string: The file path.
            -- @param attr_name string|nil: Optional specific attribute name.
            -- @return table|string|nil: Attributes table or specific attribute value.
            attributes = function(path, attr_name)
                if file_states[path] ~= nil then
                    -- If explicitly set to not exist, return nil
                    if file_states[path].exists == false then
                        return nil
                    end
                    local attrs = file_states[path].attributes
                    if attrs then
                        if attr_name then
                            return attrs[attr_name]
                        end
                        return attrs
                    end
                end
                -- Default behavior: file exists with default attributes
                local default_attrs = { size = 100, mode = "file", modification = 1000000000 }
                if attr_name then
                    return default_attrs[attr_name]
                end
                return default_attrs
            end,

            ---
            -- Set file state for testing.
            -- @param path string: The file path.
            -- @param state table: State containing exists, is_file, is_dir, attributes.
            _setFileState = function(path, state)
                file_states[path] = state
            end,

            ---
            -- Clear all file states for testing.
            _clearFileStates = function()
                file_states = {}
            end,
        }

        return lfs
    end
end

-- Mock io.open for file content reading
-- Store original io.open
local _original_io_open = io.open
local mock_io_files = {}

---
-- Set up mock file content for a specific path.
-- @param path string: The file path.
-- @param file_mock table: Mock file object with read() and close() methods.
local function setMockIOFile(path, file_mock)
    mock_io_files[path] = file_mock
end

---
-- Clear all mock io files.
local function clearMockIOFiles()
    mock_io_files = {}
end

---
-- Set up a mock file with valid ZIP/EPUB signature.
-- @param path string: The file path.
local function setMockEpubFile(path)
    mock_io_files[path] = {
        read = function(self, bytes)
            -- Return valid ZIP signature: PK\x03\x04
            return string.char(0x50, 0x4B, 0x03, 0x04)
        end,
        close = function(self) end,
    }
end

-- Override io.open globally
io.open = function(path, mode)
    if mock_io_files[path] then
        return mock_io_files[path]
    end
    return _original_io_open(path, mode)
end

-- Mock lua-ljsqlite3 module
if not package.preload["lua-ljsqlite3/init"] then
    -- Helper functions for query result logic
    ---
    -- Returns mock results for main book entry queries based on the query string.
    -- Used to simulate different book states (finished, unopened, reading).
    -- @param query string: The SQL query string.
    -- @return table: Mocked result rows.
    local function result_main_book_entry(query)
        if query:match("finished_book") then
            return {
                { "2025-11-08 15:30:45.000+00:00" },
                { 2 },
                { "chapter_last.html#kobo.1.1" },
                { 100 },
            }
        end

        if query:match("0N395DCCSFPF3") then
            return {
                { "" },
                { 0 },
                { "" },
                { 0 },
            }
        end

        return {
            { "2025-11-08 15:30:45.000+00:00" }, -- DateLastRead
            { 1 }, -- ReadStatus
            { "test_book_1!!chapter_5.html#kobo.1.1" }, -- ChapterIDBookmarked (chapter 5 = 50% through book)
            { 0 }, -- ___PercentRead (0 = will use chapter calculation)
        }
    end

    ---
    -- Returns mock results for chapter lookup queries.
    -- Simulates chapter lookup for a given book, or empty for regression test.
    -- Query: SELECT ContentID, ___FileOffset, ___FileSize, ___PercentRead
    -- @param query string: The SQL query string.
    -- @return table: Mocked result rows with 4 columns (ContentID, FileOffset, FileSize, PercentRead).
    local function result_chapter_lookup(query)
        if query:match("0N395DCCSFPF3") then
            return {}
        end
        return {
            { "test_book_1!!chapter_5.html" }, -- ContentID (chapter 5 is at 50% of book)
            { 50 }, -- ___FileOffset
            { 10 }, -- ___FileSize
            { 0 }, -- ___PercentRead (0% through this chapter)
        }
    end

    ---
    -- Returns mock results for chapter list queries for writeKoboState.
    -- Simulates a book with 10 chapters, each 10% of the book.
    -- @param query string: The SQL query string.
    -- @return table: Mocked result rows.
    local function result_chapter_list(query)
        return {
            {
                "test_book_1!!chapter_0.html",
                "test_book_1!!chapter_1.html",
                "test_book_1!!chapter_2.html",
                "test_book_1!!chapter_3.html",
                "test_book_1!!chapter_4.html",
                "test_book_1!!chapter_5.html",
                "test_book_1!!chapter_6.html",
                "test_book_1!!chapter_7.html",
                "test_book_1!!chapter_8.html",
                "test_book_1!!chapter_9.html",
            },
            { 0, 10, 20, 30, 40, 50, 60, 70, 80, 90 },
            { 10, 10, 10, 10, 10, 10, 10, 10, 10, 10 },
        }
    end

    ---
    -- Returns mock result for finding a specific chapter by FileOffset.
    -- Extracts the percent_read from query and returns the appropriate chapter.
    -- @param query string: The SQL query string.
    -- @return table: Mocked result with single chapter.
    local function result_chapter_by_offset(query)
        local percent_read = tonumber(query:match("___FileOffset <= ([%d%.]+)"))

        if not percent_read then
            return { {}, {}, {} }
        end

        local chapter_index = math.floor(percent_read / 10)

        if chapter_index < 0 then
            chapter_index = 0
        end

        if chapter_index > 9 then
            chapter_index = 9
        end

        local chapter_offset = chapter_index * 10

        return {
            { string.format("test_book_1!!chapter_%d.html", chapter_index) },
            { chapter_offset },
            { 10 },
        }
    end

    ---
    -- Returns mock result for getting the last chapter.
    -- @param query string: The SQL query string.
    -- @return table: Mocked result with last chapter.
    local function result_last_chapter(query)
        return {
            { "test_book_1!!chapter_9.html" },
        }
    end

    ---
    -- Returns mock result for progress calculation queries.
    -- Simulates a calculated progress percentage.
    -- @return table: Mocked result rows.
    local function result_progress_calc()
        return {
            { 50 },
        }
    end

    ---
    -- Returns a default mock result for unrecognized queries.
    -- @return table: Mocked result rows.
    local function result_default()
        return {
            { 50 },
            { "2025-11-08 15:30:45.000+00:00" },
            { 1 },
        }
    end

    ---
    -- Dispatches the query to the appropriate mock result function based on its content.
    -- @param query string: The SQL query string.
    -- @return table|boolean: Mocked result rows or true for update queries.
    local function exec_query(query)
        if query:match("SELECT DateLastRead, ReadStatus, ChapterIDBookmarked") then
            return result_main_book_entry(query)
        end

        if query:match("SELECT ContentID, ___FileOffset, ___FileSize, ___PercentRead") then
            return result_chapter_lookup(query)
        end

        if query:match("SELECT ContentID FROM content.*ContentType = 9.*ORDER BY ___FileOffset DESC LIMIT 1") then
            return result_last_chapter(query)
        end

        if query:match("SELECT ContentID, ___FileOffset, ___FileSize FROM content.*___FileOffset <=") then
            return result_chapter_by_offset(query)
        end

        if query:match("SELECT ContentID, ___FileOffset, ___FileSize FROM content") then
            return result_chapter_list(query)
        end

        if query:match("SUM%(CASE") then
            return result_progress_calc()
        end

        if query:match("UPDATE content") then
            return true
        end

        return result_default()
    end

    ---
    -- Mock implementation of the lua-ljsqlite3/init module for tests.
    -- Captures SQL queries and simulates database operations.
    -- @return table: Mocked sqlite3 API.
    package.preload["lua-ljsqlite3/init"] = function()
        -- Captured SQL statements for testing
        local sql_queries = {}
        -- Mock database state
        local mock_db_state = {
            should_fail_open = false,
            should_fail_prepare = false,
            book_rows = {},
        }

        return {
            OPEN_READONLY = 1,
            _getSqlQueries = function()
                return sql_queries
            end,
            _clearSqlQueries = function()
                sql_queries = {}
            end,
            ---
            -- Set whether database open should fail.
            -- @param should_fail boolean: True to make open() return nil.
            _setFailOpen = function(should_fail)
                mock_db_state.should_fail_open = should_fail
            end,
            ---
            -- Set whether query prepare should fail.
            -- @param should_fail boolean: True to make prepare() return nil.
            _setFailPrepare = function(should_fail)
                mock_db_state.should_fail_prepare = should_fail
            end,
            ---
            -- Set mock book rows to return from queries.
            -- @param rows table: Array of book row data.
            _setBookRows = function(rows)
                mock_db_state.book_rows = rows or {}
            end,
            ---
            -- Clear all mock database state.
            _clearMockState = function()
                mock_db_state.should_fail_open = false
                mock_db_state.should_fail_prepare = false
                mock_db_state.book_rows = {}
            end,
            open = function(path, flags)
                if mock_db_state.should_fail_open then
                    return nil
                end

                return {
                    execute = function(self, query, callback)
                        if callback then
                            callback({ ___PercentRead = 50, DateLastRead = "2025-11-08 15:30:45.000+00:00" })
                        end
                        return {}
                    end,
                    prepare = function(self, query)
                        if mock_db_state.should_fail_prepare then
                            return nil
                        end

                        local stmt = {
                            _query = query,
                            _bound_params = {},
                            _row_index = 0,
                            reset = function(stmt_self)
                                stmt_self._bound_params = {}
                                stmt_self._row_index = 0
                                return stmt_self
                            end,
                            bind = function(stmt_self, ...)
                                stmt_self._bound_params = { ... }
                                return stmt_self
                            end,
                            step = function(stmt_self)
                                table.insert(sql_queries, {
                                    query = stmt_self._query,
                                    params = stmt_self._bound_params,
                                })
                                return true
                            end,
                            rows = function(stmt_self)
                                local rows = mock_db_state.book_rows
                                local index = 0
                                return function()
                                    index = index + 1
                                    if index <= #rows then
                                        return rows[index]
                                    end
                                    return nil
                                end
                            end,
                            close = function(stmt_self) end,
                        }
                        return stmt
                    end,
                    exec = function(self, query)
                        return exec_query(query)
                    end,
                    close = function(self) end,
                }
            end,
        }
    end
end

-- Mock readhistory module
if not package.preload["readhistory"] then
    package.preload["readhistory"] = function()
        return {
            hist = {
                { file = "/test/book1.epub", time = 1699500000 },
                { file = "/test/book2.epub", time = 1699600000 },
            },
            addRecord = function(self, record)
                table.insert(self.hist, record)
            end,
        }
    end
end

-- Mock ui/uimanager module with call tracking
if not package.preload["ui/uimanager"] then
    package.preload["ui/uimanager"] = function()
        local UIManager = {
            -- Call tracking
            _show_calls = {},
            _close_calls = {},
            _broadcast_calls = {},
            -- Configurable behavior
            _show_return_value = true,
        }

        function UIManager:show(widget)
            -- Capture the call
            table.insert(self._show_calls, {
                widget = widget,
                text = widget and widget.text or nil,
            })
            -- Return configurable value
            return self._show_return_value
        end

        function UIManager:close(widget)
            table.insert(self._close_calls, { widget = widget })
        end

        function UIManager:broadcastEvent(event)
            table.insert(self._broadcast_calls, { event = event })
        end

        -- Helper to reset call tracking
        function UIManager:_reset()
            self._show_calls = {}
            self._close_calls = {}
            self._broadcast_calls = {}
            self._show_return_value = true
        end

        return UIManager
    end
end

-- Mock ui/widget/booklist module
if not package.preload["ui/widget/booklist"] then
    package.preload["ui/widget/booklist"] = function()
        local BookList = {
            book_info_cache = {},
        }
        return BookList
    end
end

-- Mock ui/widget/confirmbox module with call tracking
if not package.preload["ui/widget/confirmbox"] then
    package.preload["ui/widget/confirmbox"] = function()
        local ConfirmBox = {
            -- Track all ConfirmBox instances created
            _instances = {},
        }

        function ConfirmBox:new(args)
            local o = {
                text = args.text,
                ok_text = args.ok_text,
                cancel_text = args.cancel_text,
                ok_callback = args.ok_callback,
                cancel_callback = args.cancel_callback,
            }
            -- Track this instance
            table.insert(ConfirmBox._instances, o)
            return o
        end

        -- Helper to reset tracking
        function ConfirmBox:_reset()
            self._instances = {}
        end

        return ConfirmBox
    end
end

-- Note: metadata_parser is NOT mocked - tests use the real implementation
-- The real metadata_parser.lua uses mocked dependencies (lfs, logger, SQ3)

-- Mock ui/trapper module with call tracking
if not package.preload["ui/trapper"] then
    package.preload["ui/trapper"] = function()
        local Trapper = {
            -- Call tracking
            _confirm_calls = {},
            _info_calls = {},
            _wrap_calls = {},
            -- Configurable behavior
            _confirm_return_value = true,
            _info_return_value = true,
            _is_wrapped = true,
        }

        function Trapper:wrap(func)
            table.insert(self._wrap_calls, { func = func })
            -- In tests, just call the function directly without coroutine wrapping
            return func()
        end

        function Trapper:isWrapped()
            -- In tests, return configurable value (default true - simulate being in wrapped context)
            return self._is_wrapped
        end

        function Trapper:confirm(text, cancel_text, ok_text)
            -- Capture the call
            table.insert(self._confirm_calls, {
                text = text,
                cancel_text = cancel_text,
                ok_text = ok_text,
            })
            -- Return configurable value
            return self._confirm_return_value
        end

        function Trapper:info(text, fast_refresh, skip_dismiss_check)
            -- Capture the call
            table.insert(self._info_calls, {
                text = text,
                fast_refresh = fast_refresh,
                skip_dismiss_check = skip_dismiss_check,
            })
            -- Return configurable value
            return self._info_return_value
        end

        function Trapper:setPausedText(text, abort_text, continue_text)
            -- Store for reference but no-op in tests
        end

        function Trapper:clear()
            -- No-op in tests
        end

        -- Helper to reset call tracking
        function Trapper:_reset()
            self._confirm_calls = {}
            self._info_calls = {}
            self._wrap_calls = {}
            self._confirm_return_value = true
            self._info_return_value = true
            self._is_wrapped = true
        end

        return Trapper
    end
end

-- Mock Event module

if not package.preload["ui/event"] then
    package.preload["ui/event"] = function()
        local Event = {}
        function Event:new(name, ...)
            local e = {
                name = name,
                args = { ... },
            }
            setmetatable(e, { __index = Event })
            return e
        end
        return Event
    end
end

-- Mock DocSettings module
if not package.preload["docsettings"] then
    package.preload["docsettings"] = function()
        local DocSettings = {}

        -- Track which files have sidecars for testing
        local sidecars = {}

        -- Allow tests to register which files have sidecars
        function DocSettings:_setSidecarFile(doc_path, has_sidecar)
            sidecars[doc_path] = has_sidecar
        end

        -- Allow tests to clear sidecar registry
        function DocSettings:_clearSidecars()
            sidecars = {}
        end

        function DocSettings:hasSidecarFile(doc_path)
            -- Check if file has a registered sidecar status
            if sidecars[doc_path] ~= nil then
                return sidecars[doc_path]
            end
            -- Default: files have sidecars (most common case for tests)
            return true
        end

        function DocSettings:open(path)
            local instance = {
                data = { doc_path = path },
                _settings = {},
            }

            instance.readSetting = function(_, key)
                return instance._settings[key]
            end

            instance.saveSetting = function(_, key, value)
                instance._settings[key] = value
            end

            instance.flush = function(_)
                -- In tests, just mark as flushed but don't actually write to disk
                instance._flushed = true
            end

            setmetatable(instance, { __index = DocSettings })
            return instance
        end

        return DocSettings
    end
end

-- Helper function for tests to create mock doc_settings objects
-- Provides all necessary methods (readSetting, saveSetting, flush)
-- Path is stored in data.doc_path (matches real DocSettings API)
---
-- Helper function for tests to create mock DocSettings objects.
-- Provides all necessary methods (readSetting, saveSetting, flush).
-- Path is stored in data.doc_path (matches real DocSettings API).
-- @param doc_path string: The document path.
-- @param initial_settings table|nil: Optional initial settings.
-- @return table: Mock DocSettings object.
local function createMockDocSettings(doc_path, initial_settings)
    initial_settings = initial_settings or {}

    local mock = {
        data = { doc_path = doc_path },
        _settings = initial_settings,
    }

    function mock:readSetting(key)
        return self._settings[key]
    end

    function mock:saveSetting(key, value)
        self._settings[key] = value
    end

    function mock:flush()
        self._flushed = true
    end

    return mock
end

-- Helper function to reset UI mocks between tests
local function resetUIMocks()
    -- Get the mocked modules
    local UIManager = require("ui/uimanager")
    local ConfirmBox = require("ui/widget/confirmbox")
    local Trapper = require("ui/trapper")

    -- Reset their call tracking
    if UIManager._reset then
        UIManager:_reset()
    end
    if ConfirmBox._reset then
        ConfirmBox:_reset()
    end
    if Trapper._reset then
        Trapper:_reset()
    end
end

return {
    createMockDocSettings = createMockDocSettings,
    resetUIMocks = resetUIMocks,
    setMockIOFile = setMockIOFile,
    clearMockIOFiles = clearMockIOFiles,
    setMockEpubFile = setMockEpubFile,
}
