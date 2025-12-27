---
-- Bluetooth device management module.
-- Handles device discovery, connection, and paired device tracking.

local DbusAdapter = require("src/lib/bluetooth/dbus_adapter")
local DeviceParser = require("src/lib/bluetooth/device_parser")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local logger = require("logger")

local DeviceManager = {
    devices_cache = {},
    device_connect_callbacks = {},
    device_disconnect_callbacks = {},
}

---
-- Creates a new DeviceManager instance.
-- @return table New DeviceManager instance
function DeviceManager:new()
    local instance = {}
    setmetatable(instance, self)
    self.__index = self

    instance.devices_cache = {}
    instance.device_connect_callbacks = {}
    instance.device_disconnect_callbacks = {}

    return instance
end

---
-- Scans for Bluetooth devices asynchronously using non-blocking scheduled callback.
-- @param scan_duration number Optional duration in seconds to scan (default: 5)
-- @param on_devices_found function Optional callback invoked with discovered devices (or nil on failure)
function DeviceManager:scanForDevices(scan_duration, on_devices_found)
    scan_duration = scan_duration or 5
    on_devices_found = on_devices_found or function() end

    logger.info("DeviceManager: Starting device discovery")

    UIManager:show(InfoMessage:new({
        text = _("Scanning for Bluetooth devices..."),
        timeout = scan_duration + 1,
    }))

    if not DbusAdapter.startDiscovery() then
        logger.warn("DeviceManager: Failed to start discovery")

        UIManager:show(InfoMessage:new({
            text = _("Failed to start Bluetooth scan"),
            timeout = 3,
        }))

        on_devices_found(nil)

        return
    end

    logger.dbg("DeviceManager: Scanning for", scan_duration, "seconds")

    UIManager:scheduleIn(scan_duration, function()
        local output = DbusAdapter.getManagedObjects()

        if not output then
            logger.warn("DeviceManager: Failed to get managed objects")
            DbusAdapter.stopDiscovery()
            on_devices_found(nil)

            return
        end

        local devices = DeviceParser.parseDiscoveredDevices(output)
        logger.info("DeviceManager: Found", #devices, "devices")

        on_devices_found(devices)

        DbusAdapter.stopDiscovery()
        logger.dbg("DeviceManager: Discovery stopped")
    end)
end

---
-- Connects to a Bluetooth device.
-- @param device table Device information table with path and name
-- @param on_success function Optional callback to execute on successful connection
-- @return boolean True if connection succeeded, false otherwise
function DeviceManager:connectDevice(device, on_success)
    logger.info("DeviceManager: Connecting to device:", device.name, "path:", device.path)

    local local_on_success = function()
        logger.dbg("DeviceManager: Updating device cache for", device.address, "to connected")

        if self.devices_cache[device.address] then
            self.devices_cache[device.address].connected = true
        end

        if on_success then
            on_success(device)
        end
    end

    if DbusAdapter.connectDevice(device.path) then
        logger.info("DeviceManager: Successfully connected to", device.name)

        UIManager:show(InfoMessage:new({
            text = _("Connected to") .. " " .. device.name,
            timeout = 2,
        }))

        local_on_success()

        for _, callback in ipairs(self.device_connect_callbacks) do
            local ok, err = pcall(callback, device)

            if not ok then
                logger.warn("DeviceManager: Device connect callback error:", err)
            end
        end

        return true
    end

    logger.warn("DeviceManager: Failed to connect to", device.name)

    UIManager:show(InfoMessage:new({
        text = _("Failed to connect to") .. " " .. device.name,
        timeout = 3,
    }))

    return false
end

---
-- Connects to a Bluetooth device in the background (non-blocking).
-- Uses a subprocess to avoid freezing the UI during D-Bus connection.
-- Does not show notifications or invoke callbacks - use auto-detection polling
-- to detect when the connection succeeds and handle input device setup.
-- @param device table Device information table with path and name
-- @return boolean True if background connect was started, false otherwise
function DeviceManager:connectDeviceInBackground(device)
    logger.info("DeviceManager: Starting background connect to:", device.name, "path:", device.path)

    return DbusAdapter.connectDeviceInBackground(device.path)
end
---
-- Disconnects from a Bluetooth device.
-- @param device table Device information table with path and name
-- @param on_success function Optional callback to execute on successful disconnection
-- @return boolean True if disconnection succeeded, false otherwise
function DeviceManager:disconnectDevice(device, on_success)
    logger.info("DeviceManager: Disconnecting from device:", device.name, "path:", device.path)

    local local_on_success = function()
        logger.dbg("DeviceManager: Updating device cache for", device.address, "to disconnected")

        if self.devices_cache[device.address] then
            self.devices_cache[device.address].connected = false
        end

        if on_success then
            on_success(device)
        end
    end

    if DbusAdapter.disconnectDevice(device.path) then
        logger.info("DeviceManager: Successfully disconnected from", device.name)

        UIManager:show(InfoMessage:new({
            text = _("Disconnected from") .. " " .. device.name,
            timeout = 2,
        }))

        local_on_success()

        for _, callback in ipairs(self.device_disconnect_callbacks) do
            local ok, err = pcall(callback, device)

            if not ok then
                logger.warn("DeviceManager: Device disconnect callback error:", err)
            end
        end

        return true
    end

    logger.warn("DeviceManager: Failed to disconnect from", device.name)

    UIManager:show(InfoMessage:new({
        text = _("Failed to disconnect from") .. " " .. device.name,
        timeout = 3,
    }))

    return false
end

---
-- Toggles device connection state.
-- @param device_info table Device information with path, address, name
-- @param on_connect function Optional callback on successful connection
-- @param on_disconnect function Optional callback on successful disconnection
function DeviceManager:toggleConnection(device_info, on_connect, on_disconnect)
    if device_info.connected then
        self:disconnectDevice(device_info, on_disconnect)
    else
        self:connectDevice(device_info, on_connect)
    end
end

---
-- Removes (unpairs) a Bluetooth device via D-Bus.
-- @param device table Device information table with path and name
-- @param on_success function Optional callback to execute on successful removal
-- @return boolean True if removal succeeded, false otherwise
function DeviceManager:removeDevice(device, on_success)
    logger.info("DeviceManager: Removing device:", device.name, "path:", device.path)

    if DbusAdapter.removeDevice(device.path) then
        logger.info("DeviceManager: Successfully removed", device.name)

        UIManager:show(InfoMessage:new({
            text = _("Removed") .. " " .. device.name,
            timeout = 2,
        }))

        if on_success then
            on_success(device)
        end

        return true
    end

    logger.warn("DeviceManager: Failed to remove", device.name)

    UIManager:show(InfoMessage:new({
        text = _("Failed to remove") .. " " .. device.name,
        timeout = 3,
    }))

    return false
end

---
-- Sets a device as trusted.
-- @param device table Device information table with path and name
-- @param on_success function Optional callback to execute on success
-- @return boolean True if operation succeeded, false otherwise
function DeviceManager:trustDevice(device, on_success)
    logger.info("DeviceManager: Trusting device:", device.name, "path:", device.path)

    if DbusAdapter.setDeviceTrusted(device.path, true) then
        logger.info("DeviceManager: Successfully trusted", device.name)

        UIManager:show(InfoMessage:new({
            text = _("Trusted") .. " " .. device.name,
            timeout = 2,
        }))

        if on_success then
            on_success(device)
        end

        return true
    end

    logger.warn("DeviceManager: Failed to trust", device.name)

    UIManager:show(InfoMessage:new({
        text = _("Failed to trust") .. " " .. device.name,
        timeout = 3,
    }))

    return false
end

---
-- Removes trust from a device.
-- @param device table Device information table with path and name
-- @param on_success function Optional callback to execute on success
-- @return boolean True if operation succeeded, false otherwise
function DeviceManager:untrustDevice(device, on_success)
    logger.info("DeviceManager: Untrusting device:", device.name, "path:", device.path)

    if DbusAdapter.setDeviceTrusted(device.path, false) then
        logger.info("DeviceManager: Successfully untrusted", device.name)

        UIManager:show(InfoMessage:new({
            text = _("Untrusted") .. " " .. device.name,
            timeout = 2,
        }))

        if on_success then
            on_success(device)
        end

        return true
    end

    logger.warn("DeviceManager: Failed to untrust", device.name)

    UIManager:show(InfoMessage:new({
        text = _("Failed to untrust") .. " " .. device.name,
        timeout = 3,
    }))

    return false
end

function DeviceManager.fetchAllDiscoveredDevices()
    local output = DbusAdapter.getManagedObjects()

    if not output then
        logger.warn("DeviceManager: Failed to execute GetManagedObjects for paired devices")

        return
    end

    return DeviceParser.parseDiscoveredDevices(output)
end

---
-- Loads all discovered devices from D-Bus and caches them in memory.
-- Stores devices in a map with address as key for efficient lookups.
function DeviceManager:loadDevices()
    logger.dbg("DeviceManager: Loading devices")

    local all_devices = self.fetchAllDiscoveredDevices()

    logger.dbg("DeviceManager: fetched devices", all_devices)

    self.devices_cache = {}

    if all_devices then
        for _, device in ipairs(all_devices) do
            if device.address then
                self.devices_cache[device.address] = device
            end
        end
    end

    local device_count = 0

    for _ in pairs(self.devices_cache) do
        device_count = device_count + 1
    end

    logger.info("DeviceManager: Loaded", device_count, "devices")
end

---
-- Gets the list of cached devices.
-- Returns an array for backward compatibility.
-- @return table Array of device information
function DeviceManager:getDevices()
    local devices_array = {}

    for _, device in pairs(self.devices_cache) do
        table.insert(devices_array, device)
    end

    return devices_array
end

---
-- Gets a device by its Bluetooth address.
-- Uses O(1) map lookup for efficiency.
-- @param address string Bluetooth device address (e.g., "E4:17:D8:EC:04:1E")
-- @return table|nil Device information if found, nil otherwise
function DeviceManager:getDeviceByAddress(address)
    if not address then
        return nil
    end

    return self.devices_cache[address]
end

---
-- Updates a device's properties in the cache efficiently.
-- This method should be called in response to D-Bus property change signals
-- to keep the cache in sync without requiring full reloads.
-- @param device_address string Bluetooth device address
-- @param properties table Properties to update (e.g., {Connected = true, RSSI = -50})
function DeviceManager:updateDeviceProperties(device_address, properties)
    if not device_address then
        logger.warn("DeviceManager: Cannot update properties - no device address provided")

        return
    end

    if not self.devices_cache[device_address] then
        logger.dbg("DeviceManager: Device not in cache, creating entry:", device_address)

        self.devices_cache[device_address] = {
            address = device_address,
            connected = false,
            paired = false,
            trusted = false,
            rssi = 0,
            name = "",
            path = "/org/bluez/hci0/dev_" .. device_address:gsub(":", "_"),
        }
    end

    local updated_properties = {}

    for key, value in pairs(properties) do
        if key == "Connected" then
            self.devices_cache[device_address].connected = value
            table.insert(updated_properties, "connected=" .. tostring(value))
        elseif key == "Paired" then
            self.devices_cache[device_address].paired = value
            table.insert(updated_properties, "paired=" .. tostring(value))
        elseif key == "Trusted" then
            self.devices_cache[device_address].trusted = value
            table.insert(updated_properties, "trusted=" .. tostring(value))
        elseif key == "RSSI" then
            self.devices_cache[device_address].rssi = value
            table.insert(updated_properties, "rssi=" .. tostring(value))
        elseif key == "Name" then
            self.devices_cache[device_address].name = value
            table.insert(updated_properties, "name=" .. tostring(value))
        end
    end

    if #updated_properties > 0 then
        logger.dbg("DeviceManager: Updated properties for", device_address, ":", table.concat(updated_properties, ", "))
    end
end

---
-- Registers a callback to be invoked when a device connects.
-- @param callback function Callback function that receives (device) parameter
function DeviceManager:registerDeviceConnectCallback(callback)
    table.insert(self.device_connect_callbacks, callback)
    logger.dbg("DeviceManager: Registered device connect callback")
end

---
-- Registers a callback to be invoked when a device disconnects.
-- @param callback function Callback function that receives (device) parameter
function DeviceManager:registerDeviceDisconnectCallback(callback)
    table.insert(self.device_disconnect_callbacks, callback)
    logger.dbg("DeviceManager: Registered device disconnect callback")
end

return DeviceManager
