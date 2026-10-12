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

Bluetooth (`wmt_cdev_bt`, `/dev/stpbt`) and WiFi (`wlan_drv_gen4m`, `/dev/wmtWifi`) are two functions
of one MediaTek combo chip, both behind the WMT driver (`wmt_drv`). The modules are loaded once at
boot and never unloaded (`disable-wifi.sh` skips the unload on MTK). When no function is on, the
driver powers the chip off; the first function to come on powers it up again.

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

and `disable-wifi.sh` undoes it with `echo 0 >/dev/wmtWifi`. `src/lib/bluetooth/wmt_power.lua`
runs exactly this pair.

What the logs show (Kobo Clara BW, KOReader v2026.07.1):

- `On()` was issued about 1 s after the restore script started, i.e. before the script's
  `echo 1 >/dev/wmtWifi` (the handshake takes about 2.5 s), and the adapter reported Powered 2 s
  later. `On()` therefore does not wait for the WiFi function.
- Bluetooth keeps working after the WiFi function is switched off again (the plugin does that on
  every wake, and remotes keep turning pages): Bluetooth holds its own reference on the chip.
- The orphaned restore script carried on in its `wpa_cli` loop with the driver gone, and after 15 s
  ran `disable-wifi.sh` itself, taking down WiFi that another plugin had brought up meanwhile.

Whether a cold `On()` (WiFi function off, Bluetooth off, chip powered down) ever fails without the
handshake, as upstream issue #31 reported intermittently, is to be measured on the device with
`BluedroidManager1.On()` alone versus handshake-then-`On()` across several wake-ups. Until then the
plugin runs the handshake first: it costs about 2.5 s and nothing else.

Ownership rule: the plugin switches the WiFi function off only when it powered it on itself and
nothing else is using WiFi at that moment (`NetworkMgr.pending_connection`,
`NetworkMgr.pending_connectivity_check`, `NetworkMgr:isConnected()`, or a running `wpa_supplicant`).
WiFi brought up through `NetworkMgr` is never turned off by the plugin.
