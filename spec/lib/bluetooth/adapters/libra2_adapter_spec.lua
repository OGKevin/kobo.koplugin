---
-- Unit tests for Libra2Adapter chip bring-up commands.

require("spec.helper")

describe("Libra2Adapter", function()
    local Libra2Adapter

    setup(function()
        Libra2Adapter = require("src/lib/bluetooth/adapters/libra2_adapter")
    end)

    before_each(function()
        resetAllMocks()
    end)

    describe("turnOn", function()
        it("should execute the chip-init + bluetoothd + Powered=true sequence", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            Libra2Adapter:turnOn()

            local commands = getExecutedCommands()
            assert.are.equal(5, #commands)
            -- 1. SDIO power rail driver
            assert.is_truthy(commands[1]:match("insmod /drivers/mx6sll%-ntx/wifi/sdio_bt_pwr%.ko"))
            -- 2. Realtek HCI UART attach
            assert.is_truthy(commands[2]:match("rtk_hciattach"))
            assert.is_truthy(commands[2]:match("ttymxc1"))
            -- 3. bluetoothd
            assert.are.equal("/libexec/bluetooth/bluetoothd &", commands[3])
            -- 4. Wait loop until BlueZ registers hci0 on D-Bus
            assert.is_truthy(commands[4]:match("Properties%.Get"))
            -- 5. Set Powered=true
            assert.are.equal(
                "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
                    .. "org.freedesktop.DBus.Properties.Set "
                    .. "string:org.bluez.Adapter1 string:Powered variant:boolean:true",
                commands[5]
            )
        end)

        it("should return false if commands fail", function()
            setMockExecuteResult(1)
            assert.is_false(Libra2Adapter:turnOn())
        end)
    end)

    describe("turnOff", function()
        it("should execute graceful Powered=false + full chip teardown", function()
            setMockExecuteResult(0)
            clearExecutedCommands()

            Libra2Adapter:turnOff()

            local commands = getExecutedCommands()
            assert.are.equal(2, #commands)
            assert.are.equal(
                "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
                    .. "org.freedesktop.DBus.Properties.Set "
                    .. "string:org.bluez.Adapter1 string:Powered variant:boolean:false",
                commands[1]
            )
            -- Compound teardown line: kill both daemons, wait for exit, rmmod the power rail.
            assert.is_truthy(commands[2]:match("killall bluetoothd"))
            assert.is_truthy(commands[2]:match("killall rtk_hciattach"))
            assert.is_truthy(commands[2]:match("rmmod sdio_bt_pwr"))
        end)

        it("should return false if commands fail", function()
            setMockExecuteResult(1)
            assert.is_false(Libra2Adapter:turnOff())
        end)
    end)
end)
