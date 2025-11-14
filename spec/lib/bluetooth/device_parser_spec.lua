---
-- Unit tests for DeviceParser module.

require("spec.helper")

describe("DeviceParser", function()
    local DeviceParser

    setup(function()
        DeviceParser = require("src/lib/bluetooth/device_parser")
    end)

    describe("parseDiscoveredDevices", function()
        it("should parse empty output", function()
            local devices = DeviceParser.parseDiscoveredDevices("")
            assert.are.equal(0, #devices)
        end)

        it("should parse nil output", function()
            local devices = DeviceParser.parseDiscoveredDevices(nil)
            assert.are.equal(0, #devices)
        end)

        it("should skip adapter-only output and parse only real devices", function()
            local dbus_output = [[
object path "/org/bluez/hci0"
  interface "org.bluez.Adapter1"
    variant boolean true
]]
            local devices = DeviceParser.parseDiscoveredDevices(dbus_output)
            assert.are.equal(0, #devices)
        end)

        it("should parse multiple devices", function()
            local dbus_output = [[
object path "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
  interface "org.bluez.Device1"
    string "Address"
      variant string "AA:BB:CC:DD:EE:FF"
    string "Name"
      variant string "Device One"
    string "Paired"
      variant boolean true
    string "Connected"
      variant boolean false
object path "/org/bluez/hci0/dev_11_22_33_44_55_66"
  interface "org.bluez.Device1"
    string "Address"
      variant string "11:22:33:44:55:66"
    string "Name"
      variant string "Device Two"
    string "Paired"
      variant boolean false
    string "Connected"
      variant boolean true
]]
            local devices = DeviceParser.parseDiscoveredDevices(dbus_output)

            assert.are.equal(2, #devices)

            assert.are.equal("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF", devices[1].path)
            assert.are.equal("AA:BB:CC:DD:EE:FF", devices[1].address)
            assert.are.equal("Device One", devices[1].name)
            assert.is_true(devices[1].paired)
            assert.is_false(devices[1].connected)

            assert.are.equal("/org/bluez/hci0/dev_11_22_33_44_55_66", devices[2].path)
            assert.are.equal("11:22:33:44:55:66", devices[2].address)
            assert.are.equal("Device Two", devices[2].name)
            assert.is_false(devices[2].paired)
            assert.is_true(devices[2].connected)
        end)

        it("should handle devices without names", function()
            local dbus_output = [[
object path "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
  interface "org.bluez.Device1"
    string "Address"
      variant string "AA:BB:CC:DD:EE:FF"
    string "Paired"
      variant boolean true
    string "Connected"
      variant boolean false
]]
            local devices = DeviceParser.parseDiscoveredDevices(dbus_output)

            assert.are.equal(1, #devices)
            assert.are.equal("AA:BB:CC:DD:EE:FF", devices[1].address)
            assert.are.equal("", devices[1].name)
            assert.is_true(devices[1].paired)
            assert.is_false(devices[1].connected)
        end)

        it("should handle devices with empty name property", function()
            local dbus_output = [[
object path "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
  interface "org.bluez.Device1"
    string "Address"
      variant string "AA:BB:CC:DD:EE:FF"
    string "Name"
      variant string ""
    string "Paired"
      variant boolean true
    string "Connected"
      variant boolean false
]]
            local devices = DeviceParser.parseDiscoveredDevices(dbus_output)

            assert.are.equal(1, #devices)
            assert.are.equal("", devices[1].name)
        end)

        it("should handle partial device information", function()
            local dbus_output = [[
object path "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
  interface "org.bluez.Device1"
    string "Address"
      variant string "AA:BB:CC:DD:EE:FF"
]]
            local devices = DeviceParser.parseDiscoveredDevices(dbus_output)

            assert.are.equal(1, #devices)
            assert.are.equal("AA:BB:CC:DD:EE:FF", devices[1].address)
            assert.are.equal("", devices[1].name)
            assert.is_false(devices[1].paired)
            assert.is_false(devices[1].connected)
        end)

        it("should handle complex real-world D-Bus output", function()
            local dbus_output = [[
array [
   dict entry(
      object path "/org/bluez/hci0"
      array [
         dict entry(
            string "org.bluez.Adapter1"
            array [
               dict entry(
                  string "Powered"
                  variant boolean true
               )
            ]
         )
      ]
   )
   dict entry(
      object path "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
      array [
         dict entry(
            string "org.bluez.Device1"
            array [
               dict entry(
                  string "Address"
                  variant string "AA:BB:CC:DD:EE:FF"
               )
               dict entry(
                  string "Name"
                  variant string "My Keyboard"
               )
               dict entry(
                  string "Paired"
                  variant boolean true
               )
               dict entry(
                  string "Connected"
                  variant boolean true
               )
            ]
         )
      ]
   )
]
]]
            local devices = DeviceParser.parseDiscoveredDevices(dbus_output)

            assert.are.equal(1, #devices)
            assert.are.equal("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF", devices[1].path)
            assert.are.equal("AA:BB:CC:DD:EE:FF", devices[1].address)
            assert.are.equal("My Keyboard", devices[1].name)
            assert.is_true(devices[1].paired)
            assert.is_true(devices[1].connected)
        end)

        it("should handle malformed output gracefully", function()
            local dbus_output = "some random text that is not valid D-Bus output"
            local devices = DeviceParser.parseDiscoveredDevices(dbus_output)

            assert.are.equal(0, #devices)
        end)

        it("should parse device paths with various MAC address formats", function()
            local dbus_output = [[
object path "/org/bluez/hci0/dev_A0_B1_C2_D3_E4_F5"
  interface "org.bluez.Device1"
    string "Address"
      variant string "A0:B1:C2:D3:E4:F5"
    string "Paired"
      variant boolean false
    string "Connected"
      variant boolean false
]]
            local devices = DeviceParser.parseDiscoveredDevices(dbus_output)

            assert.are.equal(1, #devices)
            assert.are.equal("A0:B1:C2:D3:E4:F5", devices[1].address)
        end)
    end)
end)
