---
--- Libra 2-specific D-Bus adapter for Bluetooth control.
--- Implements the DbusAdapterInterface for Kobo Libra 2 using standard BlueZ.
--- Uses org.bluez D-Bus service with standard BlueZ interfaces.
--- Handles D-Bus command execution and communication with the BlueZ Bluetooth stack.

local ffiutil = require("ffi/util")
local logger = require("logger")

local Libra2Adapter = {}

---
--- D-Bus commands for turning Bluetooth on.
--- Starts bluetoothd daemon, resets HCI interface, and powers on adapter.
--- @field table Array of command strings to execute in sequence.
Libra2Adapter.COMMANDS_ON = {
    "/libexec/bluetooth/bluetoothd &",
    "hciconfig hci0 down",
    "hciconfig hci0 up",
    "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
        .. "org.freedesktop.DBus.Properties.Set "
        .. "string:org.bluez.Adapter1 string:Powered variant:boolean:true",
}

---
--- D-Bus commands for turning Bluetooth off.
--- Powers off adapter and stops bluetoothd daemon.
--- @field table Array of command strings to execute in sequence.
Libra2Adapter.COMMANDS_OFF = {
    "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
        .. "org.freedesktop.DBus.Properties.Set "
        .. "string:org.bluez.Adapter1 string:Powered variant:boolean:false",
    "killall bluetoothd",
}

---
--- Command to check Bluetooth power status.
--- @field string D-Bus command to query Powered property.
Libra2Adapter.COMMAND_CHECK_STATUS = "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
    .. "org.freedesktop.DBus.Properties.Get "
    .. "string:org.bluez.Adapter1 string:Powered 2>/dev/null"

---
--- Command to start Bluetooth discovery.
Libra2Adapter.COMMAND_START_DISCOVERY = "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
    .. "org.bluez.Adapter1.StartDiscovery"

---
--- Command to stop Bluetooth discovery.
Libra2Adapter.COMMAND_STOP_DISCOVERY = "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
    .. "org.bluez.Adapter1.StopDiscovery"

---
--- Command to get all managed Bluetooth objects (devices).
Libra2Adapter.COMMAND_GET_MANAGED_OBJECTS = "dbus-send --system --print-reply --dest=org.bluez / "
    .. "org.freedesktop.DBus.ObjectManager.GetManagedObjects"

---
--- Executes D-Bus commands via shell.
--- @param commands table Array of command strings to execute.
--- @return boolean True if all commands succeeded, false otherwise.
function Libra2Adapter.executeCommands(commands)
    for i, cmd in ipairs(commands) do
        logger.dbg("Libra2Adapter: Executing command", i, ":", cmd)

        local result = os.execute(cmd)

        if result ~= 0 then
            logger.warn("Libra2Adapter: Command", i, "failed with exit code:", result)

            return false
        end

        logger.dbg("Libra2Adapter: Command", i, "completed")
    end

    return true
end

---
--- Checks if Bluetooth is currently enabled.
--- @return boolean True if Bluetooth is powered on, false otherwise.
function Libra2Adapter.isEnabled()
    local handle = io.popen(Libra2Adapter.COMMAND_CHECK_STATUS)

    if not handle then
        logger.dbg("Libra2Adapter: Status check failed, assuming OFF")

        return false
    end

    local result = handle:read("*a")
    handle:close()

    local is_enabled = result and result:match("boolean%s+true") ~= nil
    logger.dbg("Libra2Adapter: Current state:", is_enabled and "ON" or "OFF")

    return is_enabled
end

---
--- Turns Bluetooth on via D-Bus commands.
--- @return boolean True if successful, false otherwise.
function Libra2Adapter.turnOn()
    logger.info("Libra2Adapter: Turning Bluetooth ON")

    return Libra2Adapter.executeCommands(Libra2Adapter.COMMANDS_ON)
end

---
--- Turns Bluetooth off via D-Bus commands.
--- @return boolean True if successful, false otherwise.
function Libra2Adapter.turnOff()
    logger.info("Libra2Adapter: Turning Bluetooth OFF")

    return Libra2Adapter.executeCommands(Libra2Adapter.COMMANDS_OFF)
end

---
--- Starts Bluetooth device discovery.
--- @return boolean True if successful, false otherwise.
function Libra2Adapter.startDiscovery()
    logger.info("Libra2Adapter: Starting device discovery")

    local result = os.execute(Libra2Adapter.COMMAND_START_DISCOVERY)

    return result == 0
end

---
--- Stops Bluetooth device discovery.
--- @return boolean True if successful, false otherwise.
function Libra2Adapter.stopDiscovery()
    logger.dbg("Libra2Adapter: Stopping device discovery")

    local result = os.execute(Libra2Adapter.COMMAND_STOP_DISCOVERY)

    return result == 0
end

---
--- Gets all managed Bluetooth objects (devices) via D-Bus.
--- @return string|nil Raw D-Bus output or nil on failure.
function Libra2Adapter.getManagedObjects()
    local handle = io.popen(Libra2Adapter.COMMAND_GET_MANAGED_OBJECTS)

    if not handle then
        logger.warn("Libra2Adapter: Failed to get managed objects")

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
function Libra2Adapter.connectDevice(device_path)
    logger.info("Libra2Adapter: Connecting to device:", device_path)

    local cmd =
        string.format("dbus-send --system --print-reply --dest=org.bluez %s org.bluez.Device1.Connect", device_path)

    local result = os.execute(cmd)

    return result == 0
end

---
--- Disconnects from a Bluetooth device via D-Bus.
--- @param device_path string D-Bus object path of the device
--- @return boolean True if disconnection succeeded, false otherwise.
function Libra2Adapter.disconnectDevice(device_path)
    logger.info("Libra2Adapter: Disconnecting from device:", device_path)

    local cmd =
        string.format("dbus-send --system --print-reply --dest=org.bluez %s org.bluez.Device1.Disconnect", device_path)

    local result = os.execute(cmd)

    return result == 0
end

---
--- Removes (unpairs) a Bluetooth device from the adapter via D-Bus.
--- @param device_path string D-Bus object path of the device
--- @return boolean True if removal succeeded, false otherwise.
function Libra2Adapter.removeDevice(device_path)
    logger.info("Libra2Adapter: Removing device:", device_path)

    local disconnected = Libra2Adapter.disconnectDevice(device_path)
    if not disconnected then
        logger.warn("Libra2Adapter: Failed to disconnect device before removal:", device_path)
    end

    local cmd = string.format(
        "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 org.bluez.Adapter1.RemoveDevice objpath:%s",
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
function Libra2Adapter.setDeviceTrusted(device_path, trusted)
    local trust_str = trusted and "true" or "false"
    logger.info("Libra2Adapter: Setting device trusted:", device_path, "to", trust_str)

    local cmd = string.format(
        "dbus-send --system --print-reply --dest=org.bluez %s "
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
function Libra2Adapter.connectDeviceInBackground(device_path)
    logger.info("Libra2Adapter: Connecting to device in background:", device_path)

    -- double_fork=true: child reparented to init, auto-reaped, no zombie collection needed
    local pid = ffiutil.runInSubProcess(function()
        local result = Libra2Adapter.connectDevice(device_path)
        logger.dbg("Libra2Adapter: Background connect result:", result)
    end, false, true)

    if not pid then
        logger.warn("Libra2Adapter: Failed to start background connect subprocess")

        return false
    end

    logger.dbg("Libra2Adapter: Background connect subprocess started")

    return true
end

return Libra2Adapter
