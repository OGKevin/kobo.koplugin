---
-- Unit tests for Libra2Adapter module.

require("spec.helper")

describe("Libra2Adapter", function()
    local Libra2Adapter

    setup(function()
        Libra2Adapter = require("src/lib/bluetooth/adapters/libra2_adapter")
    end)

    before_each(function()
        resetAllMocks()
    end)

    describe("executeCommands", function()
        it("should execute all commands in sequence on success", function()
            setMockExecuteResult(0)
            local commands = { "command1", "command2", "command3" }
            local result = Libra2Adapter.executeCommands(commands)

            assert.is_true(result)
        end)

        it("should return false if any command fails", function()
            setMockExecuteResult(1)
            local commands = { "good_command", "fail_command", "another_command" }
            local result = Libra2Adapter.executeCommands(commands)

            assert.is_false(result)
        end)

        it("should handle empty command list", function()
            setMockExecuteResult(0)
            local result = Libra2Adapter.executeCommands({})

            assert.is_true(result)
        end)
    end)

    describe("isEnabled", function()
        it("should return true when D-Bus returns 'boolean true'", function()
            setMockPopenOutput("variant boolean true")
            assert.is_true(Libra2Adapter.isEnabled())
        end)

        it("should return false when D-Bus returns 'boolean false'", function()
            setMockPopenOutput("variant boolean false")
            assert.is_false(Libra2Adapter.isEnabled())
        end)

        it("should return false when D-Bus command fails", function()
            setMockPopenOutput("")
            assert.is_false(Libra2Adapter.isEnabled())
        end)

        it("should return false when D-Bus returns unexpected format", function()
            setMockPopenOutput("unexpected output")
            assert.is_false(Libra2Adapter.isEnabled())
        end)
    end)

    describe("turnOn", function()
        it("should execute ON commands and return true on success", function()
            setMockExecuteResult(0)
            assert.is_true(Libra2Adapter.turnOn())
        end)

        it("should return false if commands fail", function()
            setMockExecuteResult(1)
            assert.is_false(Libra2Adapter.turnOn())
        end)

        it("should execute correct D-Bus commands", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            Libra2Adapter.turnOn()

            local commands = getExecutedCommands()
            assert.are.equal(4, #commands)
            assert.are.equal("/libexec/bluetooth/bluetoothd &", commands[1])
            assert.are.equal("hciconfig hci0 down", commands[2])
            assert.are.equal("hciconfig hci0 up", commands[3])
            assert.are.equal(
                "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
                    .. "org.freedesktop.DBus.Properties.Set "
                    .. "string:org.bluez.Adapter1 string:Powered variant:boolean:true",
                commands[4]
            )
        end)
    end)

    describe("turnOff", function()
        it("should execute OFF commands and return true on success", function()
            setMockExecuteResult(0)
            assert.is_true(Libra2Adapter.turnOff())
        end)

        it("should return false if commands fail", function()
            setMockExecuteResult(1)
            assert.is_false(Libra2Adapter.turnOff())
        end)

        it("should execute correct D-Bus commands", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            Libra2Adapter.turnOff()

            local commands = getExecutedCommands()
            assert.are.equal(2, #commands)
            assert.are.equal(
                "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
                    .. "org.freedesktop.DBus.Properties.Set "
                    .. "string:org.bluez.Adapter1 string:Powered variant:boolean:false",
                commands[1]
            )
            assert.are.equal("killall bluetoothd", commands[2])
        end)
    end)

    describe("startDiscovery", function()
        it("should return true on success", function()
            setMockExecuteResult(0)
            assert.is_true(Libra2Adapter.startDiscovery())
        end)

        it("should return false on failure", function()
            setMockExecuteResult(1)
            assert.is_false(Libra2Adapter.startDiscovery())
        end)
    end)

    describe("stopDiscovery", function()
        it("should return true on success", function()
            setMockExecuteResult(0)
            assert.is_true(Libra2Adapter.stopDiscovery())
        end)

        it("should return false on failure", function()
            setMockExecuteResult(1)
            assert.is_false(Libra2Adapter.stopDiscovery())
        end)
    end)

    describe("getManagedObjects", function()
        it("should return D-Bus output on success", function()
            local expected_output = "dbus output here"
            setMockPopenOutput(expected_output)

            local output = Libra2Adapter.getManagedObjects()

            assert.are.equal(expected_output, output)
        end)

        it("should return nil if popen fails", function()
            setMockPopenFailure()

            local output = Libra2Adapter.getManagedObjects()

            assert.is_nil(output)
        end)
    end)

    describe("connectDevice", function()
        it("should return true on successful connection", function()
            setMockExecuteResult(0)
            local result = Libra2Adapter.connectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            assert.is_true(result)
        end)

        it("should return false on failed connection", function()
            setMockExecuteResult(1)
            local result = Libra2Adapter.connectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            assert.is_false(result)
        end)

        it("should execute correct D-Bus command", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            Libra2Adapter.connectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            local commands = getExecutedCommands()
            assert.are.equal(1, #commands)
            assert.is_true(
                commands[1]:match("dbus%-send .* /org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF org%.bluez%.Device1%.Connect")
                    ~= nil
            )
        end)
    end)

    describe("disconnectDevice", function()
        it("should return true on successful disconnection", function()
            setMockExecuteResult(0)
            local result = Libra2Adapter.disconnectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            assert.is_true(result)
        end)

        it("should return false on failed disconnection", function()
            setMockExecuteResult(1)
            local result = Libra2Adapter.disconnectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            assert.is_false(result)
        end)

        it("should execute correct D-Bus command", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            Libra2Adapter.disconnectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            local commands = getExecutedCommands()
            assert.are.equal(1, #commands)
            assert.is_true(
                commands[1]:match("dbus%-send .* /org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF org%.bluez%.Device1%.Disconnect")
                    ~= nil
            )
        end)
    end)

    describe("removeDevice", function()
        it("should return true on successful device removal", function()
            setMockExecuteResult(0)
            local result = Libra2Adapter.removeDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            assert.is_true(result)
        end)

        it("should return false on failed device removal", function()
            setMockExecuteResult(1)
            local result = Libra2Adapter.removeDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            assert.is_false(result)
        end)

        it("should execute correct D-Bus command", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            Libra2Adapter.removeDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            local commands = getExecutedCommands()
            -- Should execute disconnect and then remove
            assert.are.equal(2, #commands)
            assert.is_true(commands[1]:match("org%.bluez%.Device1%.Disconnect") ~= nil)
            assert.is_true(
                commands[2]:match(
                    "dbus%-send .* /org/bluez/hci0 org%.bluez%.Adapter1%.RemoveDevice objpath:/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
                ) ~= nil
            )
        end)
    end)

    describe("setDeviceTrusted", function()
        it("should return true on successful trust operation", function()
            setMockExecuteResult(0)
            local result = Libra2Adapter.setDeviceTrusted("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF", true)

            assert.is_true(result)
        end)

        it("should return true on successful untrust operation", function()
            setMockExecuteResult(0)
            local result = Libra2Adapter.setDeviceTrusted("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF", false)

            assert.is_true(result)
        end)

        it("should return false on failed operation", function()
            setMockExecuteResult(1)
            local result = Libra2Adapter.setDeviceTrusted("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF", true)

            assert.is_false(result)
        end)

        it("should execute correct D-Bus command for trusting", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            Libra2Adapter.setDeviceTrusted("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF", true)

            local commands = getExecutedCommands()
            assert.are.equal(1, #commands)
            assert.is_true(
                commands[1]:match(
                    "dbus%-send .* /org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF "
                        .. "org%.freedesktop%.DBus%.Properties%.Set "
                        .. "string:org%.bluez%.Device1 string:Trusted variant:boolean:true"
                ) ~= nil
            )
        end)

        it("should execute correct D-Bus command for untrusting", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            Libra2Adapter.setDeviceTrusted("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF", false)

            local commands = getExecutedCommands()
            assert.are.equal(1, #commands)
            assert.is_true(
                commands[1]:match(
                    "dbus%-send .* /org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF "
                        .. "org%.freedesktop%.DBus%.Properties%.Set "
                        .. "string:org%.bluez%.Device1 string:Trusted variant:boolean:false"
                ) ~= nil
            )
        end)
    end)

    describe("connectDeviceInBackground", function()
        before_each(function()
            -- Clear the cached modules so ffi/util mock is used fresh
            package.loaded["src/lib/bluetooth/adapters/libra2_adapter"] = nil
            package.loaded["ffi/util"] = nil
        end)

        it("should return true when subprocess starts successfully", function()
            setMockRunInSubProcessResult(12345)

            local adapter = require("src/lib/bluetooth/adapters/libra2_adapter")
            local result = adapter.connectDeviceInBackground("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            assert.is_true(result)
        end)

        it("should return false when subprocess fails to start", function()
            setMockRunInSubProcessResult(false)

            local adapter = require("src/lib/bluetooth/adapters/libra2_adapter")
            local result = adapter.connectDeviceInBackground("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            assert.is_false(result)
        end)

        it("should pass a function to runInSubProcess that executes connect command", function()
            setMockRunInSubProcessResult(12345)
            setMockExecuteResult(0)
            clearExecutedCommands()

            local adapter = require("src/lib/bluetooth/adapters/libra2_adapter")
            adapter.connectDeviceInBackground("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            -- Get the callback that was passed to runInSubProcess
            local callback = getMockRunInSubProcessCallback()
            assert.is_not_nil(callback)

            -- Verify the correct dbus-send command was executed
            local commands = getExecutedCommands()
            assert.are.equal(1, #commands)
            assert.is_true(
                commands[1]:match("dbus%-send .* /org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF org%.bluez%.Device1%.Connect")
                    ~= nil
            )
        end)
    end)
end)
