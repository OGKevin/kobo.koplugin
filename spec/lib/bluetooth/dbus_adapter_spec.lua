---
-- Unit tests for DbusAdapter module.

require("spec.helper")

describe("DbusAdapter", function()
    local DbusAdapter

    setup(function()
        DbusAdapter = require("src/lib/bluetooth/dbus_adapter")
    end)

    before_each(function()
        resetAllMocks()
    end)

    describe("executeCommands", function()
        it("should execute all commands in sequence on success", function()
            setMockExecuteResult(0)
            local commands = { "command1", "command2", "command3" }
            local result = DbusAdapter.executeCommands(commands)

            assert.is_true(result)
        end)

        it("should return false if any command fails", function()
            setMockExecuteResult(1)
            local commands = { "good_command", "fail_command", "another_command" }
            local result = DbusAdapter.executeCommands(commands)

            assert.is_false(result)
        end)

        it("should handle empty command list", function()
            setMockExecuteResult(0)
            local result = DbusAdapter.executeCommands({})

            assert.is_true(result)
        end)
    end)

    describe("isEnabled", function()
        it("should return true when D-Bus returns 'boolean true'", function()
            setMockPopenOutput("variant boolean true")
            assert.is_true(DbusAdapter.isEnabled())
        end)

        it("should return false when D-Bus returns 'boolean false'", function()
            setMockPopenOutput("variant boolean false")
            assert.is_false(DbusAdapter.isEnabled())
        end)

        it("should return false when D-Bus command fails", function()
            setMockPopenOutput("")
            assert.is_false(DbusAdapter.isEnabled())
        end)

        it("should return false when D-Bus returns unexpected format", function()
            setMockPopenOutput("unexpected output")
            assert.is_false(DbusAdapter.isEnabled())
        end)
    end)

    describe("turnOn", function()
        it("should execute ON commands and return true on success", function()
            setMockExecuteResult(0)
            assert.is_true(DbusAdapter.turnOn())
        end)

        it("should return false if commands fail", function()
            setMockExecuteResult(1)
            assert.is_false(DbusAdapter.turnOn())
        end)

        it("should execute correct D-Bus commands", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            DbusAdapter.turnOn()

            local commands = getExecutedCommands()
            assert.are.equal(2, #commands)
            assert.are.equal(
                "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid / com.kobo.bluetooth.BluedroidManager1.On",
                commands[1]
            )
            assert.are.equal(
                "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid /org/bluez/hci0 "
                    .. "org.freedesktop.DBus.Properties.Set "
                    .. "string:org.bluez.Adapter1 string:Powered variant:boolean:true",
                commands[2]
            )
        end)
    end)

    describe("turnOff", function()
        it("should execute OFF commands and return true on success", function()
            setMockExecuteResult(0)
            assert.is_true(DbusAdapter.turnOff())
        end)

        it("should return false if commands fail", function()
            setMockExecuteResult(1)
            assert.is_false(DbusAdapter.turnOff())
        end)

        it("should execute correct D-Bus commands", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            DbusAdapter.turnOff()

            local commands = getExecutedCommands()
            assert.are.equal(2, #commands)
            assert.are.equal(
                "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid /org/bluez/hci0 "
                    .. "org.freedesktop.DBus.Properties.Set "
                    .. "string:org.bluez.Adapter1 string:Powered variant:boolean:false",
                commands[1]
            )
            assert.are.equal(
                "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid / com.kobo.bluetooth.BluedroidManager1.Off",
                commands[2]
            )
        end)
    end)

    describe("startDiscovery", function()
        it("should return true on success", function()
            setMockExecuteResult(0)
            assert.is_true(DbusAdapter.startDiscovery())
        end)

        it("should return false on failure", function()
            setMockExecuteResult(1)
            assert.is_false(DbusAdapter.startDiscovery())
        end)
    end)

    describe("stopDiscovery", function()
        it("should return true on success", function()
            setMockExecuteResult(0)
            assert.is_true(DbusAdapter.stopDiscovery())
        end)

        it("should return false on failure", function()
            setMockExecuteResult(1)
            assert.is_false(DbusAdapter.stopDiscovery())
        end)
    end)

    describe("getManagedObjects", function()
        it("should return D-Bus output on success", function()
            local expected_output = "dbus output here"
            setMockPopenOutput(expected_output)

            local output = DbusAdapter.getManagedObjects()

            assert.are.equal(expected_output, output)
        end)

        it("should return nil if popen fails", function()
            setMockPopenFailure()

            local output = DbusAdapter.getManagedObjects()

            assert.is_nil(output)
        end)
    end)

    describe("connectDevice", function()
        it("should return true on successful connection", function()
            setMockExecuteResult(0)
            local result = DbusAdapter.connectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            assert.is_true(result)
        end)

        it("should return false on failed connection", function()
            setMockExecuteResult(1)
            local result = DbusAdapter.connectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            assert.is_false(result)
        end)

        it("should execute correct D-Bus command", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            DbusAdapter.connectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

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
            local result = DbusAdapter.disconnectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            assert.is_true(result)
        end)

        it("should return false on failed disconnection", function()
            setMockExecuteResult(1)
            local result = DbusAdapter.disconnectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            assert.is_false(result)
        end)

        it("should execute correct D-Bus command", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            DbusAdapter.disconnectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            local commands = getExecutedCommands()
            assert.are.equal(1, #commands)
            assert.is_true(
                commands[1]:match("dbus%-send .* /org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF org%.bluez%.Device1%.Disconnect")
                    ~= nil
            )
        end)
    end)
end)
