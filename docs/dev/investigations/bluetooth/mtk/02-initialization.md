# Bluetooth Initialization

## D-Bus Auto-Activation Sequence

Analysis of Nickel's Bluetooth initialization (strace output, 7678 lines) revealed the exact D-Bus
sequence used.

### Timeline

```
15:18:19.863567 - Nickel calls BluedroidManager1.On()
                  Service doesn't exist, D-Bus queues the call

15:18:19.947362 - D-Bus auto-starts service (84ms later)
                  NameOwnerChanged: com.kobo.mtk.bluedroid → :1.2

15:18:22.986149 - Bluetooth adapter ready (3.1 seconds after start)
                  InterfacesAdded: /org/bluez/hci0 with org.bluez.Adapter1
```

**Key Finding:** A single D-Bus method call (`BluedroidManager1.On()`) triggers the entire
initialization sequence via D-Bus auto-activation.

## Initialization Commands

### Full Initialization Script

```bash
#!/usr/bin/env bash
# Enable Bluetooth on Kobo

echo "Step 1: Call On() method - triggers D-Bus auto-activation (this command blocks until initialization is complete)"
dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    / \
    com.kobo.bluetooth.BluedroidManager1.On

# No need to wait after On(); the command only returns when initialization is done

echo "Step 2: Power on the adapter"
dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    /org/bluez/hci0 \
    org.freedesktop.DBus.Properties.Set \
    string:org.bluez.Adapter1 \
    string:Powered \
    variant:boolean:true

echo "Step 3: Verify adapter is powered"
dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    /org/bluez/hci0 \
    org.freedesktop.DBus.Properties.Get \
    string:org.bluez.Adapter1 \
    string:Powered
```

### Critical Notes

1. **Use `com.kobo.mtk.bluedroid`** as destination for all D-Bus calls, not `org.bluez`
2. **Auto-activation** - D-Bus starts the service automatically when the method is called
3. The object paths still use `/org/bluez/hci0` but the service name is `com.kobo.mtk.bluedroid`

### Verification

```bash
# Check if processes started
ps aux | grep -E "(mtkbtd|btservice)" | grep -v grep

# Check if service is registered
dbus-send --system --print-reply \
    --dest=org.freedesktop.DBus \
    /org/freedesktop/DBus \
    org.freedesktop.DBus.ListNames | grep "com.kobo.mtk.bluedroid"

# Check adapter properties
dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    /org/bluez/hci0 \
    org.freedesktop.DBus.Properties.GetAll \
    string:org.bluez.Adapter1
```

## WiFi Dependency

Bluetooth (`wmt_cdev_bt`, `/dev/stpbt`) and WiFi (`wlan_drv_gen4m`, `/dev/wmtWifi`) are two
functions of one MediaTek combo chip, both behind the WMT driver (`wmt_drv`). The modules are loaded
once at boot and never unloaded (`disable-wifi.sh` skips the unload on MTK). When no function is on,
the driver powers the chip off; the first function to come on powers it up again.

The plugin used to "borrow" WiFi before calling `BluedroidManager1.On()`: it ran KOReader's detached
`restore-wifi-async.sh` (driver handshake, `wpa_supplicant`, up to 15 s of association wait, DHCP)
and then called `NetworkMgr:turnOffWifi()` underneath it about 3 s later. Bluetooth does not need
the connection. What `enable-wifi.sh` does on MTK beyond starting `wpa_supplicant` is the chip
power-on handshake:

```bash
echo "0xDB9DB9" >/proc/driver/wmt_dbg   # unlock the WMT debug interface
echo "7 9 0" >/proc/driver/wmt_dbg      # loopback test off
sleep 1
echo "0xDB9DB9" >/proc/driver/wmt_dbg
echo "7 9 1" >/proc/driver/wmt_dbg      # loopback test on (blocks ~1.3 s while the chip comes up)
echo 1 >/dev/wmtWifi                    # WiFi function on
```

and `disable-wifi.sh` undoes it with `echo 0 >/dev/wmtWifi`. `src/lib/bluetooth/wmt_power.lua` runs
exactly this pair.

What the logs show (Kobo Clara BW, KOReader v2026.07.1):

- `On()` was issued about 1 s after the restore script started, i.e. before the script's
  `echo 1 >/dev/wmtWifi` (the handshake takes about 2.5 s), and the adapter reported Powered 2 s
  later. `On()` therefore does not wait for the WiFi function.
- Bluetooth keeps working after the WiFi function is switched off again (the plugin does that on
  every wake, and remotes keep turning pages): Bluetooth holds its own reference on the chip.
- The orphaned restore script carried on in its `wpa_cli` loop with the driver gone, and after 15 s
  ran `disable-wifi.sh` itself, taking down WiFi that another plugin had brought up meanwhile.

Measured on 2026-10-12 (Kobo Clara BW, kernel 4.9.77, KOReader v2026.07.1): with the WiFi function
switched off (`wlan0` gone) and Bluetooth off, so that the WMT driver had powered the chip down,
`BluedroidManager1.On()` followed by `Powered=true` brought the adapter up in about 1 s, three times
out of three, with no handshake and nothing else touched. `mtkbtd` and `btservice` keep running
across `On()`/`Off()`. A cold `On()` therefore powers the chip by itself on this firmware.

The plugin consequently does no WiFi handling at all in the normal case. It keeps the handshake only
as a fallback: if `On()` fails while WiFi is off and nobody is bringing it up, the same subprocess
runs the handshake, leaves a marker file (`/tmp/kobo.koplugin-wmt-powered`) and calls `On()` again;
the plugin process then switches the WiFi function off once the adapter is up. Upstream issue #31
reported intermittent failures after wake that this fallback is meant to cover on other firmwares.

Ownership rule: the plugin switches the WiFi function off only when it powered it on itself and
nothing else is using WiFi at that moment (`NetworkMgr.pending_connection`,
`NetworkMgr.pending_connectivity_check`, `NetworkMgr:isConnected()`, or a running `wpa_supplicant`).
WiFi brought up through `NetworkMgr` is never turned off by the plugin.

## Cold Boot: Nothing Has Used the Radio Yet

The measurement above covers a chip that had been powered once since boot (by Nickel, or by an
earlier Wi-Fi or Bluetooth use in KOReader). A boot with Wi-Fi and Bluetooth both disabled in
Nickel, KOReader launched straight away, is different (measured 2026-10-17 on the same Clara BW):

- No WMT kernel module is loaded, `/dev/stpbt`, `/dev/wmtWifi` and `/dev/stpwmt` do not exist, and
  no Bluetooth daemon runs. Kobo's boot scripts load nothing; Nickel's Bluetooth manager does it on
  demand.
- Any D-Bus call to `com.kobo.mtk.bluedroid` makes D-Bus start `mtkbtd` on the spot, with no driver
  under it. `mtkbtd` loads nothing itself (it only spawns `btservice`).
- Loading the modules and running the `enable-wifi.sh` handshake is not enough: the first power-on
  then panics the kernel and the device reboots, with or without the daemon around.

What Nickel does (`MTK.cpp` in `libnickel`, visible in its strings) is:

```bash
insmod /drivers/${PLATFORM}/mt66xx/wmt_drv.ko
/usr/bin/wmt_loader                      # detects the chip, inserts the other three modules, exits
/usr/bin/wmt_launcher -p /lib/firmware & # firmware daemon: serves soc2_1_ram_{bt,wifi,mcu} patches
# then the wmt_dbg handshake and echo 1 >/dev/wmtWifi, as in enable-wifi.sh
```

With that order the chip comes up (`enter power on connsys flow` in the launcher's output), the
handshake succeeds, `On()` takes about 3 s, and Bluetooth keeps working after the Wi-Fi function is
switched off. The launcher is the missing piece: without it the power-on has no firmware to load.

The plugin therefore treats a missing `/dev/stpbt` as "first use since boot": every D-Bus command in
the MTK adapter does nothing while the node is missing (so the daemon is never started early, not
even by the paired-device listing at plugin init), and `turnBluetoothOn()` runs
`WmtPower.loadStack()` (the sequence above, the launcher detached from the onboard storage so USB
mass storage keeps working) and the handshake in its subprocess before the first `On()`. Enabling
takes about 12 s in that case instead of 2 s; later enables in the same boot are unaffected.

For other plugins: `KoboBluetooth.wifi_borrowed` (a field of `src/kobo_bluetooth.lua`) is true while
the plugin may still power the WiFi function for Bluetooth, and the `BluetoothWifiReleased` event is
broadcast when it lets go. A plugin that wants WiFi right after a wake-up can wait for that event
instead of racing the Bluetooth enable.
