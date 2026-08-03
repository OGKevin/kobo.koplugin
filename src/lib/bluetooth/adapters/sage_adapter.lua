---
--- Sage (Kobo_cadmus) chip-specific BlueZ bring-up (Realtek RTL8821C on ttyS1).
--- Shared org.bluez operations live in bluez_adapter.
--- Bring-up matches Nickel / Tharavol bluetooth.koplugin: rfkill cycle +
--- resident rtk_hciattach, then bluetoothd.

local BlueZAdapter = require("src/lib/bluetooth/adapters/bluez_adapter")

local RFKILL_STATE = "/sys/devices/platform/bt/rfkill/rfkill0/state"

---
--- Full teardown then rebuild. Soft warm starts often leave hci0 attached-but-DOWN;
--- rfkill off/on before rtk_hciattach recovers the UART chip reliably.
local COMMANDS_ON = {
    "killall rtk_hciattach 2>/dev/null; killall bluetoothd 2>/dev/null; " .. "hciconfig hci0 down 2>/dev/null; true",
    "echo 0 > " .. RFKILL_STATE,
    "sleep 1",
    "echo 1 > " .. RFKILL_STATE,
    "/sbin/rtk_hciattach -n -s 115200 /dev/ttyS1 rtk_h5 > /var/log/rtk_hciattach.log 2>&1 &",
    "sleep 2",
    "hciconfig hci0 up",
    "setsid /libexec/bluetooth/bluetoothd -n -d > /var/log/bluetoothd.log 2>&1 &",
    "i=0; while [ $i -lt 50 ] && ! dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
        .. "org.freedesktop.DBus.Properties.Get string:org.bluez.Adapter1 string:Powered "
        .. ">/dev/null 2>&1; do sleep 0.1; i=$((i+1)); done",
    "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
        .. "org.freedesktop.DBus.Properties.Set "
        .. "string:org.bluez.Adapter1 string:Powered variant:boolean:true",
    "hciconfig hci0 2>/dev/null | grep -q 'UP RUNNING'",
}

---
--- Powered=false then kill UART attach + bluetoothd and cut rfkill power.
local COMMANDS_OFF = {
    "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
        .. "org.freedesktop.DBus.Properties.Set "
        .. "string:org.bluez.Adapter1 string:Powered variant:boolean:false",
    "killall bluetoothd 2>/dev/null; killall rtk_hciattach 2>/dev/null; "
        .. "i=0; while [ $i -lt 30 ] && (pgrep bluetoothd >/dev/null || pgrep rtk_hciattach >/dev/null); "
        .. "do sleep 0.1; i=$((i+1)); done; "
        .. "echo 0 > "
        .. RFKILL_STATE
        .. "; true",
}

return BlueZAdapter:new({
    name = "Sage",
    COMMANDS_ON = COMMANDS_ON,
    COMMANDS_OFF = COMMANDS_OFF,
})
