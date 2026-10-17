---
--- Libra 2 chip-specific BlueZ bring-up (Realtek RTL8723D on i.MX6 / ttymxc1).
--- Shared org.bluez operations live in bluez_adapter.

local BlueZAdapter = require("src/lib/bluetooth/adapters/bluez_adapter")

---
--- Bring the Realtek RTL8723D up and the BlueZ adapter to Powered=true.
--- Chip-init (insmod, rtk_hciattach) is idempotent on warm starts. The
--- poll waits for bluetoothd to enumerate hci0 on D-Bus before the Set,
--- since BlueZ only exposes Adapter1 once it's noticed the new HCI device.
local COMMANDS_ON = {
    "grep -q '^sdio_bt_pwr ' /proc/modules || insmod /drivers/mx6sll-ntx/wifi/sdio_bt_pwr.ko",
    "pgrep rtk_hciattach >/dev/null || /sbin/rtk_hciattach -s 115200 ttymxc1 rtk_h5 >/dev/null 2>&1",
    "/libexec/bluetooth/bluetoothd &",
    "i=0; while [ $i -lt 50 ] && ! dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
        .. "org.freedesktop.DBus.Properties.Get string:org.bluez.Adapter1 string:Powered "
        .. ">/dev/null 2>&1; do sleep 0.1; i=$((i+1)); done",
    "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
        .. "org.freedesktop.DBus.Properties.Set "
        .. "string:org.bluez.Adapter1 string:Powered variant:boolean:true",
}

---
--- Graceful Powered=false (so peers see a clean disconnect), then a full
--- chip power-cycle: a soft power-off leaves rtk_hciattach holding the UART
--- and the chip wedged against the next bringup. Wait for both daemons to
--- exit before rmmod so the next ON doesn't race a dying bluetoothd for
--- the org.bluez D-Bus name.
local COMMANDS_OFF = {
    "dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 "
        .. "org.freedesktop.DBus.Properties.Set "
        .. "string:org.bluez.Adapter1 string:Powered variant:boolean:false",
    "killall bluetoothd 2>/dev/null; killall rtk_hciattach 2>/dev/null; "
        .. "i=0; while [ $i -lt 30 ] && (pgrep bluetoothd >/dev/null || pgrep rtk_hciattach >/dev/null); "
        .. "do sleep 0.1; i=$((i+1)); done; "
        .. "rmmod sdio_bt_pwr 2>/dev/null; true",
}

return BlueZAdapter:new({
    name = "Libra2",
    COMMANDS_ON = COMMANDS_ON,
    COMMANDS_OFF = COMMANDS_OFF,
})
