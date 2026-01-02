---
--- Bluetooth control module for MTK-based Kobo devices.
--- Provides on/off toggle functionality, device scanning using D-Bus commands
--- and prevents standby mode when Bluetooth is active.
---
--- This is based on the investigation done in docs/dev/investigations/bluetooth/

local BluetoothKeyBindings = require("src/bluetooth_keybindings")
local ConfirmBox = require("ui/widget/confirmbox")
local DbusAdapter = require("src/lib/bluetooth/dbus_adapter")
local DbusMonitor = require("src/lib/bluetooth/dbus_monitor")
local Device = require("device")
local DeviceManager = require("src/lib/bluetooth/device_manager")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDeviceHandler = require("src/lib/bluetooth/input_device_handler")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local UiMenus = require("src/lib/bluetooth/ui_menus")
local _ = require("gettext")
local ffiutil = require("ffi/util")
local logger = require("logger")

---
--- D-Bus callback priority constants.
--- Lower priority values are executed first.
--- These priorities control the execution order of D-Bus event handlers.
local PRIORITY_CACHE_SYNC = 10
local PRIORITY_USER_ACTIONS = 50

local KoboBluetooth = InputContainer:extend({
    name = "kobo_bluetooth",
    bluetooth_standby_prevented = false,
    bluetooth_was_enabled_before_suspend = false,
    key_bindings = nil,
    settings = nil,
    device_manager = nil,
    input_handler = nil,
    plugin = nil,
    dispatcher_registered_devices = {},
    additional_footer_content_func = nil,
    ui = nil,
    auto_detection_poll_task = nil,
    auto_detection_poll_interval = 1,
    last_seen_rssi = {},
    is_startup_auto_connect = true,
    is_discovery_active = false,
    is_auto_detection_active = false,
    is_auto_connect_active = false,
})

---
--- Checks if Bluetooth control is supported on this device.
--- @return boolean True if device is MTK-based Kobo, false otherwise.
function KoboBluetooth:isDeviceSupported()
    return Device:isKobo() and Device.isMTK()
end

---
--- Basic initialization required by the Widget framework.
--- This method is called automatically by Widget:new() before the plugin instance is available.
--- It is intentionally left empty because full initialization (with plugin access) happens in initWithPlugin().
function KoboBluetooth:init() end

---
--- Performs cleanup of all Bluetooth-related resources.
--- This includes stopping monitoring, closing input devices, and stopping polling.
--- Safe to call multiple times - includes nil guards for all resources.
--- @param broadcast_refresh boolean Whether to broadcast a UI refresh event (default: true)
function KoboBluetooth:_cleanup(broadcast_refresh)
    logger.dbg("KoboBluetooth: _cleanup")

    -- Stop key bindings polling
    if self.key_bindings then
        self.key_bindings:stopPolling()
    end

    -- Stop auto-detection and auto-connect
    self:stopAutoDetectionPolling(broadcast_refresh)
    self:stopAutoConnectPolling(broadcast_refresh)

    -- Stop DBus monitoring
    if self.dbus_monitor then
        self.dbus_monitor:stopMonitoring()
        self.dbus_monitor:unregisterCallback("kobobluetooth:on_disconnect")
    end

    -- Close all input devices
    if self.input_handler then
        self.input_handler:closeAllIsolatedInputDevices()
    end

    logger.dbg("KoboBluetooth: _cleanup completed")
end

---
--- Initializes Bluetooth control module with plugin instance.
--- Logs appropriate message based on device support.
--- @param plugin table Plugin instance with settings and saveSettings method
function KoboBluetooth:initWithPlugin(plugin)
    if not self:isDeviceSupported() then
        logger.warn("KoboBluetooth: Not on MTK Kobo device, Bluetooth control disabled")

        return
    end

    logger.info("KoboBluetooth: Initialized on MTK device")

    self:_cleanup(false)

    self.ui = plugin.ui
    self.device_manager = DeviceManager:new()
    self.input_handler = InputDeviceHandler:new()
    self.dbus_monitor = DbusMonitor:new()
    self.plugin = plugin

    self.dispatcher_registered_devices = {}
    self.last_seen_rssi = {}
    self.is_auto_detection_active = false
    self.is_auto_connect_active = false

    self.device_manager:registerDeviceConnectCallback(function(device)
        self:onDeviceConnected(device)
    end)
    self.device_manager:registerDeviceDisconnectCallback(function(device)
        self:onDeviceDisconnected(device)
    end)

    self.input_handler:registerDeviceCloseCallback(function(device_address, device_path)
        self:onInputDeviceClosed(device_address, device_path)
    end)

    logger.dbg("KoboBluetooth: plugin:", plugin and "available" or "nil")
    logger.dbg("KoboBluetooth: plugin.settings:", plugin and plugin.settings and "available" or "nil")

    if plugin and plugin.settings then
        logger.info("KoboBluetooth: Creating key_bindings with settings")
        self.key_bindings = BluetoothKeyBindings:new({
            settings = plugin.settings,
        })
        self.key_bindings:setup(function()
            plugin:saveSettings()
        end, self.input_handler)
        logger.info("KoboBluetooth: key_bindings setup with input_handler")
    else
        logger.warn("KoboBluetooth: Cannot create key_bindings - plugin or settings not available")
    end

    self:setupFooterContentGenerator()
    if self:isBluetoothEnabled() and not self.bluetooth_standby_prevented then
        logger.dbg("KoboBluetooth: Bluetooth enabled on startup, preventing standby.")

        UIManager:preventStandby()
        self.bluetooth_standby_prevented = true
    end

    self:_startBluetoothProcesses()
    self.input_handler:autoOpenConnectedDevices(self.device_manager:getDevices())
end

---
--- Checks if Bluetooth is currently enabled.
--- @return boolean True if Bluetooth is powered on, false otherwise.
function KoboBluetooth:isBluetoothEnabled()
    if not self:isDeviceSupported() then
        return false
    end

    return DbusAdapter.isEnabled()
end

---
--- Gets paired devices from the device manager.
--- Filters all cached devices to return only paired ones.
--- @return table Array of paired device information
function KoboBluetooth:_getPairedDevices()
    local all_devices = self.device_manager:getDevices()
    local paired_devices = {}

    for _, device in ipairs(all_devices) do
        if device.paired then
            table.insert(paired_devices, device)
        end
    end

    return paired_devices
end

---
--- Checks if footer status display is enabled.
--- @return boolean True if footer status should be shown (defaults to true)
function KoboBluetooth:isFooterStatusEnabled()
    if not self.plugin or not self.plugin.settings then
        return true
    end

    local show_footer_status = self.plugin.settings.show_bluetooth_footer_status

    if show_footer_status == nil then
        return true
    end

    return show_footer_status
end

---
--- Checks if auto-detection is currently active.
--- @return boolean True if auto-detection is running and monitoring devices
function KoboBluetooth:isAutoDetectionActive()
    if not self:isBluetoothEnabled() then
        return false
    end

    if not self.plugin or not self.plugin.settings.enable_auto_detection_polling then
        return false
    end

    return self.is_auto_detection_active
end

---
--- Checks if auto-connect is currently active.
--- @return boolean True if auto-connect is running and monitoring devices
function KoboBluetooth:isAutoConnectActive()
    if not self:isBluetoothEnabled() then
        return false
    end

    if not self.plugin or not self.plugin.settings.enable_auto_connect_polling then
        return false
    end

    return self.is_auto_connect_active
end

---
--- Sets up the footer content generator function.
--- This creates a function that will be called by ReaderFooter to display Bluetooth status.
function KoboBluetooth:setupFooterContentGenerator()
    self.additional_footer_content_func = function()
        if not self:isDeviceSupported() then
            return ""
        end

        if not self:isFooterStatusEnabled() then
            return ""
        end

        if not self.ui or not self.ui.view or not self.ui.view.footer then
            return ""
        end

        local footer = self.ui.view.footer

        local function should_hide_when_disabled(footer_obj)
            return footer_obj
                and footer_obj.settings
                and footer_obj.settings.all_at_once
                and footer_obj.settings.hide_empty_generators
        end

        local is_enabled = self:isBluetoothEnabled()
        local is_auto_connect_active = self:isAutoConnectActive()
        local is_auto_detect_active = self:isAutoDetectionActive()
        local item_prefix = footer.settings and footer.settings.item_prefix or "icons"

        local bluetooth_symbol_on = ""
        local bluetooth_symbol_off = ""
        local bluetooth_letter = "BT"

        logger.dbg(
            "KoboBluetooth: Generating footer content - is_enabled:",
            is_enabled,
            "is_auto_connect_active:",
            is_auto_connect_active,
            "is_auto_detect_active:",
            is_auto_detect_active,
            "item_prefix:",
            item_prefix
        )

        if item_prefix == "icons" then
            if is_enabled then
                if is_auto_connect_active then
                    return bluetooth_symbol_on .. "\u{F06E}"
                end

                if is_auto_detect_active then
                    return bluetooth_symbol_on .. "\u{F0208}"
                end

                return bluetooth_symbol_on
            end

            if should_hide_when_disabled(footer) then
                return ""
            end

            return bluetooth_symbol_off
        end

        if item_prefix == "compact_items" then
            if is_enabled then
                if is_auto_connect_active then
                    return bluetooth_symbol_on .. "\u{F06E}"
                end

                if is_auto_detect_active then
                    return bluetooth_symbol_on .. "\u{F0208}"
                end

                return bluetooth_symbol_on
            end

            if should_hide_when_disabled(footer) then
                return ""
            end

            return bluetooth_symbol_off
        end

        if is_enabled then
            if is_auto_connect_active then
                return bluetooth_letter .. ": " .. _("On (Connect)")
            end

            if is_auto_detect_active then
                return bluetooth_letter .. ": " .. _("On (Detect)")
            end

            return bluetooth_letter .. ": " .. _("On")
        end

        if should_hide_when_disabled(footer) then
            return ""
        end

        return bluetooth_letter .. ": " .. _("Off")
    end
end

---
--- Adds Bluetooth status to the footer.
--- Should be called when the reader UI is available.
function KoboBluetooth:addAdditionalFooterContent(ui)
    if not self:isDeviceSupported() then
        return
    end

    if not ui or not ui.view or not ui.view.footer then
        logger.warn("KoboBluetooth: Cannot add footer content - UI not available")

        return
    end

    if self.additional_footer_content_func then
        ui.view.footer:addAdditionalFooterContent(self.additional_footer_content_func)
        logger.info("KoboBluetooth: Added Bluetooth status to footer")
    end
end

---
--- Removes Bluetooth status from the footer.
--- Should be called during cleanup.
function KoboBluetooth:removeAdditionalFooterContent(ui)
    if not self:isDeviceSupported() then
        return
    end

    if not ui or not ui.view or not ui.view.footer then
        return
    end

    if self.additional_footer_content_func then
        ui.view.footer:removeAdditionalFooterContent(self.additional_footer_content_func)
        logger.info("KoboBluetooth: Removed Bluetooth status from footer")
    end
end

---
--- Emits BluetoothStateChanged event.
--- @param state boolean True if Bluetooth is ON, false if OFF.
function KoboBluetooth:emitBluetoothStateChangedEvent(state)
    UIManager:sendEvent(Event:new("BluetoothStateChanged", { state = state }))
    UIManager:broadcastEvent(Event:new("RefreshAdditionalContent"))
end

---
--- Starts all Bluetooth-related processes after Bluetooth is confirmed enabled.
--- This includes device manager, D-Bus monitoring, auto-detection, and auto-connect.
--- This is shared logic used by both manual Bluetooth enable and post-resume polling.
function KoboBluetooth:_startBluetoothProcesses()
    if not self:isBluetoothEnabled() then
        return
    end

    self.device_manager:loadDevices()
    self:syncPairedDevicesToSettings()
    self:startAutoConnectPolling()
    self:startAutoDetectionPolling()

    self.dbus_monitor:registerCallback("kobobluetooth:device_manager_sync", function(device_address, properties)
        self.device_manager:updateDeviceProperties(device_address, properties)
    end, PRIORITY_CACHE_SYNC)

    -- Register disconnect handler to handle disconnect events
    -- when auto-detect is not active as when it is
    -- it will handle disconnect events
    self.dbus_monitor:registerCallback("kobobluetooth:on_disconnect", function(device_address, properties)
        if properties.Connected ~= nil and properties.Connected == false and not self:isAutoDetectionActive() then
            self:_handleDisconnection(device_address)
        end
    end, PRIORITY_USER_ACTIONS)

    self.dbus_monitor:startMonitoring()

    if self.key_bindings then
        self.key_bindings:startPolling()
    end
end

---
--- Handles WiFi restoration after resume based on user settings.
--- Turns WiFi off when auto_restore_wifi is not enabled.
--- @param should_restore_wifi boolean Whether auto_restore_wifi is enabled
function KoboBluetooth:_handleWifiRestorationAfterResume(should_restore_wifi)
    logger.dbg("KoboBluetooth: handle wifi restoration", "should_restore:", should_restore_wifi)

    if not should_restore_wifi then
        logger.dbg("KoboBluetooth: auto_restore_wifi is false, turning WiFi back off")
        NetworkMgr:turnOffWifi()
    end
end

---
--- Internal callback for polling Bluetooth enabled state.
--- Recursively schedules itself until Bluetooth is enabled or timeout is reached.
--- @param poll_count number Current poll attempt number
--- @param max_polls number Maximum number of polling attempts
--- @param poll_interval number Milliseconds between poll attempts
--- @param should_restore_wifi boolean Whether auto_restore_wifi is enabled
function KoboBluetooth:_checkBluetoothEnabledAndStart(poll_count, max_polls, poll_interval, should_restore_wifi)
    poll_count = poll_count + 1

    if not self:isBluetoothEnabled() then
        if poll_count >= max_polls then
            logger.warn("KoboBluetooth: Timeout waiting for Bluetooth to enable after resume")
            self:_handleWifiRestorationAfterResume(should_restore_wifi)

            return
        end

        logger.dbg("KoboBluetooth: scheduling bluetooth enabled check after resume", poll_count)

        UIManager:scheduleIn(poll_interval / 1000, function()
            self:_checkBluetoothEnabledAndStart(poll_count, max_polls, poll_interval, should_restore_wifi)
        end)

        return
    end

    logger.info("KoboBluetooth: Bluetooth enabled after resume, starting processes")

    UIManager:preventStandby()
    self.bluetooth_standby_prevented = true

    self:_startBluetoothProcesses()
    self.input_handler:autoOpenConnectedDevices(self.device_manager:getDevices())

    self:_handleWifiRestorationAfterResume(should_restore_wifi)
end

---
--- Polls for Bluetooth to become enabled after resume.
--- Once enabled, starts Bluetooth processes and handles WiFi restoration.
--- This is needed because Bluetooth and WiFi are enabled asynchronously on resume.
function KoboBluetooth:_pollForBluetoothEnabled()
    local poll_count = 0
    local max_polls = 30
    local poll_interval = 100

    local should_restore_wifi = G_reader_settings:isTrue("auto_restore_wifi")

    logger.dbg("KoboBluetooth: Starting Bluetooth resume polling (auto_restore_wifi:", should_restore_wifi, ")")

    UIManager:scheduleIn(poll_interval / 1000, function()
        self:_checkBluetoothEnabledAndStart(poll_count, max_polls, poll_interval, should_restore_wifi)
    end)
end

---
--- Turns Bluetooth on via D-Bus commands and prevents standby.
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

    if not NetworkMgr:isWifiOn() then
        logger.dbg("KoboBluetooth: WiFi is not on, turning it on before turning on Bluetooth.")
        NetworkMgr:turnOnWifi(nil, false)
    end

    if not DbusAdapter.turnOn() then
        logger.warn("KoboBluetooth: Failed to turn ON")

        UIManager:show(InfoMessage:new({
            text = _("Failed to enable Bluetooth. Check device logs."),
            timeout = 3,
        }))

        return
    end

    logger.dbg("KoboBluetooth: preventing standby")
    UIManager:preventStandby()
    self.bluetooth_standby_prevented = true

    logger.info("KoboBluetooth: Turned ON, standby prevented")

    UIManager:show(InfoMessage:new({
        text = _("Bluetooth enabled"),
        timeout = 2,
    }))

    self:emitBluetoothStateChangedEvent(true)
    self:_startBluetoothProcesses()
end

---
--- Turns Bluetooth off via D-Bus commands and allows standby.
---
--- @param show_popup boolean The menu widget to refresh
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

    self:_cleanup(true)

    logger.dbg("KoboBluetooth: turning off Bluetooth via dbus adapter")

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
        logger.dbg("KoboBluetooth: allow standby")
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

    logger.dbg("KoboBluetooth: finished turnBluetoothOff")
end

---
--- Starts event-driven auto-detection for Bluetooth devices.
--- When enabled, registers a universal D-Bus callback to detect when any paired device connects.
--- Opens input handlers automatically when devices connect.
function KoboBluetooth:startAutoDetectionPolling()
    if not self.plugin or not self.plugin.settings.enable_auto_detection_polling then
        logger.dbg("KoboBluetooth: Auto-detection not enabled in settings")

        return
    end

    if not self.input_handler or not self.device_manager or not self.dbus_monitor then
        logger.warn("KoboBluetooth: Cannot start auto-detection - handlers not available")

        return
    end

    if self.plugin.settings.disable_auto_detection_after_connect then
        local devices = self.device_manager:getDevices()
        local has_connected_device = false

        for _, device in ipairs(devices) do
            if device.connected then
                has_connected_device = true
                break
            end
        end

        if has_connected_device then
            logger.dbg("KoboBluetooth: Skipping auto-detection - device already connected")

            return
        end
    end

    logger.info("KoboBluetooth: Starting auto-detection via D-Bus monitoring")

    -- Register a single universal callback for auto-detection
    self.dbus_monitor:registerCallback("kobobluetooth:auto_detection", function(device_address, properties)
        self:onAutoDetectionPropertyChanged(device_address, properties)
    end, PRIORITY_USER_ACTIONS)

    self.is_auto_detection_active = true

    UIManager:broadcastEvent(Event:new("RefreshAdditionalContent"))
end

---
--- Stops the auto-detection polling.
--- @param broadcast_refresh boolean Whether to broadcast a UI refresh event (default: true)
function KoboBluetooth:stopAutoDetectionPolling(broadcast_refresh)
    logger.dbg("KoboBluetooth: Stopping auto-detection")

    if broadcast_refresh == nil then
        broadcast_refresh = true
    end

    if self.is_auto_detection_active then
        self.dbus_monitor:unregisterCallback("kobobluetooth:auto_detection")
        self.is_auto_detection_active = false
        logger.dbg("KoboBluetooth: Unregistered auto-detection callback")
    end

    logger.dbg("KoboBluetooth: Stopped auto-detection")

    if broadcast_refresh then
        UIManager:broadcastEvent(Event:new("RefreshAdditionalContent"))
    end
end

---
--- Callback handler for auto-detection property changes.
--- Handles Connected property changes for any paired device.
--- Paired property changed to true is treated as a connection event.
--- @param device_address string Bluetooth device address
--- @param properties table Changed properties from D-Bus signal
function KoboBluetooth:onAutoDetectionPropertyChanged(device_address, properties)
    logger.dbg("KoboBluetooth: Auto-detection property changed for", device_address, ":", properties)

    if properties.Connected ~= nil then
        self:onConnectedPropertyChanged(device_address, properties.Connected)
    end

    if properties.Paired ~= nil then
        self:onConnectedPropertyChanged(device_address, properties.Paired)
    end
end

---
--- Callback handler for auto-connect property changes.
--- Handles RSSI property changes for any paired device.
--- Auto-connect only monitors RSSI to detect when devices come within range.
--- @param device_address string Bluetooth device address
--- @param properties table Changed properties from D-Bus signal
function KoboBluetooth:onAutoConnectPropertyChanged(device_address, properties)
    logger.dbg("KoboBluetooth: Auto-connect property changed for", device_address, ":", properties)

    if properties.RSSI ~= nil then
        self:onRssiPropertyChanged(device_address, properties)
    end
end

---
--- Handles device connection state change (connected or disconnected).
--- For disconnection: stores current RSSI to prevent immediate reconnection.
--- For connection: attempts to auto-open the input device.
--- @param device_address string Bluetooth device address
--- @param connected boolean True if device connected, false if disconnected
function KoboBluetooth:onConnectedPropertyChanged(device_address, connected)
    if connected == false then
        self:_handleDisconnection(device_address)
    elseif connected == true and (self.is_auto_detection_active or self.is_auto_connect_active) then
        self:_handleConnection(device_address)
    end
end

---
--- Handles device disconnection.
--- Stores current RSSI to prevent immediate reconnection.
--- Attempts to restart auto-connect and auto-detection polling after disconnect.
--- @param device_address string Bluetooth device address
function KoboBluetooth:_handleDisconnection(device_address)
    local device = self.device_manager:getDeviceByAddress(device_address)

    logger.dbg("KoboBluetooth: onDisconnect device", device)

    if not device then
        logger.dbg("KoboBluetooth: Device not found:", device_address)

        return
    end

    if device.rssi then
        logger.info("KoboBluetooth: Device", device_address, "disconnected with RSSI", device.rssi)
        self.last_seen_rssi[device_address] = device.rssi
    end

    logger.dbg("KoboBluetooth: restarting auto-connect and auto-detect polling after disconnect")

    self:startAutoConnectPolling()
    self:startAutoDetectionPolling()
end

---
--- Handles device connection.
--- Attempts to auto-open the input device when a device connects.
--- @param device_address string Bluetooth device address
function KoboBluetooth:_handleConnection(device_address)
    local device = self.device_manager:getDeviceByAddress(device_address)

    if not device then
        logger.dbg("KoboBluetooth: Device not found:", device_address)

        return
    end

    if not device.connected then
        logger.dbg("KoboBluetooth: Device not connected:", device_address)

        return
    end

    logger.info("KoboBluetooth: Device", device_address, "connected")

    logger.info("KoboBluetooth: Auto-opening input device for", device.name or device.address)

    local success = self.input_handler:openIsolatedInputDevice(device, true, true)

    if success then
        logger.info("KoboBluetooth: Auto-opened input device for", device.name or device.address)

        -- Clear last seen RSSI since device is now connected
        -- This resets tracking for the next disconnect/reconnect cycle
        self.last_seen_rssi[device_address] = nil

        if self.key_bindings then
            self.key_bindings:startPolling()
        end

        if
            self.plugin.settings.disable_auto_detection_after_connect
            or self.plugin.settings.disable_auto_connect_after_connect
        then
            if self.plugin.settings.disable_auto_detection_after_connect then
                logger.info("KoboBluetooth: Stopping auto-detection after successful connection")
                self:stopAutoDetectionPolling(true)
            end

            if self.plugin.settings.disable_auto_connect_after_connect then
                logger.info("KoboBluetooth: Stopping auto-connect after successful connection")
                self:stopAutoConnectPolling(true)
            end
        end
    end
end

---
--- Handles changes to the RSSI property.
--- Attempts to auto-connect to a device when it comes within range.
--- Only triggers connection attempt if RSSI has changed from the last seen value
--- to avoid duplicate connection attempts from repeated D-Bus signals.
--- @param device_address string Bluetooth device address
--- @param properties table Changed properties from D-Bus signal
function KoboBluetooth:onRssiPropertyChanged(device_address, properties)
    logger.info("KoboBluetooth: Device", device_address, "RSSI changed to", properties.RSSI)

    local rssi = properties.RSSI

    if not rssi or rssi <= -127 or rssi == 0 then
        logger.dbg("KoboBluetooth: Device not nearby (RSSI:", rssi, ")")

        return
    end

    local last_rssi = self.last_seen_rssi[device_address]
    logger.dbg("KoboBluetooth: last RSSI for device", device_address, last_rssi)

    if last_rssi == rssi then
        logger.dbg("KoboBluetooth: RSSI unchanged for", device_address, "- skipping connection attempt")

        return
    end

    self.last_seen_rssi[device_address] = rssi

    local device = self.device_manager:getDeviceByAddress(device_address)

    if not device then
        logger.dbg("KoboBluetooth: Paired device not found for auto connecting:", device_address)

        return
    end

    if device.connected then
        logger.dbg("KoboBluetooth: Device already connected:", device_address)

        return
    end

    if not device.paired then
        logger.dbg("KoboBluetooth: Device not paired:", device_address)

        return
    end

    logger.info("KoboBluetooth: Auto-connecting to nearby paired device:", device.name or device.address)

    self.is_startup_auto_connect = false

    self:connectToDevice(device.address, true)
end

---
--- Stops the auto-connect polling and Bluetooth discovery.
--- @param broadcast_refresh boolean Whether to broadcast a UI refresh event (default: true)
function KoboBluetooth:stopAutoConnectPolling(broadcast_refresh)
    logger.dbg("KoboBluetooth: Stopping auto-connect")

    if broadcast_refresh == nil then
        broadcast_refresh = true
    end

    if self.is_auto_connect_active then
        self.dbus_monitor:unregisterCallback("kobobluetooth:auto_connect")
        self.is_auto_connect_active = false
        self.last_seen_rssi = {}
        logger.dbg("KoboBluetooth: Unregistered auto-connect callback")
    end

    if self.is_discovery_active then
        DbusAdapter.stopDiscovery()
        self.is_discovery_active = false
    end

    logger.dbg("KoboBluetooth: Stopped auto-connect")

    if broadcast_refresh then
        UIManager:broadcastEvent(Event:new("RefreshAdditionalContent"))
    end
end

---
--- Starts auto-connecting to nearby paired Bluetooth devices via D-Bus monitoring.
--- When enabled, starts discovery and monitors RSSI changes to detect nearby devices.
function KoboBluetooth:startAutoConnectPolling()
    logger.dbg("KoboBluetooth: startAutoConnectPolling")

    if not self.plugin or not self.plugin.settings.enable_auto_connect_polling then
        logger.dbg("KoboBluetooth: Auto-connect not enabled in settings")

        return
    end

    if not self.device_manager or not self.dbus_monitor then
        logger.warn("KoboBluetooth: Cannot start auto-connect - handlers not available")

        return
    end

    if self.plugin.settings.disable_auto_connect_after_connect then
        local devices = self.device_manager:getDevices()

        for _, device in ipairs(devices) do
            if device.connected then
                logger.dbg("KoboBluetooth: Skipping auto-connect - device already connected")

                return
            end
        end
    end

    logger.info("KoboBluetooth: Starting auto-connect via D-Bus monitoring")

    -- Register a single universal callback for auto-connect
    self.dbus_monitor:registerCallback("kobobluetooth:auto_connect", function(device_address, properties)
        self:onAutoConnectPropertyChanged(device_address, properties)
    end, PRIORITY_USER_ACTIONS)

    if not self.is_discovery_active then
        local discovery_started = DbusAdapter.startDiscovery()

        if not discovery_started then
            logger.warn("KoboBluetooth: Failed to start discovery, not starting auto-connect")

            return
        end

        self.is_discovery_active = true
    end

    self.is_auto_connect_active = true
end

---
--- Initiates a Bluetooth device scan and shows results.
--- If discovery is already active (e.g., from auto-connect polling), it will
--- immediately show results without starting a new scan.
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

    if self.is_discovery_active then
        logger.dbg("KoboBluetooth: Discovery already active, showing results immediately")
        local devices = self.device_manager.fetchAllDiscoveredDevices()

        self:showScanResultsMenu(devices)

        return
    end
    self.device_manager:scanForDevices(5, function(devices)
        if devices then
            self:showScanResultsMenu(devices)
        end
    end)
end

---
--- Shows the scan results menu with the given devices.
--- @param devices table Array of discovered device information
function KoboBluetooth:showScanResultsMenu(devices)
    UiMenus.showScanResults(devices, function(device_info)
        self.device_manager:toggleConnection(device_info, function(dev)
            self.input_handler:openIsolatedInputDevice(dev, true, true)

            if self.key_bindings then
                self.key_bindings:startPolling()
            end
        end, function(dev)
            self.input_handler:closeIsolatedInputDevice(dev)
        end)

        self:syncPairedDevicesToSettings()

        self:registerDeviceWithDispatcher(device_info)
    end, function(menu_widget)
        UIManager:close(menu_widget)
        self:scanAndShowDevices()
    end)
end

---
--- Shows a menu of paired devices.
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

    -- Sync paired devices to plugin settings when viewing paired devices
    self:syncPairedDevicesToSettings()

    self.paired_devices_menu = UiMenus.showPairedDevices(self:_getPairedDevices(), function(device_info)
        self:showDeviceOptionsMenu(device_info)
    end, function(device_info)
        if self.key_bindings then
            self.key_bindings:showConfigMenu(device_info)
        end
    end, function(menu_widget)
        self:refreshPairedDevicesMenu(menu_widget)
    end)
end

function KoboBluetooth:onCloseWidget()
    logger.dbg("KoboBluetooth: onCloseWidget")

    self:_cleanup(false)
end

function KoboBluetooth:onClose()
    logger.dbg("KoboBluetooth: onClose")

    self:_cleanup(false)
end

--- When restarting koreader, dbus monitoring should be stopped.
--- if not, it prevents koreader from restarting.
function KoboBluetooth:onRestart()
    logger.dbg("KoboBluetooth: onRestart")

    self:_cleanup(false)
end

---
--- Called when device is suspended.
--- Turns off Bluetooth before suspend.
function KoboBluetooth:onSuspend()
    logger.dbg("KoboBluetooth: onSuspend")

    self.bluetooth_was_enabled_before_suspend = false

    if self:isDeviceSupported() and self:isBluetoothEnabled() then
        self.bluetooth_was_enabled_before_suspend = true
        self:turnBluetoothOff(false)
    end
end

---
--- Called when device resumes from suspend.
--- Re-enables Bluetooth if auto-resume is enabled and it was on before suspend.
function KoboBluetooth:onResume()
    if not self:isDeviceSupported() then
        return
    end

    if not self.plugin or not self.plugin.settings then
        return
    end

    if not self.plugin.settings.enable_bluetooth_auto_resume then
        return
    end

    if not self.bluetooth_was_enabled_before_suspend then
        return
    end

    NetworkMgr:restoreWifiAsync()

    UIManager:tickAfterNext(function()
        ffiutil.runInSubProcess(function()
            logger.info("KoboBluetooth: Auto-resuming Bluetooth after device wake")
            DbusAdapter.turnOn()
        end, false, true)

        self:_pollForBluetoothEnabled()
    end)
end

---
--- Called when a Bluetooth device connects via DeviceManager callback.
--- Stops auto-detection polling if disable_auto_detection_after_connect is enabled.
--- Stops auto-connect polling if disable_auto_connect_after_connect is enabled.
--- @param device table Device information
function KoboBluetooth:onDeviceConnected(device)
    if not self.plugin then
        return
    end

    if self.plugin.settings.disable_auto_detection_after_connect then
        logger.info("KoboBluetooth: Device connected, stopping auto-detection polling")
        self:stopAutoDetectionPolling(true)
    end

    if self.plugin.settings.disable_auto_connect_after_connect then
        logger.info("KoboBluetooth: Device connected, stopping auto-connect polling")
        self:stopAutoConnectPolling(true)
    end
end

---
--- Called when an input device is closed via InputDeviceHandler callback.
--- This handles unexpected disconnects detected during polling.
--- Restarts auto-detection polling if no devices remain connected and settings allow.
--- Restarts auto-connect polling if no devices remain connected and settings allow.
--- @param device_address string The Bluetooth address of the disconnected device
--- @param device_path string The input device path that was closed
function KoboBluetooth:onInputDeviceClosed(device_address, device_path)
    if not self.plugin then
        return
    end

    self.device_manager:updateDeviceProperties(device_address, { Connected = false })

    local has_connected_device = next(self.input_handler.isolated_readers) ~= nil

    if has_connected_device then
        return
    end

    if
        self.plugin.settings.enable_auto_detection_polling
        and self.plugin.settings.disable_auto_detection_after_connect
    then
        logger.info("KoboBluetooth: Last input device closed, restarting auto-detection polling")
        self:startAutoDetectionPolling()
    end

    if self.plugin.settings.enable_auto_connect_polling and self.plugin.settings.disable_auto_connect_after_connect then
        logger.info("KoboBluetooth: Last input device closed, restarting auto-connect polling")
        self.is_startup_auto_connect = true
        self:startAutoConnectPolling()
    end
end

---
--- Called when a Bluetooth device disconnects via DeviceManager callback.
--- Restarts auto-detection polling if no devices remain connected and settings allow.
--- Restarts auto-connect polling if no devices remain connected and settings allow.
--- @param device table Device information
function KoboBluetooth:onDeviceDisconnected(device)
    if not self.plugin then
        return
    end

    local devices = self.device_manager:getDevices()
    local has_connected_device = false

    for _, dev in ipairs(devices) do
        if dev.connected then
            has_connected_device = true
            break
        end
    end

    if has_connected_device then
        return
    end

    if
        self.plugin.settings.enable_auto_detection_polling
        and self.plugin.settings.disable_auto_detection_after_connect
    then
        logger.info("KoboBluetooth: Last device disconnected, restarting auto-detection polling")
        self:startAutoDetectionPolling()
    end
    if self.plugin.settings.enable_auto_connect_polling and self.plugin.settings.disable_auto_connect_after_connect then
        logger.info("KoboBluetooth: Last device disconnected, restarting auto-connect polling")
        self.is_startup_auto_connect = true
        self:startAutoConnectPolling()
    end
end

--- Connect to a Bluetooth device via events.
---
--- @param device_address string The Bluetooth device address (MAC or platform-specific identifier) to connect to.
--- @return boolean Retruns true to indicated that no other handler should handle this event.
function KoboBluetooth:onConnectToBluetoothDevice(device_address)
    self:connectToDevice(device_address)

    return true
end

---
--- Called when the reader UI is ready.
--- Adds Bluetooth status to the footer.
function KoboBluetooth:onReaderReady()
    if not self:isDeviceSupported() then
        return
    end

    if not self.ui then
        logger.warn("KoboBluetooth: onReaderReady called but UI not available")

        return
    end

    self:addAdditionalFooterContent(self.ui)
end

---
--- Called when document is closed.
--- Removes Bluetooth status from the footer.
function KoboBluetooth:onCloseDocument()
    if not self:isDeviceSupported() then
        return
    end

    if not self.ui then
        return
    end

    self:removeAdditionalFooterContent(self.ui)
end

---
--- Connects to a Bluetooth device by address.
--- @param address string The Bluetooth address of the device to connect to
--- @param show_notification boolean Optional. Whether to show connection notifications. Defaults to true.
--- @return boolean True if connection was initiated, false otherwise
function KoboBluetooth:connectToDevice(address, show_notification)
    if show_notification == nil then
        show_notification = true
    end
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

    if not self.plugin then
        logger.warn("KoboBluetooth: Plugin not initialized")

        return false
    end

    local cached_paired_devices = self.plugin.settings.paired_devices

    local cached_device = nil
    for _, device in ipairs(cached_paired_devices) do
        if device.address == address then
            cached_device = device
            break
        end
    end

    local device_name = (cached_device and cached_device.name or "Unknown Device")
    local message = nil

    if show_notification then
        message = InfoMessage:new({
            text = _("Connecting to %s..."):format(device_name),
        })
        UIManager:show(message)
    end

    local was_wifi_on = NetworkMgr:isWifiOn()

    if not self:isBluetoothEnabled() then
        logger.info("KoboBluetooth: Bluetooth disabled, turning on for connection")
        self:turnBluetoothOn()

        if not self:isBluetoothEnabled() then
            logger.warn("KoboBluetooth: Failed to turn on Bluetooth")
            if message then
                UIManager:close(message)
            end

            if not was_wifi_on and NetworkMgr:isWifiOn() then
                NetworkMgr:turnOffWifi(nil, false)
            end

            return false
        end
    end

    local paired_devices = self:_getPairedDevices()

    local device_info = nil
    for _, device in ipairs(paired_devices) do
        if device.address == address then
            device_info = device
            break
        end
    end

    if not device_info then
        logger.warn("KoboBluetooth: Device not found in paired list:", address)
        if message then
            UIManager:close(message)
        end

        if not was_wifi_on and NetworkMgr:isWifiOn() then
            NetworkMgr:turnOffWifi(nil, false)
        end

        if show_notification then
            UIManager:show(InfoMessage:new({
                text = _("Device not found in paired list"),
                timeout = 3,
            }))
        end

        return false
    end

    if device_info.connected then
        logger.warn("KoboBluetooth: Device already connected:", address)

        if message then
            UIManager:close(message)
        end

        if not was_wifi_on and NetworkMgr:isWifiOn() then
            NetworkMgr:turnOffWifi(nil, false)
        end
        if show_notification then
            UIManager:show(InfoMessage:new({
                text = _("Device already connected"),
                timeout = 3,
            }))
        end

        return false
    end

    logger.info("KoboBluetooth: Connecting to device:", address)
    local connection_result = self.device_manager:connectDevice(device_info, function(dev)
        self.input_handler:openIsolatedInputDevice(dev, false, true)

        if self.key_bindings then
            self.key_bindings:startPolling()
        end
    end)

    if not was_wifi_on and NetworkMgr:isWifiOn() then
        NetworkMgr:turnOffWifi(nil, false)
    end

    if message then
        UIManager:close(message)
    end

    return connection_result
end

---
--- Refreshes the paired devices menu.
--- @param menu_widget table The menu widget to refresh
function KoboBluetooth:refreshPairedDevicesMenu(menu_widget)
    local paired_devices = self:_getPairedDevices()
    local new_items = {}

    for idx, device in ipairs(paired_devices) do -- luacheck: ignore idx
        local status_text = device.connected and _("Connected") or _("Not connected")

        table.insert(new_items, {
            text = device.name ~= "" and device.name or device.address,
            mandatory = status_text,
            device_info = device,
        })
    end

    menu_widget:switchItemTable(nil, new_items)
end

---
--- Shows device options menu.
--- @param device_info table Device information
function KoboBluetooth:showDeviceOptionsMenu(device_info)
    local has_keybindings = false

    if self.key_bindings then
        local bindings = self.key_bindings:getDeviceBindings(device_info.address)
        has_keybindings = next(bindings) ~= nil
    end

    local options = {
        show_connect = not device_info.connected,
        show_disconnect = device_info.connected,
        show_configure_keys = self.key_bindings ~= nil and device_info.connected,
        show_reset_keybindings = has_keybindings,
        show_trust = not device_info.trusted,
        show_untrust = device_info.trusted,
        show_forget = true,

        on_connect = function()
            self.device_manager:connectDevice(device_info, function(dev)
                self.input_handler:openIsolatedInputDevice(dev, true, true)
            end)
        end,

        on_disconnect = function()
            self.device_manager:disconnectDevice(device_info, function(dev)
                self.input_handler:closeIsolatedInputDevice(dev)
            end)
        end,

        on_configure_keys = function()
            if self.key_bindings then
                self.key_bindings:showConfigMenu(device_info)
            end
        end,

        on_reset_keybindings = function()
            UIManager:show(ConfirmBox:new({
                text = _("Are you sure you want to reset all key bindings for this device?"),
                ok_text = _("Reset"),
                ok_callback = function()
                    if self.key_bindings then
                        self.key_bindings:clearDeviceBindings(device_info.address)
                        self:refreshDeviceOptionsMenu(self.device_options_menu, device_info)
                    end
                end,
            }))
        end,

        on_trust = function()
            self.device_manager:trustDevice(device_info)
        end,

        on_untrust = function()
            self.device_manager:untrustDevice(device_info)
        end,

        on_forget = function()
            self.device_manager:removeDevice(device_info, function(dev)
                self.input_handler:closeIsolatedInputDevice(dev)
                self:syncPairedDevicesToSettings()
            end)
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
--- Refreshes the device options menu.
--- Closes and reopens the dialog since ButtonDialog doesn't support in-place updates.
--- @param menu_widget table|nil The menu widget to refresh (ButtonDialog), or nil
--- @param device_info table Device information to refresh
function KoboBluetooth:refreshDeviceOptionsMenu(menu_widget, device_info)
    if menu_widget then
        UIManager:close(menu_widget)
    end

    local updated_device = self.device_manager:getDeviceByAddress(device_info.address)

    if not updated_device then
        self.device_options_menu = nil

        return
    end

    self:showDeviceOptionsMenu(updated_device)
end

---
--- Registers Bluetooth submenu under Network settings.
--- Only adds menu if device is supported.
--- @param menu_items table Menu items table to populate.
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
            {
                text = _("Settings"),
                sub_item_table = {
                    {
                        text = _("Auto-resume after wake"),
                        help_text = _(
                            "Automatically re-enable Bluetooth after device wakes from sleep if it was on before suspend."
                        ),
                        checked_func = function()
                            return self.plugin.settings.enable_bluetooth_auto_resume
                        end,
                        callback = function()
                            self.plugin.settings.enable_bluetooth_auto_resume =
                                not self.plugin.settings.enable_bluetooth_auto_resume
                            self.plugin:saveSettings()
                        end,
                    },
                    {
                        text = _("Show status in footer"),
                        help_text = _(
                            "Display Bluetooth status in the reader's footer bar. Shows an icon or text indicating whether Bluetooth is enabled or disabled."
                        ),
                        checked_func = function()
                            return self:isFooterStatusEnabled()
                        end,
                        callback = function()
                            local current = self:isFooterStatusEnabled()
                            self.plugin.settings.show_bluetooth_footer_status = not current
                            self.plugin:saveSettings()
                            UIManager:broadcastEvent(Event:new("RefreshAdditionalContent"))
                        end,
                    },
                    {
                        text = _("Auto-detection"),
                        sub_item_table = {
                            {
                                text = _("Auto-detect connecting devices"),
                                help_text = _(
                                    "When enabled, automatically opens input handlers for devices that reconnect (e.g., after waking from sleep). For devices that don't auto-connect, use the dispatcher 'Connect to device' action instead."
                                ),
                                checked_func = function()
                                    return self.plugin and self.plugin.settings.enable_auto_detection_polling
                                end,
                                callback = function()
                                    if self.plugin then
                                        self.plugin.settings.enable_auto_detection_polling =
                                            not self.plugin.settings.enable_auto_detection_polling
                                        self.plugin:saveSettings()

                                        if self.plugin.settings.enable_auto_detection_polling then
                                            if self:isBluetoothEnabled() then
                                                self:startAutoDetectionPolling()
                                            end
                                        else
                                            self:stopAutoDetectionPolling(true)
                                        end
                                    end
                                end,
                            },
                            {
                                text = _("Stop detection after connection"),
                                help_text = _(
                                    "When enabled, stops polling once a device successfully connects. Disable to keep detecting additional devices."
                                ),
                                enabled_func = function()
                                    return self.plugin and self.plugin.settings.enable_auto_detection_polling
                                end,
                                checked_func = function()
                                    return self.plugin and self.plugin.settings.disable_auto_detection_after_connect
                                end,
                                callback = function()
                                    if self.plugin then
                                        self.plugin.settings.disable_auto_detection_after_connect =
                                            not self.plugin.settings.disable_auto_detection_after_connect
                                        self.plugin:saveSettings()
                                    end
                                end,
                            },
                        },
                    },
                    {
                        text = _("Auto-connect"),
                        separator = true,
                        sub_item_table = {
                            {
                                text = _("Auto-connect to nearby devices"),
                                help_text = _(
                                    "When enabled, automatically scans for and connects to nearby paired and trusted Bluetooth devices. This is useful for devices that don't auto-reconnect on their own."
                                ),
                                checked_func = function()
                                    return self.plugin and self.plugin.settings.enable_auto_connect_polling
                                end,
                                callback = function()
                                    if self.plugin then
                                        self.plugin.settings.enable_auto_connect_polling =
                                            not self.plugin.settings.enable_auto_connect_polling
                                        self.plugin:saveSettings()

                                        if self.plugin.settings.enable_auto_connect_polling then
                                            if self:isBluetoothEnabled() then
                                                self.is_startup_auto_connect = true
                                                self:startAutoConnectPolling()
                                            end
                                        else
                                            self:stopAutoConnectPolling(true)
                                        end
                                    end
                                end,
                            },
                            {
                                text = _("Stop auto-connect after connection"),
                                help_text = _(
                                    "When enabled, stops scanning once a device successfully connects. Disable to keep scanning for additional devices."
                                ),
                                enabled_func = function()
                                    return self.plugin and self.plugin.settings.enable_auto_connect_polling
                                end,
                                checked_func = function()
                                    return self.plugin and self.plugin.settings.disable_auto_connect_after_connect
                                end,
                                callback = function()
                                    if self.plugin then
                                        self.plugin.settings.disable_auto_connect_after_connect =
                                            not self.plugin.settings.disable_auto_connect_after_connect
                                        self.plugin:saveSettings()
                                    end
                                end,
                            },
                        },
                    },
                    {
                        text = _("Dismiss pop-ups with button press"),
                        help_text = _(
                            "Allow any Bluetooth button to close notifications and dialogs. When disabled, buttons only perform their assigned actions."
                        ),
                        checked_func = function()
                            return self.plugin and self.plugin.settings.dismiss_widgets_on_button ~= false
                        end,
                        callback = function()
                            if self.plugin then
                                local current_enabled = self.plugin.settings.dismiss_widgets_on_button ~= false
                                self.plugin.settings.dismiss_widgets_on_button = not current_enabled
                                self.plugin:saveSettings()
                            end
                        end,
                    },
                },
            },
        },
    }
end

---
--- Syncs paired devices from Bluetooth to plugin settings.
--- Should be called whenever paired devices are loaded from Bluetooth.
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

    local paired_devices = self:_getPairedDevices()

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

--- Handle dispatcher Bluetooth actions
--
-- This dispatcher receives a string `action_id` and calls the appropriate
-- Bluetooth control method on the `KoboBluetooth` instance.
--
-- Supported `action_id` values:
--   * "enable"  - turns Bluetooth on (calls `turnBluetoothOn`)
--   * "disable" - turns Bluetooth off (calls `turnBluetoothOff(true)`)
--   * "toggle"  - toggles Bluetooth state (calls `toggleBluetooth(true)`)
--   * "scan"    - starts a device scan and shows results (calls `scanAndShowDevices`)
--
-- Any other `action_id` values are ignored (no-op).
--
-- @param action_id string Identifier of the action to perform.
-- @return nil
function KoboBluetooth:onBluetoothAction(action_id)
    if action_id == "enable" then
        self:turnBluetoothOn()
    elseif action_id == "disable" then
        self:turnBluetoothOff(true)
    elseif action_id == "toggle" then
        self:toggleBluetooth(true)
    elseif action_id == "scan" then
        self:scanAndShowDevices()
    end
end

---
--- Toggles Bluetooth on or off.
--- If Bluetooth is enabled, turns it off. Otherwise, turns it on.
--- @param show_popup boolean Whether to show popup notifications when turning off. Only affects behavior when turning Bluetooth off (parameter is ignored when turning on). Optional, defaults to true.
function KoboBluetooth:toggleBluetooth(show_popup)
    if show_popup == nil then
        show_popup = true
    end

    if self:isBluetoothEnabled() then
        self:turnBluetoothOff(show_popup)

        return
    end

    self:turnBluetoothOn()
end

---
--- Registers all Bluetooth control actions with the dispatcher.
--- Includes enable, disable, toggle, and scan actions.
function KoboBluetooth:registerBluetoothActionsWithDispatcher()
    if not self:isDeviceSupported() then
        return
    end

    local Dispatcher = require("dispatcher")

    local actions = {
        {
            id = "enable",
            title = _("Enable Bluetooth"),
        },
        {
            id = "disable",
            title = _("Disable Bluetooth"),
        },
        {
            id = "toggle",
            title = _("Toggle Bluetooth"),
        },
        {
            id = "scan",
            title = _("Scan for Bluetooth Devices"),
        },
    }

    for idx, action in ipairs(actions) do
        Dispatcher:registerAction(action.id, {
            category = "none",
            event = "BluetoothAction",
            arg = action.id,
            title = action.title,
            device = true,
            separator = (idx == #actions) and true or nil,
        })

        logger.dbg("KoboBluetooth: Registered dispatcher action:", action.id)
    end
end

---
--- Registers a single Bluetooth device with the dispatcher.
--- @param device table Device info with address and name fields
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
--- Registers all paired devices with the dispatcher.
--- Uses stored settings so it works even when Bluetooth is off.
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
