# Turn On/Off Bluetooth Stack (Sage)

Hardened full rebuild: soft warm starts often leave `hci0` attached-but-DOWN. Always tear down,
rfkill-cycle, then reattach.

## Turn On Bluetooth

1. Stop any leftover UART attach / BlueZ daemon and bring the controller down:

```bash
killall rtk_hciattach 2>/dev/null
killall bluetoothd 2>/dev/null
hciconfig hci0 down 2>/dev/null
```

2. Power-cycle the `sunxi-bt` rfkill node:

```bash
echo 0 > /sys/devices/platform/bt/rfkill/rfkill0/state
sleep 1
echo 1 > /sys/devices/platform/bt/rfkill/rfkill0/state
```

3. Attach the Realtek HCI over UART (resident process; redirect logs so callers that pipe the script
   do not hang):

```bash
/sbin/rtk_hciattach -n -s 115200 /dev/ttyS1 rtk_h5 \
    > /var/log/rtk_hciattach.log 2>&1 &
sleep 2
hciconfig hci0 up
```

4. Start BlueZ detached:

```bash
setsid /libexec/bluetooth/bluetoothd -n -d \
    > /var/log/bluetoothd.log 2>&1 &
```

5. Wait until BlueZ exposes `Adapter1`, set `Powered=true`, and verify `hci0` is `UP RUNNING`:

```bash
dbus-send --system --print-reply \
    --dest=org.bluez \
    /org/bluez/hci0 \
    org.freedesktop.DBus.Properties.Set \
    string:org.bluez.Adapter1 \
    string:Powered \
    variant:boolean:true

hciconfig hci0 | grep -q 'UP RUNNING'
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

2. Stop daemons and cut rfkill power:

```bash
killall bluetoothd
killall rtk_hciattach
echo 0 > /sys/devices/platform/bt/rfkill/rfkill0/state
```
