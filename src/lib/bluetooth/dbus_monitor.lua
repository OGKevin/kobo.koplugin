---
--- DBus monitor for Bluetooth device property changes.
--- Monitors D-Bus signals for property changes on Bluetooth devices using a non-blocking
--- poll() pattern similar to bluetooth_input_reader.lua.
---
--- This provides event-driven detection of device connections, disconnections, and
--- RSSI changes without continuous polling of device state.

local Subprocess = require("src/lib/bluetooth/subprocess")
local UIManager = require("ui/uimanager")
local bit = require("bit")
local ffi = require("ffi")
local logger = require("logger")

require("ffi/posix_h")

local C = ffi.C

local F_GETFL = 3
local F_SETFL = 4
local EAGAIN = 11
local SIGTERM = 15
local SIGKILL = 9
local WNOHANG = 1
local STDIN_FILENO = 0
local STDOUT_FILENO = 1
local STDERR_FILENO = 2
local O_RDWR = 2
local READ_BUF_SIZE = 4096
local MAX_LINE_BUFFER = 65536

local ok_nonblock, declared_nonblock = pcall(function()
    return tonumber(C.O_NONBLOCK)
end)

--- O_NONBLOCK as declared by ffi/posix_h when its constants are available;
--- 0o4000 (2048) is the value on every Linux architecture, Kobo's old
--- kernels included.
local O_NONBLOCK = ok_nonblock and type(declared_nonblock) == "number" and declared_nonblock or 2048

--- Signal match handed to dbus-monitor on the system bus.
local MONITOR_MATCH = "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'"

pcall(function()
    ffi.cdef([[
        int fcntl(int fd, int cmd, ...);
    ]])
end)

pcall(function()
    ffi.cdef([[
        ssize_t read(int fd, void *buf, size_t count);
    ]])
end)

pcall(function()
    ffi.cdef([[
        int pipe(int fds[2]);
        int fork(void);
        int dup2(int oldfd, int newfd);
        int execvp(const char *file, char *const argv[]);
        int close(int fd);
        int kill(int pid, int sig);
        int waitpid(int pid, int *status, int options);
        int chdir(const char *path);
        int open(const char *pathname, int flags, ...);
        void _exit(int status);
    ]])
end)

-- POSIX syscalls routed through an injectable adapter so tests can mock the
-- syscalls (fcntl/poll/read and the process calls) instead of overriding the
-- module methods.
local posix_adapter = {
    O_NONBLOCK = O_NONBLOCK,
    fcntl = function(...)
        return C.fcntl(...)
    end,
    poll = function(...)
        return C.poll(...)
    end,
    read = function(fd, buf, size)
        local n = C.read(fd, buf, size)

        if n < 0 then
            return nil, tonumber(ffi.errno())
        end

        return tonumber(n)
    end,
    pipe = function(...)
        return tonumber(C.pipe(...))
    end,
    fork = function()
        return tonumber(C.fork())
    end,
    dup2 = function(...)
        return tonumber(C.dup2(...))
    end,
    execvp = function(...)
        return tonumber(C.execvp(...))
    end,
    chdir = function(path)
        return tonumber(C.chdir(path))
    end,
    open = function(path, flags)
        return tonumber(C.open(path, flags))
    end,
    close = function(...)
        return tonumber(C.close(...))
    end,
    kill = function(...)
        return tonumber(C.kill(...))
    end,
    waitpid = function(...)
        return tonumber(C.waitpid(...))
    end,
    _exit = function(status)
        C._exit(status)
    end,
}

---
--- Copies a Lua string into a writable C string buffer.
--- @param s string Source string
--- @return userdata NUL-terminated char buffer
local function cstring(s)
    local buf = ffi.new("char[?]", #s + 1)
    ffi.copy(buf, s)

    return buf
end

local DbusMonitor = {
    monitor_fd = nil,
    monitor_pid = nil,
    property_callbacks = {}, -- key -> {callback = function, priority = number}
    sorted_callbacks = {}, -- array of {key, callback, priority} sorted by priority
    is_active = false,
    poll_task = nil,
    current_signal = {},
    line_buffer = "",
    _posix = posix_adapter,
}

---
--- Creates a new DbusMonitor instance.
--- @return table New DbusMonitor instance
function DbusMonitor:new()
    local instance = {
        monitor_fd = nil,
        monitor_pid = nil,
        property_callbacks = {}, -- key -> {callback = function, priority = number}
        sorted_callbacks = {}, -- array of {key, callback, priority} sorted by priority
        is_active = false,
        poll_task = nil,
        current_signal = {},
        line_buffer = "",
    }
    setmetatable(instance, self)
    self.__index = self

    return instance
end

---
--- Registers a universal callback for property changes on any device.
--- The callback will be invoked for all property changes from any Bluetooth device.
--- Callbacks are executed in priority order (lower priority numbers execute first).
--- @param key string Unique identifier for this callback (e.g., "auto_detection", "auto_connect")
--- @param callback function Callback function(device_address, properties) where device_address is the device and properties is a table of changed properties
--- @param priority number Optional priority for execution order (default: 100). Lower numbers execute first. Use 0-19 for critical operations like cache sync.
function DbusMonitor:registerCallback(key, callback, priority)
    if not key or not callback then
        logger.warn("DbusMonitor: Invalid key or callback")

        return
    end

    priority = priority or 100

    self.property_callbacks[key] = {
        callback = callback,
        priority = priority,
    }

    self:_rebuildSortedCallbacks()

    logger.dbg("DbusMonitor: Registered callback:", key, "with priority:", priority)
end

---
--- Unregisters a callback by its key.
--- @param key string Unique identifier for the callback
function DbusMonitor:unregisterCallback(key)
    if not key then
        return
    end

    self.property_callbacks[key] = nil

    self:_rebuildSortedCallbacks()

    logger.dbg("DbusMonitor: Unregistered callback:", key)
end

---
--- Rebuilds the sorted callbacks list from the property_callbacks map.
--- Called after registration or unregistration to maintain sorted order.
function DbusMonitor:_rebuildSortedCallbacks()
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

    logger.dbg("DbusMonitor: Rebuilt sorted callbacks list,", #self.sorted_callbacks, "callbacks")
end

-- Starts monitoring D-Bus signals for Bluetooth device property changes.
-- @return boolean True if monitoring started successfully, false otherwise
function DbusMonitor:startMonitoring()
    if self.is_active then
        logger.dbg("DbusMonitor: Already monitoring")

        return true
    end

    logger.info("DbusMonitor: Starting dbus-monitor")

    if not self:_spawnMonitor() then
        return false
    end

    if not self:_setNonBlocking(self.monitor_fd) then
        logger.warn("DbusMonitor: Failed to set monitor fd to non-blocking mode")
        self:_terminateMonitorProcess()
        self._posix.close(self.monitor_fd)
        self.monitor_fd = nil
        self.monitor_pid = nil
        self.line_buffer = ""

        return false
    end

    logger.info("DbusMonitor: Started monitoring, fd:", self.monitor_fd, "pid:", self.monitor_pid)

    self.is_active = true
    self:_schedulePoll()

    return true
end

---
--- Spawns dbus-monitor with its stdout wired to a pipe.
--- Uses pipe/fork/execvp so the child pid is known directly and no shell is
--- involved; the parent keeps the read end as monitor_fd.
--- @return boolean True when the child was spawned
function DbusMonitor:_spawnMonitor()
    local posix = self._posix
    local fds = ffi.new("int[2]")

    if posix.pipe(fds) ~= 0 then
        logger.warn("DbusMonitor: pipe() failed, errno:", ffi.errno())

        return false
    end

    local read_fd, write_fd = tonumber(fds[0]), tonumber(fds[1])
    local pid = posix.fork()

    if pid < 0 then
        logger.warn("DbusMonitor: fork() failed, errno:", ffi.errno())
        posix.close(write_fd)
        posix.close(read_fd)

        return false
    end

    if pid == 0 then
        self:_execMonitorChild(read_fd, write_fd)

        return false
    end

    posix.close(write_fd)
    self.monitor_fd = read_fd
    self.monitor_pid = pid

    return true
end

---
--- Runs in the forked child: wires its stdout to the pipe, detaches from
--- onboard storage (working directory, stdin/stderr, and inherited descriptors
--- above stderr), and replaces itself with dbus-monitor. Only returns when
--- execvp fails, in which case the child exits immediately so the parent
--- observes EOF on the pipe.
--- @param read_fd number Read end of the pipe (closed in the child)
--- @param write_fd number Write end of the pipe (becomes stdout)
function DbusMonitor:_execMonitorChild(read_fd, write_fd)
    local posix = self._posix

    posix.close(read_fd)

    if posix.dup2(write_fd, STDOUT_FILENO) < 0 then
        posix._exit(127)

        return
    end

    if write_fd ~= STDOUT_FILENO then
        posix.close(write_fd)
    end

    if posix.chdir(Subprocess.WORKING_DIRECTORY) < 0 then
        posix._exit(127)

        return
    end

    local devnull_fd = posix.open("/dev/null", O_RDWR)

    if devnull_fd >= 0 then
        posix.dup2(devnull_fd, STDIN_FILENO)
        posix.dup2(devnull_fd, STDERR_FILENO)

        if devnull_fd > STDERR_FILENO then
            posix.close(devnull_fd)
        end
    end

    for fd = 3, Subprocess.openFileLimit() - 1 do
        posix.close(fd)
    end

    local argv = ffi.new("char *[4]")
    local buffers = {}

    for i, arg in ipairs({ "dbus-monitor", "--system", MONITOR_MATCH }) do
        buffers[i] = cstring(arg)
        argv[i - 1] = buffers[i]
    end

    posix.execvp("dbus-monitor", argv)
    posix._exit(127)
end

---
--- Sets a file descriptor to non-blocking mode (for testing override).
--- fcntl() is variadic, so the combined flags are passed as a typed int cdata
--- to keep LuaJIT from promoting the Lua number to a double.
--- @param fd number File descriptor
--- @return boolean True if successful, false otherwise
function DbusMonitor:_setNonBlocking(fd)
    local posix = self._posix
    local flags = posix.fcntl(fd, F_GETFL)

    if flags < 0 then
        logger.warn("DbusMonitor: fcntl(F_GETFL) failed, errno:", ffi.errno())

        return false
    end

    local nonblock_flags = ffi.cast("int", bit.bor(tonumber(flags), posix.O_NONBLOCK))

    if posix.fcntl(fd, F_SETFL, nonblock_flags) < 0 then
        logger.warn("DbusMonitor: fcntl(F_SETFL) failed, errno:", ffi.errno())

        return false
    end

    return true
end

---
--- Polls a file descriptor (for testing override).
--- @param pollfd userdata pollfd array
--- @param nfds number Number of pollfd entries
--- @param timeout number Timeout in milliseconds
--- @return number poll() result
function DbusMonitor:_doPoll(pollfd, nfds, timeout)
    return self._posix.poll(pollfd, nfds, timeout)
end

---
--- Terminates the dbus-monitor child spawned for this monitor.
--- Sends SIGTERM and reaps without blocking; a child still alive after the
--- WNOHANG check is escalated to SIGKILL and reaped for real, so repeated
--- start/stop cycles cannot accumulate zombies. The WNOHANG reap also covers a
--- child that already exited on its own (EOF path).
function DbusMonitor:_terminateMonitorProcess()
    local pid = self.monitor_pid

    if type(pid) ~= "number" then
        logger.warn("DbusMonitor: no dbus-monitor pid to terminate")

        return
    end

    local posix = self._posix
    posix.kill(pid, SIGTERM)

    if posix.waitpid(pid, nil, WNOHANG) == 0 then
        posix.kill(pid, SIGKILL)
        posix.waitpid(pid, nil, 0)
    end

    logger.dbg("DbusMonitor: terminated dbus-monitor pid", pid)
end

---
--- Stops monitoring D-Bus signals.
function DbusMonitor:stopMonitoring()
    if not self.is_active then
        return
    end

    logger.info("DbusMonitor: Stopping monitoring")

    self.is_active = false

    if self.poll_task then
        UIManager:unschedule(self.poll_task)
        self.poll_task = nil
    end

    if self.monitor_fd then
        logger.dbg("DbusMonitor: terminating dbus-monitor and closing monitor fd")
        self:_terminateMonitorProcess()
        self._posix.close(self.monitor_fd)
        self.monitor_fd = nil
    end

    self.monitor_pid = nil
    self.current_signal = {}
    self.line_buffer = ""

    logger.dbg("DbusMonitor: Stopped monitoring")
end

---
--- Checks if monitoring is active.
--- @return boolean True if monitoring is active, false otherwise
function DbusMonitor:isActive()
    return self.is_active
end

---
--- Schedules the next poll iteration.
function DbusMonitor:_schedulePoll()
    if not self.is_active then
        return
    end

    self.poll_task = function()
        if not self.is_active or not self.monitor_fd then
            return
        end

        self:_pollForEvents()

        if self.is_active then
            UIManager:scheduleIn(0.1, self.poll_task)
        end
    end

    UIManager:scheduleIn(0.1, self.poll_task)
end

---
--- Dispatches every newline-terminated line currently held in the line buffer.
--- A trailing partial line is retained until more data arrives.
function DbusMonitor:_drainLineBuffer()
    while true do
        local newline = self.line_buffer:find("\n", 1, true)

        if not newline then
            break
        end

        local line = self.line_buffer:sub(1, newline - 1)
        self.line_buffer = self.line_buffer:sub(newline + 1)

        self:_processSignalLine(line)
    end

    if #self.line_buffer > MAX_LINE_BUFFER then
        logger.warn("DbusMonitor: Discarding oversized partial line buffer")
        self.line_buffer = ""
    end
end

---
--- Reads whatever raw bytes are available from monitor_fd into the line buffer.
--- EAGAIN means a previous read already drained the pipe; EOF means
--- dbus-monitor closed its output and monitoring stops.
--- @return boolean True if bytes were read, false on EAGAIN, EOF or read failure
function DbusMonitor:_readIntoLineBuffer()
    local buf = ffi.new("char[?]", READ_BUF_SIZE)
    local n, err = self._posix.read(self.monitor_fd, buf, READ_BUF_SIZE)

    if not n then
        if err ~= EAGAIN then
            logger.warn("DbusMonitor: read failed, errno:", err)
        end

        return false
    end

    if n == 0 then
        logger.warn("DbusMonitor: dbus-monitor closed its output (EOF)")
        self:stopMonitoring()

        return false
    end

    self.line_buffer = self.line_buffer .. ffi.string(buf, n)

    return true
end

---
--- Polls for D-Bus signal events using non-blocking I/O.
--- Lines buffered from a previous poll are dispatched even when the descriptor
--- is not ready; only newline-terminated lines are processed and a partial line
--- waits for more data. poll() can report POLLIN together with POLLHUP when
--- dbus-monitor exits with output still pending, so readable data is drained
--- before the hangup is treated as fatal.
function DbusMonitor:_pollForEvents()
    if not self.monitor_fd or self.monitor_fd < 0 then
        logger.dbg("DbusMonitor: Invalid file descriptor, stopping")
        self:stopMonitoring()

        return
    end

    local pollfd = ffi.new("struct pollfd[1]")

    self:_drainLineBuffer()

    while true do
        pollfd[0].fd = self.monitor_fd
        pollfd[0].events = C.POLLIN
        pollfd[0].revents = 0

        local result = self:_doPoll(pollfd, 1, 0)

        if result < 0 then
            logger.warn("DbusMonitor: Poll error, errno:", ffi.errno())
            self:stopMonitoring()

            return
        end

        if result == 0 then
            return
        end

        if bit.band(pollfd[0].revents, C.POLLIN) == 0 then
            if bit.band(pollfd[0].revents, C.POLLERR) ~= 0 or bit.band(pollfd[0].revents, C.POLLHUP) ~= 0 then
                logger.warn("DbusMonitor: Poll error or hangup detected")
                self:stopMonitoring()
            end

            return
        end

        if not self:_readIntoLineBuffer() then
            return
        end

        self:_drainLineBuffer()
    end
end

---
--- Processes a single line from the D-Bus monitor output.
--- Accumulates lines until a complete signal is detected.
--- @param line string A line of output from dbus-monitor
--- @return boolean if a signal block has been processed or not
function DbusMonitor:_processSignalLine(line)
    logger.dbg("DbusMonitor: processing signal line", line)

    if line:match("^signal%s") then
        if #self.current_signal > 1 then
            self:_parseAndDispatchSignal(self.current_signal)
        end

        self.current_signal = { line }
        logger.dbg("DbusMonitor: New signal started")

        return true
    end

    if #self.current_signal > 0 then
        table.insert(self.current_signal, line)
    end

    if line:match("^%s*$") then
        if #self.current_signal > 1 then
            self:_parseAndDispatchSignal(self.current_signal)
        end

        self.current_signal = {}

        return true
    end

    return false
end

---
--- Parses a complete D-Bus signal and dispatches to all registered callbacks.
--- @param signal_lines table Array of lines comprising the signal
function DbusMonitor:_parseAndDispatchSignal(signal_lines)
    local signal_text = table.concat(signal_lines, "\n")

    logger.dbg("DbusMonitor: Parsing signal block")

    local device_address = self:_extractDeviceAddress(signal_text)

    if not device_address then
        logger.dbg("DbusMonitor: No device address found in signal")

        return
    end

    logger.dbg("DbusMonitor: Signal for device:", device_address)

    local properties = self:_extractProperties(signal_text)

    if not next(properties) then
        logger.dbg("DbusMonitor: No properties found in signal")

        return
    end

    logger.info("DbusMonitor: Property changes for", device_address, ":", self:_propertiesToString(properties))

    -- Invoke callbacks in pre-sorted priority order
    for _, callback_info in ipairs(self.sorted_callbacks) do
        logger.dbg(
            "DbusMonitor: Invoking callback:",
            callback_info.key,
            "(priority:",
            callback_info.priority,
            ") for device:",
            device_address
        )

        local ok, err = pcall(callback_info.callback, device_address, properties)

        if not ok then
            logger.warn("DbusMonitor: Callback error for", callback_info.key, ":", err)
        end
    end

    if #self.sorted_callbacks == 0 then
        logger.dbg("DbusMonitor: No callbacks registered")
    end
end

---
--- Extracts the Bluetooth device address from a D-Bus signal.
--- @param signal_text string The complete signal text
--- @return string|nil Device address in format "XX:XX:XX:XX:XX:XX" or nil
function DbusMonitor:_extractDeviceAddress(signal_text)
    local address = signal_text:match("path=/org/bluez/hci0/dev_([A-F0-9_]+)")

    if address then
        return address:gsub("_", ":")
    end

    return nil
end

---
--- Extracts properties from a D-Bus signal.
--- @param signal_text string The complete signal text
--- @return table Table of property names to values
function DbusMonitor:_extractProperties(signal_text)
    local properties = {}

    local in_array = false

    for line in signal_text:gmatch("[^\n]+") do
        if line:match("array%s*%[") then
            in_array = true
        elseif line:match("^%s*%]") then
            in_array = false
        elseif in_array then
            local key = line:match('string%s+"([^"]+)"')

            if key then
                local value_line = signal_text:match(key .. '"\n%s*variant%s+([^\n]+)')

                if value_line then
                    local value_type, value = value_line:match("(%w+)%s+(.+)")

                    if value_type == "boolean" then
                        properties[key] = value:match("true") ~= nil
                    elseif value_type == "int32" or value_type == "int16" then
                        properties[key] = tonumber(value)
                    elseif value_type == "string" then
                        properties[key] = value:match('"([^"]*)"') or value
                    else
                        properties[key] = value
                    end

                    logger.dbg("DbusMonitor: Parsed property:", key, "=", properties[key])
                end
            end
        end
    end

    return properties
end

---
--- Converts properties table to a human-readable string for logging.
--- @param properties table Properties table
--- @return string String representation
function DbusMonitor:_propertiesToString(properties)
    local parts = {}

    for key, value in pairs(properties) do
        table.insert(parts, string.format("%s=%s", key, tostring(value)))
    end

    return table.concat(parts, ", ")
end

---
--- Gets the number of registered callbacks.
--- @return number Number of callbacks
function DbusMonitor:getCallbackCount()
    local count = 0

    for _ in pairs(self.property_callbacks) do
        count = count + 1
    end

    return count
end

---
--- Checks if a callback with the given key is registered.
--- @param key string The callback key to check for
--- @return boolean True if callback is registered, false otherwise
function DbusMonitor:hasCallback(key)
    return self.property_callbacks[key] ~= nil
end

return DbusMonitor
