---
--- Unit tests for MTKBluetooth implementation.

require("spec.helper")

describe("MTKBluetooth", function()
    local MTKBluetooth
    local Device
    local UIManager
    local mock_plugin

    setup(function()
        Device = require("device")
        UIManager = require("ui/uimanager")
        MTKBluetooth = require("src/lib/bluetooth/implementations/mtk_bluetooth")
    end)

    before_each(function()
        -- Reset UI manager state
        UIManager:_reset()

        -- Reset device state to MTK Kobo by default
        Device._isMTK = true
        Device.isKobo = function()
            return true
        end

        -- Setup mock plugin
        mock_plugin = {
            settings = {
                paired_devices = {},
            },
            saveSettings = function() end,
        }

        -- Reset all mocks
        resetAllMocks()
    end)

    describe("isDeviceSupported", function()
        it("should return true on MTK Kobo device", function()
            Device._isMTK = true
            local instance = MTKBluetooth:new()
            assert.is_true(instance:isDeviceSupported())
        end)

        it("should return false on non-MTK Kobo device", function()
            Device._isMTK = false
            local instance = MTKBluetooth:new()
            assert.is_false(instance:isDeviceSupported())
        end)

        it("should return false on non-Kobo device", function()
            local original_isKobo = Device.isKobo
            Device.isKobo = function()
                return false
            end
            local instance = MTKBluetooth:new()
            assert.is_false(instance:isDeviceSupported())
            Device.isKobo = original_isKobo
        end)
    end)

    describe("turnBluetoothOn", function()
        before_each(function()
            mock_plugin = {
                settings = {
                    paired_devices = {},
                },
                saveSettings = function() end,
            }
        end)

        it("should show error message on unsupported device", function()
            Device._isMTK = false
            local instance = MTKBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            instance:turnBluetoothOn()

            assert.are.equal(0, UIManager._prevent_standby_calls)
            assert.is_false(instance.bluetooth_standby_prevented)

            assert.are.equal(1, #UIManager._show_calls)
            assert.is_not_nil(UIManager._show_calls[1].widget.text)
        end)

        it("should execute ON commands and prevent standby on success", function()
            setMockExecuteResult(0)
            setMockPopenOutput("variant boolean false")
            local instance = MTKBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            instance:turnBluetoothOn()

            assert.are.equal(1, UIManager._prevent_standby_calls)
            assert.is_true(instance.bluetooth_standby_prevented)

            assert.are.equal(1, #UIManager._show_calls)
            assert.is_not_nil(UIManager._show_calls[1].widget.text)

            assert.are.equal(1, #UIManager._send_event_calls)
            assert.are.equal("BluetoothStateChanged", UIManager._send_event_calls[1].event.name)
            assert.is_true(UIManager._send_event_calls[1].event.args[1].state)
        end)

        it("should not turn on Bluetooth if already enabled", function()
            setMockExecuteResult(0)
            setMockPopenOutput("variant boolean true")
            local instance = MTKBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            UIManager:_reset()

            instance:turnBluetoothOn()

            assert.are.equal(0, UIManager._prevent_standby_calls)
            assert.are.equal(0, #UIManager._show_calls)
            assert.are.equal(0, #UIManager._send_event_calls)
        end)

        it("should not prevent standby if D-Bus command fails", function()
            setMockExecuteResult(1)
            setMockPopenOutput("variant boolean false")

            local instance = MTKBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            instance:turnBluetoothOn()

            -- Execute scheduled tasks to complete async operations (needs 30+ iterations for polling timeout)
            UIManager:executeScheduledTasks(35)

            -- preventStandby is called initially, then allowStandby is called when BT fails
            assert.are.equal(1, UIManager._prevent_standby_calls)
            assert.are.equal(1, UIManager._allow_standby_calls)
            assert.is_false(instance.bluetooth_standby_prevented)

            assert.are.equal(1, #UIManager._show_calls)
        end)

        it("should execute correct D-Bus commands for turning ON", function()
            setMockExecuteResult(0)
            setMockPopenOutput("variant boolean false")
            clearExecutedCommands()
            local instance = MTKBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            instance:turnBluetoothOn()

            -- Simulate Bluetooth becoming enabled
            setMockPopenOutput("variant boolean true")

            -- Execute scheduled tasks to complete async operations
            UIManager:executeScheduledTasks()

            -- Validate the exact D-Bus commands were executed
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

            -- Should have called preventStandby and shown message
            assert.are.equal(1, UIManager._prevent_standby_calls)
            assert.are.equal(1, #UIManager._show_calls)
        end)

        it("should turn on WiFi before enabling Bluetooth when WiFi is off", function()
            setMockExecuteResult(0)
            setMockPopenOutput("variant boolean false")
            local NetworkMgr = require("ui/network/manager")
            NetworkMgr:_reset()
            NetworkMgr:_setWifiState(false)

            local instance = MTKBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            instance:turnBluetoothOn()

            -- Should have called turnOnWifi
            assert.are.equal(1, #NetworkMgr._turn_on_wifi_calls)
            assert.are.equal(false, NetworkMgr._turn_on_wifi_calls[1].long_press)
            -- WiFi should now be on
            assert.is_true(NetworkMgr:isWifiOn())
        end)

        it("should not turn on WiFi if already on", function()
            setMockExecuteResult(0)
            setMockPopenOutput("variant boolean false")
            local NetworkMgr = require("ui/network/manager")
            NetworkMgr:_reset()
            NetworkMgr:_setWifiState(true)

            local instance = MTKBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            instance:turnBluetoothOn()

            -- Should not have called turnOnWifi
            assert.are.equal(0, #NetworkMgr._turn_on_wifi_calls)
        end)
    end)

    describe("turnBluetoothOff", function()
        it("should show error message on unsupported device", function()
            Device._isMTK = false
            local instance = MTKBluetooth:new()
            instance.bluetooth_standby_prevented = true
            instance:turnBluetoothOff()

            -- Should not allow standby
            assert.are.equal(0, UIManager._allow_standby_calls)

            -- Should show error message
            assert.are.equal(1, #UIManager._show_calls)
            assert.is_not_nil(UIManager._show_calls[1].widget.text)
        end)

        it("should execute OFF commands and allow standby on success", function()
            setMockExecuteResult(0)
            local instance = MTKBluetooth:new()

            -- First turn ON to set the flag
            instance.bluetooth_standby_prevented = true

            instance:turnBluetoothOff()

            -- Should allow standby
            assert.are.equal(1, UIManager._allow_standby_calls)
            assert.is_false(instance.bluetooth_standby_prevented)

            -- Should show success message
            assert.are.equal(1, #UIManager._show_calls)

            -- Should emit event
            assert.are.equal(1, #UIManager._send_event_calls)
            assert.are.equal("BluetoothStateChanged", UIManager._send_event_calls[1].event.name)
            assert.is_false(UIManager._send_event_calls[1].event.args[1].state)
        end)

        it("should not call allowStandby if standby was not prevented", function()
            setMockExecuteResult(0)
            local instance = MTKBluetooth:new()
            instance.bluetooth_standby_prevented = false

            instance:turnBluetoothOff()

            -- Should not call allowStandby since we never prevented it
            assert.are.equal(0, UIManager._allow_standby_calls)
        end)

        it("should not turn off Bluetooth if already disabled", function()
            setMockExecuteResult(0)
            setMockPopenOutput("variant boolean false")
            local instance = MTKBluetooth:new()

            -- Reset UIManager to clear init() calls
            UIManager:_reset()

            instance:turnBluetoothOff()

            -- Should not allow standby (already off)
            assert.are.equal(0, UIManager._allow_standby_calls)
            -- Should not show success message
            assert.are.equal(0, #UIManager._show_calls)
            -- Should not emit event
            assert.are.equal(0, #UIManager._send_event_calls)
        end)

        it("should keep standby prevented if D-Bus command fails", function()
            setMockExecuteResult(1)

            local instance = MTKBluetooth:new()
            instance.bluetooth_standby_prevented = true

            instance:turnBluetoothOff()

            -- Should not allow standby if command failed
            assert.are.equal(0, UIManager._allow_standby_calls)
            assert.is_true(instance.bluetooth_standby_prevented)

            -- Should show error message
            assert.are.equal(1, #UIManager._show_calls)
        end)

        it("should execute correct D-Bus commands for turning OFF", function()
            setMockExecuteResult(0)
            clearExecutedCommands()
            local instance = MTKBluetooth:new()
            instance.bluetooth_standby_prevented = true
            instance:turnBluetoothOff()

            -- Validate the exact D-Bus commands were executed
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

            -- Should have called allowStandby and shown message
            assert.are.equal(1, UIManager._allow_standby_calls)
            assert.are.equal(1, #UIManager._show_calls)
        end)
    end)

    describe("onResume", function()
        it("should not resume Bluetooth when auto-resume is disabled", function()
            resetAllMocks()
            setMockPopenOutput("variant boolean false")
            local instance = MTKBluetooth:new()
            mock_plugin.settings.enable_bluetooth_auto_resume = false
            instance:initWithPlugin(mock_plugin)

            instance.bluetooth_was_enabled_before_suspend = true

            instance:onResume()

            assert.is_false(instance:isBluetoothEnabled())
        end)

        it("should not resume Bluetooth when it was not enabled before suspend", function()
            resetAllMocks()
            setMockPopenOutput("variant boolean false")
            local instance = MTKBluetooth:new()
            mock_plugin.settings.enable_bluetooth_auto_resume = true
            instance:initWithPlugin(mock_plugin)

            instance.bluetooth_was_enabled_before_suspend = false

            instance:onResume()

            assert.is_false(instance:isBluetoothEnabled())
        end)

        it("should resume Bluetooth when auto-resume is enabled and BT was on before suspend", function()
            resetAllMocks()
            setMockPopenOutput("variant boolean false") -- Bluetooth starts disabled
            setMockExecuteResult(0)
            local instance = MTKBluetooth:new()
            mock_plugin.settings.enable_bluetooth_auto_resume = true
            instance:initWithPlugin(mock_plugin)

            instance.bluetooth_was_enabled_before_suspend = true
            UIManager:_reset()

            instance:onResume()

            -- Execute all scheduled tasks to complete async resume
            -- The mock automatically flips BT state when turnOn commands succeed
            UIManager:executeScheduledTasks()

            -- Now preventStandby should have been called
            assert.are.equal(1, UIManager._prevent_standby_calls)
        end)
    end)
end)
