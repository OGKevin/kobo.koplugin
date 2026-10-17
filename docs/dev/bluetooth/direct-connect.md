# Direct Connect After Enable

How the plugin connects paired devices quickly once Bluetooth is on, and how it keeps several
remotes apart. The code is in `src/kobo_bluetooth.lua` (`_startDirectConnect` and the helpers it
names) and `src/lib/bluetooth/input_device_handler.lua`.

## Why discovery alone is slow

Measured on a Clara BW with a WX02 ring remote (KOReader `crash.log`):

- Auto-connect acts once a discovery scan reports the device with an RSSI. Inquiry results arrive in
  batches roughly every 10 seconds, so a remote that is switched on is seen 18 to 28 seconds after
  Bluetooth comes up.
- The Kobo's Bluetooth service (`mtkbtd`) reports the `Connected` property up to 10 seconds after
  the HID link is up and the input node exists.
- `waitForBluetoothInputDevice` only looked for nodes that appeared after its initial snapshot, so a
  node that existed already ran into the 5 second timeout.

Together this made about 30 seconds from switching the remote on to the first page turn.

## The loop

`startAutoConnectPolling(true)` is called when Bluetooth has just come on (startup, manual enable,
auto-resume, or auto-connect switched on in the menu). It defers discovery and starts the direct
connect loop, a `UIManager:scheduleIn` task that runs every `DIRECT_CONNECT_TICK_SECONDS` (1 s):

1. `_openPresentInputNodes`: for every paired device without an open input reader, look for its
   input node (`InputDeviceHandler:findInputNodeForDevice`) and open it right away through
   `_onInputNodeDetected`, which mirrors what auto-detection does on the `Connected` signal. The
   cached `Connected` flag is ignored: right after a resume the stack may still report the device
   that was connected before standby as connected.
2. `_makeDirectConnectAttempt`: while the attempt budget lasts and the previous attempt has had its
   time (`DIRECT_CONNECT_ATTEMPT_TICKS`, 16 s), call `Device1.Connect` in the background
   (`DeviceManager:connectDeviceInBackground`) for one candidate, the device recorded in the
   `bluetooth_last_connected` setting first. Discovery is stopped for the attempt.
3. Discovery starts, or resumes, once an attempt has had its time, or after
   `DIRECT_CONNECT_DISCOVERY_DELAY_TICKS` (4) runs when no attempt was made. From then on the
   RSSI-based path of auto-connect applies as before.

`startAutoConnectPolling()` without the flag, as called after a disconnect, runs the loop with no
attempts: only the node check, which also catches connections the remote initiates.

The attempt budget is `DIRECT_CONNECT_MAX_ATTEMPTS` (2) for a single paired device and one attempt
when several are paired (see below). A manual "Connect" sets the budget to zero and, while an
attempt is pending, waits for it (`_connectAfterPendingAttempt`); `onRssiPropertyChanged` skips a
device with an open reader or one the pending attempt is contacting, so no second request is made
for a connection that is about to succeed.

## What the MTK stack does

Observed with two WX02 rings paired (same model, same name):

- The stack handles one connection at a time. A `Device1.Connect` to a device that is off occupies
  it for about 15 seconds ("connection timeout"); a request made meanwhile fails with
  `org.bluez.Error.InProgress: auto-pairing in progress`. A successful connect takes 8 to 12 seconds
  to complete, and the D-Bus call still ends in `NoReply` after 25 seconds. Hence the background
  subprocess and the 16 second spacing.
- A direct connect reaches the device that was connected last within about 5 seconds, whatever the
  order of switching the ring on and standby/wake. A direct connect to the _other_ ring times out
  even when it is on and no scan is running, while the scan sees it about 14 seconds after starting
  and the connect that follows succeeds at once. With several paired devices the loop therefore
  makes one attempt and hands over to the scan.
- An attempt made while discovery is running tends to time out even against the last-used device; an
  attempt made before the scan starts succeeds. Discovery is paused for the attempt.
- Connecting ring B while ring A is linked drops A: one HID device at a time.

Tried and reverted: contacting only the devices that were connected before standby (a ring
power-cycled before standby then had to wait for the scan, 25 s instead of 5 s), and a second blind
attempt to the other ring (it never succeeded).

## Input nodes of same-name devices

`/sys/class/input/eventN/device/uniq` holds the remote's Bluetooth address, with the byte order
reversed on MTK devices (`F6:0E:5A:FF:01:1D` for `1D:01:FF:5A:0E:F6`).
`InputDeviceHandler:findDeviceByName(name, address)` matches on it, falling back to the name for
nodes without one, and never returns a node that an isolated reader already uses, so two remotes of
the same model are each opened on their own node. `waitForBluetoothInputDevice` applies the same
match, which also finds a node that existed before its snapshot.

The device open callback stores the address of the device opened last in `bluetooth_last_connected`
(plugin settings), and the ready notification names the device ("WX02 ready") rather than the node
path.

## Background subprocess and USB mass storage

The forked subprocess that performs the background `Device1.Connect` inherits KOReader's working
directory and open files on `/mnt/onboard`. While it waits for D-Bus (up to 25 s), the storage
cannot be unmounted and plugging in the USB cable fails with "KoboUSBMS failed to setup an USBMS
session". `Subprocess.detachFromStorage()` (`src/lib/bluetooth/subprocess.lua`) changes the child's
directory to `/` and closes its inherited descriptors before the D-Bus call; both adapters call it.

## Enable on startup and plugin instances

`enable_bluetooth_on_startup` turns Bluetooth on in `initWithPlugin`, once per KOReader run
(`KoboBluetooth.startup_enable_handled`). KOReader creates a new plugin instance when a book is
opened; if that happens while an asynchronous enable is still in progress, the processes must be
started on the current instance, not on the one that started the enable and has since been closed.
`KoboBluetooth.active_instance` tracks the most recently initialised instance;
`_pollForBluetoothEnabledAndRestoreWifi` starts the processes there, unless that instance found
Bluetooth already on when it initialised and runs them itself. This covers startup, auto-resume and
manual enables alike.

## Measurements

Clara BW, WX02 rings, times from Bluetooth coming on to a working remote:

| Situation                                         | Before     | After                                    |
| ------------------------------------------------- | ---------- | ---------------------------------------- |
| Same ring, after wake or after enabling Bluetooth | about 30 s | about 5 s                                |
| Switching to the other paired ring                | 20 to 30 s | about 35 s (15 s attempt, scan, connect) |
| Cold start with "Enable on startup"               | by hand    | about 8 s after KOReader starts          |
