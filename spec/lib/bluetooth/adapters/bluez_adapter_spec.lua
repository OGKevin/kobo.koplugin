---
-- Unit tests for shared BlueZAdapter factory.

require("spec.helper")

describe("BlueZAdapter", function()
    local BlueZAdapter
    local adapter

    local DUMMY_ON = { "on_cmd_1", "on_cmd_2" }
    local DUMMY_OFF = { "off_cmd_1" }

    setup(function()
        BlueZAdapter = require("src/lib/bluetooth/adapters/bluez_adapter")
    end)

    before_each(function()
        resetAllMocks()
        adapter = BlueZAdapter:new({
            name = "Test",
            COMMANDS_ON = DUMMY_ON,
            COMMANDS_OFF = DUMMY_OFF,
        })
    end)

    describe("new", function()
        it("should require an opts table", function()
            assert.has_error(function()
                BlueZAdapter:new(nil)
            end)
        end)

        it("should require a non-empty name", function()
            assert.has_error(function()
                BlueZAdapter:new({
                    name = "",
                    COMMANDS_ON = DUMMY_ON,
                    COMMANDS_OFF = DUMMY_OFF,
                })
            end)
        end)

        it("should require COMMANDS_ON", function()
            assert.has_error(function()
                BlueZAdapter:new({
                    name = "Test",
                    COMMANDS_OFF = DUMMY_OFF,
                })
            end)
        end)

        it("should require COMMANDS_OFF", function()
            assert.has_error(function()
                BlueZAdapter:new({
                    name = "Test",
                    COMMANDS_ON = DUMMY_ON,
                })
            end)
        end)
    end)

    describe("executeCommands", function()
        it("should execute all commands in sequence on success", function()
            setMockExecuteResult(0)
            local commands = { "command1", "command2", "command3" }
            local result = adapter:executeCommands(commands)

            assert.is_true(result)
        end)

        it("should return false if any command fails", function()
            setMockExecuteResult(1)
            local commands = { "good_command", "fail_command", "another_command" }
            local result = adapter:executeCommands(commands)

            assert.is_false(result)
        end)

        it("should handle empty command list", function()
            setMockExecuteResult(0)
            local result = adapter:executeCommands({})

            assert.is_true(result)
        end)
    end)

    describe("isEnabled", function()
        it("should return true when D-Bus returns 'boolean true'", function()
            setMockPopenOutput("variant boolean true")
            assert.is_true(adapter:isEnabled())
        end)

        it("should return false when D-Bus returns 'boolean false'", function()
            setMockPopenOutput("variant boolean false")
            assert.is_false(adapter:isEnabled())
        end)

        it("should return false when D-Bus command fails", function()
            setMockPopenOutput("")
            assert.is_false(adapter:isEnabled())
        end)

        it("should return false when D-Bus returns unexpected format", function()
            setMockPopenOutput("unexpected output")
            assert.is_false(adapter:isEnabled())
        end)
    end)

    describe("turnOn", function()
        it("should execute ON commands and return true on success", function()
            setMockExecuteResult(0)
            assert.is_true(adapter:turnOn())
        end)

        it("should return false if commands fail", function()
            setMockExecuteResult(1)
            assert.is_false(adapter:turnOn())
        end)

        it("should execute the provided COMMANDS_ON sequence", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            adapter:turnOn()

            local commands = getExecutedCommands()
            assert.are.equal(2, #commands)
            assert.are.equal("on_cmd_1", commands[1])
            assert.are.equal("on_cmd_2", commands[2])
        end)
    end)

    describe("turnOff", function()
        it("should execute OFF commands and return true on success", function()
            setMockExecuteResult(0)
            assert.is_true(adapter:turnOff())
        end)

        it("should return false if commands fail", function()
            setMockExecuteResult(1)
            assert.is_false(adapter:turnOff())
        end)

        it("should execute the provided COMMANDS_OFF sequence", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            adapter:turnOff()

            local commands = getExecutedCommands()
            assert.are.equal(1, #commands)
            assert.are.equal("off_cmd_1", commands[1])
        end)
    end)

    describe("startDiscovery", function()
        it("should return true on success", function()
            setMockExecuteResult(0)
            assert.is_true(adapter:startDiscovery())
        end)

        it("should return false on failure", function()
            setMockExecuteResult(1)
            assert.is_false(adapter:startDiscovery())
        end)
    end)

    describe("stopDiscovery", function()
        it("should return true on success", function()
            setMockExecuteResult(0)
            assert.is_true(adapter:stopDiscovery())
        end)

        it("should return false on failure", function()
            setMockExecuteResult(1)
            assert.is_false(adapter:stopDiscovery())
        end)
    end)

    describe("getManagedObjects", function()
        it("should return D-Bus output on success", function()
            local expected_output = "dbus output here"
            setMockPopenOutput(expected_output)

            local output = adapter:getManagedObjects()

            assert.are.equal(expected_output, output)
        end)

        it("should return nil if popen fails", function()
            setMockPopenFailure()

            local output = adapter:getManagedObjects()

            assert.is_nil(output)
        end)
    end)

    describe("connectDevice", function()
        it("should return true on successful connection", function()
            setMockExecuteResult(0)
            local result = adapter:connectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            assert.is_true(result)
        end)

        it("should return false on failed connection", function()
            setMockExecuteResult(1)
            local result = adapter:connectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            assert.is_false(result)
        end)

        it("should execute correct D-Bus command", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            adapter:connectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

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
            local result = adapter:disconnectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            assert.is_true(result)
        end)

        it("should return false on failed disconnection", function()
            setMockExecuteResult(1)
            local result = adapter:disconnectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            assert.is_false(result)
        end)

        it("should execute correct D-Bus command", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            adapter:disconnectDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

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
            local result = adapter:removeDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            assert.is_true(result)
        end)

        it("should return false on failed device removal", function()
            setMockExecuteResult(1)
            local result = adapter:removeDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            assert.is_false(result)
        end)

        it("should execute correct D-Bus command", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            adapter:removeDevice("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

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
            local result = adapter:setDeviceTrusted("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF", true)

            assert.is_true(result)
        end)

        it("should return true on successful untrust operation", function()
            setMockExecuteResult(0)
            local result = adapter:setDeviceTrusted("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF", false)

            assert.is_true(result)
        end)

        it("should return false on failed operation", function()
            setMockExecuteResult(1)
            local result = adapter:setDeviceTrusted("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF", true)

            assert.is_false(result)
        end)

        it("should execute correct D-Bus command for trusting", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            adapter:setDeviceTrusted("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF", true)

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

            adapter:setDeviceTrusted("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF", false)

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
            package.loaded["src/lib/bluetooth/adapters/bluez_adapter"] = nil
            package.loaded["ffi/util"] = nil
        end)

        it("should return true when subprocess starts successfully", function()
            setMockRunInSubProcessResult(12345)

            local BlueZ = require("src/lib/bluetooth/adapters/bluez_adapter")
            local bg_adapter = BlueZ:new({
                name = "Test",
                COMMANDS_ON = DUMMY_ON,
                COMMANDS_OFF = DUMMY_OFF,
            })
            local result = bg_adapter:connectDeviceInBackground("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            assert.is_true(result)
        end)

        it("should return false when subprocess fails to start", function()
            setMockRunInSubProcessResult(false)

            local BlueZ = require("src/lib/bluetooth/adapters/bluez_adapter")
            local bg_adapter = BlueZ:new({
                name = "Test",
                COMMANDS_ON = DUMMY_ON,
                COMMANDS_OFF = DUMMY_OFF,
            })
            local result = bg_adapter:connectDeviceInBackground("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            assert.is_false(result)
        end)

        it("should pass a function to runInSubProcess that executes connect command", function()
            setMockRunInSubProcessResult(12345)
            setMockExecuteResult(0)
            clearExecutedCommands()

            local BlueZ = require("src/lib/bluetooth/adapters/bluez_adapter")
            local bg_adapter = BlueZ:new({
                name = "Test",
                COMMANDS_ON = DUMMY_ON,
                COMMANDS_OFF = DUMMY_OFF,
            })
            bg_adapter:connectDeviceInBackground("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF")

            local callback = getMockRunInSubProcessCallback()
            assert.is_not_nil(callback)

            local commands = getExecutedCommands()
            assert.are.equal(1, #commands)
            assert.is_true(
                commands[1]:match("dbus%-send .* /org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF org%.bluez%.Device1%.Connect")
                    ~= nil
            )
        end)
    end)
end)
