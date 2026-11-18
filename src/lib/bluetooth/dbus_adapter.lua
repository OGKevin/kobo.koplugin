---
--- Factory for creating device-specific Bluetooth D-Bus adapters.
--- Detects device type and returns appropriate adapter implementation.
--- Maintains backward compatibility with static method API.

local BluedroidProbe = require("src/lib/bluetooth/bluedroid_probe")
local Device = require("device")
local KoboFirmware = require("src/lib/kobo_firmware")
local MtkBluezAdapter = require("src/lib/bluetooth/adapters/mtk_bluez_adapter")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local DbusAdapter = {}
local adapter_instance = nil

---
--- Selects the adapter for a Kobo Libra 2.
--- @return table
local function selectLibra2Adapter()
    logger.info("DbusAdapter: Loading Libra 2 adapter for Kobo Libra 2")

    return require("src/lib/bluetooth/adapters/libra2_adapter")
end

---
--- Selects the legacy MTK adapter with the reason it was picked.
--- @param reason string Human-readable reason for the log line
--- @return table
local function selectLegacyMtkAdapter(reason)
    logger.info("DbusAdapter: " .. reason .. ", loading legacy MTK adapter")

    return require("src/lib/bluetooth/adapters/mtk_adapter")
end

---
--- Why the MTK BlueZ fallback is not eligible, or nil when it is. Eligible
--- means: firmware 5.0 or newer, the WMT Bluetooth control node present and
--- an executable bluetoothd.
--- @return string|nil
local function mtkBluezIneligibleReason()
    local firmware_ok = KoboFirmware.isAtLeast(5, 0)

    if firmware_ok == nil then
        return "unknown firmware version"
    end

    if not firmware_ok then
        return "firmware < 5.0"
    end

    if not lfs.attributes(MtkBluezAdapter.BT_CONTROL_DEVICE, "mode") then
        return "no /dev/wmtBluetooth"
    end

    if os.execute(string.format("[ -x %s ]", MtkBluezAdapter.BLUETOOTHD_ARGV[1])) ~= 0 then
        return "bluetoothd not executable"
    end

    return nil
end

---
--- Selects the adapter for MTK devices: the legacy Kobo daemon when the bus
--- has it (running or activatable), the BlueZ fallback when it is absent and
--- the device qualifies, legacy otherwise.
--- @return table
local function selectMtkAdapter()
    local probe = BluedroidProbe.probeService()

    if probe == BluedroidProbe.OWNED or probe == BluedroidProbe.ACTIVATABLE then
        return selectLegacyMtkAdapter("legacy MTK bluedroid service present (" .. probe .. ")")
    end

    if probe ~= BluedroidProbe.ABSENT then
        return selectLegacyMtkAdapter("bluedroid service probe inconclusive")
    end

    local ineligible_reason = mtkBluezIneligibleReason()

    if ineligible_reason then
        return selectLegacyMtkAdapter("skipping MTK BlueZ fallback (" .. ineligible_reason .. ")")
    end

    logger.info(
        "DbusAdapter: no bluedroid service, firmware >= 5.0, WMT Bluetooth node and bluetoothd present, loading MTK BlueZ adapter"
    )

    return MtkBluezAdapter
end

---
--- Gets the singleton adapter instance for the current device.
--- Performs device detection on first call and caches the result.
--- @return table|nil Adapter instance implementing DbusAdapterInterface, or nil if unsupported
local function getAdapter()
    if adapter_instance ~= nil then
        return adapter_instance == false and nil or adapter_instance
    end

    logger.dbg("DbusAdapter: Initializing adapter for device type")

    if Device.model == "Kobo_io" then
        adapter_instance = selectLibra2Adapter()

        return adapter_instance
    end

    if Device.isMTK() then
        adapter_instance = selectMtkAdapter()

        return adapter_instance
    end

    logger.warn("DbusAdapter: Unsupported device - Bluetooth not supported")
    adapter_instance = false

    return nil
end

---
--- Which backend the selected adapter drives: "mtk-bluedroid" (legacy Kobo
--- daemon), "mtk-bluez" (firmware 5+ fallback, standard BlueZ) or
--- "libra2-bluez". Used by the implementations to pick their bring-up path.
--- @return string|nil Backend name, or nil when no adapter is supported
function DbusAdapter.getBackend()
    local adapter = getAdapter()

    return adapter ~= nil and adapter.backend or nil
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
