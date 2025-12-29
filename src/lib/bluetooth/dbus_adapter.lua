---
--- Factory for creating device-specific Bluetooth D-Bus adapters.
--- Detects device type and returns appropriate adapter implementation.
--- Maintains backward compatibility with static method API.

local Device = require("device")
local logger = require("logger")

local DbusAdapter = {}
local adapter_instance = nil

---
--- Gets the singleton adapter instance for the current device.
--- Performs device detection on first call and caches the result.
--- @return table|nil Adapter instance implementing DbusAdapterInterface, or nil if unsupported
local function getAdapter()
    if adapter_instance ~= nil then
        return adapter_instance == false and nil or adapter_instance
    end

    logger.dbg("DbusAdapter: Initializing adapter for device type")

    if Device.isMTK() then
        logger.info("DbusAdapter: Loading MTK adapter for MTK-based Kobo device")
        adapter_instance = require("src/lib/bluetooth/adapters/mtk_adapter")
    else
        logger.warn("DbusAdapter: Non-MTK device detected - Bluetooth not supported")
        adapter_instance = false

        return nil
    end

    return adapter_instance
end

---
--- Executes D-Bus commands via shell.
--- @param commands table Array of command strings to execute.
--- @return boolean True if all commands succeeded, false otherwise.
function DbusAdapter.executeCommands(commands)
    local adapter = getAdapter()

    if not adapter then
        return false
    end

    return adapter.executeCommands(commands)
end

---
--- Checks if Bluetooth is currently enabled.
--- @return boolean True if Bluetooth is powered on, false otherwise.
function DbusAdapter.isEnabled()
    local adapter = getAdapter()

    if not adapter then
        return false
    end

    return adapter.isEnabled()
end

---
--- Turns Bluetooth on via D-Bus commands.
--- @return boolean True if successful, false otherwise.
function DbusAdapter.turnOn()
    local adapter = getAdapter()

    if not adapter then
        return false
    end

    return adapter.turnOn()
end

---
--- Turns Bluetooth off via D-Bus commands.
--- @return boolean True if successful, false otherwise.
function DbusAdapter.turnOff()
    local adapter = getAdapter()

    if not adapter then
        return false
    end

    return adapter.turnOff()
end

---
--- Starts Bluetooth device discovery.
--- @return boolean True if successful, false otherwise.
function DbusAdapter.startDiscovery()
    local adapter = getAdapter()

    if not adapter then
        return false
    end

    return adapter.startDiscovery()
end

---
--- Stops Bluetooth device discovery.
--- @return boolean True if successful, false otherwise.
function DbusAdapter.stopDiscovery()
    local adapter = getAdapter()

    if not adapter then
        return false
    end

    return adapter.stopDiscovery()
end

---
--- Gets all managed Bluetooth objects (devices) via D-Bus.
--- @return string|nil Raw D-Bus output or nil on failure.
function DbusAdapter.getManagedObjects()
    local adapter = getAdapter()

    if not adapter then
        return nil
    end

    return adapter.getManagedObjects()
end

---
--- Connects to a Bluetooth device via D-Bus.
--- @param device_path string D-Bus object path of the device
--- @return boolean True if connection succeeded, false otherwise.
function DbusAdapter.connectDevice(device_path)
    local adapter = getAdapter()

    if not adapter then
        return false
    end

    return adapter.connectDevice(device_path)
end

---
--- Connects to a Bluetooth device via D-Bus in a background subprocess.
--- This is non-blocking and will not freeze the UI.
--- Uses double-fork so the child is reparented to init, which automatically reaps zombies.
--- When using this function auto-detect must be running, as it will detect the connection
--- and open the input device.
--- @param device_path string D-Bus object path of the device
--- @return boolean True if subprocess was started, false otherwise
function DbusAdapter.connectDeviceInBackground(device_path)
    local adapter = getAdapter()

    if not adapter then
        return false
    end

    return adapter.connectDeviceInBackground(device_path)
end

---
--- Disconnects from a Bluetooth device via D-Bus.
--- @param device_path string D-Bus object path of the device
--- @return boolean True if disconnection succeeded, false otherwise.
function DbusAdapter.disconnectDevice(device_path)
    local adapter = getAdapter()

    if not adapter then
        return false
    end

    return adapter.disconnectDevice(device_path)
end

---
--- Removes (unpairs) a Bluetooth device from the adapter via D-Bus.
--- @param device_path string D-Bus object path of the device
--- @return boolean True if removal succeeded, false otherwise.
function DbusAdapter.removeDevice(device_path)
    local adapter = getAdapter()

    if not adapter then
        return false
    end

    return adapter.removeDevice(device_path)
end

---
--- Sets or clears the Trusted property on a Bluetooth device via D-Bus.
--- @param device_path string D-Bus object path of the device
--- @param trusted boolean True to trust the device, false to untrust
--- @return boolean True if the operation succeeded, false otherwise.
function DbusAdapter.setDeviceTrusted(device_path, trusted)
    local adapter = getAdapter()

    if not adapter then
        return false
    end

    return adapter.setDeviceTrusted(device_path, trusted)
end

return DbusAdapter
