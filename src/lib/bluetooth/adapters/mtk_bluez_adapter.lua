---
--- BlueZ adapter for MTK Kobo devices whose firmware ships standard BlueZ
--- instead of Kobo's com.kobo.mtk.bluedroid (Kobo Libra Colour on firmware 5+,
--- upstream issue #232). Selected by the DbusAdapter factory only when the
--- legacy service is absent from the system bus, the firmware is 5.0 or
--- newer, /dev/wmtBluetooth exists and a bluetoothd binary is executable.
---
--- Bring-up: the Bluetooth half of the combo chip is powered by writing 1 to
--- /dev/wmtBluetooth (wmt_cdev_bt then registers hci0), then bluetoothd is
--- started detached from onboard storage (Subprocess.startDaemon) and
--- Powered=true is set once /org/bluez/hci0 shows up. Teardown powers the
--- chip back down so it does not drain the battery.
---
--- The enable runs in a subprocess (see MTKBluetooth), the disable in the
--- plugin process, so what this adapter started is recorded in marker files
--- the way WmtPower does: a daemon or radio the plugin did not start is left
--- alone at shutdown.
---
--- The org.bluez D-Bus operations (power state, discovery, pairing, agents)
--- are shared with every other BlueZ device through BluezAdapter; this module
--- only adds the WMT radio power control and the bluetoothd lifecycle.
---
--- @module mtk_bluez_adapter

local BluezAdapter = require("src/lib/bluetooth/adapters/bluez_adapter")
local Subprocess = require("src/lib/bluetooth/subprocess")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local MtkBluezAdapter = setmetatable({ backend = "mtk-bluez" }, { __index = BluezAdapter })

--- Character device of the WMT Bluetooth function; writing 1 powers the radio.
MtkBluezAdapter.BT_CONTROL_DEVICE = "/dev/wmtBluetooth"

--- Values written to BT_CONTROL_DEVICE to switch the Bluetooth function on/off.
MtkBluezAdapter.BT_POWER_ON = "1"
MtkBluezAdapter.BT_POWER_OFF = "0"

--- sysfs entry the driver creates once the radio is up.
MtkBluezAdapter.HCI0_SYSFS = "/sys/class/bluetooth/hci0"

--- Program and arguments for the BlueZ daemon (on firmware 5+ Kobos).
MtkBluezAdapter.BLUETOOTHD_ARGV = {
    "/usr/libexec/bluetooth/bluetoothd",
}

--- Marker the enable subprocess creates when it started bluetoothd, so the
--- plugin process knows which daemon to stop at shutdown. /tmp clears at boot.
MtkBluezAdapter.DAEMON_MARKER = "/tmp/kobo.koplugin-bluez-btd-started"

--- Marker the enable subprocess creates when it powered the radio on, so the
--- plugin process knows it owns the radio state at shutdown.
MtkBluezAdapter.RADIO_MARKER = "/tmp/kobo.koplugin-bluez-radio-powered"

--- How many 100 ms checks to wait for hci0 and for bluetoothd to publish the
--- adapter on D-Bus.
MtkBluezAdapter.HCI0_WAIT_POLLS = 50
MtkBluezAdapter.POLL_INTERVAL_MICROSECONDS = 100000

---
--- Writes a string to a file (a sysfs/procfs control file or a marker).
--- Writes are buffered: a value the kernel rejects (EINVAL, ENODEV) only
--- surfaces when the buffer is flushed, which happens in close(), so the
--- result of close() counts as the result of write().
--- @param path string
--- @param text string
--- @return boolean True if the file could be opened, written and closed
local function writeFile(path, text)
    local file, err = io.open(path, "w")

    if not file then
        logger.warn("MtkBluezAdapter: failed to open", path, "for writing:", err)

        return false
    end

    local ok, write_err = file:write(text)
    file:close()

    if not ok then
        logger.warn("MtkBluezAdapter: failed to write", text, "to", path, ":", write_err)

        return false
    end

    return true
end

---
--- Whether a path exists.
--- @param path string
--- @return boolean
local function pathExists(path)
    return lfs.attributes(path, "mode") ~= nil
end

---
--- Waits, bounded, until check() returns true.
--- @param check function Function returning true when the wait is over
--- @param polls number Maximum number of POLL_INTERVAL_MICROSECONDS to wait
--- @return boolean True if the check succeeded, false after the deadline
local function waitFor(check, polls)
    for _ = 1, polls do
        if check() then
            return true
        end

        ffiutil.usleep(MtkBluezAdapter.POLL_INTERVAL_MICROSECONDS)
    end

    return false
end

---
--- Stops a daemon the plugin started and powers the radio down again.
--- @param powered_radio boolean Whether the plugin powered the radio on
--- @param started_daemon boolean Whether the plugin started bluetoothd
local function rollback(powered_radio, started_daemon)
    if started_daemon then
        os.execute("killall bluetoothd 2>/dev/null")
        waitFor(function()
            return not Subprocess.isProcessRunning(MtkBluezAdapter.BLUETOOTHD_ARGV[1])
        end, MtkBluezAdapter.HCI0_WAIT_POLLS)
    end

    if powered_radio then
        writeFile(MtkBluezAdapter.BT_CONTROL_DEVICE, MtkBluezAdapter.BT_POWER_OFF)
    end
end

---
--- Whether the radio driver registered hci0.
--- @return boolean
function MtkBluezAdapter.hci0Exists()
    return pathExists(MtkBluezAdapter.HCI0_SYSFS)
end

---
--- Whether the WMT Bluetooth control device exists on this device.
--- @return boolean
function MtkBluezAdapter.isBtDeviceAvailable()
    return pathExists(MtkBluezAdapter.BT_CONTROL_DEVICE)
end

---
--- Turns Bluetooth on: powers the radio through /dev/wmtBluetooth, starts
--- bluetoothd detached when not already running, waits for hci0 to appear and
--- for bluetoothd to publish /org/bluez/hci0, then sets Powered=true.
--- BlueZ answers org.bluez.Error.Busy while the adapter is already coming
--- up, so the actual Powered state decides, not the Set reply.
--- @return boolean True if successful, false otherwise.
function MtkBluezAdapter.turnOn()
    logger.info("MtkBluezAdapter: Turning Bluetooth ON")

    local powered_radio = false

    if not MtkBluezAdapter.hci0Exists() then
        if not MtkBluezAdapter.isBtDeviceAvailable() then
            logger.warn("MtkBluezAdapter: no Bluetooth control device and no hci0; radio driver not loaded?")

            return false
        end

        if not writeFile(MtkBluezAdapter.BT_CONTROL_DEVICE, MtkBluezAdapter.BT_POWER_ON) then
            logger.warn("MtkBluezAdapter: failed to power the Bluetooth radio on")

            return false
        end

        powered_radio = true

        if not waitFor(MtkBluezAdapter.hci0Exists, MtkBluezAdapter.HCI0_WAIT_POLLS) then
            logger.warn("MtkBluezAdapter: hci0 did not appear after powering the radio")
            rollback(powered_radio, false)

            return false
        end
    end

    local started_daemon = false

    if not Subprocess.isProcessRunning(MtkBluezAdapter.BLUETOOTHD_ARGV[1]) then
        if not Subprocess.startDaemon(MtkBluezAdapter.BLUETOOTHD_ARGV) then
            logger.warn("MtkBluezAdapter: Failed to start bluetoothd")
            rollback(powered_radio, false)

            return false
        end

        started_daemon = true
    end

    local dbus_ready = waitFor(MtkBluezAdapter.adapterObjectExists, MtkBluezAdapter.HCI0_WAIT_POLLS)

    if not dbus_ready then
        logger.warn("MtkBluezAdapter: bluetoothd did not expose hci0 on D-Bus")
        rollback(powered_radio, started_daemon)

        return false
    end

    -- BlueZ answers org.bluez.Error.Busy while the adapter is already coming
    -- up, so the actual Powered state decides, not the Set reply
    MtkBluezAdapter.executeCommands({ BluezAdapter.COMMAND_SET_POWERED_ON })

    if not waitFor(MtkBluezAdapter.isEnabled, MtkBluezAdapter.HCI0_WAIT_POLLS) then
        logger.warn("MtkBluezAdapter: adapter did not come up powered")
        rollback(powered_radio, started_daemon)

        return false
    end

    if started_daemon then
        writeFile(MtkBluezAdapter.DAEMON_MARKER, "")
    end

    if powered_radio then
        writeFile(MtkBluezAdapter.RADIO_MARKER, "")
    end

    return true
end

---
--- Turns Bluetooth off: Powered=false, then stops bluetoothd and powers the
--- radio down again - but only what the plugin started (marker files from
--- turnOn). A daemon or radio owned by someone else is left alone.
--- @return boolean True if successful, false otherwise.
function MtkBluezAdapter.turnOff()
    logger.info("MtkBluezAdapter: Turning Bluetooth OFF")

    -- Peers see a clean disconnect; a failure here does not stop the cleanup.
    MtkBluezAdapter.executeCommands({ BluezAdapter.COMMAND_SET_POWERED_OFF })

    if pathExists(MtkBluezAdapter.DAEMON_MARKER) then
        os.execute("killall bluetoothd 2>/dev/null")

        local stopped = waitFor(function()
            return not Subprocess.isProcessRunning(MtkBluezAdapter.BLUETOOTHD_ARGV[1])
        end, MtkBluezAdapter.HCI0_WAIT_POLLS)

        if not stopped then
            logger.warn("MtkBluezAdapter: bluetoothd did not exit after being stopped")
        end

        os.remove(MtkBluezAdapter.DAEMON_MARKER)
    else
        logger.dbg("MtkBluezAdapter: bluetoothd was not started by the plugin, leaving it running")
    end

    if pathExists(MtkBluezAdapter.RADIO_MARKER) then
        if not writeFile(MtkBluezAdapter.BT_CONTROL_DEVICE, MtkBluezAdapter.BT_POWER_OFF) then
            logger.warn("MtkBluezAdapter: failed to power the Bluetooth radio off")

            return false
        end

        os.remove(MtkBluezAdapter.RADIO_MARKER)
    else
        logger.dbg("MtkBluezAdapter: radio was already powered before the plugin, leaving it on")
    end

    return true
end

return MtkBluezAdapter
