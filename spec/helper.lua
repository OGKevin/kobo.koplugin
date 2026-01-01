-- Test helper module that provides mock dependencies for all test files
-- This module sets up package.preload mocks before any tests require actual modules

-- Remove luarocks searcher to prevent it from trying to load packages
if package.searchers ~= nil then
    for i = #package.searchers, 1, -1 do
        local searcher_info = debug.getinfo(package.searchers[i], "S")
        if searcher_info and searcher_info.source and searcher_info.source:match("luarocks") then
            table.remove(package.searchers, i)
        end
    end
end

-- Adjust package path to find plugin modules
package.path = package.path .. ";./plugins/kobo.koplugin/?.lua"

-- Global declarations for mock helper functions (used by tests)
_G.setMockExecuteResult = nil
_G.setMockPopenOutput = nil
_G.setMockPopenFailure = nil
_G.resetAllMocks = nil
_G.getExecutedCommands = nil
_G.clearExecutedCommands = nil
_G.setMockRunInSubProcessResult = nil
_G.getMockRunInSubProcessCallback = nil

-- Global mocks for shell execution (used by multiple modules)
local _mock_os_execute_result = 0
local _mock_io_popen_output = ""
local _executed_commands = {}

-- Use _G for subprocess mocks to ensure preload functions can access them
_G._mock_run_in_subprocess_result = _G._mock_run_in_subprocess_result or 12345
_G._mock_run_in_subprocess_callback = _G._mock_run_in_subprocess_callback
-- Mock os.execute for shell commands
os.execute = function(cmd)
    table.insert(_executed_commands, cmd)

    -- Auto-flip Bluetooth state when turnOn/turnOff commands succeed
    if _mock_os_execute_result == 0 then
        if cmd:match("Powered%s+variant:boolean:true") then
            _mock_io_popen_output = "variant boolean true"
        elseif cmd:match("Powered%s+variant:boolean:false") then
            _mock_io_popen_output = "variant boolean false"
        end
    end

    return _mock_os_execute_result
end

-- Mock io.popen for command output
io.popen = function(cmd)
    local mock_file = {
        read = function(self, format)
            return _mock_io_popen_output
        end,
        close = function(self) end,
    }
    return mock_file
end

-- Helper function to set mock execution results for tests
function setMockExecuteResult(result)
    _mock_os_execute_result = result
end

_G.setMockExecuteResult = setMockExecuteResult

-- Helper function to set mock popen output for tests
function setMockPopenOutput(output)
    _mock_io_popen_output = output
end

_G.setMockPopenOutput = setMockPopenOutput

-- Helper function to simulate popen failure
function setMockPopenFailure()
    _mock_io_popen_output = nil
end

_G.setMockPopenFailure = setMockPopenFailure

-- Helper function to reset all mocks to default state
function resetAllMocks()
    _mock_os_execute_result = 0
    _mock_io_popen_output = "variant boolean true"
    _executed_commands = {}
    _G._mock_run_in_subprocess_result = 12345
    _G._mock_run_in_subprocess_callback = nil
end

_G.resetAllMocks = resetAllMocks

-- Helper function to get all executed commands
function getExecutedCommands()
    return _executed_commands
end

_G.getExecutedCommands = getExecutedCommands

-- Helper function to clear executed commands
function clearExecutedCommands()
    _executed_commands = {}
end

_G.clearExecutedCommands = clearExecutedCommands

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

-- Mock datastorage module
if not package.preload["datastorage"] then
    package.preload["datastorage"] = function()
        return {
            getDocSettingsDir = function()
                return "/mnt/onboard/.kobo/koreader/docsettings"
            end,
            getDocSettingsHashDir = function()
                return "/mnt/onboard/.kobo/koreader/hash"
            end,
            getSettingsDir = function()
                return "/mnt/onboard/.kobo/koreader"
            end,
        }
    end
end

-- Mock G_reader_settings global
if not _G.G_reader_settings then
    _G.G_reader_settings = {
        _settings = {},
        readSetting = function(self, key)
            return self._settings[key]
        end,
        saveSetting = function(self, key, value)
            self._settings[key] = value
        end,
        isTrue = function(self, key)
            return self._settings[key] == true
        end,
        flush = function(self)
            -- No-op in tests
        end,
    }
end

-- Mock frontend/luasettings module
if not package.preload["frontend/luasettings"] then
    package.preload["frontend/luasettings"] = function()
        return {
            open = function()
                return _G.G_reader_settings
            end,
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
        local Device = {
            _isMTK = true, -- Default to MTK device for testing
            input = {
                -- Mock input device for event handling
                registerEventAdjustHook = function(self, hook)
                    -- Mock function - does nothing in tests
                end,
            },
        }
        function Device.isMTK()
            return Device._isMTK
        end
        function Device:isKobo()
            return os.getenv("KOBO_LIBRARY_PATH") and true or false
        end

        return Device
    end
end

-- Mock util module
if not package.preload["util"] then
    package.preload["util"] = function()
        local util = {}

        function util.template(template, vars)
            local result = template
            for k, v in pairs(vars) do
                result = result:gsub("{" .. k .. "}", tostring(v))
            end
            return result
        end

        function util.tableDeepCopy(orig)
            local copy
            if type(orig) == "table" then
                copy = {}
                for k, v in pairs(orig) do
                    copy[k] = type(v) == "table" and util.tableDeepCopy(v) or v
                end
            else
                copy = orig
            end
            return copy
        end

        function util.getFriendlySize(size)
            return tostring(size) .. " B"
        end

        function util.partialMD5(filepath)
            if not filepath then
                return nil
            end
            -- Return a mock MD5 hash for testing
            local hash = "a1b2c3d4e5f6"
            return hash
        end

        function util.splitFilePathName(filepath)
            if not filepath or type(filepath) ~= "string" then
                return "", ""
            end

            local directory = filepath:match("(.*/)")
            if directory then
                directory = directory:sub(1, -2)
                local filename = filepath:sub(#directory + 2)
                return directory, filename
            end

            return "", filepath
        end

        return util
    end
end

-- Mock for ffi/archiver module
if not package.preload["ffi/archiver"] then
    package.preload["ffi/archiver"] = function()
        local Archiver = {
            Reader = {},
        }

        -- Track mock archive states for testing
        local _mock_archive_states = {}

        ---
        -- Helper to set archive state for a specific file
        -- @param filepath string: Path to the archive file
        -- @param state table: State containing can_open, entries
        function Archiver._setArchiveState(filepath, state)
            _mock_archive_states[filepath] = state
        end

        ---
        -- Helper to clear all archive states
        function Archiver._clearArchiveStates()
            _mock_archive_states = {}
        end

        ---
        -- Creates a new Reader instance
        -- @return table: New Reader instance
        function Archiver.Reader:new()
            local reader = {
                _filepath = nil,
                _is_open = false,
                _entries = {},
            }
            setmetatable(reader, self)
            self.__index = self
            return reader
        end

        ---
        -- Opens an archive file
        -- @param filepath string: Path to the archive file
        -- @return boolean: True if opened successfully
        function Archiver.Reader:open(filepath)
            local state = _mock_archive_states[filepath]

            -- If no state is set, default to success with no entries
            if state == nil then
                state = { can_open = true, entries = {} }
            end

            if not state.can_open then
                return false
            end

            self._filepath = filepath
            self._is_open = true
            self._entries = state.entries or {}

            return true
        end

        ---
        -- Iterates over archive entries
        -- @return function: Iterator function
        function Archiver.Reader:iterate()
            if not self._is_open then
                return function()
                    return nil
                end
            end

            local index = 0
            local entries = self._entries

            return function()
                index = index + 1
                if index <= #entries then
                    return entries[index]
                end
                return nil
            end
        end

        ---
        -- Extracts an entry to memory
        -- @param key number|string: Index or path of the entry to extract
        -- @return string|nil: Content of the entry
        function Archiver.Reader:extractToMemory(key)
            if not self._is_open then
                return nil
            end

            for _, entry in ipairs(self._entries) do
                if entry.index == key or entry.path == key then
                    return entry.content or ""
                end
            end

            return nil
        end

        ---
        -- Closes the archive
        function Archiver.Reader:close()
            self._is_open = false
            self._filepath = nil
            self._entries = {}
        end

        -- Writer mock for creating archives
        Archiver.Writer = {}

        ---
        -- Creates a new Writer instance
        -- @return table: New Writer instance
        function Archiver.Writer:new()
            local writer = {
                _filepath = nil,
                _is_open = false,
                _written_files = {},
            }
            setmetatable(writer, self)
            self.__index = self
            return writer
        end

        ---
        -- Opens an archive for writing
        -- @param filepath string: Path where archive will be created
        -- @param format string: Archive format (e.g., "zip")
        -- @return boolean: True if opened successfully
        function Archiver.Writer:open(filepath, format)
            self._filepath = filepath
            self._is_open = true
            self._format = format
            return true
        end

        ---
        -- Adds a file from memory to the archive
        -- @param entry_path string: Path of the entry in the archive
        -- @param content string: Content of the file
        -- @param mtime number: Optional modification time
        -- @return boolean: True if successful
        function Archiver.Writer:addFileFromMemory(entry_path, content, mtime)
            if not self._is_open then
                return false
            end

            table.insert(self._written_files, {
                path = entry_path,
                content = content,
                mtime = mtime,
            })

            return true
        end

        ---
        -- Closes the writer and finalizes the archive
        function Archiver.Writer:close()
            if not self._is_open then
                return
            end

            -- In test mode, write files using zip command
            if self._format == "zip" and self._filepath then
                -- Create temp directory for files
                local temp_dir = os.tmpname()
                os.remove(temp_dir)
                os.execute("mkdir -p " .. temp_dir)

                -- Write each file to temp directory
                for _, file_info in ipairs(self._written_files) do
                    local file_dir = temp_dir .. "/" .. file_info.path:match("(.*/)")
                    if file_dir then
                        os.execute("mkdir -p " .. file_dir)
                    end

                    local temp_file_path = temp_dir .. "/" .. file_info.path
                    local f = io.open(temp_file_path, "wb")
                    if f then
                        f:write(file_info.content)
                        f:close()
                    end
                end

                -- Create zip archive
                os.execute(string.format("cd %s && zip -r -q %q .", temp_dir, self._filepath))

                -- Clean up temp directory
                os.execute("rm -rf " .. temp_dir)
            end

            self._is_open = false
            self._filepath = nil
            self._written_files = {}
        end

        return Archiver
    end
end

-- Mock ffi/zstd module (zstandard compression)
if not package.preload["ffi/zstd"] then
    package.preload["ffi/zstd"] = function()
        ---
        --- Compress data using zstd (mock implementation returns identity compression).
        --- @param data userdata|string: Data pointer or string to compress.
        --- @param size number: Size of data to compress.
        --- @return userdata: Compressed data pointer (mock: returns original data).
        --- @return number: Size of compressed data (mock: returns original size).
        local function zstd_compress(data, size)
            -- In real implementation, this would compress using zstd C library
            -- For testing, we just return the data as-is (identity compression)
            -- This is sufficient for testing database writing logic
            return data, size
        end

        ---
        --- Decompress zstd data (mock implementation returns identity decompression).
        --- @param data userdata|string: Compressed data pointer.
        --- @param size number: Size of compressed data.
        --- @return userdata: Decompressed data pointer.
        --- @return number: Size of decompressed data.
        local function zstd_uncompress(data, size)
            return data, size
        end

        return {
            zstd_compress = zstd_compress,
            zstd_uncompress = zstd_uncompress,
            zstd_uncompress_ctx = zstd_uncompress,
        }
    end
end

-- Mock ffi/util module (used for T() template function and subprocess)
local function setMockRunInSubProcessResult(result)
    _G._mock_run_in_subprocess_result = result
end

_G.setMockRunInSubProcessResult = setMockRunInSubProcessResult

local function getMockRunInSubProcessCallback()
    return _G._mock_run_in_subprocess_callback
end

_G.getMockRunInSubProcessCallback = getMockRunInSubProcessCallback
if not package.preload["ffi/util"] then
    package.preload["ffi/util"] = function()
        return {
            template = function(template_str, ...)
                local args = { ... }

                if #args == 0 then
                    return template_str
                end

                local result = template_str

                -- Handle %1, %2, etc. replacements
                for i, value in ipairs(args) do
                    result = result:gsub("%%(" .. i .. ")", tostring(value))
                end

                return result
            end,
            sleep = function(seconds)
                -- Mock sleep function for tests - does nothing
            end,
            runInSubProcess = function(func, with_pipe, double_fork)
                _G._mock_run_in_subprocess_callback = func

                -- Execute the subprocess function immediately in test mode
                -- This allows D-Bus commands and other subprocess operations to be tracked
                if func and type(func) == "function" then
                    func()
                end

                return _G._mock_run_in_subprocess_result
            end,
        }
    end
end

-- Mock ffi/posix_h module (FFI bindings not available in test environment)
if not package.preload["ffi/posix_h"] then
    package.preload["ffi/posix_h"] = function()
        -- Stub - actual FFI declarations are not needed in tests
        return {}
    end
end

-- Mock ffi/linux_input_h module (FFI bindings not available in test environment)
if not package.preload["ffi/linux_input_h"] then
    package.preload["ffi/linux_input_h"] = function()
        -- Stub - actual FFI declarations are not needed in tests
        return {}
    end
end

-- Mock src/lib/bluetooth/dbus_monitor module (uses FFI)
if not package.preload["src/lib/bluetooth/dbus_monitor"] then
    package.preload["src/lib/bluetooth/dbus_monitor"] = function()
        local MockDbusMonitor = {
            is_active = false,
            property_callbacks = {}, -- key -> {callback = function, priority = number}
            sorted_callbacks = {}, -- array of {key, callback, priority} sorted by priority
        }

        function MockDbusMonitor:new()
            local instance = {
                is_active = false,
                property_callbacks = {}, -- key -> {callback = function, priority = number}
                sorted_callbacks = {}, -- array of {key, callback, priority} sorted by priority
            }
            setmetatable(instance, self)
            self.__index = self

            return instance
        end

        function MockDbusMonitor:startMonitoring()
            self.is_active = true

            return true
        end

        function MockDbusMonitor:stopMonitoring()
            self.is_active = false
        end

        function MockDbusMonitor:isActive()
            return self.is_active
        end

        function MockDbusMonitor:registerCallback(key, callback, priority)
            priority = priority or 100

            self.property_callbacks[key] = {
                callback = callback,
                priority = priority,
            }

            self:_rebuildSortedCallbacks()
        end

        function MockDbusMonitor:unregisterCallback(key)
            self.property_callbacks[key] = nil

            self:_rebuildSortedCallbacks()
        end

        function MockDbusMonitor:_rebuildSortedCallbacks()
            self.sorted_callbacks = {}

            for key, callback_info in pairs(self.property_callbacks) do
                table.insert(self.sorted_callbacks, {
                    key = key,
                    callback = callback_info.callback,
                    priority = callback_info.priority,
                })
            end

            table.sort(self.sorted_callbacks, function(a, b)
                return a.priority < b.priority
            end)
        end

        function MockDbusMonitor:getCallbackCount()
            local count = 0

            for _ in pairs(self.property_callbacks) do
                count = count + 1
            end

            return count
        end

        function MockDbusMonitor:hasCallback(key)
            return self.property_callbacks[key] ~= nil
        end

        function MockDbusMonitor:simulatePropertyChange(device_address, properties)
            -- Call callbacks in pre-sorted priority order
            for _, callback_info in ipairs(self.sorted_callbacks) do
                callback_info.callback(device_address, properties)
            end
        end

        return MockDbusMonitor
    end
end

-- Mock src/lib/bluetooth/bluetooth_input_reader module (uses FFI)
if not package.preload["src/lib/bluetooth/bluetooth_input_reader"] then
    package.preload["src/lib/bluetooth/bluetooth_input_reader"] = function()
        local MockBluetoothInputReader = {
            fd = nil,
            device_path = nil,
            is_open = false,
            callbacks = {},
        }

        function MockBluetoothInputReader:new()
            local instance = {
                fd = nil,
                device_path = nil,
                is_open = false,
                callbacks = {},
            }
            setmetatable(instance, self)
            self.__index = self

            return instance
        end

        function MockBluetoothInputReader:open(device_path)
            self.device_path = device_path
            self.is_open = true
            self.fd = 999 -- Mock file descriptor

            return true
        end

        function MockBluetoothInputReader:close()
            self.fd = nil
            self.device_path = nil
            self.is_open = false
        end

        function MockBluetoothInputReader:registerKeyCallback(callback)
            table.insert(self.callbacks, callback)
        end

        function MockBluetoothInputReader:clearCallbacks()
            self.callbacks = {}
        end

        function MockBluetoothInputReader:poll(timeout_ms)
            return nil -- No events by default
        end

        function MockBluetoothInputReader:isOpen()
            return self.is_open
        end

        function MockBluetoothInputReader:getDevicePath()
            return self.device_path
        end

        function MockBluetoothInputReader:getFd()
            return self.fd
        end

        return MockBluetoothInputReader
    end
end

-- Mock dispatcher module
if not package.preload["dispatcher"] then
    package.preload["dispatcher"] = function()
        local Dispatcher = {
            registered_actions = {},
        }

        function Dispatcher:registerAction(action_id, action_def)
            self.registered_actions[action_id] = action_def
        end

        return Dispatcher
    end
end

-- Mock ui/widget/container/widgetcontainer module
if not package.preload["ui/widget/container/widgetcontainer"] then
    package.preload["ui/widget/container/widgetcontainer"] = function()
        local WidgetContainer = {}

        function WidgetContainer:extend(subclass)
            local o = subclass or {}
            setmetatable(o, self)
            self.__index = self

            return o
        end

        function WidgetContainer:new(o)
            o = o or {}
            setmetatable(o, self)
            self.__index = self

            return o
        end

        return WidgetContainer
    end
end

-- Mock libs/libkoreader-lfs module
if not package.preload["libs/libkoreader-lfs"] then
    package.preload["libs/libkoreader-lfs"] = function()
        -- Track file states for testing
        local file_states = {}
        -- Track directory contents for testing
        local directory_contents = {}

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
            -- Iterate over directory contents.
            -- @param path string: The directory path.
            -- @return function: Iterator function that returns filenames.
            dir = function(path)
                local contents = directory_contents[path]
                if not contents then
                    -- Return empty iterator for unknown directories
                    return function()
                        return nil
                    end
                end
                local index = 0
                return function()
                    index = index + 1
                    if index <= #contents then
                        return contents[index]
                    end
                    return nil
                end
            end,

            ---
            -- Set file state for testing.
            -- @param path string: The file path.
            -- @param state table: State containing exists, is_file, is_dir, attributes.
            _setFileState = function(path, state)
                file_states[path] = state
            end,

            ---
            -- Set directory contents for testing.
            -- @param path string: The directory path.
            -- @param contents table: Array of filenames (strings).
            _setDirectoryContents = function(path, contents)
                directory_contents[path] = contents
            end,

            ---
            -- Clear all file states for testing.
            _clearFileStates = function()
                file_states = {}
                directory_contents = {}
            end,
        }

        return lfs
    end
end

-- Store original io.open before we replace it
-- IMPORTANT: Only capture the REAL io.open on first load to avoid capturing
-- previous mocker instances' mocks when createIOOpenMocker is called multiple times
local _original_io_open
if not _G._test_real_io_open then
    -- First time loading helper - capture the real io.open
    _original_io_open = io.open
    _G._test_real_io_open = _original_io_open
else
    -- Subsequent loads - use the stored real io.open
    _original_io_open = _G._test_real_io_open
end

-- Helper function to create localized io.open mocks
-- Returns a table with methods to set up and tear down mocks for specific tests
local function createIOOpenMocker()
    local mock_files = {}
    local IO_OPEN_FAIL = {} -- Sentinel value to indicate open failure
    local mock_active = false

    ---
    -- Install the io.open mock (call in before_each or test setup)
    local function install()
        if mock_active then
            return -- Already installed
        end
        mock_active = true
        io.open = function(path, mode)
            local mock_file = mock_files[path]
            if mock_file ~= nil then
                if mock_file == IO_OPEN_FAIL then
                    return nil
                end
                return mock_file
            end
            return _original_io_open(path, mode)
        end
    end

    ---
    -- Remove the io.open mock (call in after_each or test teardown)
    local function uninstall()
        if not mock_active then
            return
        end
        io.open = _original_io_open
        mock_active = false
        mock_files = {}
    end

    ---
    -- Set up mock file content for a specific path
    -- @param path string: The file path
    -- @param file_mock table: Mock file object with read() and close() methods
    local function setMockFile(path, file_mock)
        mock_files[path] = file_mock
    end

    ---
    -- Set up a mock file that fails to open (returns nil)
    -- @param path string: The file path
    local function setMockFileFailure(path)
        mock_files[path] = IO_OPEN_FAIL
    end

    ---
    -- Set up a mock file with valid ZIP/EPUB signature
    -- @param path string: The file path
    local function setMockEpubFile(path)
        mock_files[path] = {
            read = function(self, bytes)
                -- Return valid ZIP signature: PK\x03\x04
                return string.char(0x50, 0x4B, 0x03, 0x04)
            end,
            close = function(self) end,
        }
    end

    ---
    -- Clear all mock files
    local function clear()
        mock_files = {}
    end

    return {
        install = install,
        uninstall = uninstall,
        setMockFile = setMockFile,
        setMockFileFailure = setMockFileFailure,
        setMockEpubFile = setMockEpubFile,
        clear = clear,
    }
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

        local book_id = query:match("ContentID = '([^']+)'")
        if not book_id then
            book_id = "test_book_1"
        end

        return {
            { "2025-11-08 15:30:45.000+00:00" }, -- DateLastRead
            { 1 }, -- ReadStatus
            { book_id .. "!!chapter_5.html#kobo.1.1" }, -- ChapterIDBookmarked (chapter 5 = 50% through book)
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

        local book_id = query:match("ContentID LIKE '([^'%%]+)")
        if not book_id then
            book_id = "test_book_1"
        end

        return {
            { book_id .. "!!chapter_5.html" }, -- ContentID (chapter 5 is at 50% of book)
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
            content_keys = {},
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
            -- Set mock content keys for books.
            -- @param keys table: Map of book_id -> boolean indicating if keys exist.
            _setContentKeys = function(keys)
                mock_db_state.content_keys = keys or {}
            end,
            ---
            -- Clear all mock database state.
            _clearMockState = function()
                mock_db_state.should_fail_open = false
                mock_db_state.should_fail_prepare = false
                mock_db_state.book_rows = {}
                mock_db_state.content_keys = {}
            end,
            open = function(path, flags)
                if mock_db_state.should_fail_open then
                    return nil
                end

                return {
                    set_busy_timeout = function(self, timeout_ms)
                        -- No-op in tests
                    end,
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
                            bind1 = function(stmt_self, index, value)
                                stmt_self._bound_params[index] = value
                                return stmt_self
                            end,
                            clearbind = function(stmt_self)
                                stmt_self._bound_params = {}
                                return stmt_self
                            end,
                            step = function(stmt_self)
                                table.insert(sql_queries, {
                                    query = stmt_self._query,
                                    params = stmt_self._bound_params,
                                })

                                if stmt_self._query:match("FROM content_keys") then
                                    local book_id = stmt_self._bound_params[1]
                                    if mock_db_state.content_keys[book_id] then
                                        return {} -- Return empty row (truthy) when keys exist
                                    end
                                    return nil -- Return nil when no keys (DONE)
                                end

                                if stmt_self._row_index < #mock_db_state.book_rows then
                                    stmt_self._row_index = stmt_self._row_index + 1
                                    return mock_db_state.book_rows[stmt_self._row_index]
                                end
                                return nil
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
            _shown_widgets = {},
            _close_calls = {},
            _broadcast_calls = {},
            _send_event_calls = {},
            _prevent_standby_calls = 0,
            _allow_standby_calls = 0,
            _scheduled_tasks = {},
            _event_hook_calls = {},
            _unschedule_calls = {},
            -- Configurable behavior
            _show_return_value = true,
        }

        -- Event hook mock
        UIManager.event_hook = {
            execute = function(self, event_name)
                table.insert(UIManager._event_hook_calls, { event_name = event_name })
            end,
        }

        function UIManager:show(widget)
            -- Capture the call
            table.insert(self._show_calls, {
                widget = widget,
                text = widget and widget.text or nil,
            })
            -- Track shown widgets
            table.insert(self._shown_widgets, widget)
            -- Return configurable value
            return self._show_return_value
        end

        function UIManager:close(widget)
            table.insert(self._close_calls, { widget = widget })
        end

        function UIManager:broadcastEvent(event)
            table.insert(self._broadcast_calls, { event = event })
        end

        function UIManager:sendEvent(event)
            table.insert(self._send_event_calls, { event = event })
        end

        function UIManager:preventStandby()
            self._prevent_standby_calls = self._prevent_standby_calls + 1
        end

        function UIManager:allowStandby()
            self._allow_standby_calls = self._allow_standby_calls + 1
        end

        function UIManager:forceRePaint()
            -- No-op in tests
        end

        function UIManager:scheduleIn(time, callback)
            if self._scheduled_tasks == nil then
                self._scheduled_tasks = {}
            end

            local task_id = #self._scheduled_tasks + 1
            self._scheduled_tasks[task_id] = { time = time, callback = callback }

            return task_id
        end

        function UIManager:tickAfterNext(callback)
            if self._scheduled_tasks == nil then
                self._scheduled_tasks = {}
            end

            local task_id = #self._scheduled_tasks + 1
            self._scheduled_tasks[task_id] = { time = 0, callback = callback }

            return task_id
        end

        function UIManager:unschedule(task_id)
            table.insert(self._unschedule_calls, { task_id = task_id })
            if self._scheduled_tasks then
                self._scheduled_tasks[task_id] = nil
            end
        end

        -- Helper to execute all scheduled callbacks (for testing async operations)
        -- @param max_iterations number Maximum number of iterations to prevent infinite loops (default 10)
        function UIManager:executeScheduledTasks(max_iterations)
            max_iterations = max_iterations or 10
            local iterations = 0

            while iterations < max_iterations do
                local tasks_to_execute = {}

                -- Collect all tasks
                for task_id, task in pairs(self._scheduled_tasks) do
                    table.insert(tasks_to_execute, { id = task_id, callback = task.callback })
                end

                -- If no tasks, we're done
                if #tasks_to_execute == 0 then
                    break
                end

                -- Clear scheduled tasks before executing (callbacks may schedule new tasks)
                self._scheduled_tasks = {}

                -- Execute all collected tasks
                for _, task in ipairs(tasks_to_execute) do
                    if task.callback then
                        task.callback()
                    end
                end

                iterations = iterations + 1
            end
        end

        -- Helper to reset call tracking
        function UIManager:_reset()
            self._show_calls = {}
            self._shown_widgets = {}
            self._close_calls = {}
            self._broadcast_calls = {}
            self._send_event_calls = {}
            self._prevent_standby_calls = 0
            self._allow_standby_calls = 0
            self._scheduled_tasks = {}
            self._event_hook_calls = {}
            self._unschedule_calls = {}
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

-- Mock InputContainer module
if not package.preload["ui/widget/container/inputcontainer"] then
    package.preload["ui/widget/container/inputcontainer"] = function()
        local InputContainer = {}
        function InputContainer:extend(subclass)
            subclass = subclass or {}
            local parent = self
            setmetatable(subclass, { __index = parent })

            function subclass:new(obj) -- luacheck: ignore self
                obj = obj or {}
                setmetatable(obj, { __index = self })
                return obj
            end

            return subclass
        end

        return InputContainer
    end
end

-- Mock InfoMessage module
if not package.preload["ui/widget/infomessage"] then
    package.preload["ui/widget/infomessage"] = function()
        local InfoMessage = {}
        function InfoMessage.new(_, opts)
            opts = opts or {}
            return {
                text = opts.text,
                timeout = opts.timeout,
                dismissable = opts.dismissable,
                dismiss_callback = opts.dismiss_callback,
            }
        end

        return InfoMessage
    end
end

-- Mock ButtonDialog module
if not package.preload["ui/widget/buttondialog"] then
    package.preload["ui/widget/buttondialog"] = function()
        local ButtonDialog = {}
        function ButtonDialog:new(opts)
            opts = opts or {}
            local o = {
                title = opts.title,
                title_align = opts.title_align,
                buttons = opts.buttons,
            }
            setmetatable(o, { __index = self })
            return o
        end

        return ButtonDialog
    end
end

-- Mock Menu module
if not package.preload["ui/widget/menu"] then
    package.preload["ui/widget/menu"] = function()
        local Menu = {}
        function Menu:new(opts)
            local o = {
                subtitle = opts.subtitle,
                item_table = opts.item_table,
                items_per_page = opts.items_per_page,
                covers_fullscreen = opts.covers_fullscreen,
                is_borderless = opts.is_borderless,
                is_popout = opts.is_popout,
                onMenuChoice = opts.onMenuChoice,
                onMenuHold = opts.onMenuHold,
                close_callback = opts.close_callback,
            }
            setmetatable(o, { __index = self })
            return o
        end

        function Menu:switchItemTable(title, new_items, per_page, reset_to_page)
            self.item_table = new_items
            self._switch_item_table_called = true
            self._switch_item_table_title = title
            self._switch_reset_page = reset_to_page
        end

        return Menu
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

-- Mock ui/network/manager module with call tracking
if not package.preload["ui/network/manager"] then
    package.preload["ui/network/manager"] = function()
        local NetworkMgr = {
            -- Call tracking
            _turn_on_wifi_calls = {},
            _turn_off_wifi_calls = {},
            _is_wifi_on_calls = 0,
            -- State tracking
            _wifi_on = false,
            wifi_was_on = false,
        }

        function NetworkMgr:turnOnWifi(complete_callback, long_press)
            table.insert(self._turn_on_wifi_calls, {
                complete_callback = complete_callback,
                long_press = long_press,
            })
            self._wifi_on = true
            if complete_callback then
                complete_callback()
            end
        end

        function NetworkMgr:turnOffWifi(complete_callback, long_press)
            table.insert(self._turn_off_wifi_calls, {
                complete_callback = complete_callback,
                long_press = long_press,
            })
            self._wifi_on = false
            if complete_callback then
                complete_callback()
            end
        end

        function NetworkMgr:isWifiOn()
            self._is_wifi_on_calls = self._is_wifi_on_calls + 1
            return self._wifi_on
        end

        function NetworkMgr:restoreWifiAsync()
            -- Mock implementation - in real code this is async
            -- For tests, call turnOnWifi to simulate the async WiFi restoration
            if not self._wifi_on then
                self:turnOnWifi(nil, false)
            end
        end

        -- Helper to reset call tracking
        function NetworkMgr:_reset()
            self._turn_on_wifi_calls = {}
            self._turn_off_wifi_calls = {}
            self._is_wifi_on_calls = 0
            self._wifi_on = false
            self.wifi_was_on = false
        end

        -- Helper to set WiFi state
        function NetworkMgr:_setWifiState(state)
            self._wifi_on = state
        end

        return NetworkMgr
    end
end

-- Mock ffi/sha2 module (SHA256 hashing for DRM)
if not package.preload["ffi/sha2"] then
    package.preload["ffi/sha2"] = function()
        ---
        -- SHA256 hash function using OpenSSL via shell.
        -- @param data string: The data to hash.
        -- @return string: Raw 32-byte SHA256 hash.
        local function sha256(data)
            -- Create temp file to avoid shell escaping issues
            local temp_file = os.tmpname()
            local file = io.open(temp_file, "wb")
            if not file then
                error("Failed to create temp file for SHA256")
            end
            file:write(data)
            file:close()

            -- Use openssl to hash the file
            local cmd = string.format("openssl dgst -sha256 -binary %q | xxd -p -c 256", temp_file)
            local handle = io.popen(cmd)
            if not handle then
                os.remove(temp_file)
                error("Failed to execute openssl for SHA256")
            end
            local hex_hash = handle:read("*a")
            handle:close()
            os.remove(temp_file)

            -- Convert hex string to binary
            hex_hash = hex_hash:gsub("%s+", "")
            local binary_hash = {}
            for i = 1, #hex_hash, 2 do
                local byte_hex = hex_hash:sub(i, i + 1)
                table.insert(binary_hash, string.char(tonumber(byte_hex, 16)))
            end

            return table.concat(binary_hash)
        end

        return {
            sha256 = sha256,
            base64_to_bin = function(base64_str)
                -- Simple base64 decoder for testing
                local cmd = string.format("echo %q | base64 -d", base64_str)
                local handle = io.popen(cmd)
                if not handle then
                    return nil
                end
                local result = handle:read("*a")
                handle:close()
                return result
            end,
            bin_to_base64 = function(bin_str)
                -- Simple base64 encoder for testing
                local temp_file = os.tmpname()
                local file = io.open(temp_file, "wb")
                if not file then
                    return nil
                end
                file:write(bin_str)
                file:close()
                local cmd = string.format("base64 -w 0 %q", temp_file)
                local handle = io.popen(cmd)
                if not handle then
                    os.remove(temp_file)
                    return nil
                end
                local result = handle:read("*a")
                handle:close()
                os.remove(temp_file)
                return result
            end,
        }
    end
end

-- Mock document/archiver module (ZIP handling for DRM)
if not package.preload["document/archiver"] then
    package.preload["document/archiver"] = function()
        ---
        -- Open an EPUB/ZIP archive using unzip command.
        -- @param filepath string: Path to the archive.
        -- @return table|nil: Archive object with list() and extractFile() methods.
        local function open(filepath)
            -- Check if file exists and is readable
            local test_file = io.open(filepath, "rb")
            if not test_file then
                return nil
            end
            test_file:close()

            local archive = {
                _filepath = filepath,
            }

            ---
            -- List all files in the archive.
            -- @return table: Array of file paths.
            function archive:list()
                local handle = io.popen(string.format("unzip -Z1 %q 2>/dev/null", self._filepath))
                if not handle then
                    return {}
                end
                local output = handle:read("*a")
                handle:close()

                local files = {}
                for line in output:gmatch("[^\r\n]+") do
                    table.insert(files, line)
                end

                return files
            end

            ---
            -- Extract a single file to memory.
            -- @param filename string: File path within the archive.
            -- @return string|nil: File contents.
            function archive:extractFile(filename)
                local handle = io.popen(string.format("unzip -p %q %q 2>/dev/null", self._filepath, filename))
                if not handle then
                    return nil
                end
                local content = handle:read("*a")
                handle:close()

                if content == "" then
                    return nil
                end

                return content
            end

            ---
            -- Close the archive (no-op for command-based implementation).
            function archive:close() end

            return archive
        end

        return {
            open = open,
        }
    end
end

-- Mock ffi/blitbuffer module (for cover image handling)
if not package.preload["ffi/blitbuffer"] then
    package.preload["ffi/blitbuffer"] = function()
        local Blitbuffer = {
            TYPE_BBRGB32 = 4,
            TYPE_BB8 = 1,
        }

        function Blitbuffer.new(width, height, bb_type)
            bb_type = bb_type or Blitbuffer.TYPE_BBRGB32
            local bytes_per_pixel = bb_type == Blitbuffer.TYPE_BBRGB32 and 4 or 1
            local stride = width * bytes_per_pixel
            local size = stride * height

            -- Create mock pixel data
            local data = string.rep("\0", size)

            local bb = {
                w = width,
                h = height,
                stride = stride,
                data = data,
                _type = bb_type,
                _freed = false,
            }

            function bb:getWidth()
                return self.w
            end

            function bb:getHeight()
                return self.h
            end

            function bb:getType()
                return self._type
            end

            function bb:free()
                self._freed = true
            end

            function bb:writeToFile(filepath, format)
                -- Mock: just create an empty file
                local f = io.open(filepath, "wb")
                if f then
                    f:write("MOCK_IMAGE_DATA")
                    f:close()
                end
            end

            return bb
        end

        return Blitbuffer
    end
end

-- Mock ui/renderimage module (for loading cover images)
if not package.preload["ui/renderimage"] then
    package.preload["ui/renderimage"] = function()
        local Blitbuffer = require("ffi/blitbuffer")

        local RenderImage = {}

        function RenderImage:renderImageFile(filepath, want_frames)
            -- Check if file exists
            local f = io.open(filepath, "rb")
            if not f then
                return nil
            end
            f:close()

            -- Return a mock BlitBuffer
            return Blitbuffer.new(100, 150, Blitbuffer.TYPE_BBRGB32)
        end

        function RenderImage:scaleBlitBuffer(bb, target_w, target_h, free_orig)
            if free_orig and bb then
                bb:free()
            end

            -- Return a new scaled BlitBuffer
            return Blitbuffer.new(target_w, target_h, bb:getType())
        end

        return RenderImage
    end
end

-- Mock document/documentregistry module (for opening documents)
if not package.preload["document/documentregistry"] then
    package.preload["document/documentregistry"] = function()
        local Blitbuffer = require("ffi/blitbuffer")

        local DocumentRegistry = {}

        function DocumentRegistry:openDocument(filepath)
            -- Check if file exists
            local f = io.open(filepath, "rb")
            if not f then
                return nil
            end
            f:close()

            local doc = {
                _filepath = filepath,
                _closed = false,
            }

            function doc.getCoverPageImage()
                if doc._closed then
                    return nil
                end

                -- Return a mock BlitBuffer representing the cover image
                return Blitbuffer.new(600, 800, Blitbuffer.TYPE_BBRGB32)
            end

            function doc.close()
                doc._closed = true
            end

            return doc
        end

        return DocumentRegistry
    end
end

-- Mock ui/widget/pathchooser module
if not package.preload["ui/widget/pathchooser"] then
    package.preload["ui/widget/pathchooser"] = function()
        local PathChooser = {}

        function PathChooser:new(opts)
            local o = {
                title = opts and opts.title or "Choose Path",
                path = opts and opts.path or "/",
                onConfirm = opts and opts.onConfirm or function() end,
            }
            setmetatable(o, { __index = self })
            return o
        end

        return PathChooser
    end
end

---
--- Creates a mock DocSettings object for testing.
--- Supports two calling patterns:
---   1. createMockDocSettings(percent_finished, status) - simple pattern
---   2. createMockDocSettings(doc_path, data) - advanced pattern with full data table
--- @param arg1 string|number: Either doc_path (string) or percent_finished (number).
--- @param arg2 string|table: Either status (string) or data table.
--- @return table: Mock DocSettings instance.
local function createMockDocSettings(arg1, arg2)
    local doc_path, data

    if type(arg1) == "number" then
        doc_path = "KOBO_VIRTUAL://TESTBOOK1/test.epub"
        data = {
            percent_finished = arg1,
            summary = { status = arg2 or "" },
        }
    else
        doc_path = arg1 or "KOBO_VIRTUAL://TESTBOOK1/test.epub"
        data = arg2 or {}
    end

    return {
        data = { doc_path = doc_path },
        readSetting = function(self, key)
            if key == "percent_finished" then
                return data.percent_finished
            end

            if key == "summary" then
                return data.summary
            end

            return data[key]
        end,
        saveSetting = function(self, key, value)
            data[key] = value
        end,
        flush = function(self)
            -- No-op in tests
        end,
    }
end

-- Helper function to reset UI mocks between tests
local function resetUIMocks()
    -- Get the mocked modules
    local UIManager = require("ui/uimanager")
    local ConfirmBox = require("ui/widget/confirmbox")
    local Trapper = require("ui/trapper")
    local NetworkMgr = require("ui/network/manager")

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
    if NetworkMgr._reset then
        NetworkMgr:_reset()
    end
end

return {
    createMockDocSettings = createMockDocSettings,
    resetUIMocks = resetUIMocks,
    createIOOpenMocker = createIOOpenMocker,
}
