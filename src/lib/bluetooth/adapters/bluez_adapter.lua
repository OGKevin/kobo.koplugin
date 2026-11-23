---
--- Generic BlueZ adapter for devices that run standard BlueZ (org.bluez).
---
--- Every BlueZ device exposes the same D-Bus surface - Adapter1 power and
--- discovery, Device1 connect/trust, ObjectManager device listing - so the
--- operations live here once. Device-specific adapters (Libra2Adapter,
--- MtkBluezAdapter) inherit everything through setmetatable inheritance and
--- only implement their own power lifecycle in turnOn/turnOff.
---
--- @module bluez_adapter

local Subprocess = require("src/lib/bluetooth/subprocess")
local ffiutil = require("ffi/util")
local logger = require("logger")

local BluezAdapter = {}

--- Which backend this adapter drives: standard BlueZ (org.bluez).
BluezAdapter.backend = "bluez"

---
--- D-Bus command to check Bluetooth power status.
--- @field string
BluezAdapter.COMMAND_CHECK_STATUS = "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
    .. "org.freedesktop.DBus.Properties.Get "
    .. "string:org.bluez.Adapter1 string:Powered 2>/dev/null"

---
--- Command to set the adapter Powered property.
--- @field string
BluezAdapter.COMMAND_SET_POWERED_ON = "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
    .. "org.freedesktop.DBus.Properties.Set "
    .. "string:org.bluez.Adapter1 string:Powered variant:boolean:true"

---
--- Command to clear the adapter Powered property.
--- @field string
BluezAdapter.COMMAND_SET_POWERED_OFF = "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
    .. "org.freedesktop.DBus.Properties.Set "
    .. "string:org.bluez.Adapter1 string:Powered variant:boolean:false"

---
--- Command to start Bluetooth discovery.
BluezAdapter.COMMAND_START_DISCOVERY = "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
    .. "org.bluez.Adapter1.StartDiscovery"

---
--- Command to stop Bluetooth discovery.
BluezAdapter.COMMAND_STOP_DISCOVERY = "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
    .. "org.bluez.Adapter1.StopDiscovery"

---
--- Command to get all managed Bluetooth objects (devices).
BluezAdapter.COMMAND_GET_MANAGED_OBJECTS = "dbus-send --system --print-reply --dest=org.bluez / "
    .. "org.freedesktop.DBus.ObjectManager.GetManagedObjects"

---
--- Executes D-Bus commands via shell.
--- @param commands table Array of command strings to execute.
--- @return boolean True if all commands succeeded, false otherwise.
function BluezAdapter.executeCommands(commands)
    for i, cmd in ipairs(commands) do
        logger.dbg("BluezAdapter: Executing command", i, ":", cmd)

        local result = os.execute(cmd)

        if result ~= 0 then
            logger.warn("BluezAdapter: Command", i, "failed with exit code:", result)

            return false
        end

        logger.dbg("BluezAdapter: Command", i, "completed")
    end

    return true
end

---
--- Checks if Bluetooth is currently enabled.
--- @return boolean True if Bluetooth is powered on, false otherwise.
function BluezAdapter.isEnabled()
    local handle = io.popen(BluezAdapter.COMMAND_CHECK_STATUS)

    if not handle then
        logger.dbg("BluezAdapter: Status check failed, assuming OFF")

        return false
    end

    local result = handle:read("*a")
    handle:close()

    local is_enabled = result and result:match("boolean%s+true") ~= nil
    logger.dbg("BluezAdapter: Current state:", is_enabled and "ON" or "OFF")

    return is_enabled
end

---
--- Whether bluetoothd has published the adapter object on D-Bus: any Get reply
--- for the Powered property means the object exists, whatever its value.
--- @return boolean
function BluezAdapter.adapterObjectExists()
    local handle = io.popen(BluezAdapter.COMMAND_CHECK_STATUS)

    if not handle then
        return false
    end

    local result = handle:read("*a")
    handle:close()

    return result ~= nil and result:find("boolean", 1, true) ~= nil
end

---
--- Starts Bluetooth device discovery.
--- @return boolean True if successful, false otherwise.
function BluezAdapter.startDiscovery()
    logger.info("BluezAdapter: Starting device discovery")

    local result = os.execute(BluezAdapter.COMMAND_START_DISCOVERY)

    return result == 0
end

---
--- Stops Bluetooth device discovery.
--- @return boolean True if successful, false otherwise.
function BluezAdapter.stopDiscovery()
    logger.dbg("BluezAdapter: Stopping device discovery")

    local result = os.execute(BluezAdapter.COMMAND_STOP_DISCOVERY)

    return result == 0
end

---
--- Gets all managed Bluetooth objects (devices) via D-Bus.
--- @return string|nil Raw D-Bus output or nil on failure.
function BluezAdapter.getManagedObjects()
    local handle = io.popen(BluezAdapter.COMMAND_GET_MANAGED_OBJECTS)

    if not handle then
        logger.warn("BluezAdapter: Failed to get managed objects")

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
function BluezAdapter.connectDevice(device_path)
    logger.info("BluezAdapter: Connecting to device:", device_path)

    local cmd =
        string.format("dbus-send --system --print-reply --dest=org.bluez %s org.bluez.Device1.Connect", device_path)

    local result = os.execute(cmd)

    return result == 0
end

---
--- Disconnects from a Bluetooth device via D-Bus.
--- @param device_path string D-Bus object path of the device
--- @return boolean True if disconnection succeeded, false otherwise.
function BluezAdapter.disconnectDevice(device_path)
    logger.info("BluezAdapter: Disconnecting from device:", device_path)

    local cmd =
        string.format("dbus-send --system --print-reply --dest=org.bluez %s org.bluez.Device1.Disconnect", device_path)

    local result = os.execute(cmd)

    return result == 0
end

---
--- Removes (unpairs) a Bluetooth device from the adapter via D-Bus.
--- @param device_path string D-Bus object path of the device
--- @return boolean True if the operation succeeded, false otherwise.
function BluezAdapter.removeDevice(device_path)
    logger.info("BluezAdapter: Removing device:", device_path)

    local disconnected = BluezAdapter.disconnectDevice(device_path)
    if not disconnected then
        logger.warn("BluezAdapter: Failed to disconnect device before removal:", device_path)
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
function BluezAdapter.setDeviceTrusted(device_path, trusted)
    local trust_str = trusted and "true" or "false"
    logger.info("BluezAdapter: Setting device trusted:", device_path, trusted)

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
function BluezAdapter.connectDeviceInBackground(device_path)
    logger.info("BluezAdapter: Connecting to device in background:", device_path)

    -- double_fork=true: child reparented to init, auto-reaped, no zombie collection needed
    local pid = ffiutil.runInSubProcess(function()
        Subprocess.detachFromStorage()

        local result = BluezAdapter.connectDevice(device_path)
        logger.dbg("BluezAdapter: Background connect result:", result)
    end, false, true)

    if not pid then
        logger.warn("BluezAdapter: Failed to start background connect subprocess")

        return false
    end

    logger.dbg("BluezAdapter: Background connect subprocess started")

    return true
end

return BluezAdapter
