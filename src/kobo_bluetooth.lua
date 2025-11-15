---
-- Bluetooth control module for MTK-based Kobo devices.
-- Provides on/off toggle functionality, device scanning using D-Bus commands
-- and prevents standby mode when Bluetooth is active.
--
-- This is based on the investigation done in docs/dev/investigations/bluetooth/

local BluetoothKeyBindings = require("src/bluetooth_keybindings")
local DbusAdapter = require("src/lib/bluetooth/dbus_adapter")
local Device = require("device")
local DeviceManager = require("src/lib/bluetooth/device_manager")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDeviceHandler = require("src/lib/bluetooth/input_device_handler")
local UIManager = require("ui/uimanager")
local UiMenus = require("src/lib/bluetooth/ui_menus")
local _ = require("gettext")
local logger = require("logger")

local KoboBluetooth = InputContainer:extend({
    name = "kobo_bluetooth",
    bluetooth_standby_prevented = false,
    key_bindings = nil,
    settings = nil,
    device_manager = nil,
    input_handler = nil,
    plugin = nil,
    dispatcher_registered_devices = {},
})

---
-- Checks if Bluetooth control is supported on this device.
-- @return boolean True if device is MTK-based Kobo, false otherwise.
function KoboBluetooth:isDeviceSupported()
    return Device:isKobo() and Device.isMTK
end

---
-- Initializes Bluetooth control module.
-- Logs appropriate message based on device support.
-- @param plugin table Plugin instance with settings and saveSettings method
function KoboBluetooth:init(plugin)
    if not self:isDeviceSupported() then
        logger.warn("KoboBluetooth: Not on MTK Kobo device, Bluetooth control disabled")

        return
    end

    logger.info("KoboBluetooth: Initialized on MTK device")

    self.device_manager = DeviceManager:new()
    self.input_handler = InputDeviceHandler:new()
    self.plugin = plugin

    if plugin and plugin.settings then
        self.key_bindings = BluetoothKeyBindings:new({
            settings = plugin.settings,
        })
        self.key_bindings:init(function()
            plugin:saveSettings()
        end, self)

        self:mergeKeyEvents()
    end

    if self:isBluetoothEnabled() and not self.bluetooth_standby_prevented then
        logger.dbg("KoboBluetooth: Bluetooth enabled on startup, preventing standby.")

        UIManager:preventStandby()
        self.bluetooth_standby_prevented = true

        self.device_manager:loadPairedDevices()
        self.input_handler:autoOpenConnectedDevices(self.device_manager:getPairedDevices())
    end
end

---
-- Merges BluetoothKeyBindings key_events into this InputContainer.
-- This allows the Bluetooth key events to be handled by KOReader's input system.
function KoboBluetooth:mergeKeyEvents()
    if not self.key_bindings then
        return
    end

    local count = 0

    for event_name, event_def in pairs(self.key_bindings.key_events) do
        self.key_events[event_name] = event_def
        count = count + 1

        local handler_name = "on" .. event_def.event

        if self.key_bindings[handler_name] and not self[handler_name] then
            self[handler_name] = function(...)
                return self.key_bindings[handler_name](self.key_bindings, ...)
            end
        end
    end

    logger.dbg("KoboBluetooth: Merged", count, "key events from BluetoothKeyBindings")
end

---
-- Checks if Bluetooth is currently enabled.
-- @return boolean True if Bluetooth is powered on, false otherwise.
function KoboBluetooth:isBluetoothEnabled()
    if not self:isDeviceSupported() then
        return false
    end

    return DbusAdapter.isEnabled()
end

---
-- Emits BluetoothStateChanged event.
-- @param state boolean True if Bluetooth is ON, false if OFF.
function KoboBluetooth:emitBluetoothStateChangedEvent(state)
    UIManager:sendEvent(Event:new("BluetoothStateChanged", { state = state }))
end

---
-- Turns Bluetooth on via D-Bus commands and prevents standby.
function KoboBluetooth:turnBluetoothOn()
    if not self:isDeviceSupported() then
        logger.warn("KoboBluetooth: Device not supported, cannot turn Bluetooth ON")

        UIManager:show(InfoMessage:new({
            text = _("Bluetooth not supported on this device"),
            timeout = 3,
        }))

        return
    end

    if self:isBluetoothEnabled() then
        logger.warn("KoboBluetooth: turn on Bluetooth was called while already on.")

        return
    end

    logger.info("KoboBluetooth: Turning Bluetooth ON")

    if not DbusAdapter.turnOn() then
        logger.warn("KoboBluetooth: Failed to turn ON")

        UIManager:show(InfoMessage:new({
            text = _("Failed to enable Bluetooth. Check device logs."),
            timeout = 3,
        }))

        return
    end

    UIManager:preventStandby()
    self.bluetooth_standby_prevented = true

    logger.info("KoboBluetooth: Turned ON, standby prevented")

    UIManager:show(InfoMessage:new({
        text = _("Bluetooth enabled"),
        timeout = 2,
    }))

    self:emitBluetoothStateChangedEvent(true)

    self.device_manager:loadPairedDevices()

    -- Sync paired devices to plugin settings when Bluetooth is turned on
    self:syncPairedDevicesToSettings()
end

---
-- Turns Bluetooth off via D-Bus commands and allows standby.
--
-- @param show_popup boolean The menu widget to refresh
function KoboBluetooth:turnBluetoothOff(show_popup)
    if show_popup == nil then
        show_popup = true
    end

    if not self:isDeviceSupported() then
        logger.warn("KoboBluetooth: Device not supported, cannot turn Bluetooth OFF")

        if show_popup then
            UIManager:show(InfoMessage:new({
                text = _("Bluetooth not supported on this device"),
                timeout = 3,
            }))
        end

        return
    end

    if not self:isBluetoothEnabled() then
        logger.warn("KoboBluetooth: turn off Bluetooth was called while already off.")

        return
    end

    logger.info("KoboBluetooth: Turning Bluetooth OFF")

    if not DbusAdapter.turnOff() then
        logger.warn("KoboBluetooth: Failed to turn OFF, leaving standby prevented")

        if show_popup then
            UIManager:show(InfoMessage:new({
                text = _("Failed to disable Bluetooth. Check device logs."),
                timeout = 3,
            }))
        end

        return
    end

    if self.bluetooth_standby_prevented then
        UIManager:allowStandby()
        self.bluetooth_standby_prevented = false
    end

    logger.info("KoboBluetooth: Turned OFF, standby allowed")

    if show_popup then
        UIManager:show(InfoMessage:new({
            text = _("Bluetooth disabled"),
            timeout = 2,
        }))
    end

    self:emitBluetoothStateChangedEvent(false)
end

---
-- Initiates a Bluetooth device scan and shows results.
function KoboBluetooth:scanAndShowDevices()
    if not self:isDeviceSupported() then
        return
    end

    if not self:isBluetoothEnabled() then
        UIManager:show(InfoMessage:new({
            text = _("Please enable Bluetooth first"),
            timeout = 3,
        }))

        return
    end

    local devices = self.device_manager:scanForDevices()

    if devices then
        UiMenus.showScanResults(devices, function(device_info)
            self.device_manager:toggleConnection(device_info, function(dev)
                self.input_handler:openInputDevice(dev, true, true)
            end, function(dev)
                self.input_handler:closeInputDevice(dev)
            end)

            -- Sync paired devices to plugin settings after connecting/pairing
            self:syncPairedDevicesToSettings()

            -- Register the newly paired device with dispatcher
            self:registerDeviceWithDispatcher(device_info)
        end)
    end
end

---
-- Shows a menu of paired devices.
function KoboBluetooth:showPairedDevices()
    if not self:isDeviceSupported() then
        return
    end

    if not self:isBluetoothEnabled() then
        UIManager:show(InfoMessage:new({
            text = _("Please enable Bluetooth first"),
            timeout = 2,
        }))

        return
    end

    self.device_manager:loadPairedDevices()

    -- Sync paired devices to plugin settings when viewing paired devices
    self:syncPairedDevicesToSettings()

    self.paired_devices_menu = UiMenus.showPairedDevices(self.device_manager:getPairedDevices(), function(device_info)
        self:showDeviceOptionsMenu(device_info)
    end, function(device_info)
        if self.key_bindings then
            self.key_bindings:showConfigMenu(device_info)
        end
    end, function(menu_widget)
        self:refreshPairedDevicesMenu(menu_widget)
    end)
end

---
-- Connects to a Bluetooth device by address.
-- @param address string The Bluetooth address of the device to connect to
-- @return boolean True if connection was initiated, false otherwise
function KoboBluetooth:connectToDevice(address)
    if not self:isDeviceSupported() then
        logger.warn("KoboBluetooth: Device not supported, cannot connect")
        return false
    end

    if not address then
        logger.warn("KoboBluetooth: No address provided")
        return false
    end

    if not self.device_manager then
        logger.warn("KoboBluetooth: Device manager not available")
        return false
    end

    -- Turn on Bluetooth if disabled
    if not self:isBluetoothEnabled() then
        logger.info("KoboBluetooth: Bluetooth disabled, turning on for connection")
        self:turnBluetoothOn()

        if not self:isBluetoothEnabled() then
            logger.warn("KoboBluetooth: Failed to turn on Bluetooth")
            return false
        end
    end

    -- Load paired devices
    self.device_manager:loadPairedDevices()
    local paired_devices = self.device_manager:getPairedDevices()

    -- Find device in paired list
    local device_info = nil
    for _, device in ipairs(paired_devices) do
        if device.address == address then
            device_info = device
            break
        end
    end

    if not device_info then
        logger.warn("KoboBluetooth: Device not found in paired list:", address)
        UIManager:show(InfoMessage:new({
            text = _("Device not found in paired list"),
            timeout = 3,
        }))
        return false
    end

    -- Check if already connected
    if device_info.connected then
        logger.warn("KoboBluetooth: Device already connected:", address)
        UIManager:show(InfoMessage:new({
            text = _("Device already connected"),
            timeout = 3,
        }))
        return false
    end

    -- Connect to device
    logger.info("KoboBluetooth: Connecting to device:", address)
    self.device_manager:connectDevice(device_info, function(dev)
        self.input_handler:openInputDevice(dev, true, true)
    end)

    return true
end

---
-- Refreshes the paired devices menu.
-- @param menu_widget table The menu widget to refresh
function KoboBluetooth:refreshPairedDevicesMenu(menu_widget)
    self.device_manager:loadPairedDevices()

    local paired_devices = self.device_manager:getPairedDevices()
    local new_items = {}

    for idx, device in ipairs(paired_devices) do -- luacheck: ignore idx
        local status_text = device.connected and _("Connected") or _("Not connected")

        table.insert(new_items, {
            text = device.name ~= "" and device.name or device.address,
            mandatory = status_text,
            device_info = device,
        })
    end

    menu_widget.item_table = new_items
    menu_widget:updateItems(1)
end

---
-- Shows device options menu.
-- @param device_info table Device information
function KoboBluetooth:showDeviceOptionsMenu(device_info)
    local options = {
        show_connect = not device_info.connected,
        show_disconnect = device_info.connected,
        show_configure_keys = self.key_bindings ~= nil,
        on_connect = function()
            self.device_manager:connectDevice(device_info, function(dev)
                self.input_handler:openInputDevice(dev, true, true)
            end)
        end,
        on_disconnect = function()
            self.device_manager:disconnectDevice(device_info, function(dev)
                self.input_handler:closeInputDevice(dev)
            end)
        end,
        on_configure_keys = function()
            if self.key_bindings then
                self.key_bindings:showConfigMenu(device_info)
            end
        end,
    }

    local on_action_complete = function()
        if self.paired_devices_menu then
            self:refreshPairedDevicesMenu(self.paired_devices_menu)
        end

        if self.device_options_menu then
            self:refreshDeviceOptionsMenu(self.device_options_menu, device_info)
        end
    end

    self.device_options_menu = UiMenus.showDeviceOptionsMenu(device_info, options, on_action_complete)
end

---
-- Refreshes the device options menu.
-- @param menu_widget table The menu widget to refresh
-- @param device_info table Device information to refresh
function KoboBluetooth:refreshDeviceOptionsMenu(menu_widget, device_info)
    self.device_manager:loadPairedDevices()

    local paired_devices = self.device_manager:getPairedDevices()
    local updated_device = nil

    for _, device in ipairs(paired_devices) do
        if device.address == device_info.address then
            updated_device = device

            break
        end
    end

    if not updated_device then
        return
    end

    local new_items = {}

    if updated_device.connected then
        table.insert(new_items, {
            text = _("Disconnect"),
            callback = function()
                self.device_manager:disconnectDevice(updated_device, function(dev)
                    self.input_handler:closeInputDevice(dev)
                end)

                if self.paired_devices_menu then
                    self:refreshPairedDevicesMenu(self.paired_devices_menu)
                end

                if self.device_options_menu then
                    self:refreshDeviceOptionsMenu(self.device_options_menu, updated_device)
                end
            end,
        })
    end

    if not updated_device.connected then
        table.insert(new_items, {
            text = _("Connect"),
            callback = function()
                self.device_manager:connectDevice(updated_device, function(dev)
                    self.input_handler:openInputDevice(dev, true, true)
                end)

                if self.paired_devices_menu then
                    self:refreshPairedDevicesMenu(self.paired_devices_menu)
                end

                if self.device_options_menu then
                    self:refreshDeviceOptionsMenu(self.device_options_menu, updated_device)
                end
            end,
        })
    end

    if self.key_bindings then
        table.insert(new_items, {
            text = _("Configure key bindings"),
            callback = function()
                self.key_bindings:showConfigMenu(updated_device)
            end,
        })
    end

    menu_widget.item_table = new_items
    menu_widget:updateItems(1)
end

---
-- Registers Bluetooth submenu under Network settings.
-- Only adds menu if device is supported.
-- @param menu_items table Menu items table to populate.
function KoboBluetooth:addToMainMenu(menu_items)
    if not self:isDeviceSupported() then
        return
    end

    menu_items.bluetooth = {
        text = _("Bluetooth"),
        sorting_hint = "network",
        sub_item_table = {
            {
                text = _("Enable/Disable"),
                checked_func = function()
                    return self:isBluetoothEnabled()
                end,
                callback = function()
                    if self:isBluetoothEnabled() then
                        self:turnBluetoothOff()
                    else
                        self:turnBluetoothOn()
                    end
                end,
            },
            {
                text = _("Scan for devices"),
                enabled_func = function()
                    return self:isBluetoothEnabled()
                end,
                callback = function()
                    self:scanAndShowDevices()
                end,
            },
            {
                text = _("Paired devices"),
                enabled_func = function()
                    return self:isBluetoothEnabled()
                end,
                callback = function()
                    self:showPairedDevices()
                end,
            },
        },
    }
end

---
-- Syncs paired devices from Bluetooth to plugin settings.
-- Should be called whenever paired devices are loaded from Bluetooth.
function KoboBluetooth:syncPairedDevicesToSettings()
    if not self:isDeviceSupported() then
        return
    end

    if not self:isBluetoothEnabled() then
        logger.dbg("KoboBluetooth: Bluetooth not enabled, cannot sync paired devices")

        return
    end

    if not self.plugin or not self.device_manager then
        return
    end

    self.device_manager:loadPairedDevices()

    local paired_devices = self.device_manager:getPairedDevices()

    -- Store simplified device info in settings (address and name only)
    self.plugin.settings.paired_devices = {}

    for _, device in ipairs(paired_devices) do
        table.insert(self.plugin.settings.paired_devices, {
            address = device.address,
            name = device.name,
        })
    end

    self.plugin:saveSettings()

    logger.info("KoboBluetooth: Synced", #self.plugin.settings.paired_devices, "paired devices to settings")
end

---
-- Registers a single Bluetooth device with the dispatcher.
-- @param device table Device info with address and name fields
function KoboBluetooth:registerDeviceWithDispatcher(device)
    if not self.plugin or not device then
        return
    end

    local Dispatcher = require("dispatcher")
    local T = require("ffi/util").template

    local device_name = device.name ~= "" and device.name or device.address
    local action_id = "bluetooth_connect_" .. device.address:gsub(":", "_")

    -- Skip if already registered
    if self.dispatcher_registered_devices[action_id] then
        logger.dbg("KoboBluetooth: Device already registered:", action_id)
        return
    end

    Dispatcher:registerAction(action_id, {
        category = "none",
        event = "ConnectToBluetoothDevice",
        arg = device.address,
        title = T(_("Connect to %1"), device_name),
        device = true,
    })

    self.dispatcher_registered_devices[action_id] = true

    logger.dbg("KoboBluetooth: Registered dispatcher action:", action_id, "for device:", device_name)
end

---
-- Registers all paired devices with the dispatcher.
-- Uses stored settings so it works even when Bluetooth is off.
function KoboBluetooth:registerPairedDevicesWithDispatcher()
    if not self:isDeviceSupported() then
        return
    end

    if not self.plugin then
        return
    end

    -- Try to sync from Bluetooth if it's enabled
    if self:isBluetoothEnabled() then
        self:syncPairedDevicesToSettings()
    end

    local paired_devices = self.plugin.settings.paired_devices

    if not paired_devices or #paired_devices == 0 then
        logger.dbg("KoboBluetooth: No paired devices in settings, skipping dispatcher registration")

        return
    end

    logger.info("KoboBluetooth: Registering dispatcher actions for", #paired_devices, "paired devices")

    for _, device in ipairs(paired_devices) do
        self:registerDeviceWithDispatcher(device)
    end
end

return KoboBluetooth
