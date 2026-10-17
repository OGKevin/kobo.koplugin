---
--- Shared BlueZ D-Bus adapter for Bluetooth control.
--- Chip-specific modules construct instances with COMMANDS_ON / COMMANDS_OFF;
--- all org.bluez discovery/connect/trust operations live on this prototype.

local ffiutil = require("ffi/util")
local logger = require("logger")

local BlueZAdapter = {}
BlueZAdapter.__index = BlueZAdapter

---
--- Command to check Bluetooth power status.
--- @field string D-Bus command to query Powered property.
BlueZAdapter.COMMAND_CHECK_STATUS = "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
    .. "org.freedesktop.DBus.Properties.Get "
    .. "string:org.bluez.Adapter1 string:Powered 2>/dev/null"

---
--- Command to start Bluetooth discovery.
BlueZAdapter.COMMAND_START_DISCOVERY = "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
    .. "org.bluez.Adapter1.StartDiscovery"

---
--- Command to stop Bluetooth discovery.
BlueZAdapter.COMMAND_STOP_DISCOVERY = "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
    .. "org.bluez.Adapter1.StopDiscovery"

---
--- Command to get all managed Bluetooth objects (devices).
BlueZAdapter.COMMAND_GET_MANAGED_OBJECTS = "dbus-send --system --print-reply --dest=org.bluez / "
    .. "org.freedesktop.DBus.ObjectManager.GetManagedObjects"

---
--- Creates a BlueZ adapter instance with chip-specific power sequences.
--- @param o table { name: string, COMMANDS_ON: table, COMMANDS_OFF: table }
--- @return table Adapter implementing DbusAdapterInterface
function BlueZAdapter:new(o)
    assert(type(o) == "table", "BlueZAdapter:new: opts table required")
    assert(type(o.name) == "string" and o.name ~= "", "BlueZAdapter:new: name (non-empty string) required")
    assert(type(o.COMMANDS_ON) == "table", "BlueZAdapter:new: COMMANDS_ON (table) required")
    assert(type(o.COMMANDS_OFF) == "table", "BlueZAdapter:new: COMMANDS_OFF (table) required")

    o.COMMAND_CHECK_STATUS = BlueZAdapter.COMMAND_CHECK_STATUS
    o.COMMAND_START_DISCOVERY = BlueZAdapter.COMMAND_START_DISCOVERY
    o.COMMAND_STOP_DISCOVERY = BlueZAdapter.COMMAND_STOP_DISCOVERY
    o.COMMAND_GET_MANAGED_OBJECTS = BlueZAdapter.COMMAND_GET_MANAGED_OBJECTS

    setmetatable(o, self)

    return o
end

---
--- Log prefix derived from the chip name (e.g. "Libra2Adapter").
--- @return string
function BlueZAdapter:_logPrefix()
    return self.name .. "Adapter"
end

---
--- Executes D-Bus commands via shell.
--- @param commands table Array of command strings to execute.
--- @return boolean True if all commands succeeded, false otherwise.
function BlueZAdapter:executeCommands(commands)
    local log_prefix = self:_logPrefix()

    for i, cmd in ipairs(commands) do
        logger.dbg(log_prefix .. ": Executing command", i, ":", cmd)

        local result = os.execute(cmd)

        if result ~= 0 then
            logger.warn(log_prefix .. ": Command", i, "failed with exit code:", result)

            return false
        end

        logger.dbg(log_prefix .. ": Command", i, "completed")
    end

    return true
end

---
--- Checks if Bluetooth is currently enabled.
--- @return boolean True if Bluetooth is powered on, false otherwise.
function BlueZAdapter:isEnabled()
    local log_prefix = self:_logPrefix()
    local handle = io.popen(self.COMMAND_CHECK_STATUS)

    if not handle then
        logger.dbg(log_prefix .. ": Status check failed, assuming OFF")

        return false
    end

    local result = handle:read("*a")
    handle:close()

    local is_enabled = result and result:match("boolean%s+true") ~= nil
    logger.dbg(log_prefix .. ": Current state:", is_enabled and "ON" or "OFF")

    return is_enabled
end

---
--- Turns Bluetooth on via chip-specific commands.
--- @return boolean True if successful, false otherwise.
function BlueZAdapter:turnOn()
    logger.info(self:_logPrefix() .. ": Turning Bluetooth ON")

    return self:executeCommands(self.COMMANDS_ON)
end

---
--- Turns Bluetooth off via chip-specific commands.
--- @return boolean True if successful, false otherwise.
function BlueZAdapter:turnOff()
    logger.info(self:_logPrefix() .. ": Turning Bluetooth OFF")

    return self:executeCommands(self.COMMANDS_OFF)
end

---
--- Starts Bluetooth device discovery.
--- @return boolean True if successful, false otherwise.
function BlueZAdapter:startDiscovery()
    logger.info(self:_logPrefix() .. ": Starting device discovery")

    local result = os.execute(self.COMMAND_START_DISCOVERY)

    return result == 0
end

---
--- Stops Bluetooth device discovery.
--- @return boolean True if successful, false otherwise.
function BlueZAdapter:stopDiscovery()
    logger.dbg(self:_logPrefix() .. ": Stopping device discovery")

    local result = os.execute(self.COMMAND_STOP_DISCOVERY)

    return result == 0
end

---
--- Gets all managed Bluetooth objects (devices) via D-Bus.
--- @return string|nil Raw D-Bus output or nil on failure.
function BlueZAdapter:getManagedObjects()
    local handle = io.popen(self.COMMAND_GET_MANAGED_OBJECTS)

    if not handle then
        logger.warn(self:_logPrefix() .. ": Failed to get managed objects")

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
function BlueZAdapter:connectDevice(device_path)
    logger.info(self:_logPrefix() .. ": Connecting to device:", device_path)

    local cmd =
        string.format("dbus-send --system --print-reply --dest=org.bluez %s org.bluez.Device1.Connect", device_path)

    local result = os.execute(cmd)

    return result == 0
end

---
--- Disconnects from a Bluetooth device via D-Bus.
--- @param device_path string D-Bus object path of the device
--- @return boolean True if disconnection succeeded, false otherwise.
function BlueZAdapter:disconnectDevice(device_path)
    logger.info(self:_logPrefix() .. ": Disconnecting from device:", device_path)

    local cmd =
        string.format("dbus-send --system --print-reply --dest=org.bluez %s org.bluez.Device1.Disconnect", device_path)

    local result = os.execute(cmd)

    return result == 0
end

---
--- Removes (unpairs) a Bluetooth device from the adapter via D-Bus.
--- @param device_path string D-Bus object path of the device
--- @return boolean True if removal succeeded, false otherwise.
function BlueZAdapter:removeDevice(device_path)
    local log_prefix = self:_logPrefix()
    logger.info(log_prefix .. ": Removing device:", device_path)

    local disconnected = self:disconnectDevice(device_path)
    if not disconnected then
        logger.warn(log_prefix .. ": Failed to disconnect device before removal:", device_path)
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
function BlueZAdapter:setDeviceTrusted(device_path, trusted)
    local trust_str = trusted and "true" or "false"
    logger.info(self:_logPrefix() .. ": Setting device trusted:", device_path, "to", trust_str)

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
function BlueZAdapter:connectDeviceInBackground(device_path)
    local log_prefix = self:_logPrefix()
    logger.info(log_prefix .. ": Connecting to device in background:", device_path)

    -- double_fork=true: child reparented to init, auto-reaped, no zombie collection needed
    local pid = ffiutil.runInSubProcess(function()
        local result = self:connectDevice(device_path)
        logger.dbg(log_prefix .. ": Background connect result:", result)
    end, false, true)

    if not pid then
        logger.warn(log_prefix .. ": Failed to start background connect subprocess")

        return false
    end

    logger.dbg(log_prefix .. ": Background connect subprocess started")

    return true
end

return BlueZAdapter
