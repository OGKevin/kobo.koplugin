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

            assert.equals(2, callback_count)
            assert.equals("E4:17:D8:EC:04:1E", device_addresses[1])
            assert.equals("AA:BB:CC:DD:EE:FF", device_addresses[2])
        end)
    end)
end)
