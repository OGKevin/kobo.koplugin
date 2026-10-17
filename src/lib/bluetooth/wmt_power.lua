---
--- Power control for the Wi-Fi function of the MediaTek combo chip (MTK Kobos:
--- Clara BW / Colour, Libra Colour).
---
--- Bluetooth and Wi-Fi share one chip driven by the WMT driver. The plugin used
--- to borrow Wi-Fi for Bluetooth by running KOReader's detached
--- restore-wifi-async.sh (driver, wpa_supplicant, a 15 s association wait and
--- DHCP) and then calling NetworkMgr:turnOffWifi() underneath it. Measured on
--- a Clara BW, Bluetooth needs none of it: BluedroidManager1.On() powers the
--- chip itself when both functions are off. The chip power-on handshake that
--- enable-wifi.sh performs before starting wpa_supplicant is kept only as a
--- fallback for firmwares where a cold On() fails (upstream issue #31).
---
--- This module runs just that handshake (powerOn) and undoes it (powerOff),
--- records across the subprocess boundary that it ran (the marker file), and
--- tells whether anyone else is using Wi-Fi so the plugin never powers the
--- chip off under a connection it does not own.
---
--- It also brings the radio driver up on a boot where nothing has used it yet
--- (loadStack): Nickel loads the WMT kernel modules and starts MediaTek's
--- firmware daemon before it touches the chip, and so must the plugin. Without
--- that, the first power-on of the chip has no firmware to load and the kernel
--- panics (measured on a Clara BW with Wi-Fi and Bluetooth off in Nickel). The
--- Bluetooth daemon itself loads nothing, and any D-Bus call to it starts it,
--- so nothing may talk to it before the stack is loaded.

local NetworkMgr = require("ui/network/manager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local WmtPower = {}

--- Character device of the WMT Wi-Fi function; exists once the WMT modules are loaded.
WmtPower.WIFI_CONTROL_DEVICE = "/dev/wmtWifi"

--- Directory of wpa_supplicant's control sockets; a socket named after the
--- interface exists while wpa_supplicant runs.
WmtPower.WPA_SUPPLICANT_SOCKET_DIR = "/var/run/wpa_supplicant"

--- The chip power-on sequence from KOReader's enable-wifi.sh ("wmt" branch):
--- unlock the WMT debug interface, toggle the loopback test (which blocks
--- for about 1.3 s while the chip comes up), then switch the Wi-Fi function on.
--- Blocks for about 2.5 s; run it in a subprocess.
WmtPower.COMMAND_POWER_ON = table.concat({
    'echo "0xDB9DB9" >/proc/driver/wmt_dbg',
    'echo "7 9 0" >/proc/driver/wmt_dbg',
    "sleep 1",
    'echo "0xDB9DB9" >/proc/driver/wmt_dbg',
    'echo "7 9 1" >/proc/driver/wmt_dbg',
    "echo 1 >/dev/wmtWifi",
}, " && ")

--- Switches the Wi-Fi function off again (what disable-wifi.sh does on MTK).
WmtPower.COMMAND_POWER_OFF = "echo 0 >/dev/wmtWifi"

--- Character device of the WMT Bluetooth function; exists once the WMT modules are loaded.
WmtPower.BT_DEVICE = "/dev/stpbt"

--- Kernel modules of the radio, in the order Nickel loads them. wmt_drv is
--- inserted by hand; wmt_loader inserts the others after detecting the chip.
WmtPower.MODULES = { "wmt_drv", "wmt_chrdev_wifi", "wmt_cdev_bt", "wlan_drv_gen4m" }

--- MediaTek's chip detection and module loader (exits when done).
WmtPower.WMT_LOADER = "/usr/bin/wmt_loader"

--- MediaTek's firmware daemon: serves the firmware patches to the driver when a
--- function is powered on. Stays running.
WmtPower.WMT_LAUNCHER = "/usr/bin/wmt_launcher"

--- Where the firmware patches live (the launcher's -p argument).
WmtPower.FIRMWARE_DIR = "/lib/firmware"

--- Time for the launcher to bring the connectivity subsystem up before the
--- first power-on handshake.
WmtPower.LAUNCHER_SETTLE_SECONDS = 3

--- Marker file the enable subprocess creates when it ran the handshake, so the
--- plugin (a different process) knows it has a Wi-Fi function to release.
WmtPower.POWERED_MARKER = "/tmp/kobo.koplugin-wmt-powered"
WmtPower.COMMAND_MARK_POWERED = "touch " .. WmtPower.POWERED_MARKER
WmtPower.COMMAND_CLEAR_POWERED = "rm -f " .. WmtPower.POWERED_MARKER

---
--- Whether the WMT Wi-Fi control device exists on this device.
--- @return boolean
function WmtPower.isAvailable()
    return lfs.attributes(WmtPower.WIFI_CONTROL_DEVICE, "mode") ~= nil
end

---
--- Whether the radio driver is loaded (the Bluetooth device node exists).
--- False on a boot where neither Nickel nor KOReader has used Wi-Fi or
--- Bluetooth yet.
--- @return boolean
function WmtPower.isStackLoaded()
    return lfs.attributes(WmtPower.BT_DEVICE, "mode") ~= nil
end

---
--- Directory of the radio's kernel modules for this platform (PLATFORM is
--- exported by koreader.sh).
--- @return string
function WmtPower.moduleDir()
    return "/drivers/" .. (os.getenv("PLATFORM") or "") .. "/mt66xx"
end

---
--- The shell command that brings the radio driver up the way Nickel does:
--- insert wmt_drv, run wmt_loader (detects the chip and inserts the other
--- modules), insert any module it left out, start the firmware daemon detached
--- from the onboard storage and from KOReader's log, then give it time.
--- @return string
function WmtPower.loadStackCommand()
    local dir = WmtPower.moduleDir()
    local others = {}

    for i = 2, #WmtPower.MODULES do
        table.insert(others, WmtPower.MODULES[i])
    end

    return table.concat({
        string.format('grep -q "^wmt_drv " /proc/modules || { insmod %s/wmt_drv.ko; usleep 250000; }', dir),
        WmtPower.WMT_LOADER .. " >/dev/null 2>&1",
        string.format(
            'for m in %s; do grep -q "^$m " /proc/modules || { insmod %s/$m.ko; usleep 250000; }; done',
            table.concat(others, " "),
            dir
        ),
        string.format(
            "cd / && setsid %s -p %s >/dev/null 2>&1 </dev/null &",
            WmtPower.WMT_LAUNCHER,
            WmtPower.FIRMWARE_DIR
        ),
        "sleep " .. WmtPower.LAUNCHER_SETTLE_SECONDS,
    }, "; ")
end

---
--- Brings the radio driver up (see loadStackCommand). Blocks for several
--- seconds: call it from a subprocess, and before anything talks to the
--- Bluetooth daemon over D-Bus.
--- @return boolean True if the command sequence succeeded
function WmtPower.loadStack()
    logger.info("WmtPower: loading the radio driver and starting the firmware daemon")

    local result = os.execute(WmtPower.loadStackCommand())

    if result ~= 0 then
        logger.warn("WmtPower: loading the radio driver failed with exit code:", result)

        return false
    end

    return true
end

---
--- Powers the Wi-Fi function of the combo chip on and leaves the marker for
--- the plugin process. No wpa_supplicant, no association, no DHCP. Blocks
--- for about 2.5 s: call it from a subprocess.
--- @return boolean True if the command sequence succeeded
function WmtPower.powerOn()
    logger.info("WmtPower: powering the Wi-Fi function on for Bluetooth")

    os.execute(WmtPower.COMMAND_MARK_POWERED)

    local result = os.execute(WmtPower.COMMAND_POWER_ON)

    if result ~= 0 then
        logger.warn("WmtPower: power-on sequence failed with exit code:", result)

        return false
    end

    return true
end

---
--- Whether the enable subprocess powered the Wi-Fi function (marker present).
--- @return boolean
function WmtPower.wasPoweredForBluetooth()
    return lfs.attributes(WmtPower.POWERED_MARKER, "mode") ~= nil
end

---
--- Forgets that the Wi-Fi function was powered for Bluetooth (removes the marker).
function WmtPower.clearPoweredForBluetooth()
    os.execute(WmtPower.COMMAND_CLEAR_POWERED)
end

---
--- Powers the Wi-Fi function of the combo chip off. Bluetooth keeps its own
--- reference on the chip, so it keeps working.
--- @return boolean True if the command succeeded
function WmtPower.powerOff()
    logger.info("WmtPower: powering the Wi-Fi function off")

    local result = os.execute(WmtPower.COMMAND_POWER_OFF)

    if result ~= 0 then
        logger.warn("WmtPower: power-off failed with exit code:", result)

        return false
    end

    return true
end

---
--- Whether something other than this plugin is using Wi-Fi now: a connection
--- attempt or connectivity check tracked by NetworkMgr, an established
--- connection, or a running wpa_supplicant (a foreign restore script that
--- bypassed NetworkMgr). Whoever started it will tear it down.
--- @return boolean in_use
--- @return string|nil reason Human-readable reason when in use
function WmtPower.isWifiInUse()
    if NetworkMgr.pending_connection then
        return true, "a Wi-Fi connection attempt is pending"
    end

    if NetworkMgr.pending_connectivity_check then
        return true, "a Wi-Fi connectivity check is pending"
    end

    if NetworkMgr:isConnected() then
        return true, "Wi-Fi is connected"
    end

    local interface = NetworkMgr.interface or "wlan0"
    local socket = WmtPower.WPA_SUPPLICANT_SOCKET_DIR .. "/" .. interface

    if lfs.attributes(socket, "mode") == "socket" then
        return true, "wpa_supplicant is running"
    end

    return false
end

return WmtPower
