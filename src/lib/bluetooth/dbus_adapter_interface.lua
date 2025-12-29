---
--- Interface contract for Bluetooth D-Bus adapters.
--- All adapter implementations must provide these methods with exact signatures.
---
--- This file serves as documentation only - implementations should override these functions.
--- Each function throws an error if not implemented to catch missing implementations early.
---
--- @interface DbusAdapterInterface

local DbusAdapterInterface = {}

--- Constants that should be defined by implementations:
--- COMMANDS_ON: table - Array of command strings to turn Bluetooth on
--- COMMANDS_OFF: table - Array of command strings to turn Bluetooth off
--- COMMAND_CHECK_STATUS: string - Command to check Bluetooth power status
--- COMMAND_START_DISCOVERY: string - Command to start device discovery
--- COMMAND_STOP_DISCOVERY: string - Command to stop device discovery
--- COMMAND_GET_MANAGED_OBJECTS: string - Command to get all managed objects

---
--- Executes D-Bus commands via shell.
--- @param commands table Array of command strings to execute
--- @return boolean True if all commands succeeded, false otherwise
function DbusAdapterInterface.executeCommands(commands)
    error("DbusAdapterInterface.executeCommands not implemented")
end

---
--- Checks if Bluetooth is currently enabled.
--- @return boolean True if Bluetooth is powered on, false otherwise
function DbusAdapterInterface.isEnabled()
    error("DbusAdapterInterface.isEnabled not implemented")
end

---
--- Turns Bluetooth on via D-Bus commands.
--- @return boolean True if successful, false otherwise
function DbusAdapterInterface.turnOn()
    error("DbusAdapterInterface.turnOn not implemented")
end

---
--- Turns Bluetooth off via D-Bus commands.
--- @return boolean True if successful, false otherwise
function DbusAdapterInterface.turnOff()
    error("DbusAdapterInterface.turnOff not implemented")
end

---
--- Starts Bluetooth device discovery.
--- @return boolean True if successful, false otherwise
function DbusAdapterInterface.startDiscovery()
    error("DbusAdapterInterface.startDiscovery not implemented")
end

---
--- Stops Bluetooth device discovery.
--- @return boolean True if successful, false otherwise
function DbusAdapterInterface.stopDiscovery()
    error("DbusAdapterInterface.stopDiscovery not implemented")
end

---
--- Gets all managed Bluetooth objects (devices) via D-Bus.
--- @return string|nil Raw D-Bus output or nil on failure
function DbusAdapterInterface.getManagedObjects()
    error("DbusAdapterInterface.getManagedObjects not implemented")
end

---
--- Connects to a Bluetooth device via D-Bus.
--- @param device_path string D-Bus object path of the device
--- @return boolean True if connection succeeded, false otherwise
function DbusAdapterInterface.connectDevice(device_path)
    error("DbusAdapterInterface.connectDevice not implemented")
end

---
--- Connects to a Bluetooth device via D-Bus in a background subprocess.
--- This is non-blocking and will not freeze the UI.
--- Uses double-fork so the child is reparented to init, which automatically reaps zombies.
--- When using this function auto-detect must be running, as it will detect the connection
--- and open the input device.
--- @param device_path string D-Bus object path of the device
--- @return boolean True if subprocess was started, false otherwise
function DbusAdapterInterface.connectDeviceInBackground(device_path)
    error("DbusAdapterInterface.connectDeviceInBackground not implemented")
end

---
--- Disconnects from a Bluetooth device via D-Bus.
--- @param device_path string D-Bus object path of the device
--- @return boolean True if disconnection succeeded, false otherwise
function DbusAdapterInterface.disconnectDevice(device_path)
    error("DbusAdapterInterface.disconnectDevice not implemented")
end

---
--- Removes (unpairs) a Bluetooth device from the adapter via D-Bus.
--- @param device_path string D-Bus object path of the device
--- @return boolean True if removal succeeded, false otherwise
function DbusAdapterInterface.removeDevice(device_path)
    error("DbusAdapterInterface.removeDevice not implemented")
end

---
--- Sets or clears the Trusted property on a Bluetooth device via D-Bus.
--- @param device_path string D-Bus object path of the device
--- @param trusted boolean True to trust the device, false to untrust
--- @return boolean True if the operation succeeded, false otherwise
function DbusAdapterInterface.setDeviceTrusted(device_path, trusted)
    error("DbusAdapterInterface.setDeviceTrusted not implemented")
end

return DbusAdapterInterface
