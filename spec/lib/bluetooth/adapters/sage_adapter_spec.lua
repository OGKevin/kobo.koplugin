---
-- Unit tests for SageAdapter chip bring-up commands.

require("spec.helper")

describe("SageAdapter", function()
    local SageAdapter

    setup(function()
        SageAdapter = require("src/lib/bluetooth/adapters/sage_adapter")
    end)

    before_each(function()
        resetAllMocks()
    end)

    describe("turnOn", function()
        it("should execute rfkill + ttyS1 rtk_hciattach bring-up sequence", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            SageAdapter:turnOn()

            local commands = getExecutedCommands()
            assert.are.equal(11, #commands)

            assert.is_truthy(commands[1]:match("killall rtk_hciattach"))
            assert.is_truthy(commands[1]:match("killall bluetoothd"))
            assert.is_truthy(commands[2]:match("rfkill0/state"))
            assert.is_truthy(commands[2]:match("echo 0"))
            assert.are.equal("sleep 1", commands[3])
            assert.is_truthy(commands[4]:match("echo 1"))
            assert.is_truthy(commands[5]:match("rtk_hciattach"))
            assert.is_truthy(commands[5]:match("/dev/ttyS1"))
            assert.is_falsy(commands[5]:match("ttymxc1"))
            assert.is_falsy(commands[5]:match("sdio_bt_pwr"))
            assert.are.equal("sleep 2", commands[6])
            assert.are.equal("hciconfig hci0 up", commands[7])
            assert.is_truthy(commands[8]:match("bluetoothd"))
            assert.is_truthy(commands[9]:match("Properties%.Get"))
            assert.is_truthy(commands[10]:match("Powered variant:boolean:true"))
            assert.is_truthy(commands[11]:match("UP RUNNING"))
        end)

        it("should return false if commands fail", function()
            setMockExecuteResult(1)
            assert.is_false(SageAdapter:turnOn())
        end)
    end)

    describe("turnOff", function()
        it("should execute Powered=false + daemon kill + rfkill off", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            SageAdapter:turnOff()

            local commands = getExecutedCommands()
            assert.are.equal(2, #commands)
            assert.is_truthy(commands[1]:match("Powered variant:boolean:false"))
            assert.is_truthy(commands[2]:match("killall bluetoothd"))
            assert.is_truthy(commands[2]:match("killall rtk_hciattach"))
            assert.is_truthy(commands[2]:match("rfkill0/state"))
            assert.is_falsy(commands[2]:match("rmmod sdio_bt_pwr"))
        end)

        it("should return false if commands fail", function()
            setMockExecuteResult(1)
            assert.is_false(SageAdapter:turnOff())
        end)
    end)
end)
