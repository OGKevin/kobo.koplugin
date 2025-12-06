---
-- Unit tests for DbusMonitor module.

require("spec.helper")

describe("DbusMonitor", function()
    local DbusMonitor
    local UIManager
    local mock_pipe
    local mock_fd

    setup(function()
        -- Load the module
        DbusMonitor = require("src.lib.bluetooth.dbus_monitor")
        UIManager = require("ui/uimanager")
    end)

    before_each(function()
        -- Reset UI manager state
        UIManager:_reset()

        -- Mock file descriptor
        mock_fd = 42

        -- Mock pipe object
        mock_pipe = {
            read = function()
                return nil
            end,
            close = function() end,
        }

        -- Mock io.popen
        _G.io = _G.io or {}
        _G.io.popen = function()
            return mock_pipe
        end
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

            assert.is_nil(monitor.monitor_pipe)
            assert.is_nil(monitor.monitor_fd)
            assert.is_table(monitor.property_callbacks)
            assert.is_false(monitor.is_active)
        end)
    end)

    describe("registerDeviceCallback", function()
        it("should register a callback for a device", function()
            local monitor = DbusMonitor:new()
            local callback = function() end

            monitor:registerDeviceCallback("E4:17:D8:EC:04:1E", callback)

            assert.equals(1, monitor:getCallbackCount())
            assert.equals(callback, monitor.property_callbacks["E4:17:D8:EC:04:1E"])
        end)

        it("should handle multiple device callbacks", function()
            local monitor = DbusMonitor:new()
            local callback1 = function() end
            local callback2 = function() end

            monitor:registerDeviceCallback("E4:17:D8:EC:04:1E", callback1)
            monitor:registerDeviceCallback("AA:BB:CC:DD:EE:FF", callback2)

            assert.equals(2, monitor:getCallbackCount())
        end)

        it("should handle invalid parameters", function()
            local monitor = DbusMonitor:new()

            monitor:registerDeviceCallback(nil, function() end)
            monitor:registerDeviceCallback("E4:17:D8:EC:04:1E", nil)

            assert.equals(0, monitor:getCallbackCount())
        end)
    end)

    describe("unregisterDeviceCallback", function()
        it("should unregister a callback", function()
            local monitor = DbusMonitor:new()
            local callback = function() end

            monitor:registerDeviceCallback("E4:17:D8:EC:04:1E", callback)
            assert.equals(1, monitor:getCallbackCount())

            monitor:unregisterDeviceCallback("E4:17:D8:EC:04:1E")
            assert.equals(0, monitor:getCallbackCount())
        end)

        it("should handle unregistering non-existent callback", function()
            local monitor = DbusMonitor:new()

            monitor:unregisterDeviceCallback("E4:17:D8:EC:04:1E")
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

        it("should start monitoring successfully", function()
            local monitor = DbusMonitor:new()
            table.insert(active_monitors, monitor)

            -- Stub the _getFileDescriptor method
            local fd_stub = stub(monitor, "_getFileDescriptor")
            fd_stub.invokes(function()
                return mock_fd
            end)

            local result = monitor:startMonitoring()

            assert.is_true(result)
            assert.is_true(monitor:isActive())
            assert.is_not_nil(monitor.monitor_pipe)
            assert.equals(mock_fd, monitor.monitor_fd)

            fd_stub:revert()
        end)

        it("should schedule polling task", function()
            local monitor = DbusMonitor:new()
            table.insert(active_monitors, monitor)

            local fd_stub = stub(monitor, "_getFileDescriptor")
            fd_stub.invokes(function()
                return mock_fd
            end)

            monitor:startMonitoring()

            assert.is_not_nil(monitor.poll_task)
            assert.is_true(#UIManager._scheduled_tasks > 0)

            fd_stub:revert()
        end)

        it("should return true if already monitoring", function()
            local monitor = DbusMonitor:new()
            table.insert(active_monitors, monitor)

            local fd_stub = stub(monitor, "_getFileDescriptor")
            fd_stub.invokes(function()
                return mock_fd
            end)

            monitor:startMonitoring()
            local result = monitor:startMonitoring()

            assert.is_true(result)

            fd_stub:revert()
        end)

        it("should handle popen failure", function()
            _G.io.popen = function()
                return nil
            end

            local monitor = DbusMonitor:new()
            local result = monitor:startMonitoring()

            assert.is_false(result)
            assert.is_false(monitor:isActive())
        end)

        it("should handle fileno failure", function()
            local monitor = DbusMonitor:new()
            table.insert(active_monitors, monitor)

            -- Stub to return error
            local fd_stub = stub(monitor, "_getFileDescriptor")
            fd_stub.invokes(function()
                return -1
            end)

            local result = monitor:startMonitoring()

            assert.is_false(result)
            assert.is_false(monitor:isActive())

            fd_stub:revert()
        end)
    end)

    describe("stopMonitoring", function()
        it("should stop monitoring", function()
            local monitor = DbusMonitor:new()

            -- Direct function replacement instead of stub
            local original_getfd = monitor._getFileDescriptor
            monitor._getFileDescriptor = function()
                return mock_fd
            end

            monitor:startMonitoring()
            assert.is_true(monitor:isActive())

            -- Restore original
            monitor._getFileDescriptor = original_getfd

            monitor:stopMonitoring()

            assert.is_false(monitor:isActive())
            assert.is_nil(monitor.monitor_pipe)
            assert.is_nil(monitor.monitor_fd)
        end)

        it("should unschedule poll task", function()
            local monitor = DbusMonitor:new()

            -- Direct function replacement instead of stub
            local original_getfd = monitor._getFileDescriptor
            monitor._getFileDescriptor = function()
                return mock_fd
            end

            monitor:startMonitoring()

            assert.is_not_nil(monitor.poll_task)

            -- Restore original
            monitor._getFileDescriptor = original_getfd

            monitor:stopMonitoring()

            assert.is_nil(monitor.poll_task)
        end)

        it("should handle stopping when not active", function()
            local monitor = DbusMonitor:new()

            monitor:stopMonitoring() -- Should not error
            assert.is_false(monitor:isActive())
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

        it("should accumulate signal lines", function()
            local monitor = DbusMonitor:new()

            monitor:_processSignalLine("signal sender=:1.3")
            monitor:_processSignalLine('   string "Connected"')
            monitor:_processSignalLine("   variant boolean true")

            assert.equals(3, #monitor.current_signal)
        end)
    end)

    describe("_parseAndDispatchSignal", function()
        it("should parse complete signal and invoke callback", function()
            local monitor = DbusMonitor:new()
            local callback_invoked = false
            local received_properties = nil

            monitor:registerDeviceCallback("E4:17:D8:EC:04:1E", function(properties)
                callback_invoked = true
                received_properties = properties
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

            assert.is_true(callback_invoked)
            assert.is_not_nil(received_properties)
            assert.is_true(received_properties.Connected)
        end)

        it("should not invoke callback if not registered", function()
            local monitor = DbusMonitor:new()
            local callback_invoked = false

            monitor:registerDeviceCallback("AA:BB:CC:DD:EE:FF", function()
                callback_invoked = true
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

            assert.is_false(callback_invoked)
        end)

        it("should handle callback errors gracefully", function()
            local monitor = DbusMonitor:new()

            monitor:registerDeviceCallback("E4:17:D8:EC:04:1E", function()
                error("Test error")
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

            -- Should not throw
            monitor:_parseAndDispatchSignal(signal_lines)
        end)
    end)

    describe("integration", function()
        it("should process complete D-Bus signal flow", function()
            local monitor = DbusMonitor:new()
            local callback_count = 0
            local last_properties = nil

            monitor:registerDeviceCallback("E4:17:D8:EC:04:1E", function(properties)
                callback_count = callback_count + 1
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
            assert.is_not_nil(last_properties)
            assert.is_true(last_properties.Connected)
        end)

        it("should handle multiple signals for different devices", function()
            local monitor = DbusMonitor:new()
            local device1_count = 0
            local device2_count = 0

            monitor:registerDeviceCallback("E4:17:D8:EC:04:1E", function()
                device1_count = device1_count + 1
            end)

            monitor:registerDeviceCallback("AA:BB:CC:DD:EE:FF", function()
                device2_count = device2_count + 1
            end)

            -- First device signal
            monitor:_processSignalLine("signal sender=:1.3 path=/org/bluez/hci0/dev_E4_17_D8_EC_04_1E")
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

            assert.equals(1, device1_count)
            assert.equals(1, device2_count)
        end)
    end)
end)
