# Bluetooth Stack Architecture

## Components

Kobo's Bluetooth implementation consists of three main processes:

| Process           | Path                     | Purpose                               |
| ----------------- | ------------------------ | ------------------------------------- |
| `mtkbtd-launcher` | `/usr/local/Kobo/`       | Launch script for MTK Bluetooth       |
| `mtkbtd`          | `/usr/local/Kobo/mtkbtd` | MediaTek Bluetooth daemon             |
| `btservice`       | `/usr/bin/btservice`     | Bluetooth service (spawned by mtkbtd) |

## Kernel Modules

<div class="warning">
These modules must remain loaded at all times. Unloading them will remove Wi-Fi
support, and does not prevent kernel panic on shutdown. Restoration is required to recover Wi-Fi
functionality. (See [Known Issues](./05-known-issues.md))
</div>

- `wmt_drv` - MediaTek WMT driver (main driver)
- `wmt_chrdev_wifi` - WiFi character device
- `wmt_cdev_bt` - Bluetooth character device
- `wlan_drv_gen4m` - WLAN driver

### Checking Loaded Modules

```bash
# Verify modules are loaded
lsmod | grep -E "(wmt|wlan|bt)"

# Expected output:
# wlan_drv_gen4m 1908365 0 - Live 0xbf14a000 (O)
# wmt_cdev_bt 16871 0 - Live 0xbf141000 (O)
# wmt_chrdev_wifi 12825 1 wlan_drv_gen4m, Live 0xbf138000 (O)
# wmt_drv 1059215 4 wlan_drv_gen4m,wmt_cdev_bt,wmt_chrdev_wifi, Live 0xbf000000 (O)
```

## D-Bus Services

Kobo uses a **custom D-Bus wrapper** instead of standard BlueZ interfaces:

| Service Name               | Purpose                                     |
| -------------------------- | ------------------------------------------- |
| `com.kobo.mtk.bluedroid`   | Main Bluetooth service (Kobo's wrapper)     |
| `com.kobo.bluetooth.Agent` | Pairing/authentication agent                |
| `org.bluez`                | **NOT EXPOSED** - use mtk.bluedroid instead |

**Key Discovery:** All D-Bus calls must use `com.kobo.mtk.bluedroid` as destination, not
`org.bluez`.

### D-Bus Service File

Service auto-activation is configured in:

```
/usr/share/dbus-1/system-services/com.kobo.mtk.bluedroid.service
```

This allows D-Bus to automatically start `mtkbtd-launcher.sh` when a method is called on
`com.kobo.mtk.bluedroid`, even if the service isn't running.

### Verifying Service Availability

```bash
# List available D-Bus services
dbus-send --system --print-reply \
    --dest=org.freedesktop.DBus \
    /org/freedesktop/DBus \
    org.freedesktop.DBus.ListNames | grep -E "(bluez|bluetooth|mtk)"

# Expected output when running:
# string "com.kobo.mtk.bluedroid"
# string "com.kobo.bluetooth.Agent"

# Check if Bluetooth service exists
dbus-send --system --print-reply \
    --dest=org.freedesktop.DBus \
    /org/freedesktop/DBus \
    org.freedesktop.DBus.GetNameOwner \
    string:com.kobo.mtk.bluedroid
```

## Process Verification

```bash
# Check if Bluetooth processes are running
ps aux | grep -E "(mtkbtd|btservice)" | grep -v grep

# Expected output when running:
# root      1178  0.0  0.0   1234    567 ?  S  15:18  0:00 {mtkbtd-launcher} /bin/sh /usr/local/Kobo/mtkbtd-launcher.sh
# root      1179  0.0  0.1   2345   1234 ?  Sl 15:18  0:00 /usr/local/Kobo/mtkbtd -skipFontLoad -platform kobo:noscreen --debug
# root      1181  0.0  0.0   1234    567 ?  S  15:18  0:00 /usr/bin/btservice
```
