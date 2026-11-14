# Turn On/Off Bluetooth Stack

## Turn On Bluetooth

1. Start Bluetooth daemon from `/tmp`, detached from KOReader's storage:

```bash
pgrep bluetoothd >/dev/null || (cd /tmp && setsid /libexec/bluetooth/bluetoothd </dev/null >/dev/null 2>&1 &)
```

KOReader runs from `/mnt/onboard/.adds/koreader` and keeps descriptors open on `/mnt/onboard`. A
daemon started as plain `/libexec/bluetooth/bluetoothd &` inherits that working directory, those
descriptors and KOReader's standard streams, so the partition stays busy and entering USB mass
storage fails with `KoboUSBMS failed to setup an USBMS session`. The command above is the manual
equivalent: it fixes the working directory, the standard streams and the lingering shell, but it
still passes the descriptors KOReader had open. The plugin starts the daemon from Lua instead:
`Subprocess.startDaemon()` (`src/lib/bluetooth/subprocess.lua`) forks, calls `setsid()`, moves the
daemon to `/tmp`, points its standard streams at `/dev/null` and closes every inherited descriptor
above stderr before `execvp`, so no shell is involved at all. `rtk_hciattach` is started the same
way with `Subprocess.runDetached()`.

2. Reset HCI interface:

```bash
hciconfig hci0 down
hciconfig hci0 up
```

3. Power on the Bluetooth adapter:

```bash
dbus-send --system --print-reply \
    --dest=org.bluez \
    /org/bluez/hci0 \
    org.freedesktop.DBus.Properties.Set \
    string:org.bluez.Adapter1 \
    string:Powered \
    variant:boolean:true
```

## Turn Off Bluetooth

1. Power off the adapter:

```bash
dbus-send --system --print-reply \
    --dest=org.bluez \
    /org/bluez/hci0 \
    org.freedesktop.DBus.Properties.Set \
    string:org.bluez.Adapter1 \
    string:Powered \
    variant:boolean:false
```

2. Stop Bluetooth daemon:

```bash
killall bluetoothd
```
