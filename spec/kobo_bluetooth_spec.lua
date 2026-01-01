---
-- Unit tests for KoboBluetooth base class module.
-- Tests focus on:
-- 1. Factory method (device detection and correct class instantiation)
-- 2. Base class behavior (error throwing for required overrides, no-ops for optional)
-- 3. Generic functionality (UI, menus, settings, auto-detection)
--
-- Device-specific behavior is tested in implementation-specific test files:
-- - spec/lib/bluetooth/implementations/mtk_bluetooth_spec.lua

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
        Device._isMTK = true
        Device.isKobo = function()
            return true
        end

        mock_plugin = {
            settings = {
                paired_devices = {},
            },
            saveSettings = function() end,
        }

        -- Reset all mocks to default behavior
        resetAllMocks()
    end)

    describe("Factory method", function()
        describe("create()", function()
            it("should return MTKBluetooth instance on MTK device", function()
                Device._isMTK = true
                Device.isKobo = function()
                    return true
                end
                local instance = KoboBluetooth.create()
                -- MTK instances inherit the base class name
                assert.equals("kobo_bluetooth", instance.name)
                assert.is_true(instance:isDeviceSupported())
            end)

            it("should return base KoboBluetooth instance on non-MTK Kobo device", function()
                Device._isMTK = false
                Device.isKobo = function()
                    return true
                end
                local instance = KoboBluetooth.create()
                assert.equals("kobo_bluetooth", instance.name)
                assert.is_false(instance:isDeviceSupported())
            end)

            it("should return base KoboBluetooth instance on non-Kobo device", function()
                Device._isMTK = false
                Device.isKobo = function()
                    return false
                end
                local instance = KoboBluetooth.create()
                assert.equals("kobo_bluetooth", instance.name)
                assert.is_false(instance:isDeviceSupported())
            end)
        end)
    end)

    describe("Base class behavior", function()
        describe("isDeviceSupported", function()
            it("should return false in base class (requires subclass override)", function()
                local instance = KoboBluetooth:new()
                assert.is_false(instance:isDeviceSupported())
            end)
        end)

        describe("Required override methods", function()
            it("turnBluetoothOn should throw error in base class", function()
                local instance = KoboBluetooth:new()
                instance:initWithPlugin(mock_plugin)

                assert.has_error(
                    function()
                        instance:turnBluetoothOn()
                    end,
                    "KoboBluetooth:turnBluetoothOn(is_resume, on_complete) must be overridden by device-specific implementation"
                )
            end)

            it("turnBluetoothOff should throw error in base class", function()
                local instance = KoboBluetooth:new()
                instance.bluetooth_standby_prevented = true

                assert.has_error(function()
                    instance:turnBluetoothOff()
                end, "KoboBluetooth:turnBluetoothOff() must be overridden by device-specific implementation")
            end)
        end)

        describe("Optional override methods", function()
            it("onResume should be no-op in base class", function()
                local instance = KoboBluetooth:new()
                -- Should not throw error
                assert.has_no_errors(function()
                    instance:onResume()
                end)
            end)
        end)
    end)

    describe("Generic functionality", function()
        -- These tests use the factory method to get the correct implementation
        -- since they test generic functionality that depends on device-specific methods

        describe("addToMainMenu", function()
            it("should not add menu item on unsupported device", function()
                Device._isMTK = false
                local instance = KoboBluetooth.create()
                local menu_items = {}

                instance:addToMainMenu(menu_items)

                assert.is_nil(menu_items.bluetooth)
            end)

            it("should add bluetooth menu item on supported device", function()
                Device._isMTK = true
                local instance = KoboBluetooth.create()
                local menu_items = {}

                instance:addToMainMenu(menu_items)

                assert.is_not_nil(menu_items.bluetooth)
                assert.are.equal("Bluetooth", menu_items.bluetooth.text)
                assert.are.equal("network", menu_items.bluetooth.sorting_hint)
            end)

            it("should have submenu structure", function()
                Device._isMTK = true
                local instance = KoboBluetooth.create()
                local menu_items = {}

                instance:addToMainMenu(menu_items)

                assert.is_not_nil(menu_items.bluetooth.sub_item_table)
                assert.are.equal(4, #menu_items.bluetooth.sub_item_table)
            end)

            it("should have Settings submenu with Auto-detection and Auto-connect options", function()
                Device._isMTK = true
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                local menu_items = {}

                instance:addToMainMenu(menu_items)

                local settings_item = menu_items.bluetooth.sub_item_table[4]
                assert.are.equal("Settings", settings_item.text)
                assert.is_not_nil(settings_item.sub_item_table)
                assert.are.equal(6, #settings_item.sub_item_table)

                local auto_detection = settings_item.sub_item_table[3]
                assert.are.equal("Auto-detection", auto_detection.text)
                assert.is_not_nil(auto_detection.sub_item_table)
                assert.are.equal(2, #auto_detection.sub_item_table)

                local auto_connect = settings_item.sub_item_table[4]
                assert.are.equal("Auto-connect", auto_connect.text)
                assert.is_not_nil(auto_connect.sub_item_table)
                assert.are.equal(2, #auto_connect.sub_item_table)
            end)
        end)

        describe("isBluetoothEnabled", function()
            it("should return true when D-Bus returns 'boolean true'", function()
                setMockPopenOutput("variant boolean true")
                local instance = KoboBluetooth.create()
                assert.is_true(instance:isBluetoothEnabled())
            end)

            it("should return false when D-Bus returns 'boolean false'", function()
                setMockPopenOutput("variant boolean false")
                local instance = KoboBluetooth.create()
                assert.is_false(instance:isBluetoothEnabled())
            end)

            it("should return false when D-Bus command fails", function()
                setMockPopenOutput("")
                local instance = KoboBluetooth.create()
                assert.is_false(instance:isBluetoothEnabled())
            end)

            it("should return false on unsupported device", function()
                Device._isMTK = false
                local instance = KoboBluetooth.create()
                assert.is_false(instance:isBluetoothEnabled())
            end)
        end)

        describe("init", function()
            it("should initialize on supported device", function()
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                assert.is_not_nil(instance)
                assert.is_not_nil(instance.device_manager)
                assert.is_not_nil(instance.input_handler)
            end)

            it("should prevent standby if Bluetooth is enabled on startup", function()
                setMockPopenOutput("variant boolean true")
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                assert.are.equal(1, UIManager._prevent_standby_calls)
                assert.is_true(instance.bluetooth_standby_prevented)
            end)
        end)

        describe("onSuspend", function()
            it("should turn off Bluetooth when suspending and device is supported and Bluetooth is enabled", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                -- Reset UIManager to clear any init popups
                UIManager:_reset()

                -- Spy on turnBluetoothOff to verify it's called
                local turnBluetoothOff_called = false
                local original_turnBluetoothOff = instance.turnBluetoothOff
                instance.turnBluetoothOff = function(self, show_popup)
                    turnBluetoothOff_called = true

                    return original_turnBluetoothOff(self, show_popup)
                end

                instance:onSuspend()

                -- Verify turnBluetoothOff was called
                assert.is_true(turnBluetoothOff_called)
                -- Verify Bluetooth was turned off without popup
                assert.are.equal(0, #UIManager._shown_widgets)
            end)

            it("should not turn off Bluetooth if already off", function()
                setMockPopenOutput("variant boolean false")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                -- Spy on turnBluetoothOff to verify it's NOT called
                local turnBluetoothOff_called = false
                local original_turnBluetoothOff = instance.turnBluetoothOff
                instance.turnBluetoothOff = function(self, show_popup)
                    turnBluetoothOff_called = true

                    return original_turnBluetoothOff(self, show_popup)
                end

                instance:onSuspend()

                -- Verify turnBluetoothOff was NOT called (Bluetooth already off)
                assert.is_false(turnBluetoothOff_called)
            end)
        end)
        describe("standby prevention pairing", function()
            it("should pair preventStandby and allowStandby calls correctly", function()
                setMockExecuteResult(0)
                setMockPopenOutput("variant boolean false")
                local instance = KoboBluetooth.create()
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
                local instance = KoboBluetooth.create()
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

        describe("event emission", function()
            it("should emit BluetoothStateChanged event with state=true when turning ON", function()
                setMockExecuteResult(0)
                setMockPopenOutput("variant boolean false")
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                instance:turnBluetoothOn()

                assert.are.equal(1, #UIManager._send_event_calls)
                assert.are.equal("BluetoothStateChanged", UIManager._send_event_calls[1].event.name)
                assert.is_true(UIManager._send_event_calls[1].event.args[1].state)
            end)

            it("should emit BluetoothStateChanged event with state=false when turning OFF", function()
                setMockExecuteResult(0)
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                instance.bluetooth_standby_prevented = true
                instance:turnBluetoothOff()

                assert.are.equal(1, #UIManager._send_event_calls)
                assert.are.equal("BluetoothStateChanged", UIManager._send_event_calls[1].event.name)
                assert.is_false(UIManager._send_event_calls[1].event.args[1].state)
            end)
        end)

        describe("refreshPairedDevicesMenu", function()
            it("should update menu items with current device status", function()
                local instance = KoboBluetooth.create()
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
                        paired = true,
                    },
                    {
                        name = "Test Device 2",
                        address = "AA:BB:CC:DD:EE:FF",
                        connected = false,
                        paired = true,
                    },
                }

                instance.device_manager.devices_cache = test_devices

                -- Mock loadDevices to keep our test data
                instance.device_manager.loadDevices = function(self)
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
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                local mock_menu = {
                    item_table = {},
                    switchItemTable = function(self, title, new_items)
                        self.item_table = new_items
                        self._switch_called = true
                    end,
                    _switch_called = false,
                }

                instance.device_manager.devices_cache = {
                    {
                        name = "",
                        address = "00:11:22:33:44:55",
                        connected = false,
                        paired = true,
                    },
                }

                -- Mock loadDevices to keep our test data
                instance.device_manager.loadDevices = function(self) end

                instance:refreshPairedDevicesMenu(mock_menu)

                assert.is_true(mock_menu._switch_called)
                assert.are.equal(1, #mock_menu.item_table)
                assert.are.equal("00:11:22:33:44:55", mock_menu.item_table[1].text)
            end)
        end)

        describe("refreshDeviceOptionsMenu", function()
            it("should close old menu and show new one when device is connected", function()
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                UIManager:_reset()

                local mock_menu = { _is_old_menu = true }

                local device_info = {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    connected = false,
                }

                instance.device_manager.devices_cache = {
                    ["00:11:22:33:44:55"] = {
                        name = "Test Device",
                        address = "00:11:22:33:44:55",
                        connected = true,
                        paired = true,
                    },
                }

                -- Mock loadDevices to keep our test data
                instance.device_manager.loadDevices = function(self) end

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
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                UIManager:_reset()

                local mock_menu = { _is_old_menu = true }

                local device_info = {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    connected = true,
                }

                instance.device_manager.devices_cache = {
                    ["00:11:22:33:44:55"] = {
                        name = "Test Device",
                        address = "00:11:22:33:44:55",
                        connected = false,
                        paired = true,
                    },
                }

                -- Mock loadDevices to keep our test data
                instance.device_manager.loadDevices = function(self) end

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

            it(
                "should show configure keys button only when device is connected and key_bindings is available",
                function()
                    local instance = KoboBluetooth.create()
                    instance:initWithPlugin(mock_plugin)

                    instance.key_bindings = {
                        showConfigMenu = function() end,
                        getDeviceBindings = function(self, device_mac)
                            return {}
                        end,
                    }

                    UIManager:_reset()

                    local mock_menu = {}

                    local device_info = {
                        name = "Test Device",
                        address = "00:11:22:33:44:55",
                        connected = true,
                        trusted = true,
                    }

                    instance.device_manager.devices_cache = {
                        ["00:11:22:33:44:55"] = {
                            name = "Test Device",
                            address = "00:11:22:33:44:55",
                            connected = true,
                            trusted = true,
                            paired = true,
                        },
                    }

                    -- Mock loadDevices to keep our test data
                    instance.device_manager.loadDevices = function(self) end

                    instance:refreshDeviceOptionsMenu(mock_menu, device_info)

                    -- New dialog should have 4 button rows: Disconnect, Configure key bindings, Untrust, and Forget
                    local new_dialog = UIManager._shown_widgets[#UIManager._shown_widgets]
                    assert.is_not_nil(new_dialog)
                    assert.is_not_nil(new_dialog.buttons)
                    assert.are.equal(4, #new_dialog.buttons)
                    assert.are.equal("Disconnect", new_dialog.buttons[1][1].text)
                    assert.are.equal("Configure key bindings", new_dialog.buttons[2][1].text)
                    assert.are.equal("Untrust", new_dialog.buttons[3][1].text)
                    assert.are.equal("Forget", new_dialog.buttons[4][1].text)
                end
            )

            it("should not show configure button when device is disconnected", function()
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                instance.key_bindings = {
                    showConfigMenu = function() end,
                    getDeviceBindings = function(self, device_mac)
                        return {}
                    end,
                }

                UIManager:_reset()

                local mock_menu = {}

                local device_info = {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    connected = false,
                    trusted = true,
                }

                instance.device_manager.devices_cache = {
                    ["00:11:22:33:44:55"] = {
                        name = "Test Device",
                        address = "00:11:22:33:44:55",
                        connected = false,
                        trusted = true,
                        paired = true,
                    },
                }

                -- Mock loadDevices to keep our test data
                instance.device_manager.loadDevices = function(self) end

                instance:refreshDeviceOptionsMenu(mock_menu, device_info)

                -- New dialog should have 3 button rows: Connect, Untrust, and Forget (no configure when disconnected)
                local new_dialog = UIManager._shown_widgets[#UIManager._shown_widgets]
                assert.is_not_nil(new_dialog)
                assert.is_not_nil(new_dialog.buttons)
                assert.are.equal(3, #new_dialog.buttons)
                assert.are.equal("Connect", new_dialog.buttons[1][1].text)
                assert.are.equal("Untrust", new_dialog.buttons[2][1].text)
                assert.are.equal("Forget", new_dialog.buttons[3][1].text)
            end)

            it("should handle device not found in paired devices", function()
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                UIManager:_reset()

                local mock_menu = {}

                local device_info = {
                    name = "Missing Device",
                    address = "FF:FF:FF:FF:FF:FF",
                    connected = false,
                }

                instance.device_manager.devices_cache = {}

                -- Mock loadDevices to keep our test data
                instance.device_manager.loadDevices = function(self) end

                instance:refreshDeviceOptionsMenu(mock_menu, device_info)

                -- Old menu should be closed
                assert.are.equal(1, #UIManager._close_calls)
                -- No new menu should be shown (device not found)
                assert.are.equal(0, #UIManager._show_calls)
                -- device_options_menu should be nil
                assert.is_nil(instance.device_options_menu)
            end)

            it("should have callbacks that trigger recursive refresh when device is connected", function()
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                instance.key_bindings = {
                    showConfigMenu = function() end,
                    getDeviceBindings = function(self, device_mac)
                        return {}
                    end,
                }

                UIManager:_reset()

                local mock_menu = {}

                local device_info = {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    connected = true,
                    trusted = true,
                }

                instance.device_manager.devices_cache = {
                    ["00:11:22:33:44:55"] = {
                        name = "Test Device",
                        address = "00:11:22:33:44:55",
                        connected = true,
                        trusted = true,
                        paired = true,
                    },
                }

                -- Mock loadDevices to keep our test data
                instance.device_manager.loadDevices = function(self) end

                instance:refreshDeviceOptionsMenu(mock_menu, device_info)

                -- New dialog should have 4 button rows: Disconnect, Configure key bindings, Untrust, and Forget
                local new_dialog = UIManager._shown_widgets[#UIManager._shown_widgets]
                assert.is_not_nil(new_dialog)
                assert.is_not_nil(new_dialog.buttons)
                assert.are.equal(4, #new_dialog.buttons)
                assert.are.equal("Disconnect", new_dialog.buttons[1][1].text)
                assert.is_not_nil(new_dialog.buttons[1][1].callback)
                assert.are.equal("Configure key bindings", new_dialog.buttons[2][1].text)
                assert.are.equal("Untrust", new_dialog.buttons[3][1].text)
                assert.are.equal("Forget", new_dialog.buttons[4][1].text)
            end)

            it("should call removeDevice when forget button is clicked", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                instance.key_bindings = {
                    showConfigMenu = function() end,
                    getDeviceBindings = function(self, device_mac)
                        return {}
                    end,
                }

                UIManager:_reset()

                local device_info = {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    connected = true,
                    path = "/org/bluez/hci0/dev_00_11_22_33_44_55",
                }

                instance.device_manager.devices_cache = {
                    {
                        name = "Test Device",
                        address = "00:11:22:33:44:55",
                        connected = true,
                        path = "/org/bluez/hci0/dev_00_11_22_33_44_55",
                    },
                }

                -- Mock loadDevices to keep our test data
                instance.device_manager.loadDevices = function(self) end

                -- Mock removeDevice to track if it was called
                local remove_device_called = false
                local original_removeDevice = instance.device_manager.removeDevice

                instance.device_manager.removeDevice = function(self, device, callback)
                    remove_device_called = true

                    if callback then
                        callback(device)
                    end

                    return true
                end

                instance:showDeviceOptionsMenu(device_info)

                local dialog = UIManager._shown_widgets[#UIManager._shown_widgets]
                assert.is_not_nil(dialog)
                assert.is_not_nil(dialog.buttons)

                -- Find the Forget button - should be in the last row
                local forget_button = nil
                for _, row in ipairs(dialog.buttons) do
                    if row[1].text == "Forget" then
                        forget_button = row[1]
                        break
                    end
                end

                assert.is_not_nil(forget_button)

                -- Click the forget button
                forget_button.callback()

                assert.is_true(remove_device_called)

                -- Restore original method
                instance.device_manager.removeDevice = original_removeDevice
            end)

            it("should show reset keybindings button when device has key bindings", function()
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                -- Mock key_bindings with device that has bindings
                instance.key_bindings = {
                    showConfigMenu = function() end,
                    getDeviceBindings = function(self, device_mac)
                        return { BTN_LEFT = "select_item" }
                    end,
                }

                UIManager:_reset()

                local device_info = {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    connected = true,
                    trusted = true,
                }

                instance:showDeviceOptionsMenu(device_info)

                local dialog = UIManager._shown_widgets[#UIManager._shown_widgets]
                assert.is_not_nil(dialog)
                assert.is_not_nil(dialog.buttons)

                -- Should have 5 buttons: Disconnect, Configure key bindings, Untrust, Reset key bindings, Forget
                assert.are.equal(5, #dialog.buttons)
                assert.are.equal("Disconnect", dialog.buttons[1][1].text)
                assert.are.equal("Configure key bindings", dialog.buttons[2][1].text)
                assert.are.equal("Untrust", dialog.buttons[3][1].text)
                assert.are.equal("Reset key bindings", dialog.buttons[4][1].text)
                assert.are.equal("Forget", dialog.buttons[5][1].text)
            end)

            it("should not show reset keybindings button when device has no key bindings", function()
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                -- Mock key_bindings with device that has no bindings
                instance.key_bindings = {
                    showConfigMenu = function() end,
                    getDeviceBindings = function(self, device_mac)
                        return {}
                    end,
                }

                UIManager:_reset()

                local device_info = {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    connected = true,
                    trusted = true,
                }

                instance:showDeviceOptionsMenu(device_info)

                local dialog = UIManager._shown_widgets[#UIManager._shown_widgets]
                assert.is_not_nil(dialog)
                assert.is_not_nil(dialog.buttons)

                -- Should have 4 buttons: Disconnect, Configure key bindings, Untrust, Forget (no reset button)
                assert.are.equal(4, #dialog.buttons)
                assert.are.equal("Disconnect", dialog.buttons[1][1].text)
                assert.are.equal("Configure key bindings", dialog.buttons[2][1].text)
                assert.are.equal("Untrust", dialog.buttons[3][1].text)
                assert.are.equal("Forget", dialog.buttons[4][1].text)
            end)

            it("should call clearDeviceBindings when reset keybindings button is clicked", function()
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                -- Mock clearDeviceBindings to track if it was called
                local clear_bindings_called = false
                local cleared_device_mac = nil

                instance.key_bindings = {
                    showConfigMenu = function() end,
                    getDeviceBindings = function(self, device_mac)
                        return { BTN_LEFT = "select_item" }
                    end,
                    clearDeviceBindings = function(self, device_mac)
                        clear_bindings_called = true
                        cleared_device_mac = device_mac
                    end,
                }

                UIManager:_reset()

                local device_info = {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    connected = true,
                }

                instance.device_manager.devices_cache = {
                    {
                        name = "Test Device",
                        address = "00:11:22:33:44:55",
                        connected = true,
                    },
                }

                -- Mock loadDevices to keep our test data
                instance.device_manager.loadDevices = function(self) end

                instance:showDeviceOptionsMenu(device_info)

                local dialog = UIManager._shown_widgets[#UIManager._shown_widgets]
                assert.is_not_nil(dialog)

                -- Find the Reset key bindings button
                local reset_button = nil
                for _, row in ipairs(dialog.buttons) do
                    if row[1].text == "Reset key bindings" then
                        reset_button = row[1]
                        break
                    end
                end

                assert.is_not_nil(reset_button)

                -- Click the reset button - this should show a confirmation dialog
                reset_button.callback()

                -- Get the confirmation dialog
                local confirm_dialog = UIManager._shown_widgets[#UIManager._shown_widgets]
                assert.is_not_nil(confirm_dialog)
                assert.are.equal(
                    "Are you sure you want to reset all key bindings for this device?",
                    confirm_dialog.text
                )

                -- Confirm the reset
                confirm_dialog.ok_callback()

                assert.is_true(clear_bindings_called)
                assert.are.equal("00:11:22:33:44:55", cleared_device_mac)
            end)

            it("should show Trust button when device is not trusted", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                UIManager:_reset()

                local device_info = {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    connected = false,
                    trusted = false,
                    path = "/org/bluez/hci0/dev_00_11_22_33_44_55",
                }

                instance.device_manager.devices_cache = {
                    {
                        name = "Test Device",
                        address = "00:11:22:33:44:55",
                        connected = false,
                        trusted = false,
                        path = "/org/bluez/hci0/dev_00_11_22_33_44_55",
                    },
                }

                instance.device_manager.loadDevices = function(self) end

                instance:showDeviceOptionsMenu(device_info)

                local dialog = UIManager._shown_widgets[#UIManager._shown_widgets]
                assert.is_not_nil(dialog)
                assert.is_not_nil(dialog.buttons)

                -- Find the Trust button
                local trust_button = nil
                for _, row in ipairs(dialog.buttons) do
                    if row[1].text == "Trust" then
                        trust_button = row[1]
                        break
                    end
                end

                assert.is_not_nil(trust_button)

                -- Untrust button should not be present
                local untrust_button = nil
                for _, row in ipairs(dialog.buttons) do
                    if row[1].text == "Untrust" then
                        untrust_button = row[1]
                        break
                    end
                end

                assert.is_nil(untrust_button)
            end)

            it("should show Untrust button when device is trusted", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                UIManager:_reset()

                local device_info = {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    connected = false,
                    trusted = true,
                    path = "/org/bluez/hci0/dev_00_11_22_33_44_55",
                }

                instance.device_manager.devices_cache = {
                    {
                        name = "Test Device",
                        address = "00:11:22:33:44:55",
                        connected = false,
                        trusted = true,
                        path = "/org/bluez/hci0/dev_00_11_22_33_44_55",
                    },
                }

                instance.device_manager.loadDevices = function(self) end

                instance:showDeviceOptionsMenu(device_info)

                local dialog = UIManager._shown_widgets[#UIManager._shown_widgets]
                assert.is_not_nil(dialog)
                assert.is_not_nil(dialog.buttons)

                -- Find the Untrust button
                local untrust_button = nil
                for _, row in ipairs(dialog.buttons) do
                    if row[1].text == "Untrust" then
                        untrust_button = row[1]
                        break
                    end
                end

                assert.is_not_nil(untrust_button)

                -- Trust button should not be present
                local trust_button = nil
                for _, row in ipairs(dialog.buttons) do
                    if row[1].text == "Trust" then
                        trust_button = row[1]
                        break
                    end
                end

                assert.is_nil(trust_button)
            end)

            it("should call trustDevice when trust button is clicked", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                UIManager:_reset()

                local device_info = {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    connected = false,
                    trusted = false,
                    path = "/org/bluez/hci0/dev_00_11_22_33_44_55",
                }

                instance.device_manager.devices_cache = {
                    {
                        name = "Test Device",
                        address = "00:11:22:33:44:55",
                        connected = false,
                        trusted = false,
                        path = "/org/bluez/hci0/dev_00_11_22_33_44_55",
                    },
                }

                instance.device_manager.loadDevices = function(self) end

                local trust_device_called = false
                local original_trustDevice = instance.device_manager.trustDevice

                instance.device_manager.trustDevice = function(self, device)
                    trust_device_called = true

                    return true
                end

                instance:showDeviceOptionsMenu(device_info)

                local dialog = UIManager._shown_widgets[#UIManager._shown_widgets]
                assert.is_not_nil(dialog)

                -- Find and click the Trust button
                local trust_button = nil
                for _, row in ipairs(dialog.buttons) do
                    if row[1].text == "Trust" then
                        trust_button = row[1]
                        break
                    end
                end

                assert.is_not_nil(trust_button)
                trust_button.callback()

                assert.is_true(trust_device_called)

                instance.device_manager.trustDevice = original_trustDevice
            end)

            it("should call untrustDevice when untrust button is clicked", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                UIManager:_reset()

                local device_info = {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    connected = false,
                    trusted = true,
                    path = "/org/bluez/hci0/dev_00_11_22_33_44_55",
                }

                instance.device_manager.devices_cache = {
                    {
                        name = "Test Device",
                        address = "00:11:22:33:44:55",
                        connected = false,
                        trusted = true,
                        path = "/org/bluez/hci0/dev_00_11_22_33_44_55",
                    },
                }

                instance.device_manager.loadDevices = function(self) end

                local untrust_device_called = false
                local original_untrustDevice = instance.device_manager.untrustDevice

                instance.device_manager.untrustDevice = function(self, device)
                    untrust_device_called = true

                    return true
                end

                instance:showDeviceOptionsMenu(device_info)

                local dialog = UIManager._shown_widgets[#UIManager._shown_widgets]
                assert.is_not_nil(dialog)

                -- Find and click the Untrust button
                local untrust_button = nil
                for _, row in ipairs(dialog.buttons) do
                    if row[1].text == "Untrust" then
                        untrust_button = row[1]
                        break
                    end
                end

                assert.is_not_nil(untrust_button)
                untrust_button.callback()

                assert.is_true(untrust_device_called)

                instance.device_manager.untrustDevice = original_untrustDevice
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

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                instance.device_manager.devices_cache = {
                    {
                        name = "Device 1",
                        address = "00:11:22:33:44:55",
                        connected = true,
                        paired = true,
                    },
                    {
                        name = "Device 2",
                        address = "AA:BB:CC:DD:EE:FF",
                        connected = false,
                        paired = true,
                    },
                }

                -- Mock loadDevices to keep our test data
                instance.device_manager.loadDevices = function(self) end

                instance:syncPairedDevicesToSettings()

                assert.is_true(save_called)
                assert.are.equal(2, #mock_plugin.settings.paired_devices)
                assert.are.equal("00:11:22:33:44:55", mock_plugin.settings.paired_devices[1].address)
                assert.are.equal("Device 1", mock_plugin.settings.paired_devices[1].name)
                assert.are.equal("AA:BB:CC:DD:EE:FF", mock_plugin.settings.paired_devices[2].address)
                assert.are.equal("Device 2", mock_plugin.settings.paired_devices[2].name)
            end)

            it("should not sync if Bluetooth not enabled", function()
                setMockPopenOutput("variant boolean false")

                mock_plugin = {
                    settings = {
                        paired_devices = {},
                    },
                    saveSettings = function() end,
                }

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                instance:syncPairedDevicesToSettings()

                assert.are.equal(0, #mock_plugin.settings.paired_devices)
            end)

            it("should not sync if plugin not provided", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                instance:syncPairedDevicesToSettings()

                -- Should not crash, just return early
                assert.is_not_nil(instance)
            end)
        end)

        describe("auto-detection polling", function()
            it("should register D-Bus callbacks when setting is enabled and Bluetooth is on", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_detection_polling = true

                -- Mock device list
                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device",
                        connected = true,
                        paired = true,
                        trusted = true,
                    },
                }
                instance.device_manager.loadDevices = function(self) end

                UIManager:_reset()
                instance:startAutoDetectionPolling()

                -- Should have registered callback and set active flag
                assert.is_true(instance.is_auto_detection_active)
                assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))
            end)

            it("should not register callbacks when setting is disabled", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_detection_polling = false

                UIManager:_reset()
                instance:startAutoDetectionPolling()

                assert.is_false(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))
            end)

            it("should not register duplicate callbacks when already running", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_detection_polling = true

                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device",
                        connected = false,
                        paired = true,
                        trusted = true,
                    },
                }
                instance.device_manager.loadDevices = function(self) end

                UIManager:_reset()
                instance:startAutoDetectionPolling()
                assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))

                instance:startAutoDetectionPolling()

                -- Should not have registered additional callbacks (still registered once)
                assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))
            end)

            it("should unregister callbacks when stopAutoDetectionPolling is called", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_detection_polling = true

                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device",
                        connected = false,
                        paired = true,
                        trusted = true,
                    },
                }
                instance.device_manager.loadDevices = function(self) end

                UIManager:_reset()
                instance:startAutoDetectionPolling()
                assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))

                instance:stopAutoDetectionPolling()

                assert.is_false(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))
                -- Should have cleared the active flag
                assert.is_false(instance.is_auto_detection_active)
            end)

            it("should auto-open input handler when device property changes to Connected", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_detection_polling = true
                instance.is_startup_detection = false

                -- Register device for auto-detection
                instance.is_auto_detection_active = true

                -- Mock device list with connected device
                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device",
                        connected = true,
                        paired = true,
                        trusted = true,
                    },
                }
                instance.device_manager.loadDevices = function(self) end
                instance.device_manager.getDeviceByAddress = function(self, address)
                    return self.devices_cache[1]
                end

                UIManager:_reset()

                -- Mock the input handler's openIsolatedInputDevice to succeed
                local opened_devices = {}
                instance.input_handler.openIsolatedInputDevice = function(
                    self,
                    device,
                    show_notification,
                    wait_for_device
                )
                    table.insert(opened_devices, {
                        device = device,
                        show_notification = show_notification,
                        wait_for_device = wait_for_device,
                    })
                    return true
                end

                -- Simulate D-Bus property change callback for auto-detection
                instance:onAutoDetectionPropertyChanged("00:11:22:33:44:55", { Connected = true })

                assert.are.equal(1, #opened_devices)
                assert.are.equal("00:11:22:33:44:55", opened_devices[1].device.address)
                assert.is_true(opened_devices[1].show_notification)
                assert.is_true(opened_devices[1].wait_for_device)
            end)

            it("should stop auto-detection after connection when setting is enabled", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_detection_polling = true
                mock_plugin.settings.disable_auto_detection_after_connect = true
                instance.is_startup_detection = false

                -- Setup device as NOT connected initially so auto-detection can begin
                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device",
                        connected = false,
                        paired = true,
                        trusted = true,
                    },
                }
                instance.device_manager.loadDevices = function(self) end
                -- When onDevicePropertyChanged queries the device, it will be connected
                instance.device_manager.getDeviceByAddress = function(self, address)
                    return {
                        address = "00:11:22:33:44:55",
                        name = "Test Device",
                        connected = true,
                        paired = true,
                        trusted = true,
                    }
                end

                UIManager:_reset()

                -- Mock the input handler's openIsolatedInputDevice to succeed
                instance.input_handler.openIsolatedInputDevice = function()
                    return true
                end

                -- Start auto-detection (registers callbacks)
                instance:startAutoDetectionPolling()
                assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))

                -- Simulate D-Bus property change callback for auto-detection
                instance:onAutoDetectionPropertyChanged("00:11:22:33:44:55", { Connected = true })

                -- Auto-detection should have stopped (callbacks unregistered)
                assert.is_false(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))
            end)

            it("should continue auto-detection after connection when setting is disabled", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_detection_polling = true
                mock_plugin.settings.disable_auto_detection_after_connect = false
                instance.is_startup_detection = false

                -- Mock device list
                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device",
                        connected = true,
                        paired = true,
                        trusted = true,
                    },
                }
                instance.device_manager.loadDevices = function(self) end
                instance.device_manager.getDeviceByAddress = function(self, address)
                    return self.devices_cache[1]
                end

                UIManager:_reset()

                -- Mock the input handler's openIsolatedInputDevice to succeed
                instance.input_handler.openIsolatedInputDevice = function()
                    return true
                end

                instance:startAutoDetectionPolling()
                assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))

                -- Simulate D-Bus property change callback for auto-detection
                instance:onAutoDetectionPropertyChanged("00:11:22:33:44:55", { Connected = true })

                -- Callbacks should still be registered
                assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))
            end)

            it("should start key bindings polling when device connects via property change", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_detection_polling = true
                instance.is_startup_detection = false

                -- Register device for auto-detection
                instance.is_auto_detection_active = true

                -- Mock device list
                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device",
                        connected = true,
                        paired = true,
                        trusted = true,
                    },
                }
                instance.device_manager.loadDevices = function(self) end
                instance.device_manager.getDeviceByAddress = function(self, address)
                    return self.devices_cache[1]
                end

                UIManager:_reset()

                -- Mock the input handler's openIsolatedInputDevice to succeed
                instance.input_handler.openIsolatedInputDevice = function()
                    return true
                end

                -- Track key bindings polling
                local key_bindings_started = false
                instance.key_bindings = {
                    startPolling = function()
                        key_bindings_started = true
                    end,
                }

                -- Simulate D-Bus property change callback for auto-detection
                instance:onAutoDetectionPropertyChanged("00:11:22:33:44:55", { Connected = true })

                assert.is_true(key_bindings_started)
            end)

            it("should unregister callbacks when Bluetooth is turned off", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_detection_polling = true

                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device",
                        connected = false,
                        paired = true,
                        trusted = true,
                    },
                }
                instance.device_manager.loadDevices = function(self) end

                UIManager:_reset()
                instance:startAutoDetectionPolling()
                assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))

                -- Stop auto-detection (called when Bluetooth is turned off)
                instance:stopAutoDetectionPolling()

                -- Callbacks should be unregistered
                assert.is_false(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))
            end)

            it(
                "should not register callbacks when device is already connected and disable_auto_detection_after_connect is enabled",
                function()
                    setMockPopenOutput("variant boolean true")

                    local instance = KoboBluetooth.create()
                    instance:initWithPlugin(mock_plugin)
                    mock_plugin.settings.enable_auto_detection_polling = true
                    mock_plugin.settings.disable_auto_detection_after_connect = true

                    -- Simulate that a paired device is already connected via Bluetooth
                    instance.device_manager.devices_cache = {
                        {
                            address = "00:11:22:33:44:55",
                            name = "Test Device",
                            connected = true,
                            paired = true,
                            trusted = true,
                        },
                    }
                    instance.device_manager.loadDevices = function(self) end

                    UIManager:_reset()
                    instance:startAutoDetectionPolling()

                    -- Callbacks should NOT have been registered
                    assert.is_false(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))
                end
            )

            it(
                "should register callbacks when device is already connected but disable_auto_detection_after_connect is disabled",
                function()
                    setMockPopenOutput("variant boolean true")

                    local instance = KoboBluetooth.create()
                    instance:initWithPlugin(mock_plugin)
                    mock_plugin.settings.enable_auto_detection_polling = true
                    mock_plugin.settings.disable_auto_detection_after_connect = false

                    -- Simulate that a paired device is already connected via Bluetooth
                    instance.device_manager.devices_cache = {
                        {
                            address = "00:11:22:33:44:55",
                            name = "Test Device",
                            connected = true,
                            paired = true,
                            trusted = true,
                        },
                    }
                    instance.device_manager.loadDevices = function(self) end

                    UIManager:_reset()
                    instance:startAutoDetectionPolling()

                    -- Callbacks SHOULD have been registered since disable_auto_detection_after_connect is false
                    assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))
                end
            )

            it(
                "should register callbacks when disable_auto_detection_after_connect is enabled but no device is connected",
                function()
                    setMockPopenOutput("variant boolean true")

                    local instance = KoboBluetooth.create()
                    instance:initWithPlugin(mock_plugin)
                    mock_plugin.settings.enable_auto_detection_polling = true
                    mock_plugin.settings.disable_auto_detection_after_connect = true

                    -- Paired device exists but is not connected
                    instance.device_manager.devices_cache = {
                        {
                            address = "00:11:22:33:44:55",
                            name = "Test Device",
                            connected = false,
                            paired = true,
                            trusted = true,
                        },
                    }
                    instance.device_manager.loadDevices = function(self) end

                    UIManager:_reset()
                    instance:startAutoDetectionPolling()

                    -- Callbacks SHOULD have been registered since no device is connected yet
                    assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))
                end
            )

            it(
                "should register callbacks when disable_auto_detection_after_connect is enabled and no paired devices exist",
                function()
                    setMockPopenOutput("variant boolean true")

                    local instance = KoboBluetooth.create()
                    instance:initWithPlugin(mock_plugin)
                    mock_plugin.settings.enable_auto_detection_polling = true
                    mock_plugin.settings.disable_auto_detection_after_connect = true

                    -- No paired devices at all
                    instance.device_manager.devices_cache = {}
                    instance.device_manager.loadDevices = function(self) end

                    UIManager:_reset()
                    instance:startAutoDetectionPolling()

                    -- Callbacks ARE registered even with no paired devices (filtering happens at callback level)
                    assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))
                end
            )
        end)

        describe("device connection callbacks", function()
            it(
                "should stop auto-detection on device connect when disable_auto_detection_after_connect is enabled",
                function()
                    setMockPopenOutput("variant boolean true")

                    local instance = KoboBluetooth.create()
                    instance:initWithPlugin(mock_plugin)
                    mock_plugin.settings.enable_auto_detection_polling = true
                    mock_plugin.settings.disable_auto_detection_after_connect = true

                    -- Start with no connected devices so auto-detection can begin
                    instance.device_manager.devices_cache = {
                        {
                            address = "00:11:22:33:44:55",
                            name = "Test Device",
                            connected = false,
                            paired = true,
                            trusted = true,
                        },
                    }
                    instance.device_manager.loadDevices = function(self) end

                    UIManager:_reset()
                    instance:startAutoDetectionPolling()
                    assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))

                    -- Simulate device connected callback
                    instance:onDeviceConnected({ address = "00:11:22:33:44:55", name = "Test Device" })

                    -- Auto-detection should have stopped (callbacks unregistered)
                    assert.is_false(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))
                end
            )

            it(
                "should not stop auto-detection on device connect when disable_auto_detection_after_connect is disabled",
                function()
                    setMockPopenOutput("variant boolean true")

                    local instance = KoboBluetooth.create()
                    instance:initWithPlugin(mock_plugin)
                    mock_plugin.settings.enable_auto_detection_polling = true
                    mock_plugin.settings.disable_auto_detection_after_connect = false

                    instance.device_manager.devices_cache = {
                        {
                            address = "00:11:22:33:44:55",
                            name = "Test Device",
                            connected = false,
                            paired = true,
                            trusted = true,
                        },
                    }
                    instance.device_manager.loadDevices = function(self) end

                    UIManager:_reset()
                    instance:startAutoDetectionPolling()
                    assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))

                    -- Simulate device connected callback
                    instance:onDeviceConnected({ address = "00:11:22:33:44:55", name = "Test Device" })

                    -- Auto-detection should still be running
                    assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))
                end
            )

            it("should restart auto-detection on device disconnect when last device disconnects", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_detection_polling = true
                mock_plugin.settings.disable_auto_detection_after_connect = true

                -- No callbacks initially (was stopped after connection)
                instance.is_auto_detection_active = false

                -- Mock loadDevices to return no connected devices (last device disconnected)
                instance.device_manager.loadDevices = function(self)
                    self.devices_cache = {
                        {
                            address = "00:11:22:33:44:55",
                            name = "Test Device",
                            connected = false,
                            paired = true,
                            trusted = true,
                        },
                    }
                end

                UIManager:_reset()

                -- Simulate device disconnected callback
                instance:onDeviceDisconnected({ address = "00:11:22:33:44:55", name = "Test Device" })

                -- Auto-detection should have restarted (callbacks registered)
                assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))
            end)

            it("should not restart auto-detection on device disconnect when other devices still connected", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_detection_polling = true
                mock_plugin.settings.disable_auto_detection_after_connect = true

                -- No callbacks initially
                instance.is_auto_detection_active = false

                -- Set devices_cache directly to have one still-connected device
                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device 1",
                        connected = false,
                        paired = true,
                        trusted = true,
                    },
                    {
                        address = "AA:BB:CC:DD:EE:FF",
                        name = "Test Device 2",
                        connected = true,
                        paired = true,
                        trusted = true,
                    },
                }

                UIManager:_reset()

                -- Simulate device disconnected callback
                instance:onDeviceDisconnected({ address = "00:11:22:33:44:55", name = "Test Device 1" })

                -- Auto-detection should NOT have restarted (another device still connected)
                assert.is_false(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))
            end)

            it("should not restart auto-detection on device disconnect when setting is disabled", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_detection_polling = false
                mock_plugin.settings.disable_auto_detection_after_connect = true

                instance.is_auto_detection_active = false

                instance.device_manager.loadDevices = function(self)
                    self.devices_cache = {}
                end

                UIManager:_reset()

                -- Simulate device disconnected callback
                instance:onDeviceDisconnected({ address = "00:11:22:33:44:55", name = "Test Device" })

                -- Auto-detection should NOT have started (setting disabled)
                assert.is_false(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))
            end)

            it(
                "should not restart auto-detection on device disconnect when disable_auto_detection_after_connect is disabled",
                function()
                    setMockPopenOutput("variant boolean true")

                    local instance = KoboBluetooth.create()
                    instance:initWithPlugin(mock_plugin)
                    mock_plugin.settings.enable_auto_detection_polling = true
                    mock_plugin.settings.disable_auto_detection_after_connect = false

                    instance.is_auto_detection_active = false

                    instance.device_manager.loadDevices = function(self)
                        self.devices_cache = {}
                    end

                    UIManager:_reset()

                    -- Simulate device disconnected callback
                    instance:onDeviceDisconnected({ address = "00:11:22:33:44:55", name = "Test Device" })

                    -- Auto-detection should NOT have started (disable_auto_detection_after_connect is false)
                    assert.is_false(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))
                end
            )

            it(
                "should restart auto-detection on input device close when last device disconnects unexpectedly",
                function()
                    setMockPopenOutput("variant boolean true")

                    local instance = KoboBluetooth.create()

                    mock_plugin.settings.enable_auto_detection_polling = true
                    mock_plugin.settings.disable_auto_detection_after_connect = true

                    -- No callbacks initially (was stopped after connection)
                    instance.is_auto_detection_active = false

                    instance:initWithPlugin(mock_plugin)

                    instance.device_manager.getDevices = function(self)
                        return {
                            {
                                address = "00:11:22:33:44:55",
                                name = "Test Device",
                                connected = false,
                                paired = true,
                                trusted = true,
                            },
                        }
                    end

                    -- No callbacks initially (was stopped after connection)
                    instance.auto_detection_registered_devices = {}

                    -- No isolated readers remaining (last device disconnected)
                    instance.input_handler.isolated_readers = {}

                    UIManager:_reset()

                    -- Simulate input device closed callback (unexpected disconnect)
                    instance:onInputDeviceClosed("00:11:22:33:44:55", "/dev/input/event4")

                    -- Auto-detection should have restarted (callbacks registered)
                    assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))
                end
            )

            it("should not restart auto-detection on input device close when other devices still connected", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_detection_polling = true
                mock_plugin.settings.disable_auto_detection_after_connect = true

                -- No callbacks initially
                instance.is_auto_detection_active = false

                -- Another device still has an open reader
                instance.input_handler.isolated_readers = {
                    ["AA:BB:CC:DD:EE:FF"] = {
                        device_path = "/dev/input/event5",
                        reader = {},
                    },
                }

                UIManager:_reset()

                -- Simulate input device closed callback
                instance:onInputDeviceClosed("00:11:22:33:44:55", "/dev/input/event4")

                -- Auto-detection should NOT have restarted (another device still connected)
                assert.is_false(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))
            end)

            it("should not restart auto-detection on input device close when setting is disabled", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_detection_polling = false
                mock_plugin.settings.disable_auto_detection_after_connect = true

                instance.is_auto_detection_active = false
                instance.input_handler.isolated_readers = {}

                UIManager:_reset()

                -- Simulate input device closed callback
                instance:onInputDeviceClosed("00:11:22:33:44:55", "/dev/input/event4")

                -- Auto-detection should NOT have started (setting disabled)
                assert.is_false(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))
            end)

            it(
                "should not restart auto-detection on input device close when disable_auto_detection_after_connect is disabled",
                function()
                    setMockPopenOutput("variant boolean true")

                    local instance = KoboBluetooth.create()
                    instance:initWithPlugin(mock_plugin)
                    mock_plugin.settings.enable_auto_detection_polling = true
                    mock_plugin.settings.disable_auto_detection_after_connect = false

                    instance.is_auto_detection_active = false
                    instance.input_handler.isolated_readers = {}

                    UIManager:_reset()

                    -- Simulate input device closed callback
                    instance:onInputDeviceClosed("00:11:22:33:44:55", "/dev/input/event4")

                    -- Auto-detection should NOT have started (disable_auto_detection_after_connect is false)
                    assert.is_false(instance.dbus_monitor:hasCallback("kobobluetooth:auto_detection"))
                end
            )
        end)

        describe("toggleBluetooth", function()
            it("should turn on Bluetooth when currently off", function()
                setMockPopenOutput("variant boolean false")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                -- Mock turnBluetoothOn
                local turn_on_called = false
                instance.turnBluetoothOn = function(self)
                    turn_on_called = true
                end

                instance:toggleBluetooth()

                -- Should have called turnBluetoothOn
                assert.is_true(turn_on_called)
            end)

            it("should turn off Bluetooth when currently on with popup by default", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                -- Mock turnBluetoothOff
                local turn_off_called = false
                local captured_show_popup = nil
                instance.turnBluetoothOff = function(self, show_popup)
                    turn_off_called = true
                    captured_show_popup = show_popup
                end

                instance:toggleBluetooth()

                -- Should have called turnBluetoothOff with show_popup=true (default)
                assert.is_true(turn_off_called)
                assert.is_true(captured_show_popup)
            end)

            it("should turn off Bluetooth without popup when show_popup is false", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                -- Mock turnBluetoothOff
                local turn_off_called = false
                local captured_show_popup = nil
                instance.turnBluetoothOff = function(self, show_popup)
                    turn_off_called = true
                    captured_show_popup = show_popup
                end

                instance:toggleBluetooth(false)

                -- Should have called turnBluetoothOff with show_popup=false
                assert.is_true(turn_off_called)
                assert.is_false(captured_show_popup)
            end)

            it("should turn off Bluetooth with popup when show_popup is true", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                -- Mock turnBluetoothOff
                local turn_off_called = false
                local captured_show_popup = nil
                instance.turnBluetoothOff = function(self, show_popup)
                    turn_off_called = true
                    captured_show_popup = show_popup
                end

                instance:toggleBluetooth(true)

                -- Should have called turnBluetoothOff with show_popup=true
                assert.is_true(turn_off_called)
                assert.is_true(captured_show_popup)
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

                local instance = KoboBluetooth.create()
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

                local instance = KoboBluetooth.create()
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

                local instance = KoboBluetooth.create()
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
                local instance = KoboBluetooth.create()
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

                local instance = KoboBluetooth.create()
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

                local instance = KoboBluetooth.create()
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

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                instance.device_manager.devices_cache = {
                    { name = "BT Device", address = "11:22:33:44:55:66", paired = true },
                }

                -- Mock loadDevices to keep our test data
                instance.device_manager.loadDevices = function(self) end

                instance:registerPairedDevicesWithDispatcher()

                assert.are.equal(1, #mock_plugin.settings.paired_devices)
                assert.is_true(instance.dispatcher_registered_devices["bluetooth_connect_11_22_33_44_55_66"])
            end)

            it("should not register if plugin not provided", function()
                local instance = KoboBluetooth.create()
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

                local instance = KoboBluetooth.create()
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

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                instance.device_manager.devices_cache = {
                    {
                        name = "Test Device",
                        address = "00:11:22:33:44:55",
                        connected = false,
                        paired = true,
                    },
                }

                -- Mock loadDevices to keep our test data
                instance.device_manager.loadDevices = function(self) end

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

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                instance.device_manager.devices_cache = {
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

            it("should return false if no address provided", function()
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                local result = instance:connectToDevice(nil)

                assert.is_false(result)
            end)

            it("should return false if device manager not available", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                instance.device_manager = nil

                local result = instance:connectToDevice("00:11:22:33:44:55")

                assert.is_false(result)
            end)

            it("should return false if plugin not initialized", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
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

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                instance.device_manager.devices_cache = {}

                -- Mock loadDevices to keep our test data
                instance.device_manager.loadDevices = function(self) end

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

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                instance.device_manager.devices_cache = {
                    {
                        name = "Test Device",
                        address = "00:11:22:33:44:55",
                        connected = true,
                    },
                }

                -- Mock loadDevices to keep our test data
                instance.device_manager.loadDevices = function(self) end

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

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                instance.device_manager.devices_cache = {
                    {
                        name = "Test Device",
                        address = "00:11:22:33:44:55",
                        connected = false,
                        paired = true,
                    },
                }

                -- Mock loadDevices to keep our test data
                instance.device_manager.loadDevices = function(self) end

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

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                instance.device_manager.devices_cache = mock_paired_devices or {}
                if device_connected ~= nil and #(mock_paired_devices or {}) > 0 then
                    instance.device_manager.devices_cache[1].connected = device_connected
                end

                instance.device_manager.loadDevices = function(self) end

                return instance, NetworkMgr
            end

            it("should restore WiFi state when it was off before successful connection", function()
                setMockPopenOutput("variant boolean false") -- Bluetooth is off initially
                setMockExecuteResult(0) -- BT commands will succeed

                local test_device = {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    paired = true,
                }
                local instance, NetworkMgr = setupWifiRestorationTest(false, { test_device }, false)

                instance.device_manager.connectDevice = function(self, device_info, on_success)
                    on_success(device_info)
                    return true
                end

                -- First call to connectToDevice with BT off returns true (async started)
                -- The callback will call connectToDevice again, which should succeed
                local result = instance:connectToDevice("00:11:22:33:44:55")

                assert.is_true(result)
                -- Execute all scheduled callbacks to simulate async completion
                UIManager:executeScheduledTasks()

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
                    paired = true,
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
                setMockExecuteResult(1) -- Make BT commands fail

                local test_device = {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    paired = true,
                }
                local instance, NetworkMgr = setupWifiRestorationTest(false, { test_device }, false)

                local result = instance:connectToDevice("00:11:22:33:44:55")

                -- Execute scheduled tasks with enough iterations for polling timeout (30 polls)
                UIManager:executeScheduledTasks(35)

                -- With async pattern, initial call returns true (async operation started)
                assert.is_true(result)
                -- WiFi should have been turned on and then turned back off (even though BT failed)
                assert.are.equal(1, #NetworkMgr._turn_on_wifi_calls)
                assert.are.equal(1, #NetworkMgr._turn_off_wifi_calls)
                assert.is_false(NetworkMgr:isWifiOn())
            end)

            it("should restore WiFi state when device not found in paired list", function()
                setMockPopenOutput("variant boolean false") -- Bluetooth is off initially
                setMockExecuteResult(0) -- BT commands will succeed

                local instance, NetworkMgr = setupWifiRestorationTest(false, {}, nil)

                local result = instance:connectToDevice("00:11:22:33:44:55")

                -- Execute scheduled tasks
                UIManager:executeScheduledTasks()

                -- Initial call returns true (async started), callback will fail but that's internal
                assert.is_true(result)
                -- WiFi should have been turned on and then turned back off
                assert.are.equal(1, #NetworkMgr._turn_on_wifi_calls)
                assert.are.equal(1, #NetworkMgr._turn_off_wifi_calls)
                assert.is_false(NetworkMgr:isWifiOn())
            end)

            it("should restore WiFi state when device already connected", function()
                setMockPopenOutput("variant boolean false") -- Bluetooth is off initially
                setMockExecuteResult(0) -- BT commands will succeed

                local test_device = {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    paired = true,
                }
                local instance, NetworkMgr = setupWifiRestorationTest(false, { test_device }, true)

                local result = instance:connectToDevice("00:11:22:33:44:55")

                -- Execute scheduled tasks
                UIManager:executeScheduledTasks()

                -- Initial call returns true (async started), callback will fail but that's internal
                assert.is_true(result)
                -- WiFi should have been turned on and then turned back off
                assert.are.equal(1, #NetworkMgr._turn_on_wifi_calls)
                assert.are.equal(1, #NetworkMgr._turn_off_wifi_calls)
                assert.is_false(NetworkMgr:isWifiOn())
            end)

            it("should restore WiFi state when connectDevice fails", function()
                setMockPopenOutput("variant boolean false") -- Bluetooth is off initially
                setMockExecuteResult(0) -- BT commands will succeed

                local test_device = {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    paired = true,
                }
                local instance, NetworkMgr = setupWifiRestorationTest(false, { test_device }, false)

                -- Mock connectDevice to simulate a connection failure
                instance.device_manager.connectDevice = function(self, device_info, on_success)
                    -- Connection fails - don't call on_success callback
                    return false
                end

                local result = instance:connectToDevice("00:11:22:33:44:55")

                -- Execute scheduled tasks
                UIManager:executeScheduledTasks()

                -- Initial call returns true (async started), callback will fail but that's internal
                assert.is_true(result)
                -- WiFi should have been turned on (for Bluetooth) and then turned back off
                assert.are.equal(1, #NetworkMgr._turn_on_wifi_calls)
                assert.are.equal(1, #NetworkMgr._turn_off_wifi_calls)
                assert.is_false(NetworkMgr:isWifiOn())
            end)

            it("should return true when connection succeeds and restore WiFi state", function()
                setMockPopenOutput("variant boolean false") -- Bluetooth is off initially
                setMockExecuteResult(0) -- BT commands will succeed

                local test_device = {
                    name = "Test Device",
                    address = "00:11:22:33:44:55",
                    paired = true,
                }
                local instance, NetworkMgr = setupWifiRestorationTest(false, { test_device }, false)

                -- Mock connectDevice to simulate a successful connection
                instance.device_manager.connectDevice = function(self, device_info, on_success)
                    on_success(device_info)
                    return true
                end

                local result = instance:connectToDevice("00:11:22:33:44:55")

                -- Execute all scheduled callbacks to simulate async completion
                UIManager:executeScheduledTasks()

                -- Connection should succeed and WiFi should be restored
                assert.is_true(result)
                assert.are.equal(1, #NetworkMgr._turn_on_wifi_calls)
                assert.are.equal(1, #NetworkMgr._turn_off_wifi_calls)
                assert.is_false(NetworkMgr:isWifiOn())
            end)
        end)

        describe("onConnectToBluetoothDevice", function()
            it("should call connectToDevice with device address and return true", function()
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

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                instance.device_manager.devices_cache = {
                    {
                        name = "Test Device",
                        address = "00:11:22:33:44:55",
                        connected = false,
                        paired = true,
                    },
                }

                -- Mock loadDevices to keep our test data
                instance.device_manager.loadDevices = function(self) end

                local connect_called = false
                local captured_address = nil
                instance.device_manager.connectDevice = function(self, device_info, on_success)
                    connect_called = true
                    captured_address = device_info.address
                end

                local result = instance:onConnectToBluetoothDevice("00:11:22:33:44:55")

                assert.is_true(result)
                assert.is_true(connect_called)
                assert.are.equal("00:11:22:33:44:55", captured_address)
            end)
        end)

        describe("onBluetoothAction", function()
            it("should call turnBluetoothOn when action_id is 'enable'", function()
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                -- Mock turnBluetoothOn
                local turn_on_called = false
                instance.turnBluetoothOn = function(self)
                    turn_on_called = true
                end

                instance:onBluetoothAction("enable")

                -- Should have called turnBluetoothOn
                assert.is_true(turn_on_called)
            end)

            it("should call turnBluetoothOff with popup when action_id is 'disable'", function()
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                -- Mock turnBluetoothOff
                local turn_off_called = false
                local captured_show_popup = nil
                instance.turnBluetoothOff = function(self, show_popup)
                    turn_off_called = true
                    captured_show_popup = show_popup
                end

                instance:onBluetoothAction("disable")

                -- Should have called turnBluetoothOff(true)
                assert.is_true(turn_off_called)
                assert.is_true(captured_show_popup)
            end)

            it("should call toggleBluetooth with popup when action_id is 'toggle'", function()
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                -- Mock toggleBluetooth
                local toggle_called = false
                local captured_show_popup = nil
                instance.toggleBluetooth = function(self, show_popup)
                    toggle_called = true
                    captured_show_popup = show_popup
                end

                instance:onBluetoothAction("toggle")

                -- Should have called toggleBluetooth(true)
                assert.is_true(toggle_called)
                assert.is_true(captured_show_popup)
            end)

            it("should call scanAndShowDevices when action_id is 'scan'", function()
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                -- Mock scanAndShowDevices
                local scan_called = false
                instance.scanAndShowDevices = function(self)
                    scan_called = true
                end

                instance:onBluetoothAction("scan")

                assert.is_true(scan_called)
            end)

            it("should do nothing when action_id is unknown", function()
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                -- Mock all methods to track if they get called
                local turn_on_called = false
                local turn_off_called = false
                local toggle_called = false
                local scan_called = false

                instance.turnBluetoothOn = function(self)
                    turn_on_called = true
                end
                instance.turnBluetoothOff = function(self, show_popup)
                    turn_off_called = true
                end
                instance.toggleBluetooth = function(self, show_popup)
                    toggle_called = true
                end
                instance.scanAndShowDevices = function(self)
                    scan_called = true
                end

                -- Should not crash or call any methods
                instance:onBluetoothAction("unknown_action")

                assert.is_false(turn_on_called)
                assert.is_false(turn_off_called)
                assert.is_false(toggle_called)
                assert.is_false(scan_called)
            end)
        end)

        describe("onConnectedPropertyChanged", function()
            it("should open input device when Connected becomes true", function()
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Name"
            variant string "Test Device"
         )
         dict entry(
            string "Connected"
            variant boolean true
         )
      ]
   )
]])

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                -- Need to add device to paired_devices for getDeviceByAddress to work
                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device",
                        connected = true,
                    },
                }
                instance.device_manager.loadDevices = function(self) end
                instance.device_manager.getDeviceByAddress = function(self, address)
                    for _, dev in ipairs(self.devices_cache) do
                        if dev.address == address then
                            return dev
                        end
                    end
                    return nil
                end

                -- Register device for auto-detection
                instance.is_auto_detection_active = true

                local open_called = false
                local open_device = nil
                instance.input_handler.openIsolatedInputDevice = function(self, device, show_notification, auto_start)
                    open_called = true
                    open_device = device
                    return true
                end

                instance:onConnectedPropertyChanged("00:11:22:33:44:55", true)

                assert.is_true(open_called)
                assert.are.equal("00:11:22:33:44:55", open_device.address)
            end)
        end)

        describe("registerBluetoothActionsWithDispatcher", function()
            it("should register all Bluetooth actions with dispatcher", function()
                local Dispatcher = require("dispatcher")
                Dispatcher.registered_actions = {}

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                instance:registerBluetoothActionsWithDispatcher()
                -- Verify all actions are registered
                assert.is_not_nil(Dispatcher.registered_actions["enable"])
                assert.are.equal("BluetoothAction", Dispatcher.registered_actions["enable"].event)
                assert.are.equal("enable", Dispatcher.registered_actions["enable"].arg)

                assert.is_not_nil(Dispatcher.registered_actions["disable"])
                assert.are.equal("BluetoothAction", Dispatcher.registered_actions["disable"].event)
                assert.are.equal("disable", Dispatcher.registered_actions["disable"].arg)

                assert.is_not_nil(Dispatcher.registered_actions["toggle"])
                assert.are.equal("BluetoothAction", Dispatcher.registered_actions["toggle"].event)
                assert.are.equal("toggle", Dispatcher.registered_actions["toggle"].arg)

                assert.is_not_nil(Dispatcher.registered_actions["scan"])
                assert.are.equal("BluetoothAction", Dispatcher.registered_actions["scan"].event)
                assert.are.equal("scan", Dispatcher.registered_actions["scan"].arg)

                -- Verify last action has separator
                assert.is_true(Dispatcher.registered_actions["scan"].separator)
            end)
        end)

        describe("stopAutoConnectPolling", function()
            it("should unregister devices and stop discovery", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                -- Simulate active auto-connect with registered device
                instance.is_auto_connect_active = true
                instance.last_seen_rssi["00:11:22:33:44:55"] = -50
                instance.is_discovery_active = true

                clearExecutedCommands()

                instance:stopAutoConnectPolling()

                -- Devices should be unregistered
                assert.is_false(instance.is_auto_connect_active)
                assert.is_nil(instance.last_seen_rssi["00:11:22:33:44:55"])

                -- Discovery should be stopped
                local commands = getExecutedCommands()
                assert.are.equal(1, #commands)
                assert.truthy(commands[1]:match("StopDiscovery"))
            end)

            it("should clear is_discovery_active flag", function()
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                instance.is_discovery_active = true
                instance.is_auto_connect_active = true

                instance:stopAutoConnectPolling()

                assert.is_false(instance.is_discovery_active)
            end)

            it("should handle being called when no poll is running", function()
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                instance.auto_connect_poll_task = nil

                -- Should not error
                instance:stopAutoConnectPolling()

                assert.is_nil(instance.auto_connect_poll_task)
            end)

            it("should not stop discovery when no poll task exists", function()
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                instance.auto_connect_poll_task = nil
                clearExecutedCommands()

                instance:stopAutoConnectPolling()

                -- No commands should be executed
                local commands = getExecutedCommands()
                assert.are.equal(0, #commands)
            end)
        end)

        describe("connectToDevice show_notification parameter", function()
            it("should show notification by default", function()
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

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                instance.device_manager.devices_cache = {
                    {
                        name = "Test Device",
                        address = "00:11:22:33:44:55",
                        connected = false,
                    },
                }
                instance.device_manager.loadDevices = function(self) end
                instance.device_manager.connectDevice = function(self, device_info, on_success)
                    return true
                end

                UIManager:_reset()

                instance:connectToDevice("00:11:22:33:44:55")

                -- Should have shown a connecting message
                assert.is_true(#UIManager._show_calls > 0)
            end)

            it("should not show notification when show_notification is false", function()
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

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                instance.device_manager.devices_cache = {
                    {
                        name = "Test Device",
                        address = "00:11:22:33:44:55",
                        connected = false,
                    },
                }
                instance.device_manager.loadDevices = function(self) end
                instance.device_manager.connectDevice = function(self, device_info, on_success)
                    return true
                end

                UIManager:_reset()

                instance:connectToDevice("00:11:22:33:44:55", false)

                -- Should not have shown any messages
                assert.are.equal(0, #UIManager._show_calls)
            end)

            it("should show notification when show_notification is true", function()
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

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                instance.device_manager.devices_cache = {
                    {
                        name = "Test Device",
                        address = "00:11:22:33:44:55",
                        connected = false,
                    },
                }
                instance.device_manager.loadDevices = function(self) end
                instance.device_manager.connectDevice = function(self, device_info, on_success)
                    return true
                end

                UIManager:_reset()

                instance:connectToDevice("00:11:22:33:44:55", true)

                -- Should have shown a connecting message
                assert.is_true(#UIManager._show_calls > 0)
            end)

            it("should store RSSI when device disconnects to prevent immediate reconnection", function()
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Paired"
            variant boolean true
         )
         dict entry(
            string "Connected"
            variant boolean false
         )
         dict entry(
            string "RSSI"
            variant int16 -55
         )
      ]
   )
]])

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                instance.is_auto_connect_active = true

                -- Simulate disconnect event via calling _handleDisconnection directly
                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device",
                        paired = true,
                        connected = false,
                        rssi = -55,
                    },
                }
                instance.device_manager.loadDevices = function(self) end
                instance.device_manager.getDeviceByAddress = function(self, address)
                    for _, dev in ipairs(self.devices_cache) do
                        if dev.address == address then
                            return dev
                        end
                    end
                    return nil
                end
                instance:_handleDisconnection("00:11:22:33:44:55")

                -- Should have stored the current RSSI
                assert.are.equal(-55, instance.last_seen_rssi["00:11:22:33:44:55"])
            end)
        end)

        describe("startAutoConnectPolling", function()
            it("should not start if setting is disabled", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_connect_polling = false

                UIManager:_reset()
                instance:startAutoConnectPolling()

                assert.is_nil(instance.auto_connect_poll_task)
                assert.are.equal(0, #UIManager._scheduled_tasks)
            end)

            it("should not start if plugin is nil", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                instance.plugin = nil

                UIManager:_reset()
                instance:startAutoConnectPolling()

                assert.is_nil(instance.auto_connect_poll_task)
            end)

            it("should not start if device_manager is nil", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_connect_polling = true
                instance.device_manager = nil

                UIManager:_reset()
                instance:startAutoConnectPolling()

                assert.is_nil(instance.auto_connect_poll_task)
            end)

            it("should not start if already running", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_connect_polling = true

                instance.device_manager.devices_cache = {}
                instance.device_manager.loadDevices = function(self) end

                -- Simulate already running
                instance.is_discovery_active = true

                UIManager:_reset()
                clearExecutedCommands()
                instance:startAutoConnectPolling()

                -- Should not have started discovery again
                local commands = getExecutedCommands()
                local discovery_commands = 0

                for _, cmd in ipairs(commands) do
                    if cmd:match("StartDiscovery") then
                        discovery_commands = discovery_commands + 1
                    end
                end

                assert.are.equal(0, discovery_commands)
            end)

            it("should skip if device already connected and disable_after_connect is enabled", function()
                setMockPopenOutput("variant boolean true")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_connect_polling = true
                mock_plugin.settings.disable_auto_connect_after_connect = true

                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device",
                        connected = true,
                        paired = true,
                        trusted = true,
                    },
                }
                instance.device_manager.loadDevices = function(self) end

                UIManager:_reset()
                instance:startAutoConnectPolling()

                assert.is_nil(instance.auto_connect_poll_task)
                assert.are.equal(0, #UIManager._scheduled_tasks)
            end)

            it("should start discovery when starting polling", function()
                setMockPopenOutput("variant boolean true")
                setMockExecuteResult(0)

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_connect_polling = true

                instance.device_manager.devices_cache = {}
                instance.device_manager.loadDevices = function(self) end

                UIManager:_reset()
                clearExecutedCommands()
                instance:startAutoConnectPolling()

                local commands = getExecutedCommands()
                local found_start_discovery = false

                for _, cmd in ipairs(commands) do
                    if cmd:match("StartDiscovery") then
                        found_start_discovery = true
                        break
                    end
                end

                assert.is_true(found_start_discovery)
            end)
        end)

        describe("auto-connect menu items", function()
            it("should have auto-connect submenu under Settings", function()
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                local menu_items = {}
                instance:addToMainMenu(menu_items)

                assert.is_not_nil(menu_items.bluetooth)
                assert.is_not_nil(menu_items.bluetooth.sub_item_table)

                -- Find Settings submenu
                local settings_item = nil

                for _, item in ipairs(menu_items.bluetooth.sub_item_table) do
                    if item.text == "Settings" then
                        settings_item = item
                        break
                    end
                end

                assert.is_not_nil(settings_item)
                assert.is_not_nil(settings_item.sub_item_table)

                -- Find Auto-connect submenu
                local auto_connect_item = nil

                for _, item in ipairs(settings_item.sub_item_table) do
                    if item.text == "Auto-connect" then
                        auto_connect_item = item
                        break
                    end
                end

                assert.is_not_nil(auto_connect_item)
                assert.is_not_nil(auto_connect_item.sub_item_table)
                assert.are.equal(2, #auto_connect_item.sub_item_table)
            end)

            it("should toggle enable_auto_connect_polling setting", function()
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_connect_polling = false

                local menu_items = {}
                instance:addToMainMenu(menu_items)

                -- Find the auto-connect enable item
                local settings_item = nil

                for _, item in ipairs(menu_items.bluetooth.sub_item_table) do
                    if item.text == "Settings" then
                        settings_item = item
                        break
                    end
                end

                local auto_connect_item = nil

                for _, item in ipairs(settings_item.sub_item_table) do
                    if item.text == "Auto-connect" then
                        auto_connect_item = item
                        break
                    end
                end

                local enable_item = auto_connect_item.sub_item_table[1]

                assert.is_false(enable_item.checked_func())

                -- Toggle it
                enable_item.callback()

                assert.is_true(mock_plugin.settings.enable_auto_connect_polling)
                assert.is_true(enable_item.checked_func())
            end)

            it("should toggle disable_auto_connect_after_connect setting", function()
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_connect_polling = true
                mock_plugin.settings.disable_auto_connect_after_connect = true

                local menu_items = {}
                instance:addToMainMenu(menu_items)

                -- Find the auto-connect stop after connect item
                local settings_item = nil

                for _, item in ipairs(menu_items.bluetooth.sub_item_table) do
                    if item.text == "Settings" then
                        settings_item = item
                        break
                    end
                end

                local auto_connect_item = nil

                for _, item in ipairs(settings_item.sub_item_table) do
                    if item.text == "Auto-connect" then
                        auto_connect_item = item
                        break
                    end
                end

                local stop_item = auto_connect_item.sub_item_table[2]

                assert.is_true(stop_item.checked_func())

                -- Toggle it
                stop_item.callback()

                assert.is_false(mock_plugin.settings.disable_auto_connect_after_connect)
                assert.is_false(stop_item.checked_func())
            end)
        end)

        describe("discovery state tracking", function()
            it("should set is_discovery_active when starting auto-connect polling", function()
                setMockPopenOutput("variant boolean true")
                setMockExecuteResult(0)

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_connect_polling = true

                instance.device_manager.devices_cache = {}
                instance.device_manager.loadDevices = function(self) end

                assert.is_false(instance.is_discovery_active)

                UIManager:_reset()
                instance:startAutoConnectPolling()

                assert.is_true(instance.is_discovery_active)
            end)

            it("should clear is_discovery_active when stopping auto-connect polling", function()
                setMockPopenOutput("variant boolean true")
                setMockExecuteResult(0)

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_connect_polling = true

                instance.device_manager.devices_cache = {}
                instance.device_manager.loadDevices = function(self) end

                UIManager:_reset()
                instance:startAutoConnectPolling()
                assert.is_true(instance.is_discovery_active)

                instance:stopAutoConnectPolling()

                assert.is_false(instance.is_discovery_active)
            end)

            it("should skip starting new scan when discovery is already active", function()
                setMockPopenOutput("variant boolean true")
                setMockExecuteResult(0)

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                instance.is_discovery_active = true

                local scan_called = false
                instance.device_manager.scanForDevices = function(self, duration, callback)
                    scan_called = true
                end

                instance:scanAndShowDevices()

                assert.is_false(scan_called)
            end)

            it("should start scan when discovery is not active", function()
                setMockPopenOutput("variant boolean true")
                setMockExecuteResult(0)

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                instance.is_discovery_active = false

                local scan_called = false
                instance.device_manager.scanForDevices = function(self, duration, callback)
                    scan_called = true
                end

                local show_discovered_called = false
                instance.showDiscoveredDevices = function(self)
                    show_discovered_called = true
                end

                instance:scanAndShowDevices()

                assert.is_true(scan_called)
                assert.is_false(show_discovered_called)
            end)
        end)

        describe("auto-resume after wake", function()
            it("should have auto-resume menu item with checked_func", function()
                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                local menu_items = {}

                instance:addToMainMenu(menu_items)

                local settings_menu = menu_items.bluetooth.sub_item_table[4]
                assert.are.equal("Settings", settings_menu.text)
                assert.is_not_nil(settings_menu.sub_item_table)

                local auto_resume_item = settings_menu.sub_item_table[1]
                assert.are.equal("Auto-resume after wake", auto_resume_item.text)
                assert.is_function(auto_resume_item.checked_func)
            end)

            it("should toggle auto-resume setting when menu item is clicked", function()
                local save_settings_calls = 0
                local test_plugin = {
                    settings = { enable_bluetooth_auto_resume = false },
                    saveSettings = function()
                        save_settings_calls = save_settings_calls + 1
                    end,
                }

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(test_plugin)
                local menu_items = {}

                instance:addToMainMenu(menu_items)

                local settings_menu = menu_items.bluetooth.sub_item_table[4]
                local auto_resume_item = settings_menu.sub_item_table[1]

                auto_resume_item.callback()

                assert.is_true(test_plugin.settings.enable_bluetooth_auto_resume)
                assert.are.equal(2, save_settings_calls)
            end)
        end)

        describe("onRssiPropertyChanged", function()
            it("should do nothing if RSSI is nil", function()
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Paired"
            variant boolean true
         )
         dict entry(
            string "Connected"
            variant boolean false
         )
      ]
   )
]])

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                local connect_called = false
                instance.device_manager.connectDeviceInBackground = function(self, device)
                    connect_called = true
                    return true
                end

                instance:onRssiPropertyChanged("00:11:22:33:44:55", { RSSI = nil })

                assert.is_false(connect_called)
            end)

            it("should do nothing if RSSI is -127 (out of range)", function()
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Paired"
            variant boolean true
         )
         dict entry(
            string "Connected"
            variant boolean false
         )
      ]
   )
]])

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                local connect_called = false
                instance.device_manager.connectDeviceInBackground = function(self, device)
                    connect_called = true
                    return true
                end

                instance:onRssiPropertyChanged("00:11:22:33:44:55", { RSSI = -127 })

                assert.is_false(connect_called)
            end)

            it("should do nothing if device is already connected", function()
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Paired"
            variant boolean true
         )
         dict entry(
            string "Connected"
            variant boolean true
         )
         dict entry(
            string "RSSI"
            variant int16 -50
         )
      ]
   )
]])

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                local connect_called = false
                instance.device_manager.connectDeviceInBackground = function(self, device)
                    connect_called = true
                    return true
                end

                instance:onRssiPropertyChanged("00:11:22:33:44:55", { RSSI = -50 })

                assert.is_false(connect_called)
            end)

            it("should do nothing if device is not paired", function()
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Paired"
            variant boolean false
         )
         dict entry(
            string "Connected"
            variant boolean false
         )
         dict entry(
            string "RSSI"
            variant int16 -50
         )
      ]
   )
]])

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                local connect_called = false
                instance.device_manager.connectDeviceInBackground = function(self, device)
                    connect_called = true
                    return true
                end

                instance:onRssiPropertyChanged("00:11:22:33:44:55", { RSSI = -50 })

                assert.is_false(connect_called)
            end)

            it("should connect to nearby paired device that is not connected", function()
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Name"
            variant string "Test Device"
         )
         dict entry(
            string "Paired"
            variant boolean true
         )
         dict entry(
            string "Connected"
            variant boolean false
         )
         dict entry(
            string "RSSI"
            variant int16 -50
         )
      ]
   )
]])

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                -- Need to add device to paired_devices for getDeviceByAddress to work
                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device",
                        paired = true,
                        connected = false,
                    },
                }
                instance.device_manager.loadDevices = function(self) end
                instance.device_manager.getDeviceByAddress = function(self, address)
                    for _, dev in ipairs(self.devices_cache) do
                        if dev.address == address then
                            return dev
                        end
                    end
                    return nil
                end

                -- Register device for auto-connect
                instance.is_auto_connect_active = true

                local connect_called = false
                local connect_address = nil
                local connect_show_notification = nil
                instance.connectToDevice = function(self, address, show_notification)
                    connect_called = true
                    connect_address = address
                    connect_show_notification = show_notification
                end

                instance:onRssiPropertyChanged("00:11:22:33:44:55", { RSSI = -50 })

                assert.is_true(connect_called)
                assert.are.equal("00:11:22:33:44:55", connect_address)
                assert.is_true(connect_show_notification)
            end)

            it("should not connect if RSSI has not changed from last seen value", function()
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Paired"
            variant boolean true
         )
         dict entry(
            string "Connected"
            variant boolean false
         )
         dict entry(
            string "RSSI"
            variant int16 -50
         )
      ]
   )
]])

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                -- Need to add device to paired_devices for getDeviceByAddress to work
                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device",
                        paired = true,
                        connected = false,
                    },
                }
                instance.device_manager.loadDevices = function(self) end
                instance.device_manager.getDeviceByAddress = function(self, address)
                    for _, dev in ipairs(self.devices_cache) do
                        if dev.address == address then
                            return dev
                        end
                    end
                    return nil
                end

                -- Register device for auto-connect
                instance.is_auto_connect_active = true

                local connect_count = 0
                instance.connectToDevice = function(self, address, show_notification)
                    connect_count = connect_count + 1
                end

                -- First RSSI change should trigger connection
                instance:onRssiPropertyChanged("00:11:22:33:44:55", { RSSI = -50 })
                assert.are.equal(1, connect_count)

                -- Same RSSI should not trigger another connection
                instance:onRssiPropertyChanged("00:11:22:33:44:55", { RSSI = -50 })
                assert.are.equal(1, connect_count)
            end)

            it("should connect if RSSI has changed from last seen value", function()
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Paired"
            variant boolean true
         )
         dict entry(
            string "Connected"
            variant boolean false
         )
         dict entry(
            string "RSSI"
            variant int16 -50
         )
      ]
   )
]])

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                -- Need to add device to paired_devices for getDeviceByAddress to work
                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device",
                        paired = true,
                        connected = false,
                    },
                }
                instance.device_manager.loadDevices = function(self) end
                instance.device_manager.getDeviceByAddress = function(self, address)
                    for _, dev in ipairs(self.devices_cache) do
                        if dev.address == address then
                            return dev
                        end
                    end
                    return nil
                end

                -- Register device for auto-connect
                instance.is_auto_connect_active = true

                local connect_count = 0
                instance.connectToDevice = function(self, address, show_notification)
                    connect_count = connect_count + 1
                end

                -- First RSSI change
                instance:onRssiPropertyChanged("00:11:22:33:44:55", { RSSI = -50 })
                assert.are.equal(1, connect_count)

                -- Different RSSI should trigger another connection
                instance:onRssiPropertyChanged("00:11:22:33:44:55", { RSSI = -45 })
                assert.are.equal(2, connect_count)
            end)

            it("should reset is_startup_auto_connect flag", function()
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Paired"
            variant boolean true
         )
         dict entry(
            string "Connected"
            variant boolean false
         )
         dict entry(
            string "RSSI"
            variant int16 -50
         )
      ]
   )
]])

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                instance.is_startup_auto_connect = true

                -- Register device for auto-connect
                instance.is_auto_connect_active = true

                instance.device_manager.connectDeviceInBackground = function(self, device)
                    return true
                end

                instance:onRssiPropertyChanged("00:11:22:33:44:55", { RSSI = -50 })

                assert.is_false(instance.is_startup_auto_connect)
            end)

            it("should clear last seen RSSI when device connects", function()
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Connected"
            variant boolean true
         )
      ]
   )
]])

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)

                -- Set a last seen RSSI
                instance.last_seen_rssi["00:11:22:33:44:55"] = -50

                -- Mock device
                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        connected = true,
                    },
                }
                instance.device_manager.loadDevices = function(self) end
                instance.device_manager.getDeviceByAddress = function(self, address)
                    return self.devices_cache[1]
                end

                instance.input_handler.openIsolatedInputDevice = function(self, device)
                    return true
                end

                instance.is_auto_detection_active = true
                instance:onConnectedPropertyChanged("00:11:22:33:44:55", true)

                -- Last seen RSSI should be cleared
                assert.is_nil(instance.last_seen_rssi["00:11:22:33:44:55"])
            end)

            it("should clear last seen RSSI when auto-connect is stopped", function()
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Paired"
            variant boolean true
         )
      ]
   )
]])

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_connect_polling = true

                instance:startAutoConnectPolling()
                instance.last_seen_rssi["00:11:22:33:44:55"] = -50

                instance:stopAutoConnectPolling()

                -- Last seen RSSI should be cleared
                assert.is_nil(instance.last_seen_rssi["00:11:22:33:44:55"])
            end)

            it("should not attempt reconnection when RSSI is same as disconnect value", function()
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Paired"
            variant boolean true
         )
         dict entry(
            string "Connected"
            variant boolean false
         )
         dict entry(
            string "RSSI"
            variant int16 -55
         )
      ]
   )
]])

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                instance.is_auto_connect_active = true

                -- Simulate disconnect event (stores RSSI -55) by calling _handleDisconnection directly
                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device",
                        paired = true,
                        connected = false,
                        rssi = -55,
                    },
                }
                instance.device_manager.loadDevices = function(self) end
                instance.device_manager.getDeviceByAddress = function(self, address)
                    for _, dev in ipairs(self.devices_cache) do
                        if dev.address == address then
                            return dev
                        end
                    end
                    return nil
                end
                instance:_handleDisconnection("00:11:22:33:44:55")

                local connect_count = 0
                instance.connectToDevice = function(self, address, show_notification)
                    connect_count = connect_count + 1
                end

                -- Need to add device to paired_devices for getDeviceByAddress to work
                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device",
                        paired = true,
                        connected = false,
                    },
                }
                instance.device_manager.loadDevices = function(self) end
                instance.device_manager.getDeviceByAddress = function(self, address)
                    for _, dev in ipairs(self.devices_cache) do
                        if dev.address == address then
                            return dev
                        end
                    end
                    return nil
                end

                -- RSSI update with same value should not trigger connection
                instance:onRssiPropertyChanged("00:11:22:33:44:55", { RSSI = -55 })
                assert.are.equal(0, connect_count)
            end)

            it("should attempt reconnection when RSSI changes from disconnect value", function()
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Paired"
            variant boolean true
         )
         dict entry(
            string "Connected"
            variant boolean false
         )
         dict entry(
            string "RSSI"
            variant int16 -55
         )
      ]
   )
]])

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                instance.is_auto_connect_active = true

                -- Need to add device to paired_devices for getDeviceByAddress to work
                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device",
                        paired = true,
                        connected = false,
                    },
                }
                instance.device_manager.loadDevices = function(self) end
                instance.device_manager.getDeviceByAddress = function(self, address)
                    for _, dev in ipairs(self.devices_cache) do
                        if dev.address == address then
                            return dev
                        end
                    end
                    return nil
                end

                -- Simulate disconnect event (stores RSSI -55) by calling _handleDisconnection directly
                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device",
                        paired = true,
                        connected = false,
                        rssi = -55,
                    },
                }
                instance.device_manager.loadDevices = function(self) end
                instance.device_manager.getDeviceByAddress = function(self, address)
                    for _, dev in ipairs(self.devices_cache) do
                        if dev.address == address then
                            return dev
                        end
                    end
                    return nil
                end
                instance:_handleDisconnection("00:11:22:33:44:55")

                local connect_count = 0
                instance.connectToDevice = function(self, address, show_notification)
                    connect_count = connect_count + 1
                end

                -- RSSI update with different value should trigger connection
                instance:onRssiPropertyChanged("00:11:22:33:44:55", { RSSI = -50 })
                assert.are.equal(1, connect_count)
            end)
        end)

        describe("auto-connect via D-Bus monitoring", function()
            it("should register callbacks for paired devices", function()
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Paired"
            variant boolean true
         )
      ]
   )
]])

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_connect_polling = true

                UIManager:_reset()
                instance:startAutoConnectPolling()

                -- Should have registered callback for the paired device
                assert.is_true(instance.is_auto_connect_active)
                assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_connect"))
            end)

            it("should start discovery when auto-connect is enabled", function()
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Paired"
            variant boolean true
         )
      ]
   )
]])
                setMockExecuteResult(0)
                clearExecutedCommands()

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_connect_polling = true

                UIManager:_reset()
                instance:startAutoConnectPolling()

                -- Should have started discovery
                local commands = getExecutedCommands()
                local found_start_discovery = false

                for _, cmd in ipairs(commands) do
                    if cmd:match("StartDiscovery") then
                        found_start_discovery = true
                        break
                    end
                end

                assert.is_true(found_start_discovery)
                assert.is_true(instance.is_discovery_active)
            end)

            it("should stop auto-connect on device connect when setting enabled", function()
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Paired"
            variant boolean true
         )
      ]
   )
]])
                setMockExecuteResult(0)

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_connect_polling = true
                mock_plugin.settings.disable_auto_connect_after_connect = true

                UIManager:_reset()
                instance:startAutoConnectPolling()
                assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_connect"))

                clearExecutedCommands()

                -- Simulate device connected via onConnectedPropertyChanged
                -- Auto-connect is already active from startAutoConnectPolling

                -- Need to add device to paired_devices for getDeviceByAddress to work
                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device",
                        connected = true,
                    },
                }
                instance.device_manager.loadDevices = function(self) end
                instance.device_manager.getDeviceByAddress = function(self, address)
                    for _, dev in ipairs(self.devices_cache) do
                        if dev.address == address then
                            return dev
                        end
                    end
                    return nil
                end

                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Connected"
            variant boolean true
         )
      ]
   )
]])
                instance.input_handler.openIsolatedInputDevice = function(self, device)
                    return true
                end
                instance:onConnectedPropertyChanged("00:11:22:33:44:55", true)

                -- Auto-connect should have stopped
                assert.is_false(instance.dbus_monitor:hasCallback("kobobluetooth:auto_connect"))
                assert.is_false(instance.is_discovery_active)
            end)

            it("should not stop auto-connect on device connect when setting disabled", function()
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Paired"
            variant boolean true
         )
      ]
   )
]])
                setMockExecuteResult(0)

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_connect_polling = true
                mock_plugin.settings.disable_auto_connect_after_connect = false

                UIManager:_reset()
                instance:startAutoConnectPolling()
                assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_connect"))

                -- Simulate device connected via onConnectedPropertyChanged
                instance.is_auto_detection_active = true
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Connected"
            variant boolean true
         )
      ]
   )
]])
                instance.input_handler.openIsolatedInputDevice = function(self, device)
                    return true
                end
                instance:onConnectedPropertyChanged("00:11:22:33:44:55", true)

                -- Auto-connect should still be running
                assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_connect"))
            end)

            it("should restart auto-connect on device disconnect when last device disconnects", function()
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Paired"
            variant boolean true
         )
      ]
   )
]])
                setMockExecuteResult(0)

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_connect_polling = true
                mock_plugin.settings.disable_auto_connect_after_connect = true

                -- No callbacks registered initially (was stopped after connection)
                instance.is_auto_connect_active = false

                -- Mock loadDevices to return no connected devices
                instance.device_manager.loadDevices = function(self)
                    self.devices_cache = {
                        {
                            address = "00:11:22:33:44:55",
                            name = "Test Device",
                            connected = false,
                            paired = true,
                            trusted = true,
                        },
                    }
                end

                UIManager:_reset()

                -- Simulate device disconnected callback
                instance:onDeviceDisconnected({ address = "00:11:22:33:44:55", name = "Test Device" })

                -- Auto-connect should have restarted
                assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_connect"))
            end)

            it("should not restart auto-connect if another device still connected", function()
                setMockPopenOutput("variant boolean true")
                setMockExecuteResult(0)

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_connect_polling = true
                mock_plugin.settings.disable_auto_connect_after_connect = true

                instance.is_auto_connect_active = false

                -- Set devices_cache directly to have one still-connected device
                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device 1",
                        connected = false,
                        paired = true,
                        trusted = true,
                    },
                    {
                        address = "AA:BB:CC:DD:EE:FF",
                        name = "Test Device 2",
                        connected = true,
                        paired = true,
                        trusted = true,
                    },
                }

                UIManager:_reset()

                -- Simulate device disconnected callback
                instance:onDeviceDisconnected({ address = "00:11:22:33:44:55", name = "Test Device 1" })

                -- Auto-connect should NOT have restarted
                assert.is_false(instance.dbus_monitor:hasCallback("kobobluetooth:auto_connect"))
            end)

            it("should restart auto-connect on input device close when last device closes", function()
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Paired"
            variant boolean true
         )
      ]
   )
]])
                setMockExecuteResult(0)

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_connect_polling = true
                mock_plugin.settings.disable_auto_connect_after_connect = true

                instance.is_auto_connect_active = false

                -- No isolated readers remaining
                instance.input_handler.isolated_readers = {}

                instance.device_manager.loadDevices = function(self)
                    self.devices_cache = {
                        {
                            address = "00:11:22:33:44:55",
                            name = "Test Device",
                            connected = false,
                            paired = true,
                        },
                    }
                end

                UIManager:_reset()

                -- Simulate input device closed callback
                instance:onInputDeviceClosed("00:11:22:33:44:55", "/dev/input/event4")

                -- Auto-connect should have restarted
                assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_connect"))
            end)
        end)

        describe("auto-connect Bluetooth on/off integration", function()
            it("should start auto-connect monitoring when Bluetooth turned on", function()
                setMockExecuteResult(0)
                setMockPopenOutput("variant boolean false")

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_connect_polling = true

                instance.device_manager.devices_cache = {
                    {
                        address = "00:11:22:33:44:55",
                        name = "Test Device",
                        paired = true,
                    },
                }
                instance.device_manager.loadDevices = function(self) end

                UIManager:_reset()
                instance:turnBluetoothOn()

                -- Simulate Bluetooth becoming enabled
                setMockPopenOutput("variant boolean true")

                -- Execute scheduled tasks to complete async Bluetooth enable
                UIManager:executeScheduledTasks()

                assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_connect"))
            end)

            it("should stop auto-connect monitoring when Bluetooth turned off", function()
                setMockExecuteResult(0)
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Paired"
            variant boolean true
         )
      ]
   )
]])

                local instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                mock_plugin.settings.enable_auto_connect_polling = true
                instance.bluetooth_standby_prevented = true

                -- Start monitoring first
                UIManager:_reset()
                instance:startAutoConnectPolling()
                assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_connect"))

                clearExecutedCommands()

                instance:turnBluetoothOff()

                assert.is_false(instance.dbus_monitor:hasCallback("kobobluetooth:auto_connect"))
            end)

            it("should start auto-connect monitoring on startup if Bluetooth already enabled", function()
                setMockPopenOutput([[
object path "/org/bluez/hci0/dev_00_11_22_33_44_55"
   dict entry(
      string "org.bluez.Device1"
      array [
         dict entry(
            string "Address"
            variant string "00:11:22:33:44:55"
         )
         dict entry(
            string "Paired"
            variant boolean true
         )
      ]
   )
]])
                setMockExecuteResult(0)

                mock_plugin.settings.enable_auto_connect_polling = true

                local instance = KoboBluetooth.create()

                UIManager:_reset()
                instance:initWithPlugin(mock_plugin)

                assert.is_true(instance.dbus_monitor:hasCallback("kobobluetooth:auto_connect"))
            end)
        end)

        describe("Footer Content Generation", function()
            local instance
            local mock_ui

            before_each(function()
                -- Setup device as MTK Kobo
                Device._isMTK = true
                Device.isKobo = function()
                    return true
                end
                setMockPopenOutput("variant boolean true")

                mock_plugin = {
                    settings = {
                        show_bluetooth_footer_status = nil, -- Will test with different values
                    },
                    saveSettings = function() end,
                }

                mock_ui = {
                    view = {
                        footer = {
                            settings = {
                                item_prefix = "icons",
                                all_at_once = true,
                                hide_empty_generators = false,
                            },
                        },
                    },
                }

                instance = KoboBluetooth.create()
                instance:initWithPlugin(mock_plugin)
                instance.ui = mock_ui
            end)

            describe("setupFooterContentGenerator", function()
                it("should create a footer content function", function()
                    assert.is_not_nil(instance.additional_footer_content_func)
                    assert.is_function(instance.additional_footer_content_func)
                end)
            end)

            describe("footer content with setting enabled (nil defaults to true)", function()
                before_each(function()
                    mock_plugin.settings.show_bluetooth_footer_status = nil
                    instance:setupFooterContentGenerator()
                end)

                it("should show Bluetooth on icon in icons mode when enabled", function()
                    setMockPopenOutput("variant boolean true")
                    local content = instance.additional_footer_content_func()
                    assert.is_string(content)
                    assert.is_not.equal("", content)
                    -- Should contain the Bluetooth on symbol (UTF-8 encoded)
                end)

                it("should show Bluetooth off icon in icons mode when disabled", function()
                    setMockPopenOutput("variant boolean false")
                    local content = instance.additional_footer_content_func()
                    assert.is_string(content)
                    assert.is_not.equal("", content)
                    -- Should contain the Bluetooth off symbol (UTF-8 encoded)
                end)

                it("should show text in text mode when enabled", function()
                    setMockPopenOutput("variant boolean true")
                    mock_ui.view.footer.settings.item_prefix = "text"
                    local content = instance.additional_footer_content_func()
                    assert.are.equal("BT: On", content)
                end)

                it("should show text in text mode when disabled", function()
                    setMockPopenOutput("variant boolean false")
                    mock_ui.view.footer.settings.item_prefix = "text"
                    local content = instance.additional_footer_content_func()
                    assert.are.equal("BT: Off", content)
                end)

                it("should show compact icon when enabled", function()
                    setMockPopenOutput("variant boolean true")
                    mock_ui.view.footer.settings.item_prefix = "compact_items"
                    local content = instance.additional_footer_content_func()
                    assert.is_string(content)
                    assert.is_not.equal("", content)
                    -- Should contain the Bluetooth on symbol
                end)

                it("should show compact icon when disabled", function()
                    setMockPopenOutput("variant boolean false")
                    mock_ui.view.footer.settings.item_prefix = "compact_items"
                    local content = instance.additional_footer_content_func()
                    assert.is_string(content)
                    assert.is_not.equal("", content)
                    -- Should contain the Bluetooth off symbol
                end)

                it("should hide when Bluetooth is off and hide_empty_generators is true", function()
                    setMockPopenOutput("variant boolean false")
                    mock_ui.view.footer.settings.hide_empty_generators = true
                    local content = instance.additional_footer_content_func()
                    assert.are.equal("", content)
                end)

                it("should not hide when Bluetooth is on and hide_empty_generators is true", function()
                    setMockPopenOutput("variant boolean true")
                    mock_ui.view.footer.settings.hide_empty_generators = true
                    local content = instance.additional_footer_content_func()
                    assert.is_string(content)
                    assert.is_not.equal("", content)
                end)
            end)

            describe("footer content with setting explicitly enabled (true)", function()
                before_each(function()
                    mock_plugin.settings.show_bluetooth_footer_status = true
                    instance:setupFooterContentGenerator()
                end)

                it("should show Bluetooth status when setting is true", function()
                    setMockPopenOutput("variant boolean true")
                    local content = instance.additional_footer_content_func()
                    assert.is_not.equal("", content)
                end)
            end)

            describe("footer content with setting disabled (false)", function()
                before_each(function()
                    mock_plugin.settings.show_bluetooth_footer_status = false
                    instance:setupFooterContentGenerator()
                end)

                it("should return empty string when setting is false", function()
                    setMockPopenOutput("variant boolean true")
                    local content = instance.additional_footer_content_func()
                    assert.are.equal("", content)
                end)

                it("should return empty string when disabled and Bluetooth is on", function()
                    setMockPopenOutput("variant boolean true")
                    local content = instance.additional_footer_content_func()
                    assert.are.equal("", content)
                end)

                it("should return empty string when disabled and Bluetooth is off", function()
                    setMockPopenOutput("variant boolean false")
                    local content = instance.additional_footer_content_func()
                    assert.are.equal("", content)
                end)
            end)

            describe("footer content when UI is nil", function()
                it("should return empty string when UI is nil", function()
                    instance.ui = nil
                    local content = instance.additional_footer_content_func()
                    assert.are.equal("", content)
                end)

                it("should return empty string when UI.view is nil", function()
                    instance.ui = {}
                    local content = instance.additional_footer_content_func()
                    assert.are.equal("", content)
                end)

                it("should return empty string when UI.view.footer is nil", function()
                    instance.ui = { view = {} }
                    local content = instance.additional_footer_content_func()
                    assert.are.equal("", content)
                end)
            end)
        end)
    end)
end)
