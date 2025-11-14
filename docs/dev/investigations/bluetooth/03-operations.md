# Bluetooth Operations

## Scan for Devices

### Start Discovery

```bash
#!/usr/bin/env bash
# Scan for Bluetooth devices

echo "Starting discovery..."
dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    /org/bluez/hci0 \
    org.bluez.Adapter1.StartDiscovery

echo "Scanning for 5 seconds..."
sleep 5

echo "Stopping discovery..."
dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    /org/bluez/hci0 \
    org.bluez.Adapter1.StopDiscovery
```

### List Discovered Devices

```bash
# List all discovered devices
dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    / \
    org.freedesktop.DBus.ObjectManager.GetManagedObjects \
    | grep -A 10 '/org/bluez/hci0/dev_'

# Example output:
# /org/bluez/hci0/dev_E4_17_D8_EC_04_1E
#   string "Name"
#   variant string "My Bluetooth Device"
#   string "Address"
#   variant string "E4:17:D8:EC:04:1E"
```

**Note:** Device paths use underscores in MAC addresses (e.g., `E4_17_D8_EC_04_1E`), not colons.

## Connect to Device

### Connection Script

```bash
#!/usr/bin/env bash
# Connect to a Bluetooth device
# Usage: ./connect.sh DEVICE_MAC
# MAC format: XX_XX_XX_XX_XX_XX (underscores, not colons)

DEVICE_MAC="$1"

if [ -z "$DEVICE_MAC" ]; then
    echo "Usage: $0 DEVICE_MAC (e.g., E4_17_D8_EC_04_1E)"
    exit 1
fi

echo "Step 1: Check if device needs pairing"
PAIRED=$(dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    /org/bluez/hci0/dev_"${DEVICE_MAC}" \
    org.freedesktop.DBus.Properties.Get \
    string:org.bluez.Device1 \
    string:Paired 2>&1 | grep boolean | awk '{print $3}')

if [ "$PAIRED" = "false" ]; then
    echo "Pairing device..."
    dbus-send --system --print-reply \
        --dest=com.kobo.mtk.bluedroid \
        /org/bluez/hci0/dev_"${DEVICE_MAC}" \
        org.bluez.Device1.Pair
    sleep 3
fi

echo "Step 2: Set device as trusted"
dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    /org/bluez/hci0/dev_"${DEVICE_MAC}" \
    org.freedesktop.DBus.Properties.Set \
    string:org.bluez.Device1 \
    string:Trusted \
    variant:boolean:true

echo "Step 3: Connect to device"
dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    /org/bluez/hci0/dev_"${DEVICE_MAC}" \
    org.bluez.Device1.Connect

echo "Step 4: Verify connection"
dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    /org/bluez/hci0/dev_"${DEVICE_MAC}" \
    org.freedesktop.DBus.Properties.Get \
    string:org.bluez.Device1 \
    string:Connected
```

### Handling "AlreadyConnected" Error

If you get `Error org.bluez.Error.AlreadyConnected: already connected` when the device isn't
actually connected, the device is in a stale state. Performing a new device scan (discovery) clears
the stale state. A disconnect is not required.

## Check Device Status

### Get Device Properties

```bash
#!/usr/bin/env bash
# Check device connection status
# Usage: ./device_status.sh DEVICE_MAC

DEVICE_MAC="$1"

if [ -z "$DEVICE_MAC" ]; then
    echo "Usage: $0 DEVICE_MAC"
    exit 1
fi

echo "=== All Device Properties ==="
dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    /org/bluez/hci0/dev_"${DEVICE_MAC}" \
    org.freedesktop.DBus.Properties.GetAll \
    string:org.bluez.Device1

echo ""
echo "=== Connected Status ==="
dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    /org/bluez/hci0/dev_"${DEVICE_MAC}" \
    org.freedesktop.DBus.Properties.Get \
    string:org.bluez.Device1 \
    string:Connected

echo ""
echo "=== Paired Status ==="
dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    /org/bluez/hci0/dev_"${DEVICE_MAC}" \
    org.freedesktop.DBus.Properties.Get \
    string:org.bluez.Device1 \
    string:Paired

echo ""
echo "=== Trusted Status ==="
dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    /org/bluez/hci0/dev_"${DEVICE_MAC}" \
    org.freedesktop.DBus.Properties.Get \
    string:org.bluez.Device1 \
    string:Trusted
```

## Check Adapter Status

```bash
#!/usr/bin/env bash
# Check Bluetooth adapter status

echo "=== All Adapter Properties ==="
dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    /org/bluez/hci0 \
    org.freedesktop.DBus.Properties.GetAll \
    string:org.bluez.Adapter1

echo ""
echo "=== Powered Status ==="
dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    /org/bluez/hci0 \
    org.freedesktop.DBus.Properties.Get \
    string:org.bluez.Adapter1 \
    string:Powered

echo ""
echo "=== Discovering Status ==="
dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    /org/bluez/hci0 \
    org.freedesktop.DBus.Properties.Get \
    string:org.bluez.Adapter1 \
    string:Discovering

echo ""
echo "=== Discoverable Status ==="
dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    /org/bluez/hci0 \
    org.freedesktop.DBus.Properties.Get \
    string:org.bluez.Adapter1 \
    string:Discoverable
```

## Disconnect Device

```bash
#!/usr/bin/env bash
# Disconnect from a Bluetooth device
# Usage: ./disconnect.sh DEVICE_MAC

DEVICE_MAC="$1"

if [ -z "$DEVICE_MAC" ]; then
    echo "Usage: $0 DEVICE_MAC"
    exit 1
fi

dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    /org/bluez/hci0/dev_"${DEVICE_MAC}" \
    org.bluez.Device1.Disconnect
```

## Remove Device

```bash
#!/usr/bin/env bash
# Remove (unpair) a Bluetooth device
# Usage: ./remove.sh DEVICE_MAC

DEVICE_MAC="$1"

if [ -z "$DEVICE_MAC" ]; then
    echo "Usage: $0 DEVICE_MAC"
    exit 1
fi

# Remove device from adapter
dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    /org/bluez/hci0 \
    org.bluez.Adapter1.RemoveDevice \
    objpath:/org/bluez/hci0/dev_"${DEVICE_MAC}"
```
