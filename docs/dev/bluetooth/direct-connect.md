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
   `bluetooth_last_connected` setting first. Discovery is stopped for the attempt. If the background
   subprocess cannot be started, nothing is reserved: discovery goes on and the attempt is due again
   16 runs later.
3. Discovery starts, or resumes, once an attempt has had its time, or after
   `DIRECT_CONNECT_DISCOVERY_DELAY_TICKS` (4) runs when no attempt was made. A start that fails is
   tried again on the next run. From then on the RSSI-based path of auto-connect applies as before.

`startAutoConnectPolling()` without the flag, as called after a disconnect, runs the loop with no
attempts (a running loop drops the attempts it had left): only the node check, which also catches
connections the remote initiates.

The attempt budget is `DIRECT_CONNECT_MAX_ATTEMPTS` (2) when a single device is paired and one
attempt when several are, whether or not the others are connected (see below). A manual "Connect"
sets the budget to zero and, while an attempt is pending, waits for it
(`_connectAfterPendingAttempt`); the waiting request is dropped if Bluetooth is turned off or the
instance closes meanwhile. `onRssiPropertyChanged` skips a device with an open reader or one the
pending attempt is contacting, so no second request is made for a connection that is about to
succeed; in the latter case the reading is forgotten, so the next one is acted on once the attempt
is over.

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
- Connecting ring B while ring A is linked drops A. This is what the log shows (A's `Connected` goes
  false as B's HID link comes up); whether the stack's HID host, the kernel's HID layer or the rings
  themselves enforce it was not investigated.

Tried and reverted: contacting only the devices that were connected before standby (a ring
power-cycled before standby then had to wait for the scan, 25 s instead of 5 s), and a second blind
attempt to the other ring (it never succeeded).

## Input nodes of same-name devices

`/sys/class/input/eventN/device/uniq` holds the remote's Bluetooth address, with the byte order
reversed on MTK devices (`F6:0E:5A:FF:01:1D` for `1D:01:FF:5A:0E:F6`).
`InputDeviceHandler:findDeviceByName(name, address)` compares a node's `uniq` with the device's
address and never returns a node that an isolated reader already uses, so two remotes of the same
model are each opened on their own node. `waitForBluetoothInputDevice` applies the same match, which
also finds a node that existed before its snapshot.

A node without a `uniq` is matched by name alone. Two same-name remotes cannot be told apart on such
a node: the first one looked up gets it. The nodes of the MTK stack carry the address, so this only
concerns stacks that leave `uniq` empty.

The device open callback stores the address of the device opened last in `bluetooth_last_connected`
(plugin settings), and the ready notification names the device ("WX02 ready") rather than the node
path.

## Background subprocess and USB mass storage

The background `Device1.Connect` runs in a forked subprocess, because the call blocks for up to 25
seconds. Both adapters' `connectDeviceInBackground` call `Subprocess.detachFromStorage()`
(`src/lib/bluetooth/subprocess.lua`) in the child first. That releases the child's working directory
and the file descriptors it inherited on `/mnt/onboard`, which is what made USB mass storage fail
with "KoboUSBMS failed to setup an USBMS session" while an attempt was pending. The child is a fork
of KOReader and does not exec, so it keeps the memory mappings it inherited until it exits; the
detach does not release those.

## Enable on startup and plugin re-initialisation

The plugin keeps a single `KoboBluetooth` object for the whole KOReader run (`main.lua`). KOReader
closes the plugin and initialises it again whenever it switches between file manager and reader, so
`onClose`/`onCloseWidget` and `initWithPlugin` run on that same object many times.

- `enable_bluetooth_on_startup` turns Bluetooth on in `initWithPlugin` once per run; the object
  remembers that in `startup_enable_handled`.
- An asynchronous enable can still be in progress when the plugin is closed and initialised again.
  `_pollForBluetoothEnabledAndRestoreWifi` therefore checks two things when the adapter comes up. If
  the plugin is closed (`is_closed`), nothing is started and a pending connection request is
  dropped: the next `initWithPlugin` finds Bluetooth on and starts the processes as usual. If that
  `initWithPlugin` has already started them (`_hasBluetoothProcesses`), they are not started a
  second time.

This covers startup, auto-resume and manual enables alike.

## Measurements

Clara BW, WX02 rings, times from Bluetooth coming on to a working remote:

| Situation                                         | Before     | After                                    |
| ------------------------------------------------- | ---------- | ---------------------------------------- |
| Same ring, after wake or after enabling Bluetooth | about 30 s | about 5 s                                |
| Switching to the other paired ring                | 20 to 30 s | about 35 s (15 s attempt, scan, connect) |
| Cold start with "Enable on startup"               | by hand    | about 8 s after KOReader starts          |
