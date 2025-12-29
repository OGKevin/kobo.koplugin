---
--- MTK-specific D-Bus adapter for Bluetooth control on MTK Kobo devices.
--- Implements the DbusAdapterInterface for MTK Bluetooth chipsets.
--- Uses com.kobo.mtk.bluedroid D-Bus service.
--- Handles D-Bus command execution and communication with the MTK Bluetooth stack.

local ffiutil = require("ffi/util")
local logger = require("logger")

local MtkAdapter = {}

---
--- D-Bus commands for turning Bluetooth on.
--- @field table Array of command strings to execute in sequence.
MtkAdapter.COMMANDS_ON = {
    "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid / com.kobo.bluetooth.BluedroidManager1.On",
    "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid /org/bluez/hci0 "
        .. "org.freedesktop.DBus.Properties.Set "
        .. "string:org.bluez.Adapter1 string:Powered variant:boolean:true",
}

---
--- D-Bus commands for turning Bluetooth off.
--- @field table Array of command strings to execute in sequence.
MtkAdapter.COMMANDS_OFF = {
    "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid /org/bluez/hci0 "
        .. "org.freedesktop.DBus.Properties.Set "
        .. "string:org.bluez.Adapter1 string:Powered variant:boolean:false",
    "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid / com.kobo.bluetooth.BluedroidManager1.Off",
}

---
--- Command to check Bluetooth power status.
--- @field string D-Bus command to query Powered property.
MtkAdapter.COMMAND_CHECK_STATUS = "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid /org/bluez/hci0 "
    .. "org.freedesktop.DBus.Properties.Get "
    .. "string:org.bluez.Adapter1 string:Powered 2>/dev/null"

---
--- Command to start Bluetooth discovery.
MtkAdapter.COMMAND_START_DISCOVERY = "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid /org/bluez/hci0 "
    .. "org.bluez.Adapter1.StartDiscovery"

---
--- Command to stop Bluetooth discovery.
MtkAdapter.COMMAND_STOP_DISCOVERY = "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid /org/bluez/hci0 "
    .. "org.bluez.Adapter1.StopDiscovery"

---
--- Command to get all managed Bluetooth objects (devices).
MtkAdapter.COMMAND_GET_MANAGED_OBJECTS = "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid / "
    .. "org.freedesktop.DBus.ObjectManager.GetManagedObjects"

---
--- Executes D-Bus commands via shell.
--- @param commands table Array of command strings to execute.
--- @return boolean True if all commands succeeded, false otherwise.
function MtkAdapter.executeCommands(commands)
    for i, cmd in ipairs(commands) do
        logger.dbg("MtkAdapter: Executing command", i, ":", cmd)

        local result = os.execute(cmd)

        if result ~= 0 then
            logger.warn("MtkAdapter: Command", i, "failed with exit code:", result)

            return false
        end

        logger.dbg("MtkAdapter: Command", i, "completed")
    end

    return true
end

---
--- Checks if Bluetooth is currently enabled.
--- @return boolean True if Bluetooth is powered on, false otherwise.
function MtkAdapter.isEnabled()
    local handle = io.popen(MtkAdapter.COMMAND_CHECK_STATUS)

    if not handle then
        logger.dbg("MtkAdapter: Status check failed, assuming OFF")

        return false
    end

    local result = handle:read("*a")
    handle:close()

    local is_enabled = result and result:match("boolean%s+true") ~= nil
    logger.dbg("MtkAdapter: Current state:", is_enabled and "ON" or "OFF")

    return is_enabled
end

---
--- Turns Bluetooth on via D-Bus commands.
--- @return boolean True if successful, false otherwise.
function MtkAdapter.turnOn()
    logger.info("MtkAdapter: Turning Bluetooth ON")

    return MtkAdapter.executeCommands(MtkAdapter.COMMANDS_ON)
end

---
--- Turns Bluetooth off via D-Bus commands.
--- @return boolean True if successful, false otherwise.
function MtkAdapter.turnOff()
    logger.info("MtkAdapter: Turning Bluetooth OFF")

    return MtkAdapter.executeCommands(MtkAdapter.COMMANDS_OFF)
end

---
--- Starts Bluetooth device discovery.
--- @return boolean True if successful, false otherwise.
function MtkAdapter.startDiscovery()
    logger.info("MtkAdapter: Starting device discovery")

    local result = os.execute(MtkAdapter.COMMAND_START_DISCOVERY)

    return result == 0
end

---
--- Stops Bluetooth device discovery.
--- @return boolean True if successful, false otherwise.
function MtkAdapter.stopDiscovery()
    logger.dbg("MtkAdapter: Stopping device discovery")

    local result = os.execute(MtkAdapter.COMMAND_STOP_DISCOVERY)

    return result == 0
end

---
--- Gets all managed Bluetooth objects (devices) via D-Bus.
--- @return string|nil Raw D-Bus output or nil on failure.
function MtkAdapter.getManagedObjects()
    local handle = io.popen(MtkAdapter.COMMAND_GET_MANAGED_OBJECTS)

    if not handle then
        logger.warn("MtkAdapter: Failed to get managed objects")

        return nil
    end

    local output = handle:read("*a")
    handle:close()

    return output
end

---
--- Connects to a Bluetooth device via D-Bus.
--- @param device_path string D-Bus object path of the device
--- @return boolean True if connection succeeded, false otherwise.
function MtkAdapter.connectDevice(device_path)
    logger.info("MtkAdapter: Connecting to device:", device_path)

    local cmd = string.format(
        "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid %s org.bluez.Device1.Connect",
        device_path
    )

    local result = os.execute(cmd)

    return result == 0
end

---
--- Disconnects from a Bluetooth device via D-Bus.
--- @param device_path string D-Bus object path of the device
--- @return boolean True if disconnection succeeded, false otherwise.
function MtkAdapter.disconnectDevice(device_path)
    logger.info("MtkAdapter: Disconnecting from device:", device_path)

    local cmd = string.format(
        "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid %s org.bluez.Device1.Disconnect",
        device_path
    )

    local result = os.execute(cmd)

    return result == 0
end

---
--- Removes (unpairs) a Bluetooth device from the adapter via D-Bus.
--- @param device_path string D-Bus object path of the device
--- @return boolean True if removal succeeded, false otherwise.
function MtkAdapter.removeDevice(device_path)
    logger.info("MtkAdapter: Removing device:", device_path)

    local disconnected = MtkAdapter.disconnectDevice(device_path)
    if not disconnected then
        logger.warn("MtkAdapter: Failed to disconnect device before removal:", device_path)
    end

    local cmd = string.format(
        "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid /org/bluez/hci0 org.bluez.Adapter1.RemoveDevice objpath:%s",
        device_path
    )

    local result = os.execute(cmd)

    return result == 0
end

---
--- Sets or clears the Trusted property on a Bluetooth device via D-Bus.
--- @param device_path string D-Bus object path of the device
--- @param trusted boolean True to trust the device, false to untrust
--- @return boolean True if the operation succeeded, false otherwise.
function MtkAdapter.setDeviceTrusted(device_path, trusted)
    local trust_str = trusted and "true" or "false"
    logger.info("MtkAdapter: Setting device trusted:", device_path, "to", trust_str)

    local cmd = string.format(
        "dbus-send --system --print-reply --dest=com.kobo.mtk.bluedroid %s "
            .. "org.freedesktop.DBus.Properties.Set "
            .. "string:org.bluez.Device1 string:Trusted variant:boolean:%s",
        device_path,
        trust_str
    )

    local result = os.execute(cmd)

    return result == 0
end

---
--- Connects to a Bluetooth device via D-Bus in a background subprocess.
--- This is non-blocking and will not freeze the UI.
--- Uses double-fork so the child is reparented to init, which automatically reaps zombies.
--- When using this function auto-detect must be running, as it will detect the connection
--- and open the input device.
--- @param device_path string D-Bus object path of the device
--- @return boolean True if subprocess was started, false otherwise
function MtkAdapter.connectDeviceInBackground(device_path)
    logger.info("MtkAdapter: Connecting to device in background:", device_path)

    -- double_fork=true: child reparented to init, auto-reaped, no zombie collection needed
    local pid = ffiutil.runInSubProcess(function()
        local result = MtkAdapter.connectDevice(device_path)
        logger.dbg("MtkAdapter: Background connect result:", result)
    end, false, true)

    if not pid then
        logger.warn("MtkAdapter: Failed to start background connect subprocess")

        return false
    end

    logger.dbg("MtkAdapter: Background connect subprocess started")

    return true
end

return MtkAdapter
