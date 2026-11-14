---
-- Unit tests for DbusMonitor module.

require("spec.helper")

describe("DbusMonitor", function()
    local DbusMonitor
    local UIManager
    local Subprocess
    local ffi
    local bit
    local mock_fd

    setup(function()
        ffi = require("ffi")
        bit = require("bit")
        pcall(function()
            ffi.cdef([[
                struct pollfd {
                    int fd;
                    short events;
                    short revents;
                };
                enum {
                    POLLIN = 0x001,
                    POLLERR = 0x008,
                    POLLHUP = 0x010
                };
            ]])
        end)

        -- Load the module
        DbusMonitor = require("src.lib.bluetooth.dbus_monitor")
        UIManager = require("ui/uimanager")
        Subprocess = require("src/lib/bluetooth/subprocess")
    end)

    local F_GETFL = 3
    local F_SETFL = 4
    local EAGAIN = 11
    local O_NONBLOCK = 2048
    local O_RDWR = 2
    local POLLIN = 1
    local POLLHUP = 0x010
    local SIGTERM = 15
    local SIGKILL = 9
    local WNOHANG = 1
    local READ_FD = 42
    local WRITE_FD = 43
    local CHILD_PID = 4242
    local FD_LIMIT = 12
    local DEVNULL_FD = 44
    local STDIN_FILENO = 0
    local STDOUT_FILENO = 1
    local STDERR_FILENO = 2

    -- POSIX adapter mock: syscalls are mocked per instance so the real
    -- _setNonBlocking, _doPoll, _spawnMonitor and _execMonitorChild stay under
    -- test while fcntl/poll/read/pipe/fork/execvp are replaced.
    local function make_posix_mock()
        local calls = {
            fcntl = {},
            poll = 0,
            read = 0,
            pipe = 0,
            fork = 0,
            dup2 = {},
            execvp = {},
            chdir = {},
            open = {},
            close = {},
            kill = {},
            waitpid = {},
            exit = {},
        }
        local adapter = {
            O_NONBLOCK = O_NONBLOCK,
            fcntl = function(fd, cmd, arg)
                table.insert(calls.fcntl, { fd = fd, cmd = cmd, arg = arg })

                if cmd == F_GETFL then
                    return O_RDWR
                end

                return 0
            end,
            poll = function(pollfd_arg)
                calls.poll = calls.poll + 1
                pollfd_arg[0].revents = POLLIN

                return 1
            end,
            read = function(_, buf)
                calls.read = calls.read + 1

                local chunk = "signal sender=:1.3\n"
                ffi.copy(buf, chunk, #chunk)

                return #chunk
            end,
            pipe = function(fds)
                calls.pipe = calls.pipe + 1
                fds[0] = READ_FD
                fds[1] = WRITE_FD

                return 0
            end,
            fork = function()
                calls.fork = calls.fork + 1

                return CHILD_PID
            end,
            dup2 = function(oldfd, newfd)
                table.insert(calls.dup2, { oldfd = oldfd, newfd = newfd })

                return newfd
            end,
            execvp = function(file, argv)
                local args = {}
                local i = 0
                while argv[i] ~= nil do
                    assert(i < 64, "argv missing NULL terminator")
                    table.insert(args, ffi.string(argv[i]))
                    i = i + 1
                end
                table.insert(calls.execvp, { file = file, argv = args })

                return 0
            end,
            chdir = function(path)
                table.insert(calls.chdir, path)

                return 0
            end,
            open = function(path, flags)
                table.insert(calls.open, { path = path, flags = flags })

                return DEVNULL_FD
            end,
            close = function(fd)
                table.insert(calls.close, fd)

                return 0
            end,
            kill = function(pid, sig)
                table.insert(calls.kill, { pid = pid, sig = sig })

                return 0
            end,
            waitpid = function(pid, status, options)
                table.insert(calls.waitpid, { pid = pid, options = options })

                return pid
            end,
            _exit = function(status)
                table.insert(calls.exit, status)
            end,
        }

        return adapter, calls
    end

    before_each(function()
        -- Reset UI manager state
        UIManager:_reset()
        clearExecutedCommands()

        Subprocess.openFileLimit = function()
            return FD_LIMIT
        end

        -- Mock file descriptor
        mock_fd = READ_FD
    end)

    after_each(function()
        -- No cleanup needed
    end)

    describe("new", function()
        it("should create a new instance", function()
            local monitor = DbusMonitor:new()

            assert.is_not_nil(monitor)
            assert.is_false(monitor:isActive())
            assert.equals(0, monitor:getCallbackCount())
        end)

        it("should initialize with empty state", function()
            local monitor = DbusMonitor:new()

            assert.is_nil(monitor.monitor_pid)
            assert.is_nil(monitor.monitor_fd)
            assert.is_table(monitor.property_callbacks)
            assert.is_false(monitor.is_active)
        end)
    end)

    describe("registerCallback", function()
        it("should register a universal callback", function()
            local monitor = DbusMonitor:new()
            local callback = function() end

            monitor:registerCallback("test_callback", callback)

            assert.equals(1, monitor:getCallbackCount())
            assert.equals(callback, monitor.property_callbacks["test_callback"].callback)
            assert.equals(100, monitor.property_callbacks["test_callback"].priority)
        end)

        it("should handle multiple callbacks", function()
            local monitor = DbusMonitor:new()
            local callback1 = function() end
            local callback2 = function() end

            monitor:registerCallback("auto_detection", callback1)
            monitor:registerCallback("auto_connect", callback2)

            assert.equals(2, monitor:getCallbackCount())
        end)

        it("should handle invalid parameters", function()
            local monitor = DbusMonitor:new()

            monitor:registerCallback(nil, function() end)
            monitor:registerCallback("test", nil)

            assert.equals(0, monitor:getCallbackCount())
        end)

        it("should allow callback replacement", function()
            local monitor = DbusMonitor:new()
            local callback1 = function() end
            local callback2 = function() end

            monitor:registerCallback("test", callback1)
            assert.equals(callback1, monitor.property_callbacks["test"].callback)

            monitor:registerCallback("test", callback2)
            assert.equals(callback2, monitor.property_callbacks["test"].callback)
            assert.equals(1, monitor:getCallbackCount())
        end)

        it("should register callbacks with custom priority", function()
            local monitor = DbusMonitor:new()
            local callback1 = function() end
            local callback2 = function() end

            monitor:registerCallback("high_priority", callback1, 10)
            monitor:registerCallback("low_priority", callback2, 50)

            assert.equals(10, monitor.property_callbacks["high_priority"].priority)
            assert.equals(50, monitor.property_callbacks["low_priority"].priority)
        end)

        it("should maintain sorted callback order by priority", function()
            local monitor = DbusMonitor:new()
            local callback1 = function() end
            local callback2 = function() end
            local callback3 = function() end

            -- Register in non-sorted order
            monitor:registerCallback("medium", callback2, 50)
            monitor:registerCallback("low", callback3, 100)
            monitor:registerCallback("high", callback1, 10)

            -- Verify sorted_callbacks is in priority order
            assert.equals(3, #monitor.sorted_callbacks)
            assert.equals("high", monitor.sorted_callbacks[1].key)
            assert.equals(10, monitor.sorted_callbacks[1].priority)
            assert.equals("medium", monitor.sorted_callbacks[2].key)
            assert.equals(50, monitor.sorted_callbacks[2].priority)
            assert.equals("low", monitor.sorted_callbacks[3].key)
            assert.equals(100, monitor.sorted_callbacks[3].priority)
        end)

        it("should update sorted list when callback is replaced", function()
            local monitor = DbusMonitor:new()
            local callback1 = function() end
            local callback2 = function() end

            monitor:registerCallback("test", callback1, 10)
            assert.equals(1, #monitor.sorted_callbacks)
            assert.equals(10, monitor.sorted_callbacks[1].priority)

            -- Replace with different priority
            monitor:registerCallback("test", callback2, 50)
            assert.equals(1, #monitor.sorted_callbacks)
            assert.equals(50, monitor.sorted_callbacks[1].priority)
        end)
    end)

    describe("unregisterCallback", function()
        it("should unregister a callback", function()
            local monitor = DbusMonitor:new()
            local callback = function() end

            monitor:registerCallback("test", callback)
            assert.equals(1, monitor:getCallbackCount())

            monitor:unregisterCallback("test")
            assert.equals(0, monitor:getCallbackCount())
        end)

        it("should update sorted list when callback is unregistered", function()
            local monitor = DbusMonitor:new()
            local callback1 = function() end
            local callback2 = function() end

            monitor:registerCallback("high", callback1, 10)
            monitor:registerCallback("low", callback2, 50)
            assert.equals(2, #monitor.sorted_callbacks)

            monitor:unregisterCallback("high")
            assert.equals(1, #monitor.sorted_callbacks)
            assert.equals("low", monitor.sorted_callbacks[1].key)
        end)

        it("should handle unregistering non-existent callback", function()
            local monitor = DbusMonitor:new()

            monitor:unregisterCallback("test")
            assert.equals(0, monitor:getCallbackCount())
        end)
    end)

    describe("startMonitoring", function()
        local active_monitors = {}

        after_each(function()
            -- Clean up all monitors created during tests
            for _, monitor in ipairs(active_monitors) do
                if monitor:isActive() then
                    monitor:stopMonitoring()
                end
            end
            active_monitors = {}
        end)

        it("should spawn dbus-monitor and start monitoring", function()
            local monitor = DbusMonitor:new()
            local adapter, calls = make_posix_mock()
            monitor._posix = adapter
            table.insert(active_monitors, monitor)

            local result = monitor:startMonitoring()

            assert.is_true(result)
            assert.is_true(monitor:isActive())
            assert.equals(READ_FD, monitor.monitor_fd)
            assert.equals(CHILD_PID, monitor.monitor_pid)
            assert.equals(1, calls.pipe)
            assert.equals(1, calls.fork)
            assert.same({ WRITE_FD }, calls.close)
            assert.same({}, calls.execvp)
        end)

        it("should schedule polling task", function()
            local monitor = DbusMonitor:new()
            monitor._posix = make_posix_mock()
            table.insert(active_monitors, monitor)

            monitor:startMonitoring()

            assert.is_not_nil(monitor.poll_task)
            assert.is_true(#UIManager._scheduled_tasks > 0)
        end)

        it("should return true if already monitoring", function()
            local monitor = DbusMonitor:new()
            local adapter, calls = make_posix_mock()
            monitor._posix = adapter
            table.insert(active_monitors, monitor)

            monitor:startMonitoring()
            local result = monitor:startMonitoring()

            assert.is_true(result)
            assert.equals(1, calls.fork)
        end)

        it("should handle pipe failure", function()
            local monitor = DbusMonitor:new()
            local adapter, calls = make_posix_mock()
            adapter.pipe = function()
                return -1
            end
            monitor._posix = adapter

            local result = monitor:startMonitoring()

            assert.is_false(result)
            assert.is_false(monitor:isActive())
            assert.equals(0, calls.fork)
            assert.same({}, calls.close)
        end)

        it("should close both pipe ends when fork fails", function()
            local monitor = DbusMonitor:new()
            local adapter, calls = make_posix_mock()
            adapter.fork = function()
                return -1
            end
            monitor._posix = adapter
            table.insert(active_monitors, monitor)

            local result = monitor:startMonitoring()

            assert.is_false(result)
            assert.is_false(monitor:isActive())
            assert.same({ WRITE_FD, READ_FD }, calls.close)
            assert.same({}, calls.kill)
        end)

        it("should terminate the child when non-blocking setup fails", function()
            local monitor = DbusMonitor:new()
            local adapter, calls = make_posix_mock()
            adapter.fcntl = function(fd, cmd, arg)
                if cmd == F_GETFL then
                    return O_RDWR
                end

                return -1
            end
            monitor._posix = adapter
            table.insert(active_monitors, monitor)

            local result = monitor:startMonitoring()

            assert.is_false(result)
            assert.is_false(monitor:isActive())
            assert.is_nil(monitor.monitor_fd)
            assert.is_nil(monitor.monitor_pid)
            assert.equals(1, #calls.kill)
            assert.equals(CHILD_PID, calls.kill[1].pid)
            assert.equals(SIGTERM, calls.kill[1].sig)
            assert.equals(1, #calls.waitpid)
            assert.equals(CHILD_PID, calls.waitpid[1].pid)
            assert.equals(1, calls.waitpid[1].options)
            assert.same({ WRITE_FD, READ_FD }, calls.close)
        end)
    end)

    describe("_execMonitorChild", function()
        local function closed_fds(first, second, third)
            local fds = { first, second, third }

            for fd = 3, FD_LIMIT - 1 do
                table.insert(fds, fd)
            end

            return fds
        end

        it("should wire stdout to the pipe, detach from storage and exec dbus-monitor", function()
            local monitor = DbusMonitor:new()
            local adapter, calls = make_posix_mock()
            monitor._posix = adapter

            monitor:_execMonitorChild(READ_FD, WRITE_FD)

            assert.same(closed_fds(READ_FD, WRITE_FD, DEVNULL_FD), calls.close)
            assert.same({ "/tmp" }, calls.chdir)
            assert.same({ { path = "/dev/null", flags = O_RDWR } }, calls.open)
            assert.same({
                { oldfd = WRITE_FD, newfd = STDOUT_FILENO },
                { oldfd = DEVNULL_FD, newfd = STDIN_FILENO },
                { oldfd = DEVNULL_FD, newfd = STDERR_FILENO },
            }, calls.dup2)
            assert.equals(1, #calls.execvp)
            assert.equals("dbus-monitor", calls.execvp[1].file)

            assert.same({
                "dbus-monitor",
                "--system",
                "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'",
            }, calls.execvp[1].argv)
            assert.same({ 127 }, calls.exit)
        end)

        it("should never close the monitor pipe's stdout", function()
            local monitor = DbusMonitor:new()
            local adapter, calls = make_posix_mock()
            monitor._posix = adapter

            monitor:_execMonitorChild(READ_FD, WRITE_FD)

            for _, fd in ipairs(calls.close) do
                assert.are_not.equal(STDOUT_FILENO, fd)
            end
        end)

        it("should not close stdout when the pipe already writes to fd 1", function()
            local monitor = DbusMonitor:new()
            local adapter, calls = make_posix_mock()
            monitor._posix = adapter

            monitor:_execMonitorChild(READ_FD, STDOUT_FILENO)

            assert.same(closed_fds(READ_FD, DEVNULL_FD), calls.close)
            assert.same({ { oldfd = STDOUT_FILENO, newfd = STDOUT_FILENO } }, { calls.dup2[1] })
        end)

        it("should exit without exec when chdir fails", function()
            local monitor = DbusMonitor:new()
            local adapter, calls = make_posix_mock()
            adapter.chdir = function()
                return -1
            end
            monitor._posix = adapter

            monitor:_execMonitorChild(READ_FD, WRITE_FD)

            assert.same({ 127 }, calls.exit)
            assert.same({}, calls.open)
            assert.same({}, calls.execvp)
        end)

        it("should exit without exec when dup2 fails", function()
            local monitor = DbusMonitor:new()
            local adapter, calls = make_posix_mock()
            adapter.dup2 = function()
                return -1
            end
            monitor._posix = adapter

            monitor:_execMonitorChild(READ_FD, WRITE_FD)

            assert.same({}, calls.execvp)
            assert.same({ 127 }, calls.exit)
            assert.same({}, calls.chdir)
            assert.same({}, calls.open)
        end)

        it("should still exec when /dev/null cannot be opened", function()
            local monitor = DbusMonitor:new()
            local adapter, calls = make_posix_mock()
            adapter.open = function()
                return -1
            end
            monitor._posix = adapter

            monitor:_execMonitorChild(READ_FD, WRITE_FD)

            assert.same({ { oldfd = WRITE_FD, newfd = STDOUT_FILENO } }, calls.dup2)
            assert.same(closed_fds(READ_FD, WRITE_FD), calls.close)
            assert.equals(1, #calls.execvp)
            assert.same({ 127 }, calls.exit)
        end)

        it("should not close a /dev/null descriptor that lands on stderr", function()
            local monitor = DbusMonitor:new()
            local adapter, calls = make_posix_mock()
            adapter.open = function()
                return STDERR_FILENO
            end
            monitor._posix = adapter

            monitor:_execMonitorChild(READ_FD, WRITE_FD)

            assert.same({
                { oldfd = WRITE_FD, newfd = STDOUT_FILENO },
                { oldfd = STDERR_FILENO, newfd = STDIN_FILENO },
                { oldfd = STDERR_FILENO, newfd = STDERR_FILENO },
            }, calls.dup2)
            assert.same(closed_fds(READ_FD, WRITE_FD), calls.close)
        end)
    end)

    describe("stopMonitoring", function()
        it("should stop monitoring and terminate the child", function()
            local monitor = DbusMonitor:new()
            local adapter, calls = make_posix_mock()
            monitor._posix = adapter

            monitor:startMonitoring()
            assert.is_true(monitor:isActive())

            monitor:stopMonitoring()

            assert.is_false(monitor:isActive())
            assert.is_nil(monitor.monitor_fd)
            assert.is_nil(monitor.monitor_pid)
            assert.equals(1, #calls.kill)
            assert.equals(CHILD_PID, calls.kill[1].pid)
            assert.equals(SIGTERM, calls.kill[1].sig)
            assert.equals(1, #calls.waitpid)
            assert.equals(CHILD_PID, calls.waitpid[1].pid)
            assert.equals(READ_FD, calls.close[#calls.close])
        end)

        it("should unschedule poll task", function()
            local monitor = DbusMonitor:new()
            monitor._posix = make_posix_mock()

            monitor:startMonitoring()

            assert.is_not_nil(monitor.poll_task)

            monitor:stopMonitoring()

            assert.is_nil(monitor.poll_task)
        end)

        it("should handle stopping when not active", function()
            local monitor = DbusMonitor:new()

            monitor:stopMonitoring() -- Should not error
            assert.is_false(monitor:isActive())
        end)
    end)

    describe("_terminateMonitorProcess", function()
        it("should reap the child after SIGTERM", function()
            local monitor = DbusMonitor:new()
            local adapter, calls = make_posix_mock()
            monitor._posix = adapter
            monitor.monitor_pid = CHILD_PID

            monitor:_terminateMonitorProcess()

            assert.equals(1, #calls.kill)
            assert.equals(CHILD_PID, calls.kill[1].pid)
            assert.equals(SIGTERM, calls.kill[1].sig)
            assert.equals(1, #calls.waitpid)
            assert.equals(CHILD_PID, calls.waitpid[1].pid)
            assert.equals(WNOHANG, calls.waitpid[1].options)
        end)

        it("should escalate to SIGKILL when the child is still running", function()
            local monitor = DbusMonitor:new()
            local adapter, calls = make_posix_mock()
            local waitpid_options = {}
            adapter.waitpid = function(pid, status, options)
                table.insert(waitpid_options, options)

                if #waitpid_options == 1 then
                    return 0
                end

                return pid
            end
            monitor._posix = adapter
            monitor.monitor_pid = CHILD_PID

            monitor:_terminateMonitorProcess()

            assert.equals(2, #calls.kill)
            assert.equals(SIGTERM, calls.kill[1].sig)
            assert.equals(SIGKILL, calls.kill[2].sig)
            assert.same({ WNOHANG, 0 }, waitpid_options)
        end)

        it("should do nothing when no pid is known", function()
            local monitor = DbusMonitor:new()
            local adapter, calls = make_posix_mock()
            monitor._posix = adapter

            monitor:_terminateMonitorProcess()

            assert.equals(0, #calls.kill)
            assert.equals(0, #calls.waitpid)
        end)
    end)

    describe("_extractDeviceAddress", function()
        it("should extract device address from signal path", function()
            local monitor = DbusMonitor:new()
            local signal = "path=/org/bluez/hci0/dev_E4_17_D8_EC_04_1E"

            local address = monitor:_extractDeviceAddress(signal)

            assert.equals("E4:17:D8:EC:04:1E", address)
        end)

        it("should return nil for invalid path", function()
            local monitor = DbusMonitor:new()
            local signal = "path=/org/bluez/hci0/adapter"

            local address = monitor:_extractDeviceAddress(signal)

            assert.is_nil(address)
        end)

        it("should handle different device addresses", function()
            local monitor = DbusMonitor:new()
            local signal = "path=/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"

            local address = monitor:_extractDeviceAddress(signal)

            assert.equals("AA:BB:CC:DD:EE:FF", address)
        end)
    end)

    describe("_extractProperties", function()
        it("should extract boolean property", function()
            local monitor = DbusMonitor:new()
            local signal = [[
array [
    dict entry(
        string "Connected"
        variant             boolean true
    )
]
]]

            local properties = monitor:_extractProperties(signal)

            assert.is_true(properties.Connected)
        end)

        it("should extract int32 property", function()
            local monitor = DbusMonitor:new()
            local signal = [[
array [
    dict entry(
        string "RSSI"
        variant             int32 -43
    )
]
]]

            local properties = monitor:_extractProperties(signal)

            assert.equals(-43, properties.RSSI)
        end)

        it("should extract multiple properties", function()
            local monitor = DbusMonitor:new()
            local signal = [[
array [
    dict entry(
        string "Connected"
        variant             boolean true
    )
    dict entry(
        string "RSSI"
        variant             int32 -50
    )
    dict entry(
        string "Name"
        variant             string "Test Device"
    )
]
]]

            local properties = monitor:_extractProperties(signal)

            assert.is_true(properties.Connected)
            assert.equals(-50, properties.RSSI)
            assert.equals("Test Device", properties.Name)
        end)

        it("should return empty table for no properties", function()
            local monitor = DbusMonitor:new()
            local signal = "array [\n]"

            local properties = monitor:_extractProperties(signal)

            assert.is_table(properties)
            assert.is_true(not next(properties))
        end)
    end)

    describe("_processSignalLine", function()
        it("should detect signal start", function()
            local monitor = DbusMonitor:new()

            monitor:_processSignalLine("signal sender=:1.3 -> dest=(null destination)")

            assert.equals(1, #monitor.current_signal)
        end)

        it("should detect timestamped signal start", function()
            local monitor = DbusMonitor:new()

            monitor:_processSignalLine("signal time=123.456 sender=:1.2 -> dest=(null destination)")

            assert.equals(1, #monitor.current_signal)
        end)

        it("should accumulate signal lines", function()
            local monitor = DbusMonitor:new()

            monitor:_processSignalLine("signal sender=:1.3")
            monitor:_processSignalLine('   string "Connected"')
            monitor:_processSignalLine("   variant boolean true")

            assert.equals(3, #monitor.current_signal)
        end)

        it("should dispatch accumulated signal on blank line terminator", function()
            local monitor = DbusMonitor:new()
            local dispatched = false

            monitor:registerCallback("test", function()
                dispatched = true
            end)

            monitor:_processSignalLine("signal time=1.0 sender=:1.3 path=/org/bluez/hci0/dev_E4_17_D8_EC_04_1E")
            monitor:_processSignalLine('   string "org.bluez.Device1"')
            monitor:_processSignalLine("   array [")
            monitor:_processSignalLine("      dict entry(")
            monitor:_processSignalLine('         string "Connected"')
            monitor:_processSignalLine("         variant             boolean true")
            monitor:_processSignalLine("      )")
            monitor:_processSignalLine("   ]")
            monitor:_processSignalLine("")

            assert.is_true(dispatched)
        end)
    end)

    describe("_setNonBlocking", function()
        it("should set O_NONBLOCK while preserving existing flags", function()
            local monitor = DbusMonitor:new()
            local adapter, calls = make_posix_mock()
            monitor._posix = adapter

            local result = monitor:_setNonBlocking(mock_fd)

            assert.is_true(result)
            assert.equals(2, #calls.fcntl)
            assert.equals(mock_fd, calls.fcntl[1].fd)
            assert.equals(F_GETFL, calls.fcntl[1].cmd)
            assert.equals(mock_fd, calls.fcntl[2].fd)
            assert.equals(F_SETFL, calls.fcntl[2].cmd)

            -- O_RDWR from F_GETFL is preserved and O_NONBLOCK is added
            local set_flags = tonumber(calls.fcntl[2].arg)
            assert.is_not_nil(set_flags)
            assert.equals(bit.bor(2, O_NONBLOCK), set_flags)
            assert.is_truthy(bit.band(set_flags, O_NONBLOCK) ~= 0)
        end)

        it("should return false when fcntl(F_GETFL) fails", function()
            local monitor = DbusMonitor:new()
            local adapter, calls = make_posix_mock()
            adapter.fcntl = function(fd, cmd, arg)
                table.insert(calls.fcntl, { fd = fd, cmd = cmd, arg = arg })

                return -1
            end
            monitor._posix = adapter

            assert.is_false(monitor:_setNonBlocking(mock_fd))
            assert.equals(1, #calls.fcntl)
        end)

        it("should return false when fcntl(F_SETFL) fails", function()
            local monitor = DbusMonitor:new()
            local adapter, calls = make_posix_mock()
            adapter.fcntl = function(fd, cmd, arg)
                table.insert(calls.fcntl, { fd = fd, cmd = cmd, arg = arg })

                if cmd == F_GETFL then
                    return 2
                end

                return -1
            end
            monitor._posix = adapter

            assert.is_false(monitor:_setNonBlocking(mock_fd))
            assert.equals(2, #calls.fcntl)
        end)
    end)

    describe("_pollForEvents", function()
        local COMPLETE_SIGNAL = table.concat({
            "signal time=1.0 sender=:1.3 path=/org/bluez/hci0/dev_E4_17_D8_EC_04_1E",
            '   string "org.bluez.Device1"',
            "   array [",
            "      dict entry(",
            '         string "Connected"',
            "         variant             boolean true",
            "      )",
            "   ]",
            "",
            "",
        }, "\n")

        local function new_active_monitor()
            local monitor = DbusMonitor:new()
            local adapter, calls = make_posix_mock()
            monitor._posix = adapter
            monitor.monitor_fd = mock_fd
            monitor.monitor_pid = CHILD_PID
            monitor.is_active = true

            return monitor, calls
        end

        it("should read raw bytes, dispatch complete lines, and retain a partial line", function()
            local monitor = new_active_monitor()

            local poll_calls = 0
            local read_calls = 0
            local dispatched = {}

            monitor:registerCallback("test", function(device_address, properties)
                table.insert(dispatched, { address = device_address, properties = properties })
            end)

            monitor._posix.poll = function(pollfd_arg)
                poll_calls = poll_calls + 1

                if poll_calls == 1 then
                    pollfd_arg[0].revents = POLLIN
                    return 1
                end

                return 0
            end

            monitor._posix.read = function(_, buf)
                read_calls = read_calls + 1

                local chunk = COMPLETE_SIGNAL .. "signal sender=:1.3 partial"
                ffi.copy(buf, chunk, #chunk)

                return #chunk
            end

            monitor:_pollForEvents()

            assert.equals(2, poll_calls)
            assert.equals(1, read_calls)
            assert.equals(1, #dispatched)
            assert.equals("E4:17:D8:EC:04:1E", dispatched[1].address)
            assert.is_true(dispatched[1].properties.Connected)
            assert.equals("signal sender=:1.3 partial", monitor.line_buffer)
            assert.equals(0, #monitor.current_signal)
        end)

        it("should dispatch complete lines already buffered before polling", function()
            local monitor = new_active_monitor()
            monitor.line_buffer = COMPLETE_SIGNAL

            local poll_calls = 0
            local dispatched = {}

            monitor:registerCallback("test", function(device_address, properties)
                table.insert(dispatched, { address = device_address, properties = properties })
            end)

            monitor._posix.poll = function()
                poll_calls = poll_calls + 1

                return 0
            end

            monitor._posix.read = function()
                error("read must not be called when the descriptor is not ready")
            end

            monitor:_pollForEvents()

            assert.equals(1, #dispatched)
            assert.equals("E4:17:D8:EC:04:1E", dispatched[1].address)
            assert.is_true(dispatched[1].properties.Connected)
            assert.equals(1, poll_calls)
            assert.equals("", monitor.line_buffer)
        end)

        it("should stop monitoring when dbus-monitor closes its output", function()
            local monitor, calls = new_active_monitor()

            monitor._posix.poll = function(pollfd_arg)
                pollfd_arg[0].revents = POLLIN

                return 1
            end

            monitor._posix.read = function()
                return 0
            end

            monitor:_pollForEvents()

            assert.is_false(monitor.is_active)
            assert.is_nil(monitor.monitor_fd)
            assert.equals(1, #calls.kill)
            assert.equals(CHILD_PID, calls.kill[1].pid)
            assert.equals(SIGTERM, calls.kill[1].sig)
            assert.equals(1, #calls.waitpid)
            assert.equals(READ_FD, calls.close[#calls.close])
        end)

        it("should drain pending data when poll reports POLLIN with POLLHUP", function()
            local monitor = new_active_monitor()

            local poll_calls = 0
            local dispatched = {}

            monitor:registerCallback("test", function(device_address, properties)
                table.insert(dispatched, { address = device_address, properties = properties })
            end)

            monitor._posix.poll = function(pollfd_arg)
                poll_calls = poll_calls + 1

                if poll_calls == 1 then
                    pollfd_arg[0].revents = bit.bor(POLLIN, POLLHUP)
                    return 1
                end

                pollfd_arg[0].revents = POLLHUP
                return 1
            end

            monitor._posix.read = function(_, buf)
                local chunk = COMPLETE_SIGNAL
                ffi.copy(buf, chunk, #chunk)

                return #chunk
            end

            monitor:_pollForEvents()

            assert.equals(1, #dispatched)
            assert.equals("E4:17:D8:EC:04:1E", dispatched[1].address)
            assert.is_true(dispatched[1].properties.Connected)
            assert.is_false(monitor.is_active)
        end)

        it("should return without stopping monitoring on EAGAIN", function()
            local monitor, calls = new_active_monitor()

            monitor._posix.poll = function(pollfd_arg)
                pollfd_arg[0].revents = POLLIN

                return 1
            end

            monitor._posix.read = function()
                return nil, EAGAIN
            end

            monitor:_pollForEvents()

            assert.is_true(monitor.is_active)
            assert.equals(0, #calls.kill)
        end)
    end)

    describe("_parseAndDispatchSignal", function()
        it("should parse complete signal and invoke all callbacks", function()
            local monitor = DbusMonitor:new()
            local callback1_invoked = false
            local callback2_invoked = false
            local received_device_address_1 = nil
            local received_properties_1 = nil
            local received_device_address_2 = nil
            local received_properties_2 = nil

            monitor:registerCallback("test_callback_1", function(device_address, properties)
                callback1_invoked = true
                received_device_address_1 = device_address
                received_properties_1 = properties
            end)

            monitor:registerCallback("test_callback_2", function(device_address, properties)
                callback2_invoked = true
                received_device_address_2 = device_address
                received_properties_2 = properties
            end)

            local signal_lines = {
                "signal sender=:1.3 path=/org/bluez/hci0/dev_E4_17_D8_EC_04_1E",
                '   string "org.bluez.Device1"',
                "   array [",
                "      dict entry(",
                '         string "Connected"',
                "         variant             boolean true",
                "      )",
                "   ]",
            }

            monitor:_parseAndDispatchSignal(signal_lines)

            assert.is_true(callback1_invoked)
            assert.is_true(callback2_invoked)
            assert.equals("E4:17:D8:EC:04:1E", received_device_address_1)
            assert.equals("E4:17:D8:EC:04:1E", received_device_address_2)
            assert.is_not_nil(received_properties_1)
            assert.is_not_nil(received_properties_2)
            assert.is_true(received_properties_1.Connected)
            assert.is_true(received_properties_2.Connected)
        end)

        it("should work with no callbacks registered", function()
            local monitor = DbusMonitor:new()

            local signal_lines = {
                "signal sender=:1.3 path=/org/bluez/hci0/dev_E4_17_D8_EC_04_1E",
                '   string "org.bluez.Device1"',
                "   array [",
                "      dict entry(",
                '         string "Connected"',
                "         variant             boolean true",
                "      )",
                "   ]",
            }

            -- Should not throw error
            monitor:_parseAndDispatchSignal(signal_lines)
        end)

        it("should handle callback errors gracefully", function()
            local monitor = DbusMonitor:new()
            local callback2_invoked = false

            monitor:registerCallback("error_callback", function()
                error("Test error")
            end)

            monitor:registerCallback("good_callback", function()
                callback2_invoked = true
            end)

            local signal_lines = {
                "signal sender=:1.3 path=/org/bluez/hci0/dev_E4_17_D8_EC_04_1E",
                '   string "org.bluez.Device1"',
                "   array [",
                "      dict entry(",
                '         string "Connected"',
                "         variant             boolean true",
                "      )",
                "   ]",
            }

            -- Should not throw and should continue to call other callbacks
            monitor:_parseAndDispatchSignal(signal_lines)
            assert.is_true(callback2_invoked)
        end)

        it("should execute callbacks in priority order", function()
            local monitor = DbusMonitor:new()
            local execution_order = {}

            -- Register callbacks in non-sorted order with different priorities
            monitor:registerCallback("medium", function()
                table.insert(execution_order, "medium")
            end, 50)

            monitor:registerCallback("low", function()
                table.insert(execution_order, "low")
            end, 100)

            monitor:registerCallback("high", function()
                table.insert(execution_order, "high")
            end, 10)

            monitor:registerCallback("very_high", function()
                table.insert(execution_order, "very_high")
            end, 5)

            local signal_lines = {
                "signal sender=:1.3 path=/org/bluez/hci0/dev_E4_17_D8_EC_04_1E",
                '   string "org.bluez.Device1"',
                "   array [",
                "      dict entry(",
                '         string "Connected"',
                "         variant             boolean true",
                "      )",
                "   ]",
            }

            monitor:_parseAndDispatchSignal(signal_lines)

            -- Verify callbacks were executed in priority order (lower priority number = earlier execution)
            assert.equals(4, #execution_order)
            assert.equals("very_high", execution_order[1])
            assert.equals("high", execution_order[2])
            assert.equals("medium", execution_order[3])
            assert.equals("low", execution_order[4])
        end)

        it("should maintain execution order after adding new callbacks", function()
            local monitor = DbusMonitor:new()
            local execution_order = {}

            -- Register initial callbacks
            monitor:registerCallback("low", function()
                table.insert(execution_order, "low")
            end, 100)

            monitor:registerCallback("high", function()
                table.insert(execution_order, "high")
            end, 10)

            local signal_lines = {
                "signal sender=:1.3 path=/org/bluez/hci0/dev_E4_17_D8_EC_04_1E",
                '   string "org.bluez.Device1"',
                "   array [",
                "      dict entry(",
                '         string "Connected"',
                "         variant             boolean true",
                "      )",
                "   ]",
            }

            -- First execution
            monitor:_parseAndDispatchSignal(signal_lines)
            assert.equals(2, #execution_order)
            assert.equals("high", execution_order[1])
            assert.equals("low", execution_order[2])

            -- Add a medium priority callback
            execution_order = {}
            monitor:registerCallback("medium", function()
                table.insert(execution_order, "medium")
            end, 50)

            -- Second execution with new callback
            monitor:_parseAndDispatchSignal(signal_lines)
            assert.equals(3, #execution_order)
            assert.equals("high", execution_order[1])
            assert.equals("medium", execution_order[2])
            assert.equals("low", execution_order[3])
        end)

        it("should maintain execution order after removing callbacks", function()
            local monitor = DbusMonitor:new()
            local execution_order = {}

            monitor:registerCallback("low", function()
                table.insert(execution_order, "low")
            end, 100)

            monitor:registerCallback("high", function()
                table.insert(execution_order, "high")
            end, 10)

            monitor:registerCallback("medium", function()
                table.insert(execution_order, "medium")
            end, 50)

            -- Remove medium priority callback
            monitor:unregisterCallback("medium")

            local signal_lines = {
                "signal sender=:1.3 path=/org/bluez/hci0/dev_E4_17_D8_EC_04_1E",
                '   string "org.bluez.Device1"',
                "   array [",
                "      dict entry(",
                '         string "Connected"',
                "         variant             boolean true",
                "      )",
                "   ]",
            }

            monitor:_parseAndDispatchSignal(signal_lines)

            -- Verify only high and low executed in correct order
            assert.equals(2, #execution_order)
            assert.equals("high", execution_order[1])
            assert.equals("low", execution_order[2])
        end)
    end)

    describe("integration", function()
        it("should process complete D-Bus signal flow", function()
            local monitor = DbusMonitor:new()
            local callback_count = 0
            local last_device_address = nil
            local last_properties = nil

            monitor:registerCallback("test", function(device_address, properties)
                callback_count = callback_count + 1
                last_device_address = device_address
                last_properties = properties
            end)

            -- Simulate D-Bus monitor output
            monitor:_processSignalLine("signal sender=:1.3 path=/org/bluez/hci0/dev_E4_17_D8_EC_04_1E")
            monitor:_processSignalLine('   string "org.bluez.Device1"')
            monitor:_processSignalLine("   array [")
            monitor:_processSignalLine("      dict entry(")
            monitor:_processSignalLine('         string "Connected"')
            monitor:_processSignalLine("         variant             boolean true")
            monitor:_processSignalLine("      )")
            monitor:_processSignalLine("   ]")
            monitor:_processSignalLine("") -- Empty line signals end

            assert.equals(1, callback_count)
            assert.equals("E4:17:D8:EC:04:1E", last_device_address)
            assert.is_not_nil(last_properties)
            assert.is_true(last_properties.Connected)
        end)

        it("should handle multiple signals for different devices", function()
            local monitor = DbusMonitor:new()
            local callback_count = 0
            local device_addresses = {}

            monitor:registerCallback("universal", function(device_address, properties)
                callback_count = callback_count + 1
                table.insert(device_addresses, device_address)
            end)

            -- First device signal (timestamped header as dbus-monitor prints on some systems)
            monitor:_processSignalLine("signal time=1.0 sender=:1.3 path=/org/bluez/hci0/dev_E4_17_D8_EC_04_1E")
            monitor:_processSignalLine("   array [")
            monitor:_processSignalLine('      string "Connected"')
            monitor:_processSignalLine("      variant boolean true")
            monitor:_processSignalLine("   ]")
            monitor:_processSignalLine("")

            -- Second device signal
            monitor:_processSignalLine("signal sender=:1.3 path=/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")
            monitor:_processSignalLine("   array [")
            monitor:_processSignalLine('      string "RSSI"')
            monitor:_processSignalLine("      variant int32 -60")
            monitor:_processSignalLine("   ]")
            monitor:_processSignalLine("")

            assert.equals(2, callback_count)
            assert.equals("E4:17:D8:EC:04:1E", device_addresses[1])
            assert.equals("AA:BB:CC:DD:EE:FF", device_addresses[2])
        end)
    end)
end)
