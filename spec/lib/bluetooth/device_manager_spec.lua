---
-- Unit tests for DeviceManager module.

require("spec.helper")

describe("DeviceManager", function()
    local DeviceManager
    local UIManager

    setup(function()
        DeviceManager = require("src/lib/bluetooth/device_manager")
        UIManager = require("ui/uimanager")
    end)

    before_each(function()
        resetAllMocks()
        UIManager:_reset()
    end)

    describe("new", function()
        it("should create a new instance with empty cache", function()
            local manager = DeviceManager:new()

            assert.is_not_nil(manager)
            assert.is_table(manager.devices_cache)
            assert.are.equal(0, #manager.devices_cache)
        end)
    end)

    describe("scanForDevices", function()
        it("should show scanning message", function()
            setMockExecuteResult(0)
            setMockPopenOutput("")

            local manager = DeviceManager:new()
            manager:scanForDevices(1)

            assert.are.equal(1, #UIManager._show_calls)
            assert.is_not_nil(UIManager._show_calls[1].widget.text)
        end)

        it("should call callback with nil and show error if discovery fails to start", function()
            setMockExecuteResult(1)

            local manager = DeviceManager:new()
            local callback_called = false
            local callback_devices = "not_called"

            manager:scanForDevices(1, function(devices)
                callback_called = true
                callback_devices = devices
            end)

            assert.is_true(callback_called)
            assert.is_nil(callback_devices)
            assert.are.equal(2, #UIManager._show_calls)
        end)

        it("should schedule callback that parses devices on success", function()
            setMockExecuteResult(0)
            local dbus_output = [[
object path "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
  string "Address"
    variant string "AA:BB:CC:DD:EE:FF"
  string "Name"
    variant string "Test Device"
  string "Paired"
    variant boolean true
  string "Connected"
    variant boolean false
]]
            setMockPopenOutput(dbus_output)

            local manager = DeviceManager:new()
            local callback_called = false
            local callback_devices = nil

            manager:scanForDevices(1, function(devices)
                callback_called = true
                callback_devices = devices
            end)

            -- Callback should be scheduled but not called yet
            assert.is_false(callback_called)
            assert.are.equal(1, #UIManager._scheduled_tasks)

            -- Clear executed commands from startDiscovery
            clearExecutedCommands()

            -- Invoke the scheduled callback
            local scheduled_callback = UIManager._scheduled_tasks[1].callback
            scheduled_callback()

            assert.is_true(callback_called)
            assert.is_not_nil(callback_devices)
            assert.are.equal(1, #callback_devices)
            assert.are.equal("Test Device", callback_devices[1].name)

            -- Verify stopDiscovery was called
            local commands = getExecutedCommands()
            assert.are.equal(1, #commands)
            assert.is_true(commands[1]:match("StopDiscovery") ~= nil)
        end)

        it("should use default scan duration if not provided", function()
            setMockExecuteResult(0)
            setMockPopenOutput("")

            local manager = DeviceManager:new()
            manager:scanForDevices()

            assert.is_not_nil(manager)
        end)

        it("should call callback with nil when getManagedObjects fails", function()
            setMockExecuteResult(0)
            setMockPopenFailure()

            local manager = DeviceManager:new()
            local callback_called = false
            local callback_devices = "not_called"

            manager:scanForDevices(1, function(devices)
                callback_called = true
                callback_devices = devices
            end)

            -- Clear executed commands from startDiscovery
            clearExecutedCommands()

            -- Invoke the scheduled callback
            assert.are.equal(1, #UIManager._scheduled_tasks)
            local scheduled_callback = UIManager._scheduled_tasks[1].callback
            scheduled_callback()

            assert.is_true(callback_called)
            assert.is_nil(callback_devices)

            -- Verify stopDiscovery was called
            local commands = getExecutedCommands()
            assert.are.equal(1, #commands)
            assert.is_true(commands[1]:match("StopDiscovery") ~= nil)
        end)

        it("should use default empty callback if none provided", function()
            setMockExecuteResult(0)
            setMockPopenOutput("")

            local manager = DeviceManager:new()
            -- Should not error when no callback provided
            manager:scanForDevices(1)

            assert.are.equal(1, #UIManager._scheduled_tasks)
            local scheduled_callback = UIManager._scheduled_tasks[1].callback
            -- Should not error when invoking default callback
            scheduled_callback()
        end)
    end)

    describe("connectDevice", function()
        it("should show success message on successful connection", function()
            setMockExecuteResult(0)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local manager = DeviceManager:new()
            local result = manager:connectDevice(device)

            assert.is_true(result)
            assert.are.equal(1, #UIManager._show_calls)
        end)

        it("should call on_success callback after connection", function()
            setMockExecuteResult(0)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local callback_called = false
            local callback_device = nil

            local manager = DeviceManager:new()
            manager:connectDevice(device, function(dev)
                callback_called = true
                callback_device = dev
            end)

            assert.is_true(callback_called)
            assert.are.equal(device, callback_device)
        end)

        it("should show error message on failed connection", function()
            setMockExecuteResult(1)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local manager = DeviceManager:new()
            local result = manager:connectDevice(device)

            assert.is_false(result)
            assert.are.equal(1, #UIManager._show_calls)
        end)

        it("should not call on_success callback on failed connection", function()
            setMockExecuteResult(1)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local callback_called = false

            local manager = DeviceManager:new()
            manager:connectDevice(device, function()
                callback_called = true
            end)

            assert.is_false(callback_called)
        end)
    end)

    describe("disconnectDevice", function()
        it("should show success message on successful disconnection", function()
            setMockExecuteResult(0)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local manager = DeviceManager:new()
            local result = manager:disconnectDevice(device)

            assert.is_true(result)
            assert.are.equal(1, #UIManager._show_calls)
        end)

        it("should call on_success callback after disconnection", function()
            setMockExecuteResult(0)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local callback_called = false

            local manager = DeviceManager:new()
            manager:disconnectDevice(device, function()
                callback_called = true
            end)

            assert.is_true(callback_called)
        end)

        it("should show error message on failed disconnection", function()
            setMockExecuteResult(1)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local manager = DeviceManager:new()
            local result = manager:disconnectDevice(device)

            assert.is_false(result)
            assert.are.equal(1, #UIManager._show_calls)
        end)
    end)

    describe("toggleConnection", function()
        it("should connect when device is not connected", function()
            setMockExecuteResult(0)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
                connected = false,
            }

            local connect_called = false

            local manager = DeviceManager:new()
            manager:toggleConnection(device, function()
                connect_called = true
            end)

            assert.is_true(connect_called)
        end)

        it("should disconnect when device is connected", function()
            setMockExecuteResult(0)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
                connected = true,
            }

            local disconnect_called = false

            local manager = DeviceManager:new()
            manager:toggleConnection(device, nil, function()
                disconnect_called = true
            end)

            assert.is_true(disconnect_called)
        end)
    end)

    describe("removeDevice", function()
        it("should show success message on successful removal", function()
            setMockExecuteResult(0)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local manager = DeviceManager:new()
            local result = manager:removeDevice(device)

            assert.is_true(result)
            assert.are.equal(1, #UIManager._show_calls)
            assert.is_true(UIManager._show_calls[1].text:match("Removed") ~= nil)
        end)

        it("should call on_success callback after removal", function()
            setMockExecuteResult(0)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local callback_called = false
            local callback_device = nil

            local manager = DeviceManager:new()
            manager:removeDevice(device, function(dev)
                callback_called = true
                callback_device = dev
            end)

            assert.is_true(callback_called)
            assert.are.equal(device, callback_device)
        end)

        it("should show error message on failed removal", function()
            setMockExecuteResult(1)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local manager = DeviceManager:new()
            local result = manager:removeDevice(device)

            assert.is_false(result)
            assert.are.equal(1, #UIManager._show_calls)
            assert.is_true(UIManager._show_calls[1].text:match("Failed to remove") ~= nil)
        end)

        it("should not call on_success callback on failed removal", function()
            setMockExecuteResult(1)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local callback_called = false

            local manager = DeviceManager:new()
            manager:removeDevice(device, function()
                callback_called = true
            end)

            assert.is_false(callback_called)
        end)
    end)

    describe("loadDevices", function()
        it("should cache all devices", function()
            local dbus_output = [[
object path "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
  string "Address"
    variant string "AA:BB:CC:DD:EE:FF"
  string "Name"
    variant string "Paired Device"
  string "Paired"
    variant boolean true
  string "Connected"
    variant boolean false
object path "/org/bluez/hci0/dev_11_22_33_44_55_66"
  string "Address"
    variant string "11:22:33:44:55:66"
  string "Name"
    variant string "Unpaired Device"
  string "Paired"
    variant boolean false
  string "Connected"
    variant boolean false
]]
            setMockPopenOutput(dbus_output)

            local manager = DeviceManager:new()
            manager:loadDevices()

            local device_count = 0

            for _ in pairs(manager.devices_cache) do
                device_count = device_count + 1
            end

            assert.are.equal(2, device_count)
            assert.are.equal("Paired Device", manager.devices_cache["AA:BB:CC:DD:EE:FF"].name)
            assert.is_true(manager.devices_cache["AA:BB:CC:DD:EE:FF"].paired)
            assert.are.equal("Unpaired Device", manager.devices_cache["11:22:33:44:55:66"].name)
            assert.is_false(manager.devices_cache["11:22:33:44:55:66"].paired)
        end)

        it("should handle empty response", function()
            setMockPopenOutput("")

            local manager = DeviceManager:new()
            manager:loadDevices()

            local device_count = 0

            for _ in pairs(manager.devices_cache) do
                device_count = device_count + 1
            end

            assert.are.equal(0, device_count)
        end)

        it("should replace previous cache", function()
            local first_output = [[
object path "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
  string "Address"
    variant string "AA:BB:CC:DD:EE:FF"
  string "Paired"
    variant boolean true
]]
            setMockPopenOutput(first_output)

            local manager = DeviceManager:new()
            manager:loadDevices()

            local device_count = 0

            for _ in pairs(manager.devices_cache) do
                device_count = device_count + 1
            end

            assert.are.equal(1, device_count)

            local second_output = [[
object path "/org/bluez/hci0/dev_11_22_33_44_55_66"
  string "Address"
    variant string "11:22:33:44:55:66"
  string "Paired"
    variant boolean true
object path "/org/bluez/hci0/dev_22_33_44_55_66_77"
  string "Address"
    variant string "22:33:44:55:66:77"
  string "Paired"
    variant boolean true
]]
            setMockPopenOutput(second_output)

            manager:loadDevices()

            device_count = 0

            for _ in pairs(manager.devices_cache) do
                device_count = device_count + 1
            end

            assert.are.equal(2, device_count)
        end)
    end)

    describe("getDevices", function()
        it("should return the cached devices", function()
            local dbus_output = [[
object path "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
  string "Address"
    variant string "AA:BB:CC:DD:EE:FF"
  string "Paired"
    variant boolean true
]]
            setMockPopenOutput(dbus_output)

            local manager = DeviceManager:new()
            manager:loadDevices()

            local devices = manager:getDevices()

            assert.are.equal(1, #devices)
            assert.are.equal("AA:BB:CC:DD:EE:FF", devices[1].address)
        end)
    end)

    describe("trustDevice", function()
        it("should show success message on successful trust", function()
            setMockExecuteResult(0)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local manager = DeviceManager:new()
            local result = manager:trustDevice(device)

            assert.is_true(result)
            assert.are.equal(1, #UIManager._show_calls)
        end)

        it("should call on_success callback after trusting", function()
            setMockExecuteResult(0)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local callback_called = false
            local callback_device = nil

            local manager = DeviceManager:new()
            manager:trustDevice(device, function(dev)
                callback_called = true
                callback_device = dev
            end)

            assert.is_true(callback_called)
            assert.are.equal(device, callback_device)
        end)

        it("should show error message on failed trust", function()
            setMockExecuteResult(1)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local manager = DeviceManager:new()
            local result = manager:trustDevice(device)

            assert.is_false(result)
            assert.are.equal(1, #UIManager._show_calls)
        end)

        it("should not call on_success callback on failed trust", function()
            setMockExecuteResult(1)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local callback_called = false

            local manager = DeviceManager:new()
            manager:trustDevice(device, function()
                callback_called = true
            end)

            assert.is_false(callback_called)
        end)
    end)

    describe("untrustDevice", function()
        it("should show success message on successful untrust", function()
            setMockExecuteResult(0)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local manager = DeviceManager:new()
            local result = manager:untrustDevice(device)

            assert.is_true(result)
            assert.are.equal(1, #UIManager._show_calls)
        end)

        it("should call on_success callback after untrusting", function()
            setMockExecuteResult(0)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local callback_called = false
            local callback_device = nil

            local manager = DeviceManager:new()
            manager:untrustDevice(device, function(dev)
                callback_called = true
                callback_device = dev
            end)

            assert.is_true(callback_called)
            assert.are.equal(device, callback_device)
        end)

        it("should show error message on failed untrust", function()
            setMockExecuteResult(1)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local manager = DeviceManager:new()
            local result = manager:untrustDevice(device)

            assert.is_false(result)
            assert.are.equal(1, #UIManager._show_calls)
        end)

        it("should not call on_success callback on failed untrust", function()
            setMockExecuteResult(1)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local callback_called = false

            local manager = DeviceManager:new()
            manager:untrustDevice(device, function()
                callback_called = true
            end)

            assert.is_false(callback_called)
        end)
    end)
    describe("connectDeviceInBackground", function()
        before_each(function()
            -- Clear cached modules so ffi/util mock is used fresh
            package.loaded["src/lib/bluetooth/dbus_adapter"] = nil
            package.loaded["ffi/util"] = nil
        end)

        it("should return true when background connect starts successfully", function()
            setMockRunInSubProcessResult(12345)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local manager = DeviceManager:new()
            local result = manager:connectDeviceInBackground(device)

            assert.is_true(result)
        end)

        it("should return false when background connect fails to start", function()
            setMockRunInSubProcessResult(false)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local manager = DeviceManager:new()
            local result = manager:connectDeviceInBackground(device)

            assert.is_false(result)
        end)

        it("should call DbusAdapter.connectDeviceInBackground with device path", function()
            setMockRunInSubProcessResult(12345)

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
            }

            local manager = DeviceManager:new()
            manager:connectDeviceInBackground(device)

            -- Verify the subprocess was started (callback was captured)
            local captured_callback = getMockRunInSubProcessCallback()
            assert.is_not_nil(captured_callback)
        end)
    end)
end)
