---
--- Power control for the Wi-Fi function of the MediaTek combo chip (MTK Kobos:
--- Clara BW / Colour, Libra Colour).
---
--- Bluetooth and Wi-Fi share one chip driven by the WMT driver. The plugin used
--- to borrow Wi-Fi for Bluetooth by running KOReader's detached
--- restore-wifi-async.sh (driver, wpa_supplicant, a 15 s association wait and
--- DHCP) and then calling NetworkMgr:turnOffWifi() underneath it. Bluetooth
--- needs none of the connection: only the chip power-on handshake that
--- enable-wifi.sh performs before it starts wpa_supplicant.
---
--- This module runs just that handshake (powerOn) and undoes it (powerOff),
--- and it tells whether anyone else is using Wi-Fi so the plugin never powers
--- the chip off under a connection it does not own.

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

---
--- Whether the WMT Wi-Fi control device exists on this device.
--- @return boolean
function WmtPower.isAvailable()
    return lfs.attributes(WmtPower.WIFI_CONTROL_DEVICE, "mode") ~= nil
end

---
--- Powers the Wi-Fi function of the combo chip on. No wpa_supplicant, no
--- association, no DHCP. Blocks for about 2.5 s: call it from a subprocess.
--- @return boolean True if the command sequence succeeded
function WmtPower.powerOn()
    logger.info("WmtPower: powering the Wi-Fi function on for Bluetooth")

    local result = os.execute(WmtPower.COMMAND_POWER_ON)

    if result ~= 0 then
        logger.warn("WmtPower: power-on sequence failed with exit code:", result)

        return false
    end

    return true
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
