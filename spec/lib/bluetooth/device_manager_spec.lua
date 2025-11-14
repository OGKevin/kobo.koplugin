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
            assert.is_table(manager.paired_devices_cache)
            assert.are.equal(0, #manager.paired_devices_cache)
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

        it("should return nil and show error if discovery fails to start", function()
            setMockExecuteResult(1)

            local manager = DeviceManager:new()
            local devices = manager:scanForDevices()

            assert.is_nil(devices)
            assert.are.equal(2, #UIManager._show_calls)
        end)

        it("should return parsed devices on success", function()
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
            local devices = manager:scanForDevices(1)

            assert.is_not_nil(devices)
            assert.are.equal(1, #devices)
            assert.are.equal("Test Device", devices[1].name)
        end)

        it("should use default scan duration if not provided", function()
            setMockExecuteResult(0)
            setMockPopenOutput("")

            local manager = DeviceManager:new()
            manager:scanForDevices()

            assert.is_not_nil(manager)
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

    describe("loadPairedDevices", function()
        it("should cache only paired devices", function()
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
            manager:loadPairedDevices()

            assert.are.equal(1, #manager.paired_devices_cache)
            assert.are.equal("Paired Device", manager.paired_devices_cache[1].name)
            assert.is_true(manager.paired_devices_cache[1].paired)
        end)

        it("should handle empty response", function()
            setMockPopenOutput("")

            local manager = DeviceManager:new()
            manager:loadPairedDevices()

            assert.are.equal(0, #manager.paired_devices_cache)
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
            manager:loadPairedDevices()
            assert.are.equal(1, #manager.paired_devices_cache)

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

            manager:loadPairedDevices()

            assert.are.equal(2, #manager.paired_devices_cache)
        end)
    end)

    describe("getPairedDevices", function()
        it("should return the cached paired devices", function()
            local dbus_output = [[
object path "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
  string "Address"
    variant string "AA:BB:CC:DD:EE:FF"
  string "Paired"
    variant boolean true
]]
            setMockPopenOutput(dbus_output)

            local manager = DeviceManager:new()
            manager:loadPairedDevices()

            local devices = manager:getPairedDevices()

            assert.are.equal(1, #devices)
            assert.are.equal("AA:BB:CC:DD:EE:FF", devices[1].address)
        end)
    end)
end)
