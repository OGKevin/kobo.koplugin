---
-- Integration tests for KoboBluetooth module.
-- Tests the integration between KoboBluetooth, DeviceManager, InputDeviceHandler, and UI components.

require("spec.helper")

describe("KoboBluetooth Integration", function()
    local KoboBluetooth
    local Device
    local UIManager

    setup(function()
        Device = require("device")
        UIManager = require("ui/uimanager")
        KoboBluetooth = require("src.kobo_bluetooth")
    end)

    before_each(function()
        UIManager:_reset()
        Device.isMTK = true
        Device.isKobo = function()
            return true
        end
        resetAllMocks()
    end)

    describe("Initialization with Bluetooth enabled", function()
        it("should initialize device_manager and input_handler", function()
            setMockPopenOutput("variant boolean true")
            local instance = KoboBluetooth:new()
            instance:init()

            assert.is_not_nil(instance.device_manager)
            assert.is_not_nil(instance.input_handler)
            assert.is_true(instance.bluetooth_standby_prevented)
        end)

        it("should load paired devices and auto-open connected devices on startup", function()
            local dbus_output = [[
object path "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
  string "Address"
    variant string "AA:BB:CC:DD:EE:FF"
  string "Name"
    variant string "Connected Device"
  string "Paired"
    variant boolean true
  string "Connected"
    variant boolean true
]]
            setMockPopenOutput(dbus_output)

            local instance = KoboBluetooth:new()
            instance:init()

            local paired_devices = instance.device_manager:getPairedDevices()
            assert.are.equal(1, #paired_devices)
            assert.are.equal("Connected Device", paired_devices[1].name)
            assert.is_true(paired_devices[1].connected)
        end)
    end)

    describe("Device scanning workflow", function()
        it("should scan, parse, and show devices", function()
            setMockPopenOutput("variant boolean true")
            setMockExecuteResult(0)

            local instance = KoboBluetooth:new()
            instance:init()

            UIManager:_reset()

            local dbus_scan_output = [[
object path "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
  string "Address"
    variant string "AA:BB:CC:DD:EE:FF"
  string "Name"
    variant string "Scanned Device"
  string "Paired"
    variant boolean false
  string "Connected"
    variant boolean false
]]
            setMockPopenOutput(dbus_scan_output)

            instance:scanAndShowDevices()

            assert.is_true(#UIManager._show_calls >= 1)
        end)

        it("should show error if Bluetooth is not enabled", function()
            setMockPopenOutput("variant boolean false")

            local instance = KoboBluetooth:new()
            instance:init()

            instance:scanAndShowDevices()

            assert.are.equal(1, #UIManager._show_calls)
            assert.is_not_nil(UIManager._show_calls[1].widget.text:match("enable Bluetooth"))
        end)
    end)

    describe("Device connection workflow", function()
        it("should connect device through device_manager", function()
            setMockPopenOutput("variant boolean true")
            setMockExecuteResult(0)

            local instance = KoboBluetooth:new()
            instance:init()

            local device = {
                path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF",
                name = "Test Device",
                address = "AA:BB:CC:DD:EE:FF",
                connected = false,
            }

            local on_connect_called = false
            instance.device_manager:connectDevice(device, function()
                on_connect_called = true
            end)

            assert.is_true(on_connect_called)
        end)
    end)

    describe("Paired devices workflow", function()
        it("should load and display paired devices", function()
            setMockPopenOutput("variant boolean true")

            local dbus_paired_output = [[
object path "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
  string "Address"
    variant string "AA:BB:CC:DD:EE:FF"
  string "Name"
    variant string "Paired Device 1"
  string "Paired"
    variant boolean true
  string "Connected"
    variant boolean false
object path "/org/bluez/hci0/dev_11_22_33_44_55_66"
  string "Address"
    variant string "11:22:33:44:55:66"
  string "Name"
    variant string "Paired Device 2"
  string "Paired"
    variant boolean true
  string "Connected"
    variant boolean true
]]
            setMockPopenOutput(dbus_paired_output)

            local instance = KoboBluetooth:new()
            instance:init()

            instance:showPairedDevices()

            local paired_devices = instance.device_manager:getPairedDevices()
            assert.are.equal(2, #paired_devices)
            assert.are.equal("Paired Device 1", paired_devices[1].name)
            assert.are.equal("Paired Device 2", paired_devices[2].name)
        end)
    end)

    describe("Bluetooth on/off workflow with device management", function()
        it("should turn on Bluetooth and load paired devices", function()
            setMockPopenOutput("variant boolean false")
            setMockExecuteResult(0)

            local instance = KoboBluetooth:new()
            instance:init()

            UIManager:_reset()

            instance:turnBluetoothOn()

            assert.is_true(instance.bluetooth_standby_prevented)
            assert.are.equal(1, UIManager._prevent_standby_calls)

            local dbus_paired_output = [[
object path "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
  string "Address"
    variant string "AA:BB:CC:DD:EE:FF"
  string "Paired"
    variant boolean true
]]
            setMockPopenOutput(dbus_paired_output)

            instance.device_manager:loadPairedDevices()

            local paired_devices = instance.device_manager:getPairedDevices()
            assert.are.equal(1, #paired_devices)
        end)

        it("should turn off Bluetooth and allow standby", function()
            setMockPopenOutput("variant boolean true")
            setMockExecuteResult(0)

            local instance = KoboBluetooth:new()
            instance:init()

            instance.bluetooth_standby_prevented = true

            instance:turnBluetoothOff()

            assert.is_false(instance.bluetooth_standby_prevented)
            assert.are.equal(1, UIManager._allow_standby_calls)
        end)
    end)

    describe("Main menu integration", function()
        it("should create menu with all expected items", function()
            setMockPopenOutput("variant boolean false")

            local instance = KoboBluetooth:new()
            instance:init()

            local menu_items = {}
            instance:addToMainMenu(menu_items)

            assert.is_not_nil(menu_items.bluetooth)
            assert.are.equal("Bluetooth", menu_items.bluetooth.text)
            assert.are.equal(3, #menu_items.bluetooth.sub_item_table)

            assert.are.equal("Enable/Disable", menu_items.bluetooth.sub_item_table[1].text)
            assert.are.equal("Scan for devices", menu_items.bluetooth.sub_item_table[2].text)
            assert.are.equal("Paired devices", menu_items.bluetooth.sub_item_table[3].text)
        end)

        it("should enable scan menu only when Bluetooth is on", function()
            setMockPopenOutput("variant boolean false")

            local instance = KoboBluetooth:new()
            instance:init()

            local menu_items = {}
            instance:addToMainMenu(menu_items)

            local scan_item = menu_items.bluetooth.sub_item_table[2]
            assert.is_function(scan_item.enabled_func)
            assert.is_false(scan_item.enabled_func())

            setMockPopenOutput("variant boolean true")
            assert.is_true(scan_item.enabled_func())
        end)
    end)
end)
