---
--- Libra 2-specific D-Bus adapter for Bluetooth control.
--- Implements the DbusAdapterInterface for Kobo Libra 2 using standard BlueZ.
--- Handles the Realtek RTL8723D chip: the SDIO power-rail kernel module, the
--- HCI UART attach and the daemon lifecycle.
--- The org.bluez D-Bus operations (power state, discovery, pairing, agents)
--- are shared with every other BlueZ device through BluezAdapter; this module
--- only adds the Realtek chip bring-up and teardown.

local BluezAdapter = require("src/lib/bluetooth/adapters/bluez_adapter")
local Subprocess = require("src/lib/bluetooth/subprocess")
local logger = require("logger")

local Libra2Adapter = setmetatable({ backend = "libra2-bluez" }, { __index = BluezAdapter })

---
--- Command to load the SDIO Bluetooth power-rail kernel module when not yet loaded.
--- @field string
Libra2Adapter.COMMAND_LOAD_POWER_MODULE =
    "grep -q '^sdio_bt_pwr ' /proc/modules || insmod /drivers/mx6sll-ntx/wifi/sdio_bt_pwr.ko"

---
--- Program and arguments to initialize the Realtek RTL8723D HCI UART.
--- @field table
Libra2Adapter.HCIATTACH_ARGV = {
    "/sbin/rtk_hciattach",
    "-s",
    "115200",
    "ttymxc1",
    "rtk_h5",
}

---
--- Program and arguments for the BlueZ daemon.
--- @field table
Libra2Adapter.BLUETOOTHD_ARGV = {
    "/libexec/bluetooth/bluetoothd",
}

---
--- Wait for bluetoothd to enumerate hci0 on D-Bus (BlueZ only exposes Adapter1
--- once it notices the new HCI device), then set Powered=true.
--- @field table Array of D-Bus shell commands run after the daemons are up.
Libra2Adapter.COMMANDS_ON = {
    "i=0; while [ $i -lt 50 ] && ! dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
        .. "org.freedesktop.DBus.Properties.Get string:org.bluez.Adapter1 string:Powered "
        .. ">/dev/null 2>&1; do sleep 0.1; i=$((i+1)); done",
    BluezAdapter.COMMAND_SET_POWERED_ON,
}

---
--- Graceful Powered=false (so peers see a clean disconnect), then a full
--- chip power-cycle: a soft power-off leaves rtk_hciattach holding the UART
--- and the chip wedged against the next bringup. Wait for both daemons to
--- exit before rmmod so the next ON doesn't race a dying bluetoothd for
--- the org.bluez D-Bus name.
--- @field table Array of shell commands run in sequence.
Libra2Adapter.COMMANDS_OFF = {
    BluezAdapter.COMMAND_SET_POWERED_OFF,
    "killall bluetoothd 2>/dev/null; killall rtk_hciattach 2>/dev/null; "
        .. "i=0; while [ $i -lt 30 ] && (pgrep bluetoothd >/dev/null || pgrep rtk_hciattach >/dev/null); "
        .. "do sleep 0.1; i=$((i+1)); done; "
        .. "rmmod sdio_bt_pwr 2>/dev/null; true",
}

---
--- Turns Bluetooth on: loads the power-rail driver, launches rtk_hciattach and
--- bluetoothd detached from onboard storage when not already running, and sets
--- Powered=true over D-Bus once hci0 is registered.
--- @return boolean True if successful, false otherwise.
function Libra2Adapter.turnOn()
    logger.info("Libra2Adapter: Turning Bluetooth ON")

    if not Libra2Adapter.executeCommands({ Libra2Adapter.COMMAND_LOAD_POWER_MODULE }) then
        return false
    end

    if not Subprocess.isProcessRunning(Libra2Adapter.HCIATTACH_ARGV[1]) then
        if not Subprocess.runDetached(Libra2Adapter.HCIATTACH_ARGV) then
            logger.warn("Libra2Adapter: Failed to attach HCI UART")

            return false
        end
    end

    if not Subprocess.isProcessRunning(Libra2Adapter.BLUETOOTHD_ARGV[1]) then
        if not Subprocess.startDaemon(Libra2Adapter.BLUETOOTHD_ARGV) then
            logger.warn("Libra2Adapter: Failed to start bluetoothd")

            return false
        end
    end

    return Libra2Adapter.executeCommands(Libra2Adapter.COMMANDS_ON)
end

---
--- Turns Bluetooth off via D-Bus commands.
--- @return boolean True if successful, false otherwise.
function Libra2Adapter.turnOff()
    logger.info("Libra2Adapter: Turning Bluetooth OFF")

    return Libra2Adapter.executeCommands(Libra2Adapter.COMMANDS_OFF)
end

return Libra2Adapter
