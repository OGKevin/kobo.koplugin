describe("InputDeviceHandler", function()
    local InputDeviceHandler
    local handler

    setup(function()
        require("spec/helper")
    end)

    before_each(function()
        InputDeviceHandler = require("src/lib/bluetooth/input_device_handler")
        handler = InputDeviceHandler:new()
    end)

    describe("initialization", function()
        it("should create a new instance with default values", function()
            assert.is_not_nil(handler)
            assert.are.equal("/dev/input/event4", handler.input_device_path)
            assert.are.same({}, handler.isolated_readers)
            assert.are.same({}, handler.key_event_callbacks)
        end)
    end)

    describe("_getDeviceName", function()
        it("should return nil for invalid path", function()
            local name = handler:_getDeviceName("invalid")
            assert.is_nil(name)
        end)

        it("should extract event number from path", function()
            -- Mock the file read
            local original_open = io.open
            io.open = function(path, mode)
                if path == "/sys/class/input/event4/device/name" then
                    return {
                        read = function()
                            return "Test Device"
                        end,
                        close = function() end,
                    }
                end

                return nil
            end

            local name = handler:_getDeviceName("/dev/input/event4")
            assert.are.equal("Test Device", name)

            io.open = original_open
        end)
    end)

    describe("findDeviceByName", function()
        it("should return nil when device name is empty", function()
            local path = handler:findDeviceByName("")
            assert.is_nil(path)
        end)

        it("should return nil when device name is nil", function()
            local path = handler:findDeviceByName(nil)
            assert.is_nil(path)
        end)

        it("should find device by matching name", function()
            -- Mock detectBluetoothInputDevices
            handler.detectBluetoothInputDevices = function()
                return { "/dev/input/event4", "/dev/input/event5" }
            end

            -- Mock _getDeviceName
            handler._getDeviceName = function(self, path)
                if path == "/dev/input/event4" then
                    return "Device A"
                elseif path == "/dev/input/event5" then
                    return "Device B"
                end

                return nil
            end

            local path = handler:findDeviceByName("Device B")
            assert.are.equal("/dev/input/event5", path)
        end)

        it("should return nil when no matching device found", function()
            handler.detectBluetoothInputDevices = function()
                return { "/dev/input/event4" }
            end

            handler._getDeviceName = function(self, path)
                return "Device A"
            end

            local path = handler:findDeviceByName("Device B")
            assert.is_nil(path)
        end)
    end)

    describe("_autoDetectInputDevice", function()
        it("should return fallback when no devices detected", function()
            handler.detectBluetoothInputDevices = function()
                return {}
            end

            local path = handler:_autoDetectInputDevice()
            assert.are.equal("/dev/input/event4", path)
        end)

        it("should auto-select when single device detected", function()
            handler.detectBluetoothInputDevices = function()
                return { "/dev/input/event5" }
            end

            local path = handler:_autoDetectInputDevice()
            assert.are.equal("/dev/input/event5", path)
        end)

        it("should return fallback when multiple devices detected", function()
            handler.detectBluetoothInputDevices = function()
                return { "/dev/input/event4", "/dev/input/event5" }
            end

            local path = handler:_autoDetectInputDevice()
            assert.are.equal("/dev/input/event4", path)
        end)
    end)

    describe("waitForBluetoothInputDevice", function()
        local original_time
        local mock_time

        before_each(function()
            original_time = os.time
            mock_time = 0

            os.time = function()
                return mock_time
            end

            -- Mock ffiUtil.sleep
            package.loaded["ffi/util"] = {
                sleep = function(duration)
                    mock_time = mock_time + duration
                end,
            }
        end)

        after_each(function()
            os.time = original_time
            package.loaded["ffi/util"] = nil
        end)

        it("should detect new device when count increases from 0 to 1", function()
            local call_count = 0

            handler.detectBluetoothInputDevices = function()
                call_count = call_count + 1

                if call_count == 1 then
                    return {} -- Initial scan: no devices
                else
                    return { "/dev/input/event4" } -- New device appeared
                end
            end

            local path = handler:waitForBluetoothInputDevice(3, 0.1)
            assert.are.equal("/dev/input/event4", path)
        end)

        it("should detect new device when count increases from 1 to 2", function()
            local call_count = 0

            handler.detectBluetoothInputDevices = function()
                call_count = call_count + 1

                if call_count == 1 then
                    return { "/dev/input/event4" } -- Initial: 1 device
                else
                    return { "/dev/input/event4", "/dev/input/event5" } -- New device appeared
                end
            end

            local path = handler:waitForBluetoothInputDevice(3, 0.1)
            assert.are.equal("/dev/input/event5", path) -- Should return the NEW device
        end)

        it("should timeout when no new device appears", function()
            handler.detectBluetoothInputDevices = function()
                return { "/dev/input/event4" } -- Same device every time
            end

            local path = handler:waitForBluetoothInputDevice(1, 0.1)
            assert.is_nil(path)
        end)

        it("should return the correct new device when multiple initial devices exist", function()
            local call_count = 0

            handler.detectBluetoothInputDevices = function()
                call_count = call_count + 1

                if call_count == 1 then
                    return { "/dev/input/event4", "/dev/input/event5" } -- Initial: 2 devices
                else
                    return { "/dev/input/event4", "/dev/input/event5", "/dev/input/event6" } -- +1 new
                end
            end

            local path = handler:waitForBluetoothInputDevice(3, 0.1)
            assert.are.equal("/dev/input/event6", path) -- Should return event6, not event4 or event5
        end)
    end)

    describe("openIsolatedInputDevice", function()
        local device_info

        before_each(function()
            device_info = {
                address = "AA:BB:CC:DD:EE:FF",
                name = "Test Device",
            }
        end)

        it("should use name matching as primary strategy", function()
            local name_match_called = false

            handler.findDeviceByName = function(self, name)
                name_match_called = true

                return "/dev/input/event5"
            end

            handler:openIsolatedInputDevice(device_info, false, false)

            assert.is_true(name_match_called)
        end)

        it("should fall back to auto-detection when name matching fails", function()
            local auto_detect_called = false

            handler.findDeviceByName = function()
                return nil -- Name matching fails
            end

            handler._autoDetectInputDevice = function()
                auto_detect_called = true

                return "/dev/input/event4"
            end

            handler:openIsolatedInputDevice(device_info, false, false)

            assert.is_true(auto_detect_called)
        end)

        it("should register callbacks with the isolated reader", function()
            handler.findDeviceByName = function()
                return "/dev/input/event4"
            end

            handler:registerKeyEventCallback(function() end)

            handler:openIsolatedInputDevice(device_info, false, false)

            -- Check that reader was created and has callbacks
            assert.is_not_nil(handler.isolated_readers["AA:BB:CC:DD:EE:FF"])
            local reader = handler.isolated_readers["AA:BB:CC:DD:EE:FF"].reader
            assert.is_not_nil(reader)
            assert.is_true(#reader.callbacks > 0)
        end)
    end)

    describe("closeIsolatedInputDevice", function()
        it("should close and remove the isolated reader", function()
            local device_info = {
                address = "AA:BB:CC:DD:EE:FF",
                name = "Test Device",
            }

            handler.findDeviceByName = function()
                return "/dev/input/event4"
            end

            handler:openIsolatedInputDevice(device_info, false, false)
            assert.is_not_nil(handler.isolated_readers["AA:BB:CC:DD:EE:FF"])

            handler:closeIsolatedInputDevice(device_info)
            assert.is_nil(handler.isolated_readers["AA:BB:CC:DD:EE:FF"])
        end)
    end)

    describe("hasIsolatedReaders", function()
        it("should return false when no readers are open", function()
            assert.is_false(handler:hasIsolatedReaders())
        end)

        it("should return true when readers are open", function()
            local device_info = {
                address = "AA:BB:CC:DD:EE:FF",
                name = "Test Device",
            }

            handler.findDeviceByName = function()
                return "/dev/input/event4"
            end

            handler:openIsolatedInputDevice(device_info, false, false)
            assert.is_true(handler:hasIsolatedReaders())
        end)
    end)

    describe("pollIsolatedReaders", function()
        it("should clean up disconnected readers and invoke callbacks", function()
            -- Setup: open a device and mock its reader
            local device_info = { address = "AA:BB:CC:DD:EE:FF", name = "Test Device" }
            handler.findDeviceByName = function()
                return "/dev/input/event4"
            end
            handler:openIsolatedInputDevice(device_info, false, false)

            -- Verify reader was created
            assert.is_not_nil(handler.isolated_readers["AA:BB:CC:DD:EE:FF"])

            -- Mock the reader as closed
            local reader = handler.isolated_readers["AA:BB:CC:DD:EE:FF"].reader
            reader.isOpen = function()
                return false
            end

            -- Register a callback to track invocations
            local callback_invoked = false
            local callback_address = nil
            local callback_path = nil
            handler:registerDeviceCloseCallback(function(addr, path)
                callback_invoked = true
                callback_address = addr
                callback_path = path
            end)

            -- Act: poll should detect and clean up
            handler:pollIsolatedReaders(0)

            -- Assert: reader should be removed from table
            assert.is_nil(handler.isolated_readers["AA:BB:CC:DD:EE:FF"])

            -- Assert: callback should have been invoked with correct parameters
            assert.is_true(callback_invoked)
            assert.are.equal("AA:BB:CC:DD:EE:FF", callback_address)
            assert.are.equal("/dev/input/event4", callback_path)
        end)

        it("should continue cleanup loop when callback throws error", function()
            -- Setup: open two devices
            local device1 = { address = "AA:BB:CC:DD:EE:FF", name = "Device 1" }
            local device2 = { address = "11:22:33:44:55:66", name = "Device 2" }

            local call_count = 0
            handler.findDeviceByName = function()
                call_count = call_count + 1
                if call_count == 1 then
                    return "/dev/input/event4"
                else
                    return "/dev/input/event5"
                end
            end

            handler:openIsolatedInputDevice(device1, false, false)
            handler:openIsolatedInputDevice(device2, false, false)

            -- Mock both readers as closed
            handler.isolated_readers["AA:BB:CC:DD:EE:FF"].reader.isOpen = function()
                return false
            end
            handler.isolated_readers["11:22:33:44:55:66"].reader.isOpen = function()
                return false
            end

            -- Register two callbacks: first throws error, second succeeds
            local callback1_invoked = false
            local callback2_invoked = false

            handler:registerDeviceCloseCallback(function(addr, path)
                callback1_invoked = true
                error("Simulated callback error")
            end)

            handler:registerDeviceCloseCallback(function(addr, path)
                callback2_invoked = true
            end)

            -- Act: poll should handle errors gracefully
            handler:pollIsolatedReaders(0)

            -- Assert: both readers should be removed despite callback error
            assert.is_nil(handler.isolated_readers["AA:BB:CC:DD:EE:FF"])
            assert.is_nil(handler.isolated_readers["11:22:33:44:55:66"])

            -- Assert: both callbacks should have been attempted
            assert.is_true(callback1_invoked)
            assert.is_true(callback2_invoked)
        end)

        it("should not clean up readers that are still open", function()
            -- Setup: open a device
            local device_info = { address = "AA:BB:CC:DD:EE:FF", name = "Test Device" }
            handler.findDeviceByName = function()
                return "/dev/input/event4"
            end
            handler:openIsolatedInputDevice(device_info, false, false)

            -- Reader stays open (default behavior, no need to mock)
            local reader = handler.isolated_readers["AA:BB:CC:DD:EE:FF"].reader
            assert.is_not_nil(reader)

            -- Register callback that should NOT be invoked
            local callback_invoked = false
            handler:registerDeviceCloseCallback(function(addr, path)
                callback_invoked = true
            end)

            -- Act: poll should not clean up open reader
            handler:pollIsolatedReaders(0)

            -- Assert: reader should still be present
            assert.is_not_nil(handler.isolated_readers["AA:BB:CC:DD:EE:FF"])

            -- Assert: callback should NOT have been invoked
            assert.is_false(callback_invoked)
        end)
    end)
end)
