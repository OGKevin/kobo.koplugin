---
--- Unit tests for MTKBluetooth implementation.

require("spec.helper")

describe("MTKBluetooth", function()
    local MTKBluetooth
    local KoboBluetooth
    local WmtPower
    local Device
    local UIManager
    local mock_plugin

    setup(function()
        Device = require("device")
        UIManager = require("ui/uimanager")
        KoboBluetooth = require("src/kobo_bluetooth")
        WmtPower = require("src/lib/bluetooth/wmt_power")
        MTKBluetooth = require("src/lib/bluetooth/implementations/mtk_bluetooth")
    end)

    -- Whether an event with this name was broadcast through UIManager
    local function wasBroadcast(event_name)
        for _, call in ipairs(UIManager._broadcast_calls or {}) do
            local event = call.event or call
            if event and event.name == event_name then
                return true
            end
        end
        return false
    end

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

        -- The enable subprocess has not powered the chip unless a test says so
        require("libs/libkoreader-lfs")._setFileState(WmtPower.POWERED_MARKER, { exists = false })
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

            -- Execute scheduled tasks to complete async operations
            -- (needs 80+ iterations for the polling timeout with the chip power-on fallback)
            UIManager:executeScheduledTasks(90)

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
            require("ui/network/manager"):_setWifiState(true)
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

        it("should enable Bluetooth with no WiFi handling when WiFi is off and On() works", function()
            setMockExecuteResult(0)
            setMockPopenOutput("variant boolean false")
            clearExecutedCommands()
            local NetworkMgr = require("ui/network/manager")
            NetworkMgr:_reset()
            NetworkMgr:_setWifiState(false)

            local instance = MTKBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            instance:turnBluetoothOn()

            -- The plugin holds Wi-Fi until the adapter is up (it may still need the fallback)
            assert.is_true(KoboBluetooth.wifi_borrowed)

            UIManager:executeScheduledTasks()

            local commands = getExecutedCommands()
            -- clear marker, On(), Powered=true: no handshake, no power-off
            assert.are.equal(3, #commands)
            assert.are.equal(WmtPower.COMMAND_CLEAR_POWERED, commands[1])
            assert.is_not_nil(commands[2]:find("BluedroidManager1.On", 1, true))
            assert.is_not_nil(commands[3]:find("Powered variant:boolean:true", 1, true))

            -- Never through NetworkMgr: no restore script, no turnOffWifi
            assert.are.equal(0, #NetworkMgr._turn_on_wifi_calls)
            assert.are.equal(0, #NetworkMgr._turn_off_wifi_calls)
            assert.is_false(KoboBluetooth.wifi_borrowed)
            assert.is_true(wasBroadcast("BluetoothWifiReleased"))
        end)

        it("should load the radio driver and run the handshake before On() on a cold boot", function()
            setMockExecuteResult(0)
            setMockPopenOutput("variant boolean false")
            clearExecutedCommands()
            local NetworkMgr = require("ui/network/manager")
            NetworkMgr:_reset()
            NetworkMgr:_setWifiState(false)
            local lfs = require("libs/libkoreader-lfs")
            -- Nothing has used the radio since boot: no Bluetooth device node, no ready marker
            lfs._setFileState(WmtPower.BT_DEVICE, { exists = false })
            lfs._setFileState(WmtPower.STACK_READY_MARKER, { exists = false })

            local instance = MTKBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            instance:turnBluetoothOn()

            assert.is_true(KoboBluetooth.wifi_borrowed)

            -- Nothing may touch D-Bus during the bring-up, even though the node appears early
            assert.is_true(WmtPower.bringing_up)
            lfs._setFileState(WmtPower.BT_DEVICE, { exists = true, attributes = { mode = "char device" } })
            assert.is_false(WmtPower.isStackLoaded())

            -- The subprocess loads the stack, runs the handshake (marker) and marks the stack ready
            lfs._setFileState(WmtPower.POWERED_MARKER, { exists = true, attributes = { mode = "file" } })
            lfs._setFileState(WmtPower.STACK_READY_MARKER, { exists = true, attributes = { mode = "file" } })
            UIManager:executeScheduledTasks()

            local commands = getExecutedCommands()
            assert.are.equal(WmtPower.COMMAND_CLEAR_POWERED, commands[1])
            assert.is_not_nil(commands[2]:find(WmtPower.WMT_LOADER, 1, true))
            assert.are.equal(WmtPower.COMMAND_MARK_POWERED, commands[3])
            assert.are.equal(WmtPower.COMMAND_POWER_ON, commands[4])
            assert.are.equal(WmtPower.COMMAND_MARK_STACK_READY, commands[5])
            assert.is_not_nil(commands[6]:find("BluedroidManager1.On", 1, true))
            assert.is_not_nil(commands[7]:find("Powered variant:boolean:true", 1, true))
            assert.is_false(WmtPower.bringing_up)
            -- Released afterwards under the ownership rule
            assert.are.equal(WmtPower.COMMAND_POWER_OFF, commands[#commands])
            assert.is_false(KoboBluetooth.wifi_borrowed)

            lfs._clearFileStates()
        end)

        it("should fall back to powering the chip when On() fails with WiFi off, and release it", function()
            setMockExecuteResult(1)
            setMockPopenOutput("variant boolean false")
            clearExecutedCommands()
            local NetworkMgr = require("ui/network/manager")
            NetworkMgr:_reset()
            NetworkMgr:_setWifiState(false)
            local lfs = require("libs/libkoreader-lfs")

            local instance = MTKBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            instance:turnBluetoothOn()

            -- The subprocess ran the fallback: in real life the marker file now exists
            lfs._setFileState(WmtPower.POWERED_MARKER, { exists = true, attributes = { mode = "file" } })

            UIManager:executeScheduledTasks(90)

            local commands = getExecutedCommands()
            assert.are.equal(WmtPower.COMMAND_CLEAR_POWERED, commands[1])
            assert.is_not_nil(commands[2]:find("BluedroidManager1.On", 1, true))
            assert.are.equal(WmtPower.COMMAND_MARK_POWERED, commands[3])
            assert.are.equal(WmtPower.COMMAND_POWER_ON, commands[4])
            assert.is_not_nil(commands[5]:find("BluedroidManager1.On", 1, true))
            assert.are.equal(WmtPower.COMMAND_CLEAR_POWERED, commands[#commands - 1])
            assert.are.equal(WmtPower.COMMAND_POWER_OFF, commands[#commands])
            assert.are.equal(0, #NetworkMgr._turn_off_wifi_calls)
            assert.is_false(KoboBluetooth.wifi_borrowed)
            assert.is_true(wasBroadcast("BluetoothWifiReleased"))
        end)

        it("should not touch WiFi if already on", function()
            setMockExecuteResult(0)
            setMockPopenOutput("variant boolean false")
            clearExecutedCommands()
            local NetworkMgr = require("ui/network/manager")
            NetworkMgr:_reset()
            NetworkMgr:_setWifiState(true)

            local instance = MTKBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            instance:turnBluetoothOn()

            assert.is_false(KoboBluetooth.wifi_borrowed)

            UIManager:executeScheduledTasks()

            for _, cmd in ipairs(getExecutedCommands()) do
                assert.is_not.equal(WmtPower.COMMAND_POWER_ON, cmd)
                assert.is_not.equal(WmtPower.COMMAND_POWER_OFF, cmd)
            end
            assert.are.equal(0, #NetworkMgr._turn_on_wifi_calls)
            assert.are.equal(0, #NetworkMgr._turn_off_wifi_calls)
            assert.is_false(wasBroadcast("BluetoothWifiReleased"))
        end)

        it("should wait for KOReader's WiFi restore after resume instead of powering the chip", function()
            setMockExecuteResult(0)
            setMockPopenOutput("variant boolean false")
            clearExecutedCommands()
            local NetworkMgr = require("ui/network/manager")
            NetworkMgr:_reset()
            NetworkMgr:_setWifiState(false)
            -- NetworkListener:onResume is restoring Wi-Fi in the background
            NetworkMgr.wifi_was_on = true
            G_reader_settings:saveSetting("auto_restore_wifi", true)

            local instance = MTKBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            instance:turnBluetoothOn(true)

            assert.is_false(KoboBluetooth.wifi_borrowed)

            -- Still waiting for Wi-Fi: nothing has been executed yet
            UIManager:executeScheduledTasks(3)
            assert.are.equal(0, #getExecutedCommands())

            -- The restore script brought Wi-Fi up: Bluetooth is enabled, Wi-Fi is left alone
            NetworkMgr:_setWifiState(true)
            UIManager:executeScheduledTasks()

            local commands = getExecutedCommands()
            assert.are.equal(2, #commands)
            assert.is_not_nil(commands[1]:find("BluedroidManager1.On", 1, true))
            assert.are.equal(0, #NetworkMgr._turn_off_wifi_calls)
            assert.is_true(NetworkMgr:isWifiOn())

            G_reader_settings:saveSetting("auto_restore_wifi", nil)
        end)

        it("should not power the chip while a NetworkMgr connection attempt is pending", function()
            setMockExecuteResult(0)
            setMockPopenOutput("variant boolean false")
            clearExecutedCommands()
            local NetworkMgr = require("ui/network/manager")
            NetworkMgr:_reset()
            NetworkMgr:_setWifiState(false)
            NetworkMgr.pending_connection = true

            local instance = MTKBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            instance:turnBluetoothOn()

            assert.is_false(KoboBluetooth.wifi_borrowed)

            NetworkMgr:_setWifiState(true)
            UIManager:executeScheduledTasks()

            for _, cmd in ipairs(getExecutedCommands()) do
                assert.is_not.equal(WmtPower.COMMAND_POWER_ON, cmd)
                assert.is_not.equal(WmtPower.COMMAND_POWER_OFF, cmd)
            end

            NetworkMgr:_reset()
        end)

        it("should leave the WiFi function on when something else started using it meanwhile", function()
            setMockExecuteResult(0)
            setMockPopenOutput("variant boolean false")
            clearExecutedCommands()
            local NetworkMgr = require("ui/network/manager")
            NetworkMgr:_reset()
            NetworkMgr:_setWifiState(false)

            local instance = MTKBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            instance:turnBluetoothOn()

            assert.is_true(KoboBluetooth.wifi_borrowed)

            -- The subprocess powered the chip (fallback), and someone called
            -- NetworkMgr:enableWifi() while Bluetooth was coming up
            require("libs/libkoreader-lfs")._setFileState(WmtPower.POWERED_MARKER, {
                exists = true,
                attributes = { mode = "file" },
            })
            NetworkMgr.pending_connection = true
            UIManager:executeScheduledTasks()

            for _, cmd in ipairs(getExecutedCommands()) do
                assert.is_not.equal(WmtPower.COMMAND_POWER_OFF, cmd)
            end
            assert.are.equal(0, #NetworkMgr._turn_off_wifi_calls)
            -- The hold is released either way so waiters can proceed
            assert.is_false(KoboBluetooth.wifi_borrowed)
            assert.is_true(wasBroadcast("BluetoothWifiReleased"))

            NetworkMgr:_reset()
        end)

        it("should release the hold without touching WiFi when the chip was never powered", function()
            setMockExecuteResult(1)
            setMockPopenOutput("variant boolean false")
            clearExecutedCommands()
            local NetworkMgr = require("ui/network/manager")
            NetworkMgr:_reset()
            NetworkMgr:_setWifiState(false)

            local instance = MTKBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            instance:turnBluetoothOn()

            -- Marker absent: as if the fallback handshake itself had not run
            UIManager:executeScheduledTasks(90)

            for _, cmd in ipairs(getExecutedCommands()) do
                assert.is_not.equal(WmtPower.COMMAND_POWER_OFF, cmd)
            end
            assert.is_false(KoboBluetooth.wifi_borrowed)
            assert.is_true(wasBroadcast("BluetoothWifiReleased"))
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
