---
-- Low-level D-Bus adapter for Bluetooth control on MTK Kobo devices.
-- Handles D-Bus command execution and communication with the Bluetooth stack.

local logger = require("logger")

local DbusAdapter = {}

---
-- D-Bus commands for turning Bluetooth on.
-- @field table Array of command strings to execute in sequence.
DbusAdapter.COMMANDS_ON = {
    "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid / com.kobo.bluetooth.BluedroidManager1.On",
    "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid /org/bluez/hci0 "
        .. "org.freedesktop.DBus.Properties.Set "
        .. "string:org.bluez.Adapter1 string:Powered variant:boolean:true",
}

---
-- D-Bus commands for turning Bluetooth off.
-- @field table Array of command strings to execute in sequence.
DbusAdapter.COMMANDS_OFF = {
    "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid /org/bluez/hci0 "
        .. "org.freedesktop.DBus.Properties.Set "
        .. "string:org.bluez.Adapter1 string:Powered variant:boolean:false",
    "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid / com.kobo.bluetooth.BluedroidManager1.Off",
}

---
-- Command to check Bluetooth power status.
-- @field string D-Bus command to query Powered property.
DbusAdapter.COMMAND_CHECK_STATUS = "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid /org/bluez/hci0 "
    .. "org.freedesktop.DBus.Properties.Get "
    .. "string:org.bluez.Adapter1 string:Powered 2>/dev/null"

---
-- Command to start Bluetooth discovery.
DbusAdapter.COMMAND_START_DISCOVERY = "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid /org/bluez/hci0 "
    .. "org.bluez.Adapter1.StartDiscovery"

---
-- Command to stop Bluetooth discovery.
DbusAdapter.COMMAND_STOP_DISCOVERY = "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid /org/bluez/hci0 "
    .. "org.bluez.Adapter1.StopDiscovery"

---
-- Command to get all managed Bluetooth objects (devices).
DbusAdapter.COMMAND_GET_MANAGED_OBJECTS = "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid / "
    .. "org.freedesktop.DBus.ObjectManager.GetManagedObjects"

---
-- Executes D-Bus commands via shell.
-- @param commands table Array of command strings to execute.
-- @return boolean True if all commands succeeded, false otherwise.
function DbusAdapter.executeCommands(commands)
    for i, cmd in ipairs(commands) do
        logger.dbg("DbusAdapter: Executing command", i, ":", cmd)

        local result = os.execute(cmd)

        if result ~= 0 then
            logger.warn("DbusAdapter: Command", i, "failed with exit code:", result)

            return false
        end

        logger.dbg("DbusAdapter: Command", i, "completed")
    end

    return true
end

---
-- Checks if Bluetooth is currently enabled.
-- @return boolean True if Bluetooth is powered on, false otherwise.
function DbusAdapter.isEnabled()
    local handle = io.popen(DbusAdapter.COMMAND_CHECK_STATUS)

    if not handle then
        logger.dbg("DbusAdapter: Status check failed, assuming OFF")

        return false
    end

    local result = handle:read("*a")
    handle:close()

    local is_enabled = result and result:match("boolean%s+true") ~= nil
    logger.dbg("DbusAdapter: Current state:", is_enabled and "ON" or "OFF")

    return is_enabled
end

---
-- Turns Bluetooth on via D-Bus commands.
-- @return boolean True if successful, false otherwise.
function DbusAdapter.turnOn()
    logger.info("DbusAdapter: Turning Bluetooth ON")

    return DbusAdapter.executeCommands(DbusAdapter.COMMANDS_ON)
end

---
-- Turns Bluetooth off via D-Bus commands.
-- @return boolean True if successful, false otherwise.
function DbusAdapter.turnOff()
    logger.info("DbusAdapter: Turning Bluetooth OFF")

    return DbusAdapter.executeCommands(DbusAdapter.COMMANDS_OFF)
end

---
-- Starts Bluetooth device discovery.
-- @return boolean True if successful, false otherwise.
function DbusAdapter.startDiscovery()
    logger.info("DbusAdapter: Starting device discovery")

    local result = os.execute(DbusAdapter.COMMAND_START_DISCOVERY)

    return result == 0
end

---
-- Stops Bluetooth device discovery.
-- @return boolean True if successful, false otherwise.
function DbusAdapter.stopDiscovery()
    logger.dbg("DbusAdapter: Stopping device discovery")

    local result = os.execute(DbusAdapter.COMMAND_STOP_DISCOVERY)

    return result == 0
end

---
-- Gets all managed Bluetooth objects (devices) via D-Bus.
-- @return string|nil Raw D-Bus output or nil on failure.
function DbusAdapter.getManagedObjects()
    local handle = io.popen(DbusAdapter.COMMAND_GET_MANAGED_OBJECTS)

    if not handle then
        logger.warn("DbusAdapter: Failed to get managed objects")

        return nil
    end

    local output = handle:read("*a")
    handle:close()

    return output
end

---
-- Connects to a Bluetooth device via D-Bus.
-- @param device_path string D-Bus object path of the device
-- @return boolean True if connection succeeded, false otherwise.
function DbusAdapter.connectDevice(device_path)
    logger.info("DbusAdapter: Connecting to device:", device_path)

    local cmd = string.format(
        "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid %s org.bluez.Device1.Connect",
        device_path
    )

    local result = os.execute(cmd)

    return result == 0
end

---
-- Disconnects from a Bluetooth device via D-Bus.
-- @param device_path string D-Bus object path of the device
-- @return boolean True if disconnection succeeded, false otherwise.
function DbusAdapter.disconnectDevice(device_path)
    logger.info("DbusAdapter: Disconnecting from device:", device_path)

    local cmd = string.format(
        "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid %s org.bluez.Device1.Disconnect",
        device_path
    )

    local result = os.execute(cmd)

    return result == 0
end

return DbusAdapter
