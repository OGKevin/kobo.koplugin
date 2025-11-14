---
-- Bluetooth device management module.
-- Handles device discovery, connection, and paired device tracking.

local DbusAdapter = require("src/lib/bluetooth/dbus_adapter")
local DeviceParser = require("src/lib/bluetooth/device_parser")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local ffiUtil = require("ffi/util")
local logger = require("logger")

local DeviceManager = {
    paired_devices_cache = {},
}

---
-- Creates a new DeviceManager instance.
-- @return table New DeviceManager instance
function DeviceManager:new()
    local instance = {}
    setmetatable(instance, self)
    self.__index = self

    instance.paired_devices_cache = {}

    return instance
end

---
-- Scans for Bluetooth devices by starting discovery, waiting, and parsing results.
-- @param scan_duration number Optional duration in seconds to scan (default: 5)
-- @return table|nil Array of discovered devices or nil on failure
function DeviceManager:scanForDevices(scan_duration)
    scan_duration = scan_duration or 5

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

        return nil
    end

    logger.dbg("DeviceManager: Scanning for", scan_duration, "seconds")
    ffiUtil.sleep(scan_duration)

    DbusAdapter.stopDiscovery()
    logger.dbg("DeviceManager: Discovery stopped")

    local output = DbusAdapter.getManagedObjects()

    if not output then
        logger.warn("DeviceManager: Failed to get managed objects")

        return nil
    end

    local devices = DeviceParser.parseDiscoveredDevices(output)
    logger.info("DeviceManager: Found", #devices, "devices")

    return devices
end

---
-- Connects to a Bluetooth device.
-- @param device table Device information table with path and name
-- @param on_success function Optional callback to execute on successful connection
-- @return boolean True if connection succeeded, false otherwise
function DeviceManager:connectDevice(device, on_success)
    logger.info("DeviceManager: Connecting to device:", device.name, "path:", device.path)

    if DbusAdapter.connectDevice(device.path) then
        logger.info("DeviceManager: Successfully connected to", device.name)

        UIManager:show(InfoMessage:new({
            text = _("Connected to") .. " " .. device.name,
            timeout = 2,
        }))

        if on_success then
            on_success(device)
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
-- Disconnects from a Bluetooth device.
-- @param device table Device information table with path and name
-- @param on_success function Optional callback to execute on successful disconnection
-- @return boolean True if disconnection succeeded, false otherwise
function DeviceManager:disconnectDevice(device, on_success)
    logger.info("DeviceManager: Disconnecting from device:", device.name, "path:", device.path)

    if DbusAdapter.disconnectDevice(device.path) then
        logger.info("DeviceManager: Successfully disconnected from", device.name)

        UIManager:show(InfoMessage:new({
            text = _("Disconnected from") .. " " .. device.name,
            timeout = 2,
        }))

        if on_success then
            on_success(device)
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
-- Loads paired devices from D-Bus and caches them in memory.
function DeviceManager:loadPairedDevices()
    logger.dbg("DeviceManager: Loading paired devices")

    local output = DbusAdapter.getManagedObjects()

    if not output then
        logger.warn("DeviceManager: Failed to execute GetManagedObjects for paired devices")

        return
    end

    local all_devices = DeviceParser.parseDiscoveredDevices(output)

    self.paired_devices_cache = {}

    for _, device in ipairs(all_devices) do
        if device.paired then
            table.insert(self.paired_devices_cache, device)
            logger.dbg("DeviceManager: Cached paired device:", device.name, device.address)
        end
    end

    logger.info("DeviceManager: Loaded", #self.paired_devices_cache, "paired devices")
end

---
-- Gets the list of cached paired devices.
-- @return table Array of paired device information
function DeviceManager:getPairedDevices()
    return self.paired_devices_cache
end

return DeviceManager
