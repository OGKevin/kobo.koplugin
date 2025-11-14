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
