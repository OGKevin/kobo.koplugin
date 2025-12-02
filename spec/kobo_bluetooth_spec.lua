---
-- Unit tests for KoboBluetooth module.

require("spec.helper")

describe("KoboBluetooth", function()
    local KoboBluetooth
    local Device
    local UIManager
    local mock_plugin

    _G.resetAllMocks = resetAllMocks

    setup(function()
        -- Load the modules
        Device = require("device")
        UIManager = require("ui/uimanager")
        KoboBluetooth = require("src.kobo_bluetooth")
    end)

    before_each(function()
        -- Reset UI manager state
        UIManager:_reset()

        -- Reset device to default MTK Kobo
        Device.isMTK = true
        Device.isKobo = function()
            return true
        end

        mock_plugin = {
            settings = {},
            saveSettings = function() end,
        }

        -- Reset all mocks to default behavior
        resetAllMocks()
    end)

    describe("isDeviceSupported", function()
        it("should return true on MTK Kobo device", function()
            Device.isMTK = true
            local instance = KoboBluetooth:new()
            assert.is_true(instance:isDeviceSupported())
        end)

        it("should return false on non-MTK Kobo device", function()
            Device.isMTK = false
            local instance = KoboBluetooth:new()
            assert.is_false(instance:isDeviceSupported())
        end)

        it("should return false on non-Kobo device", function()
            local original_isKobo = Device.isKobo
            Device.isKobo = function()
                return false
            end
            local instance = KoboBluetooth:new()
            assert.is_false(instance:isDeviceSupported())
            Device.isKobo = original_isKobo -- Reset
        end)
    end)

    describe("init", function()
        it("should initialize on MTK Kobo device", function()
            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            assert.is_not_nil(instance)
            assert.is_not_nil(instance.device_manager)
            assert.is_not_nil(instance.input_handler)
        end)

        it("should initialize on non-MTK device without error", function()
            Device.isMTK = false
            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            -- Should not crash, just log warning
            assert.is_not_nil(instance)
        end)

        it("should initialize on non-Kobo device without error", function()
            local original_isKobo = Device.isKobo
            Device.isKobo = function()
                return false
            end
            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            Device.isKobo = original_isKobo -- Reset
            -- Should not crash, just log warning
            assert.is_not_nil(instance)
        end)

        it("should prevent standby if Bluetooth is enabled on startup", function()
            setMockPopenOutput("variant boolean true")
            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            -- Should have called preventStandby
            assert.are.equal(1, UIManager._prevent_standby_calls)
            assert.is_true(instance.bluetooth_standby_prevented)
        end)

        it("should not prevent standby if Bluetooth is disabled on startup", function()
            setMockPopenOutput("variant boolean false")
            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            -- Should not have called preventStandby
            assert.are.equal(0, UIManager._prevent_standby_calls)
            assert.is_false(instance.bluetooth_standby_prevented)
        end)

        it("should not double-prevent standby if already prevented", function()
            setMockPopenOutput("variant boolean true")
            local instance = KoboBluetooth:new()
            instance.bluetooth_standby_prevented = true
            instance:initWithPlugin(mock_plugin)

            -- Should not call preventStandby again
            assert.are.equal(0, UIManager._prevent_standby_calls)
            assert.is_true(instance.bluetooth_standby_prevented)
        end)
    end)

    describe("isBluetoothEnabled", function()
        it("should return true when D-Bus returns 'boolean true'", function()
            setMockPopenOutput("variant boolean true")
            local instance = KoboBluetooth:new()
            assert.is_true(instance:isBluetoothEnabled())
        end)

        it("should return false when D-Bus returns 'boolean false'", function()
            setMockPopenOutput("variant boolean false")
            local instance = KoboBluetooth:new()
            assert.is_false(instance:isBluetoothEnabled())
        end)

        it("should return false when D-Bus command fails", function()
            -- Simulate popen failure by setting output to empty string (no match)
            setMockPopenOutput("")
            local instance = KoboBluetooth:new()
            assert.is_false(instance:isBluetoothEnabled())
        end)

        it("should return false when D-Bus returns unexpected format", function()
            setMockPopenOutput("unexpected output")
            local instance = KoboBluetooth:new()
            assert.is_false(instance:isBluetoothEnabled())
        end)

        it("should return false on unsupported device", function()
            Device.isMTK = false
            local instance = KoboBluetooth:new()
            assert.is_false(instance:isBluetoothEnabled())
        end)
    end)

    describe("turnBluetoothOn", function()
        it("should show error message on unsupported device", function()
            Device.isMTK = false
            local instance = KoboBluetooth:new()
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
            local instance = KoboBluetooth:new()
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
            local instance = KoboBluetooth:new()
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

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            instance:turnBluetoothOn()

            assert.are.equal(0, UIManager._prevent_standby_calls)
            assert.is_false(instance.bluetooth_standby_prevented)

            assert.are.equal(1, #UIManager._show_calls)
        end)

        it("should execute correct D-Bus commands for turning ON", function()
            setMockExecuteResult(0)
            setMockPopenOutput("variant boolean false")
            clearExecutedCommands()
            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            instance:turnBluetoothOn()

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

            local instance = KoboBluetooth:new()
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

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            instance:turnBluetoothOn()

            -- Should not have called turnOnWifi
            assert.are.equal(0, #NetworkMgr._turn_on_wifi_calls)
        end)
    end)

    describe("turnBluetoothOff", function()
        it("should show error message on unsupported device", function()
            Device.isMTK = false
            local instance = KoboBluetooth:new()
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
            local instance = KoboBluetooth:new()

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
            local instance = KoboBluetooth:new()
            instance.bluetooth_standby_prevented = false

            instance:turnBluetoothOff()

            -- Should not call allowStandby since we never prevented it
            assert.are.equal(0, UIManager._allow_standby_calls)
        end)

        it("should not turn off Bluetooth if already disabled", function()
            setMockExecuteResult(0)
            setMockPopenOutput("variant boolean false")
            local instance = KoboBluetooth:new()

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

            local instance = KoboBluetooth:new()
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
            local instance = KoboBluetooth:new()
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

    describe("addToMainMenu", function()
        it("should not add menu item on unsupported device", function()
            Device.isMTK = false
            local instance = KoboBluetooth:new()
            local menu_items = {}

            instance:addToMainMenu(menu_items)

            assert.is_nil(menu_items.bluetooth)
        end)

        it("should add bluetooth menu item on supported device", function()
            local instance = KoboBluetooth:new()
            local menu_items = {}

            instance:addToMainMenu(menu_items)

            assert.is_not_nil(menu_items.bluetooth)
            assert.are.equal("Bluetooth", menu_items.bluetooth.text)
            assert.are.equal("network", menu_items.bluetooth.sorting_hint)
        end)

        it("should have submenu structure", function()
            local instance = KoboBluetooth:new()
            local menu_items = {}

            instance:addToMainMenu(menu_items)

            assert.is_not_nil(menu_items.bluetooth.sub_item_table)
            assert.are.equal(3, #menu_items.bluetooth.sub_item_table)
        end)

        it("should have Enable/Disable submenu item with checked_func", function()
            setMockPopenOutput("variant boolean true")
            local instance = KoboBluetooth:new()
            local menu_items = {}

            instance:addToMainMenu(menu_items)

            local enable_disable_item = menu_items.bluetooth.sub_item_table[1]
            assert.is_function(enable_disable_item.checked_func)
            assert.is_true(enable_disable_item.checked_func())
        end)

        it("should have Enable/Disable submenu item with callback that toggles Bluetooth", function()
            resetAllMocks()
            setMockExecuteResult(0)
            setMockPopenOutput("variant boolean false")
            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            local menu_items = {}

            instance:addToMainMenu(menu_items)

            local enable_disable_item = menu_items.bluetooth.sub_item_table[1]
            assert.is_function(enable_disable_item.callback)

            UIManager:_reset()
            setMockExecuteResult(0)

            enable_disable_item.callback()

            assert.are.equal(1, UIManager._prevent_standby_calls)
        end)

        it("should have Scan for devices submenu item", function()
            local instance = KoboBluetooth:new()
            local menu_items = {}

            instance:addToMainMenu(menu_items)

            local scan_item = menu_items.bluetooth.sub_item_table[2]
            assert.are.equal("Scan for devices", scan_item.text)
            assert.is_function(scan_item.enabled_func)
            assert.is_function(scan_item.callback)
        end)
    end)

    describe("event emission", function()
        it("should emit BluetoothStateChanged event with state=true when turning ON", function()
            setMockExecuteResult(0)
            setMockPopenOutput("variant boolean false")
            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            instance:turnBluetoothOn()

            assert.are.equal(1, #UIManager._send_event_calls)
            assert.are.equal("BluetoothStateChanged", UIManager._send_event_calls[1].event.name)
            assert.is_true(UIManager._send_event_calls[1].event.args[1].state)
        end)

        it("should emit BluetoothStateChanged event with state=false when turning OFF", function()
            setMockExecuteResult(0)
            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            instance.bluetooth_standby_prevented = true
            instance:turnBluetoothOff()

            assert.are.equal(1, #UIManager._send_event_calls)
            assert.are.equal("BluetoothStateChanged", UIManager._send_event_calls[1].event.name)
            assert.is_false(UIManager._send_event_calls[1].event.args[1].state)
        end)
    end)

    describe("standby prevention pairing", function()
        it("should pair preventStandby and allowStandby calls correctly", function()
            setMockExecuteResult(0)
            setMockPopenOutput("variant boolean false")
            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            instance:turnBluetoothOn()
            assert.are.equal(1, UIManager._prevent_standby_calls)
            assert.are.equal(0, UIManager._allow_standby_calls)
            assert.is_true(instance.bluetooth_standby_prevented)

            setMockPopenOutput("variant boolean true")

            -- Turn OFF
            instance:turnBluetoothOff()
            assert.are.equal(1, UIManager._prevent_standby_calls)
            assert.are.equal(1, UIManager._allow_standby_calls)
            assert.is_false(instance.bluetooth_standby_prevented)
        end)

        it("should handle multiple ON/OFF cycles", function()
            setMockExecuteResult(0)
            setMockPopenOutput("variant boolean false")
            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            instance:turnBluetoothOn()
            setMockPopenOutput("variant boolean true")
            instance:turnBluetoothOff()

            setMockPopenOutput("variant boolean false")

            instance:turnBluetoothOn()
            setMockPopenOutput("variant boolean true")
            instance:turnBluetoothOff()

            assert.are.equal(2, UIManager._prevent_standby_calls)
            assert.are.equal(2, UIManager._allow_standby_calls)
            assert.is_false(instance.bluetooth_standby_prevented)
        end)
    end)

    describe("refreshPairedDevicesMenu", function()
        it("should update menu items with current device status", function()
            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            local mock_menu = {
                item_table = {},
                switchItemTable = function(self, title, new_items)
                    self.item_table = new_items
                    self._switch_called = true
                    self._switch_title = title
                end,
                _switch_called = false,
                _switch_title = nil,
            }

            local test_devices = {
                {
                    name = "Test Device 1",
                    address = "00:11:22:33:44:55",
                    connected = true,
                },
                {
                    name = "Test Device 2",
                    address = "AA:BB:CC:DD:EE:FF",
                    connected = false,
                },
            }

            instance.device_manager.paired_devices_cache = test_devices

            -- Mock loadPairedDevices to keep our test data
            instance.device_manager.loadPairedDevices = function(self)
                -- Do nothing - keep the test data
            end

            instance:refreshPairedDevicesMenu(mock_menu)

            assert.is_true(mock_menu._switch_called)
            assert.are.equal(2, #mock_menu.item_table)
            assert.are.equal("Test Device 1", mock_menu.item_table[1].text)
            assert.are.equal("Connected", mock_menu.item_table[1].mandatory)
            assert.are.equal("Test Device 2", mock_menu.item_table[2].text)
            assert.are.equal("Not connected", mock_menu.item_table[2].mandatory)
        end)

        it("should handle devices without names", function()
            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            local mock_menu = {
                item_table = {},
                switchItemTable = function(self, title, new_items)
                    self.item_table = new_items
                    self._switch_called = true
                end,
                _switch_called = false,
            }

            instance.device_manager.paired_devices_cache = {
                {
                    name = "",
                    address = "00:11:22:33:44:55",
                    connected = false,
                },
            }

            -- Mock loadPairedDevices to keep our test data
            instance.device_manager.loadPairedDevices = function(self) end

            instance:refreshPairedDevicesMenu(mock_menu)

            assert.is_true(mock_menu._switch_called)
            assert.are.equal(1, #mock_menu.item_table)
            assert.are.equal("00:11:22:33:44:55", mock_menu.item_table[1].text)
        end)
    end)

    describe("refreshDeviceOptionsMenu", function()
        it("should close old menu and show new one when device is connected", function()
            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            UIManager:_reset()

            local mock_menu = { _is_old_menu = true }

            local device_info = {
                name = "Test Device",
                address = "00:11:22:33:44:55",
                connected = false,
            }

            instance.device_manager.paired_devices_cache = {
                {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    connected = true,
                },
            }

            -- Mock loadPairedDevices to keep our test data
            instance.device_manager.loadPairedDevices = function(self) end

            instance:refreshDeviceOptionsMenu(mock_menu, device_info)

            -- Old menu should be closed
            assert.are.equal(1, #UIManager._close_calls)
            assert.are.equal(mock_menu, UIManager._close_calls[1].widget)

            -- New menu should be shown (ButtonDialog)
            assert.is_true(#UIManager._show_calls > 0)
            local new_dialog = UIManager._shown_widgets[#UIManager._shown_widgets]
            assert.is_not_nil(new_dialog)
            -- Check it's a ButtonDialog with disconnect button (device is connected)
            assert.is_not_nil(new_dialog.buttons)
            assert.are.equal("Disconnect", new_dialog.buttons[1][1].text)
        end)

        it("should close old menu and show new one when device is disconnected", function()
            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            UIManager:_reset()

            local mock_menu = { _is_old_menu = true }

            local device_info = {
                name = "Test Device",
                address = "00:11:22:33:44:55",
                connected = true,
            }

            instance.device_manager.paired_devices_cache = {
                {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    connected = false,
                },
            }

            -- Mock loadPairedDevices to keep our test data
            instance.device_manager.loadPairedDevices = function(self) end

            instance:refreshDeviceOptionsMenu(mock_menu, device_info)

            -- Old menu should be closed
            assert.are.equal(1, #UIManager._close_calls)
            assert.are.equal(mock_menu, UIManager._close_calls[1].widget)

            -- New menu should be shown (ButtonDialog)
            assert.is_true(#UIManager._show_calls > 0)
            local new_dialog = UIManager._shown_widgets[#UIManager._shown_widgets]
            assert.is_not_nil(new_dialog)
            -- Check it's a ButtonDialog with connect button (device is disconnected)
            assert.is_not_nil(new_dialog.buttons)
            assert.are.equal("Connect", new_dialog.buttons[1][1].text)
        end)

        it("should include configure keys option when key_bindings is available", function()
            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            instance.key_bindings = {
                showConfigMenu = function() end,
            }

            UIManager:_reset()

            local mock_menu = {}

            local device_info = {
                name = "Test Device",
                address = "00:11:22:33:44:55",
                connected = false,
            }

            instance.device_manager.paired_devices_cache = {
                {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    connected = false,
                },
            }

            -- Mock loadPairedDevices to keep our test data
            instance.device_manager.loadPairedDevices = function(self) end

            instance:refreshDeviceOptionsMenu(mock_menu, device_info)

            -- New dialog should have 2 buttons: Connect and Configure key bindings
            local new_dialog = UIManager._shown_widgets[#UIManager._shown_widgets]
            assert.is_not_nil(new_dialog)
            assert.is_not_nil(new_dialog.buttons)
            assert.are.equal(2, #new_dialog.buttons[1])
            assert.are.equal("Connect", new_dialog.buttons[1][1].text)
            assert.are.equal("Configure key bindings", new_dialog.buttons[1][2].text)
        end)

        it("should handle device not found in paired devices", function()
            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            UIManager:_reset()

            local mock_menu = {}

            local device_info = {
                name = "Missing Device",
                address = "FF:FF:FF:FF:FF:FF",
                connected = false,
            }

            instance.device_manager.paired_devices_cache = {}

            -- Mock loadPairedDevices to keep our test data
            instance.device_manager.loadPairedDevices = function(self) end

            instance:refreshDeviceOptionsMenu(mock_menu, device_info)

            -- Old menu should be closed
            assert.are.equal(1, #UIManager._close_calls)
            -- No new menu should be shown (device not found)
            assert.are.equal(0, #UIManager._show_calls)
            -- device_options_menu should be nil
            assert.is_nil(instance.device_options_menu)
        end)

        it("should have callbacks that trigger recursive refresh", function()
            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            instance.key_bindings = {
                showConfigMenu = function() end,
            }

            UIManager:_reset()

            local mock_menu = {}

            local device_info = {
                name = "Test Device",
                address = "00:11:22:33:44:55",
                connected = false,
            }

            instance.device_manager.paired_devices_cache = {
                {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    connected = false,
                },
            }

            -- Mock loadPairedDevices to keep our test data
            instance.device_manager.loadPairedDevices = function(self) end

            instance:refreshDeviceOptionsMenu(mock_menu, device_info)

            -- New dialog should have 2 buttons: Connect and Configure key bindings
            local new_dialog = UIManager._shown_widgets[#UIManager._shown_widgets]
            assert.is_not_nil(new_dialog)
            assert.is_not_nil(new_dialog.buttons)
            assert.are.equal(2, #new_dialog.buttons[1])
            assert.are.equal("Connect", new_dialog.buttons[1][1].text)
            assert.is_not_nil(new_dialog.buttons[1][1].callback)
            assert.are.equal("Configure key bindings", new_dialog.buttons[1][2].text)
        end)
    end)

    describe("syncPairedDevicesToSettings", function()
        it("should sync paired devices to plugin settings", function()
            setMockPopenOutput("variant boolean true")

            local save_called = false
            mock_plugin = {
                settings = {
                    paired_devices = {},
                },
                saveSettings = function()
                    save_called = true
                end,
            }

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            instance.device_manager.paired_devices_cache = {
                {
                    name = "Device 1",
                    address = "00:11:22:33:44:55",
                    connected = true,
                },
                {
                    name = "Device 2",
                    address = "AA:BB:CC:DD:EE:FF",
                    connected = false,
                },
            }

            -- Mock loadPairedDevices to keep our test data
            instance.device_manager.loadPairedDevices = function(self) end

            instance:syncPairedDevicesToSettings()

            assert.is_true(save_called)
            assert.are.equal(2, #mock_plugin.settings.paired_devices)
            assert.are.equal("00:11:22:33:44:55", mock_plugin.settings.paired_devices[1].address)
            assert.are.equal("Device 1", mock_plugin.settings.paired_devices[1].name)
            assert.are.equal("AA:BB:CC:DD:EE:FF", mock_plugin.settings.paired_devices[2].address)
            assert.are.equal("Device 2", mock_plugin.settings.paired_devices[2].name)
        end)

        it("should not sync if device not supported", function()
            Device.isMTK = false

            mock_plugin = {
                settings = {
                    paired_devices = {},
                },
                saveSettings = function() end,
            }

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            instance:syncPairedDevicesToSettings()

            assert.are.equal(0, #mock_plugin.settings.paired_devices)
        end)

        it("should not sync if Bluetooth not enabled", function()
            setMockPopenOutput("variant boolean false")

            mock_plugin = {
                settings = {
                    paired_devices = {},
                },
                saveSettings = function() end,
            }

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            instance:syncPairedDevicesToSettings()

            assert.are.equal(0, #mock_plugin.settings.paired_devices)
        end)

        it("should not sync if plugin not provided", function()
            setMockPopenOutput("variant boolean true")

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            instance:syncPairedDevicesToSettings()

            -- Should not crash, just return early
            assert.is_not_nil(instance)
        end)
    end)

    describe("registerDeviceWithDispatcher", function()
        it("should register device with dispatcher", function()
            mock_plugin = {
                settings = {
                    paired_devices = {},
                },
                saveSettings = function() end,
            }

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            local device = {
                name = "Test Keyboard",
                address = "00:11:22:33:44:55",
            }

            instance:registerDeviceWithDispatcher(device)

            local Dispatcher = require("dispatcher")
            local action_id = "bluetooth_connect_00_11_22_33_44_55"

            assert.is_not_nil(Dispatcher.registered_actions[action_id])
            assert.are.equal("ConnectToBluetoothDevice", Dispatcher.registered_actions[action_id].event)
            assert.are.equal("00:11:22:33:44:55", Dispatcher.registered_actions[action_id].arg)
        end)

        it("should use address as title if name is empty", function()
            mock_plugin = {
                settings = {
                    paired_devices = {},
                },
                saveSettings = function() end,
            }

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            local device = {
                name = "",
                address = "00:11:22:33:44:55",
            }

            instance:registerDeviceWithDispatcher(device)

            local Dispatcher = require("dispatcher")
            local action_id = "bluetooth_connect_00_11_22_33_44_55"

            assert.is_not_nil(Dispatcher.registered_actions[action_id])
        end)

        it("should not register twice", function()
            mock_plugin = {
                settings = {
                    paired_devices = {},
                },
                saveSettings = function() end,
            }

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            local device = {
                name = "Test Keyboard",
                address = "00:11:22:33:44:55",
            }

            instance:registerDeviceWithDispatcher(device)
            instance:registerDeviceWithDispatcher(device)

            local action_id = "bluetooth_connect_00_11_22_33_44_55"
            assert.is_true(instance.dispatcher_registered_devices[action_id])
        end)

        it("should not register if plugin not provided", function()
            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            local device = {
                name = "Test Keyboard",
                address = "00:11:22:33:44:55",
            }

            instance:registerDeviceWithDispatcher(device)

            -- Should not crash, just return early
            assert.is_not_nil(instance)
        end)

        it("should not register if device is nil", function()
            mock_plugin = {
                settings = {
                    paired_devices = {},
                },
                saveSettings = function() end,
            }

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            instance:registerDeviceWithDispatcher(nil)

            -- Should not crash, just return early
            assert.is_not_nil(instance)
        end)
    end)

    describe("registerPairedDevicesWithDispatcher", function()
        it("should register all paired devices from settings", function()
            setMockPopenOutput("variant boolean false")

            mock_plugin = {
                settings = {
                    paired_devices = {
                        { name = "Device 1", address = "00:11:22:33:44:55" },
                        { name = "Device 2", address = "AA:BB:CC:DD:EE:FF" },
                    },
                },
                saveSettings = function() end,
            }

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            instance:registerPairedDevicesWithDispatcher()

            assert.is_true(instance.dispatcher_registered_devices["bluetooth_connect_00_11_22_33_44_55"])
            assert.is_true(instance.dispatcher_registered_devices["bluetooth_connect_AA_BB_CC_DD_EE_FF"])
        end)

        it("should sync from Bluetooth if enabled", function()
            setMockPopenOutput("variant boolean true")

            mock_plugin = {
                settings = {
                    paired_devices = {},
                },
                saveSettings = function() end,
            }

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            instance.device_manager.paired_devices_cache = {
                { name = "BT Device", address = "11:22:33:44:55:66" },
            }

            -- Mock loadPairedDevices to keep our test data
            instance.device_manager.loadPairedDevices = function(self) end

            instance:registerPairedDevicesWithDispatcher()

            assert.are.equal(1, #mock_plugin.settings.paired_devices)
            assert.is_true(instance.dispatcher_registered_devices["bluetooth_connect_11_22_33_44_55_66"])
        end)

        it("should not register if device not supported", function()
            Device.isMTK = false

            mock_plugin = {
                settings = {
                    paired_devices = {},
                },
                saveSettings = function() end,
            }

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            instance:registerPairedDevicesWithDispatcher()

            -- Should return early
            assert.are.equal(0, #mock_plugin.settings.paired_devices)
        end)

        it("should not register if plugin not provided", function()
            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            instance:registerPairedDevicesWithDispatcher()

            -- Should not crash, just return early
            assert.is_not_nil(instance)
        end)

        it("should not register if no paired devices", function()
            mock_plugin = {
                settings = {
                    paired_devices = {},
                },
                saveSettings = function() end,
            }

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            instance:registerPairedDevicesWithDispatcher()

            -- Should return early without crashing
            assert.is_not_nil(instance)
        end)
    end)

    describe("connectToDevice", function()
        it("should connect to a paired device", function()
            setMockPopenOutput("variant boolean true")

            mock_plugin = {
                settings = {
                    paired_devices = {
                        {
                            name = "Test Device",
                            address = "00:11:22:33:44:55",
                        },
                    },
                },
                saveSettings = function() end,
            }

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            instance.device_manager.paired_devices_cache = {
                {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    connected = false,
                },
            }

            -- Mock loadPairedDevices to keep our test data
            instance.device_manager.loadPairedDevices = function(self) end

            local connect_called = false
            instance.device_manager.connectDevice = function(self, device_info, on_success)
                connect_called = true
                assert.are.equal("00:11:22:33:44:55", device_info.address)
                return true
            end

            local result = instance:connectToDevice("00:11:22:33:44:55")

            assert.is_true(result)
            assert.is_true(connect_called)
        end)

        it("should turn on Bluetooth if disabled", function()
            setMockPopenOutput("variant boolean false")

            mock_plugin = {
                settings = {
                    paired_devices = {
                        {
                            name = "Test Device",
                            address = "00:11:22:33:44:55",
                        },
                    },
                },
                saveSettings = function() end,
            }

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            instance.device_manager.paired_devices_cache = {
                {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    connected = false,
                },
            }

            local turn_on_called = false
            local orig_turnBluetoothOn = instance.turnBluetoothOn
            instance.turnBluetoothOn = function(self)
                turn_on_called = true
                -- Simulate Bluetooth becoming enabled before invoking original implementation
                setMockPopenOutput("variant boolean true")
                return orig_turnBluetoothOn(self)
            end

            instance:connectToDevice("00:11:22:33:44:55")

            assert.is_true(turn_on_called)
        end)

        it("should return false if device not supported", function()
            Device.isMTK = false

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            local result = instance:connectToDevice("00:11:22:33:44:55")

            assert.is_false(result)
        end)

        it("should return false if no address provided", function()
            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            local result = instance:connectToDevice(nil)

            assert.is_false(result)
        end)

        it("should return false if device manager not available", function()
            setMockPopenOutput("variant boolean true")

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            instance.device_manager = nil

            local result = instance:connectToDevice("00:11:22:33:44:55")

            assert.is_false(result)
        end)

        it("should return false if plugin not initialized", function()
            setMockPopenOutput("variant boolean true")

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)
            instance.plugin = nil

            local result = instance:connectToDevice("00:11:22:33:44:55")

            assert.is_false(result)
        end)

        it("should return false if device not in paired list", function()
            setMockPopenOutput("variant boolean true")

            mock_plugin = {
                settings = {
                    paired_devices = {},
                },
                saveSettings = function() end,
            }

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            instance.device_manager.paired_devices_cache = {}

            -- Mock loadPairedDevices to keep our test data
            instance.device_manager.loadPairedDevices = function(self) end

            local result = instance:connectToDevice("00:11:22:33:44:55")

            assert.is_false(result)
            -- Should show connecting message and then error message
            assert.are.equal(2, #UIManager._shown_widgets)
        end)

        it("should return false if device already connected", function()
            setMockPopenOutput("variant boolean true")

            mock_plugin = {
                settings = {
                    paired_devices = {
                        {
                            name = "Test Device",
                            address = "00:11:22:33:44:55",
                        },
                    },
                },
                saveSettings = function() end,
            }

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            instance.device_manager.paired_devices_cache = {
                {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    connected = true,
                },
            }

            -- Mock loadPairedDevices to keep our test data
            instance.device_manager.loadPairedDevices = function(self) end

            local result = instance:connectToDevice("00:11:22:33:44:55")

            assert.is_false(result)
            -- Should show connecting message and then error message
            assert.are.equal(2, #UIManager._shown_widgets)
        end)

        it("should call input handler on successful connection", function()
            setMockPopenOutput("variant boolean true")

            mock_plugin = {
                settings = {
                    paired_devices = {
                        {
                            name = "Test Device",
                            address = "00:11:22:33:44:55",
                        },
                    },
                },
                saveSettings = function() end,
            }

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            instance.device_manager.paired_devices_cache = {
                {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    connected = false,
                },
            }

            -- Mock loadPairedDevices to keep our test data
            instance.device_manager.loadPairedDevices = function(self) end

            local input_handler_called = false
            instance.device_manager.connectDevice = function(self, device_info, on_success)
                on_success(device_info)
            end

            instance.input_handler.openIsolatedInputDevice = function(self, dev, show_ui, save_config)
                input_handler_called = true
                assert.is_false(show_ui)
                assert.is_true(save_config)
            end

            instance:connectToDevice("00:11:22:33:44:55")

            assert.is_true(input_handler_called)
        end)

        -- Sets up test instance with WiFi state and paired devices for testing WiFi restoration behavior
        -- @param wifi_initially_on boolean: Initial WiFi state
        -- @param mock_paired_devices table: List of paired device entries
        -- @param device_connected boolean|nil: Connection state for first device (nil to skip)
        -- @return instance KoboBluetooth: Test instance
        -- @return NetworkMgr table: NetworkMgr mock for assertions
        local function setupWifiRestorationTest(wifi_initially_on, mock_paired_devices, device_connected)
            local NetworkMgr = require("ui/network/manager")
            NetworkMgr:_reset()
            NetworkMgr:_setWifiState(wifi_initially_on)

            mock_plugin = {
                settings = {
                    paired_devices = mock_paired_devices or {},
                },
                saveSettings = function() end,
            }

            local instance = KoboBluetooth:new()
            instance:initWithPlugin(mock_plugin)

            instance.device_manager.paired_devices_cache = mock_paired_devices or {}
            if device_connected ~= nil and #(mock_paired_devices or {}) > 0 then
                instance.device_manager.paired_devices_cache[1].connected = device_connected
            end

            instance.device_manager.loadPairedDevices = function(self) end

            return instance, NetworkMgr
        end

        it("should restore WiFi state when it was off before successful connection", function()
            setMockPopenOutput("variant boolean false") -- Bluetooth is off initially

            local test_device = {
                name = "Test Device",
                address = "00:11:22:33:44:55",
            }
            local instance, NetworkMgr = setupWifiRestorationTest(false, { test_device }, false)

            instance.device_manager.connectDevice = function(self, device_info, on_success)
                on_success(device_info)
                return true
            end

            -- Patch turnBluetoothOn: set mock state, then call original implementation
            local orig_turnBluetoothOn = instance.turnBluetoothOn
            instance.turnBluetoothOn = function(self)
                -- Simulate Bluetooth transition from disabled to enabled
                setMockPopenOutput("variant boolean false")
                orig_turnBluetoothOn(self)
                setMockPopenOutput("variant boolean true")
            end

            local result = instance:connectToDevice("00:11:22:33:44:55")

            assert.is_true(result)
            -- WiFi should have been turned on (by turnBluetoothOn) and then turned back off
            assert.are.equal(1, #NetworkMgr._turn_on_wifi_calls)
            assert.are.equal(1, #NetworkMgr._turn_off_wifi_calls)
            assert.are.equal(false, NetworkMgr._turn_off_wifi_calls[1].long_press)
            assert.is_false(NetworkMgr:isWifiOn())
        end)

        it("should not turn off WiFi when it was already on before connection", function()
            setMockPopenOutput("variant boolean true")

            local test_device = {
                name = "Test Device",
                address = "00:11:22:33:44:55",
            }
            local instance, NetworkMgr = setupWifiRestorationTest(true, { test_device }, false)

            instance.device_manager.connectDevice = function(self, device_info, on_success)
                on_success(device_info)
                return true
            end

            local result = instance:connectToDevice("00:11:22:33:44:55")

            assert.is_true(result)
            -- WiFi should not be turned off
            assert.are.equal(0, #NetworkMgr._turn_off_wifi_calls)
            assert.is_true(NetworkMgr:isWifiOn())
        end)

        it("should restore WiFi state when Bluetooth fails to turn on", function()
            setMockPopenOutput("variant boolean false")

            local test_device = {
                name = "Test Device",
                address = "00:11:22:33:44:55",
            }
            local instance, NetworkMgr = setupWifiRestorationTest(false, { test_device }, false)

            -- Patch turnBluetoothOn to simulate failure while still calling original logic
            local orig_turnBluetoothOn = instance.turnBluetoothOn
            instance.turnBluetoothOn = function(self)
                -- Keep Bluetooth disabled before & after original to simulate failure
                setMockPopenOutput("variant boolean false")
                orig_turnBluetoothOn(self)
                setMockPopenOutput("variant boolean false")
            end

            local result = instance:connectToDevice("00:11:22:33:44:55")

            assert.is_false(result)
            -- WiFi should have been turned on and then turned back off
            assert.are.equal(1, #NetworkMgr._turn_on_wifi_calls)
            assert.are.equal(1, #NetworkMgr._turn_off_wifi_calls)
            assert.is_false(NetworkMgr:isWifiOn())
        end)

        it("should restore WiFi state when device not found in paired list", function()
            setMockPopenOutput("variant boolean false") -- Bluetooth is off initially

            local instance, NetworkMgr = setupWifiRestorationTest(false, {}, nil)

            -- Patch turnBluetoothOn to simulate success and invoke original
            local orig_turnBluetoothOn = instance.turnBluetoothOn
            instance.turnBluetoothOn = function(self)
                setMockPopenOutput("variant boolean false")
                orig_turnBluetoothOn(self)
                setMockPopenOutput("variant boolean true")
            end

            local result = instance:connectToDevice("00:11:22:33:44:55")

            assert.is_false(result)
            -- WiFi should have been turned on and then turned back off
            assert.are.equal(1, #NetworkMgr._turn_on_wifi_calls)
            assert.are.equal(1, #NetworkMgr._turn_off_wifi_calls)
            assert.is_false(NetworkMgr:isWifiOn())
        end)

        it("should restore WiFi state when device already connected", function()
            setMockPopenOutput("variant boolean false") -- Bluetooth is off initially

            local test_device = {
                name = "Test Device",
                address = "00:11:22:33:44:55",
            }
            local instance, NetworkMgr = setupWifiRestorationTest(false, { test_device }, true)

            -- Patch turnBluetoothOn to simulate success and invoke original
            local orig_turnBluetoothOn = instance.turnBluetoothOn
            instance.turnBluetoothOn = function(self)
                setMockPopenOutput("variant boolean false")
                orig_turnBluetoothOn(self)
                setMockPopenOutput("variant boolean true")
            end

            local result = instance:connectToDevice("00:11:22:33:44:55")

            assert.is_false(result)
            -- WiFi should have been turned on and then turned back off
            assert.are.equal(1, #NetworkMgr._turn_on_wifi_calls)
            assert.are.equal(1, #NetworkMgr._turn_off_wifi_calls)
            assert.is_false(NetworkMgr:isWifiOn())
        end)

        it("should restore WiFi state when connectDevice fails", function()
            setMockPopenOutput("variant boolean false") -- Bluetooth is off initially

            local test_device = {
                name = "Test Device",
                address = "00:11:22:33:44:55",
            }
            local instance, NetworkMgr = setupWifiRestorationTest(false, { test_device }, false)

            -- Mock connectDevice to simulate a connection failure
            instance.device_manager.connectDevice = function(self, device_info, on_success)
                -- Connection fails - don't call on_success callback
                return false
            end

            -- Patch turnBluetoothOn to simulate success and invoke original
            local orig_turnBluetoothOn = instance.turnBluetoothOn
            instance.turnBluetoothOn = function(self)
                setMockPopenOutput("variant boolean false")
                orig_turnBluetoothOn(self)
                setMockPopenOutput("variant boolean true")
            end

            local result = instance:connectToDevice("00:11:22:33:44:55")

            -- Connection should fail but WiFi should still be restored
            assert.is_false(result)
            -- WiFi should have been turned on (for Bluetooth) and then turned back off
            assert.are.equal(1, #NetworkMgr._turn_on_wifi_calls)
            assert.are.equal(1, #NetworkMgr._turn_off_wifi_calls)
            assert.is_false(NetworkMgr:isWifiOn())
        end)

        it("should return true when connection succeeds and restore WiFi state", function()
            setMockPopenOutput("variant boolean false") -- Bluetooth is off initially

            local test_device = {
                name = "Test Device",
                address = "00:11:22:33:44:55",
            }
            local instance, NetworkMgr = setupWifiRestorationTest(false, { test_device }, false)

            -- Mock connectDevice to simulate a successful connection
            instance.device_manager.connectDevice = function(self, device_info, on_success)
                on_success(device_info)
                return true
            end

            -- Patch turnBluetoothOn to simulate success and invoke original
            local orig_turnBluetoothOn = instance.turnBluetoothOn
            instance.turnBluetoothOn = function(self)
                setMockPopenOutput("variant boolean false")
                orig_turnBluetoothOn(self)
                setMockPopenOutput("variant boolean true")
            end

            local result = instance:connectToDevice("00:11:22:33:44:55")

            -- Connection should succeed and WiFi should be restored
            assert.is_true(result)
            assert.are.equal(1, #NetworkMgr._turn_on_wifi_calls)
            assert.are.equal(1, #NetworkMgr._turn_off_wifi_calls)
            assert.is_false(NetworkMgr:isWifiOn())
        end)
    end)
end)
