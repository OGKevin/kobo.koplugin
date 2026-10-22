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
---
--- Everything here is done from Lua, step by step and logged; the shell is
--- used only where a binary has to run (insmod, wmt_loader) or a daemon has
--- to be started detached (wmt_launcher).

local NetworkMgr = require("ui/network/manager")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local WmtPower = {}

--- Character device of the WMT Wi-Fi function; exists once the WMT modules are loaded.
WmtPower.WIFI_CONTROL_DEVICE = "/dev/wmtWifi"

--- Character device of the WMT Bluetooth function; exists once the WMT modules are loaded.
WmtPower.BT_DEVICE = "/dev/stpbt"

--- Debug interface of the WMT driver, used by the power-on handshake.
WmtPower.WMT_DEBUG_FILE = "/proc/driver/wmt_dbg"

--- Where the kernel lists the loaded modules.
WmtPower.MODULES_FILE = "/proc/modules"

--- Where the kernel lists processes (used to find the firmware daemon).
WmtPower.PROC_DIR = "/proc"

--- Directory of wpa_supplicant's control sockets; a socket named after the
--- interface exists while wpa_supplicant runs.
WmtPower.WPA_SUPPLICANT_SOCKET_DIR = "/var/run/wpa_supplicant"

--- The chip power-on handshake, taken from the "wmt" branch of KOReader's
--- platform/kobo/enable-wifi.sh
--- (https://github.com/koreader/koreader/blob/v2026.07.1/platform/kobo/enable-wifi.sh):
--- unlock the WMT debug interface, switch the loopback test off, wait a
--- second, unlock again and switch it on (this blocks for about 1.3 s while
--- the chip comes up). Each entry is one write to WMT_DEBUG_FILE; a number is
--- a pause in seconds.
WmtPower.HANDSHAKE = { "0xDB9DB9", "7 9 0", 1, "0xDB9DB9", "7 9 1" }

--- Values written to WIFI_CONTROL_DEVICE to switch the Wi-Fi function on and
--- off (what enable-wifi.sh and disable-wifi.sh do on MTK,
--- https://github.com/koreader/koreader/blob/v2026.07.1/platform/kobo/disable-wifi.sh).
WmtPower.WIFI_FUNCTION_ON = "1"
WmtPower.WIFI_FUNCTION_OFF = "0"

--- Kernel modules of the radio, in the order Nickel loads them. wmt_drv is
--- inserted by hand; wmt_loader inserts the others after detecting the chip.
WmtPower.MODULES = { "wmt_drv", "wmt_chrdev_wifi", "wmt_cdev_bt", "wlan_drv_gen4m" }

--- Pause after inserting a module, as enable-wifi.sh does (usleep 250000).
--- ffi/util's sleep() is C sleep(), whole seconds only, hence usleep here.
WmtPower.MODULE_SETTLE_MICROSECONDS = 250000

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

--- Marker file the enable subprocess creates once loadStack and the handshake
--- are done, so the plugin process knows the daemon may be contacted. /tmp is
--- cleared at boot, which is exactly the lifetime of the stack.
WmtPower.STACK_READY_MARKER = "/tmp/kobo.koplugin-wmt-stack-ready"

--- Marker file the enable subprocess creates when it ran the handshake, so the
--- plugin (a different process) knows it has a Wi-Fi function to release.
WmtPower.POWERED_MARKER = "/tmp/kobo.koplugin-wmt-powered"

--- True while this process is bringing the stack up in a subprocess: the daemon
--- must not be contacted until the subprocess has left STACK_READY_MARKER, even
--- though the device nodes appear a second into the bring-up.
WmtPower.bringing_up = false

---
--- Writes a string to a file (a sysfs/procfs control file or a marker).
--- Writes are buffered: a value the kernel rejects (EINVAL, EIO) only
--- surfaces when the buffer is flushed, which happens in close(), so the
--- result of close() counts as much as the result of write().
--- @param path string
--- @param text string
--- @return boolean True if the file could be opened, written and closed
local function writeFile(path, text)
    local file, err = io.open(path, "w")

    if not file then
        logger.warn("WmtPower: cannot open", path, "for writing:", err)

        return false
    end

    local written, write_err = file:write(text)
    local closed, close_err = file:close()

    if not written or not closed then
        logger.warn("WmtPower: writing", text, "to", path, "failed:", write_err or close_err)

        return false
    end

    return true
end

---
--- Reads a whole file.
--- @param path string
--- @return string|nil Content, or nil if the file cannot be opened
local function readFile(path)
    local file = io.open(path, "r")

    if not file then
        return nil
    end

    local content = file:read("*a")
    file:close()

    return content
end

---
--- Whether the WMT Wi-Fi control device exists on this device.
--- @return boolean
function WmtPower.isAvailable()
    return lfs.attributes(WmtPower.WIFI_CONTROL_DEVICE, "mode") ~= nil
end

---
--- Whether a kernel module is loaded, read from MODULES_FILE.
--- @param name string Module name
--- @return boolean
function WmtPower.isModuleLoaded(name)
    local modules = readFile(WmtPower.MODULES_FILE) or ""

    return modules:find("^" .. name .. " ") ~= nil or modules:find("\n" .. name .. " ") ~= nil
end

---
--- Directory of the radio's kernel modules for this platform. PLATFORM is
--- exported by KOReader's platform/kobo/koreader.sh
--- (https://github.com/koreader/koreader/blob/v2026.07.1/platform/kobo/koreader.sh).
--- @return string
function WmtPower.moduleDir()
    return "/drivers/" .. (os.getenv("PLATFORM") or "") .. "/mt66xx"
end

---
--- Inserts a kernel module of the radio and lets it settle.
--- @param name string Module name
--- @return boolean True if insmod succeeded
function WmtPower.insertModule(name)
    local command = string.format("insmod %s/%s.ko", WmtPower.moduleDir(), name)
    logger.info("WmtPower: inserting module", name)

    local result = os.execute(command)

    if result ~= 0 then
        logger.warn("WmtPower: insmod", name, "failed with exit code:", result)

        return false
    end

    ffiutil.usleep(WmtPower.MODULE_SETTLE_MICROSECONDS)

    return true
end

---
--- Runs MediaTek's loader, which detects the chip and inserts the remaining
--- modules. Its exit status is only logged: on the Clara BW it exits with 255
--- after loading everything, so loadStack checks the module list instead.
function WmtPower.runLoader()
    logger.info("WmtPower: running", WmtPower.WMT_LOADER)

    local result = os.execute(WmtPower.WMT_LOADER .. " >/dev/null 2>&1")
    logger.info("WmtPower:", WmtPower.WMT_LOADER, "exited with status", result)
end

---
--- Whether MediaTek's firmware daemon is running, found by reading the
--- command lines under PROC_DIR.
--- @return boolean
function WmtPower.isLauncherRunning()
    local ok, iterator, state = pcall(lfs.dir, WmtPower.PROC_DIR)

    if not ok then
        return false
    end

    for entry in iterator, state do
        if entry:match("^%d+$") then
            local cmdline = readFile(WmtPower.PROC_DIR .. "/" .. entry .. "/cmdline") or ""
            local executable = cmdline:match("^[^%z]*") or ""

            if executable == WmtPower.WMT_LAUNCHER then
                return true
            end
        end
    end

    return false
end

---
--- The shell command that starts the firmware daemon detached: its own
--- session, working directory off the onboard partition, no inherited
--- standard streams, so neither USB mass storage nor KOReader's log is held.
--- @return string
function WmtPower.launcherCommand()
    return string.format(
        "cd /tmp && setsid %s -p %s >/dev/null 2>&1 </dev/null &",
        WmtPower.WMT_LAUNCHER,
        WmtPower.FIRMWARE_DIR
    )
end

---
--- Starts the firmware daemon (see launcherCommand) and gives it time to bring
--- the connectivity subsystem up.
--- @return boolean True if the shell accepted the command
function WmtPower.startLauncher()
    logger.info("WmtPower: starting", WmtPower.WMT_LAUNCHER)

    local result = os.execute(WmtPower.launcherCommand())

    if result ~= 0 then
        logger.warn("WmtPower: starting", WmtPower.WMT_LAUNCHER, "failed with exit code:", result)

        return false
    end

    ffiutil.sleep(WmtPower.LAUNCHER_SETTLE_SECONDS)

    return true
end

---
--- Brings the radio driver up the way Nickel does: insert wmt_drv, run
--- wmt_loader, insert any module it left out, start the firmware daemon
--- unless one is running. Blocks for several seconds: call it from a
--- subprocess, and before anything talks to the Bluetooth daemon over D-Bus.
--- @return boolean True if every module is loaded and the daemon was started or found
function WmtPower.loadStack()
    logger.info("WmtPower: loading the radio driver and starting the firmware daemon")

    local first = WmtPower.MODULES[1]

    if not WmtPower.isModuleLoaded(first) and not WmtPower.insertModule(first) then
        return false
    end

    WmtPower.runLoader()

    for i = 2, #WmtPower.MODULES do
        local name = WmtPower.MODULES[i]

        if not WmtPower.isModuleLoaded(name) then
            logger.info("WmtPower:", WmtPower.WMT_LOADER, "did not insert", name)
            WmtPower.insertModule(name)
        end
    end

    for _, name in ipairs(WmtPower.MODULES) do
        if not WmtPower.isModuleLoaded(name) then
            logger.warn("WmtPower: module", name, "is still not loaded")

            return false
        end
    end

    if WmtPower.isLauncherRunning() then
        logger.info("WmtPower:", WmtPower.WMT_LAUNCHER, "is already running")

        return true
    end

    return WmtPower.startLauncher()
end

---
--- Runs the power-on handshake (see HANDSHAKE), then switches the Wi-Fi
--- function on. No wpa_supplicant, no association, no DHCP. Blocks for about
--- 2.5 s: call it from a subprocess. Leaves POWERED_MARKER first, so the
--- plugin process releases the function even if this subprocess is cut short.
--- @return boolean True if every write succeeded
function WmtPower.powerOn()
    logger.info("WmtPower: powering the Wi-Fi function on for Bluetooth")

    WmtPower.markPowered()

    for _, step in ipairs(WmtPower.HANDSHAKE) do
        if type(step) == "number" then
            ffiutil.sleep(step)
        elseif not writeFile(WmtPower.WMT_DEBUG_FILE, step) then
            return false
        end
    end

    return writeFile(WmtPower.WIFI_CONTROL_DEVICE, WmtPower.WIFI_FUNCTION_ON)
end

---
--- Switches the Wi-Fi function of the combo chip off. Bluetooth keeps its own
--- reference on the chip, so it keeps working.
--- @return boolean True if the write succeeded
function WmtPower.powerOff()
    logger.info("WmtPower: powering the Wi-Fi function off")

    return writeFile(WmtPower.WIFI_CONTROL_DEVICE, WmtPower.WIFI_FUNCTION_OFF)
end

---
--- Records that this subprocess powered the Wi-Fi function (see POWERED_MARKER).
--- @return boolean True if the marker was written
function WmtPower.markPowered()
    return writeFile(WmtPower.POWERED_MARKER, "")
end

---
--- Whether the enable subprocess powered the Wi-Fi function (marker present).
--- @return boolean
function WmtPower.wasPoweredForBluetooth()
    return lfs.attributes(WmtPower.POWERED_MARKER, "mode") ~= nil
end

---
--- Forgets that the Wi-Fi function was powered for Bluetooth (removes the marker).
--- @return boolean True if the marker is gone
function WmtPower.clearPoweredForBluetooth()
    local ok, err = os.remove(WmtPower.POWERED_MARKER)

    if not ok and lfs.attributes(WmtPower.POWERED_MARKER, "mode") then
        logger.warn("WmtPower: cannot remove", WmtPower.POWERED_MARKER, ":", err)

        return false
    end

    return true
end

---
--- Records that loadStack and the handshake are done (see STACK_READY_MARKER).
--- @return boolean True if the marker was written
function WmtPower.markStackReady()
    return writeFile(WmtPower.STACK_READY_MARKER, "")
end

---
--- Whether the radio stack is up, so the Bluetooth daemon may be contacted:
--- either this plugin brought it up (marker present), or someone else did,
--- which shows as the device node plus a running firmware daemon (Nickel
--- starts one whenever it uses the radio). False on a boot where neither
--- Nickel nor KOReader has used Wi-Fi or Bluetooth yet, and false while this
--- process is in the middle of bringing the stack up. The stack never goes
--- away within a boot, so a positive answer is recorded in the marker and
--- the process scan runs at most once per boot.
--- @return boolean
function WmtPower.isStackLoaded()
    if lfs.attributes(WmtPower.STACK_READY_MARKER, "mode") then
        return true
    end

    if WmtPower.bringing_up then
        return false
    end

    if lfs.attributes(WmtPower.BT_DEVICE, "mode") ~= nil and WmtPower.isLauncherRunning() then
        WmtPower.markStackReady()

        return true
    end

    return false
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
