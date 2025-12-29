---
-- Unit tests for DbusAdapter factory module.

require("spec.helper")

describe("DbusAdapter factory", function()
    local Device

    setup(function()
        Device = require("device")
    end)

    before_each(function()
        resetAllMocks()
        -- Clear cached modules to test factory initialization fresh
        package.loaded["src/lib/bluetooth/dbus_adapter"] = nil
        package.loaded["src/lib/bluetooth/adapters/mtk_adapter"] = nil
    end)

    describe("device detection and adapter selection", function()
        it("should load MTK adapter for MTK devices", function()
            Device._isMTK = true
            setMockPopenOutput("variant boolean true")

            local adapter = require("src/lib/bluetooth/dbus_adapter")
            local result = adapter.isEnabled()

            -- Verify MTK adapter was loaded by checking it returns expected result
            assert.is_true(result)
        end)

        it("should return false for turnOn on non-MTK devices", function()
            Device._isMTK = false

            local adapter = require("src/lib/bluetooth/dbus_adapter")

            assert.is_false(adapter.turnOn())
        end)

        it("should return false for turnOff on non-MTK devices", function()
            Device._isMTK = false

            local adapter = require("src/lib/bluetooth/dbus_adapter")

            assert.is_false(adapter.turnOff())
        end)

        it("should return false for isEnabled on non-MTK devices", function()
            Device._isMTK = false

            local adapter = require("src/lib/bluetooth/dbus_adapter")

            assert.is_false(adapter.isEnabled())
        end)

        it("should return nil for getManagedObjects on non-MTK devices", function()
            Device._isMTK = false

            local adapter = require("src/lib/bluetooth/dbus_adapter")

            assert.is_nil(adapter.getManagedObjects())
        end)

        it("should return false for connectDevice on non-MTK devices", function()
            Device._isMTK = false

            local adapter = require("src/lib/bluetooth/dbus_adapter")

            assert.is_false(adapter.connectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"))
        end)

        it("should return false for disconnectDevice on non-MTK devices", function()
            Device._isMTK = false

            local adapter = require("src/lib/bluetooth/dbus_adapter")

            assert.is_false(adapter.disconnectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"))
        end)

        it("should return false for removeDevice on non-MTK devices", function()
            Device._isMTK = false

            local adapter = require("src/lib/bluetooth/dbus_adapter")

            assert.is_false(adapter.removeDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"))
        end)

        it("should return false for setDeviceTrusted on non-MTK devices", function()
            Device._isMTK = false

            local adapter = require("src/lib/bluetooth/dbus_adapter")

            assert.is_false(adapter.setDeviceTrusted("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF", true))
        end)

        it("should return false for startDiscovery on non-MTK devices", function()
            Device._isMTK = false

            local adapter = require("src/lib/bluetooth/dbus_adapter")

            assert.is_false(adapter.startDiscovery())
        end)

        it("should return false for stopDiscovery on non-MTK devices", function()
            Device._isMTK = false

            local adapter = require("src/lib/bluetooth/dbus_adapter")

            assert.is_false(adapter.stopDiscovery())
        end)

        it("should return false for executeCommands on non-MTK devices", function()
            Device._isMTK = false

            local adapter = require("src/lib/bluetooth/dbus_adapter")

            assert.is_false(adapter.executeCommands({ "command1", "command2" }))
        end)

        it("should return false for connectDeviceInBackground on non-MTK devices", function()
            Device._isMTK = false

            local adapter = require("src/lib/bluetooth/dbus_adapter")

            assert.is_false(adapter.connectDeviceInBackground("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"))
        end)
    end)

    describe("backward compatibility", function()
        before_each(function()
            Device._isMTK = true
            setMockExecuteResult(0)
            setMockPopenOutput("variant boolean true")
        end)

        it("should provide static API for turnOn", function()
            local adapter = require("src/lib/bluetooth/dbus_adapter")
            assert.is_true(adapter.turnOn())
        end)

        it("should provide static API for turnOff", function()
            local adapter = require("src/lib/bluetooth/dbus_adapter")
            assert.is_true(adapter.turnOff())
        end)

        it("should provide static API for isEnabled", function()
            local adapter = require("src/lib/bluetooth/dbus_adapter")
            assert.is_true(adapter.isEnabled())
        end)

        it("should provide static API for startDiscovery", function()
            local adapter = require("src/lib/bluetooth/dbus_adapter")
            assert.is_true(adapter.startDiscovery())
        end)

        it("should provide static API for stopDiscovery", function()
            local adapter = require("src/lib/bluetooth/dbus_adapter")
            assert.is_true(adapter.stopDiscovery())
        end)

        it("should provide static API for getManagedObjects", function()
            local adapter = require("src/lib/bluetooth/dbus_adapter")
            local output = adapter.getManagedObjects()
            assert.is_not_nil(output)
        end)

        it("should provide static API for connectDevice", function()
            local adapter = require("src/lib/bluetooth/dbus_adapter")
            assert.is_true(adapter.connectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"))
        end)

        it("should provide static API for disconnectDevice", function()
            local adapter = require("src/lib/bluetooth/dbus_adapter")
            assert.is_true(adapter.disconnectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"))
        end)

        it("should provide static API for removeDevice", function()
            local adapter = require("src/lib/bluetooth/dbus_adapter")
            assert.is_true(adapter.removeDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"))
        end)

        it("should provide static API for setDeviceTrusted", function()
            local adapter = require("src/lib/bluetooth/dbus_adapter")
            assert.is_true(adapter.setDeviceTrusted("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF", true))
        end)

        it("should provide static API for executeCommands", function()
            local adapter = require("src/lib/bluetooth/dbus_adapter")
            assert.is_true(adapter.executeCommands({ "command1", "command2" }))
        end)

        it("should provide static API for connectDeviceInBackground", function()
            setMockRunInSubProcessResult(12345)
            package.loaded["ffi/util"] = nil

            local adapter = require("src/lib/bluetooth/dbus_adapter")
            assert.is_true(adapter.connectDeviceInBackground("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"))
        end)
    end)
end)
