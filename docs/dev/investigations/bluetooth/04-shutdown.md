# Bluetooth Power Off

Shutdown is not effective; a reboot is required to be able to restart nickel.

To power off Bluetooth before rebooting:

```bash
dbus-send --system --dest=com.kobo.mtk.bluedroid \
    /org/bluez/hci0 \
    org.freedesktop.DBus.Properties.Set \
    string:org.bluez.Adapter1 \
    string:Powered \
    variant:boolean:false

dbus-send --system --print-reply \
    --dest=com.kobo.mtk.bluedroid \
    / \
    com.kobo.bluetooth.BluedroidManager1.Off
```

See [Known Issues](./05-known-issues.md) for details.
