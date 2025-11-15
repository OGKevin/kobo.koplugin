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
            assert.are.same({}, handler.bt_input_devices)
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

    describe("openInputDevice", function()
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

            -- Mock file existence and Device.input
            io.open = function(path)
                return {
                    close = function() end,
                }
            end

            package.loaded["device"] = {
                input = {
                    open = function() end,
                    close = function() end,
                },
            }

            handler:openInputDevice(device_info, false, false)

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

            io.open = function()
                return {
                    close = function() end,
                }
            end

            package.loaded["device"] = {
                input = {
                    open = function() end,
                },
            }

            handler:openInputDevice(device_info, false, false)

            assert.is_true(auto_detect_called)
        end)
    end)
end)
