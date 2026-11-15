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
instance closes meanwhile. `onRssiPropertyChanged` skips a device with an open reader, and makes no
request while a background attempt is pending, whichever device that attempt is contacting: the
reading is forgotten, so the next one is acted on once the attempt is over.

## Nothing waits on the UI thread

Three automatic paths used to block KOReader's main thread, which freezes the whole UI (seen as a
screen that does not react while a lock screen is waiting for input). All three are in the KOReader
`crash.log` of a Clara BW on which KOReader was restarted with the remote switched on. Two of them
waited for an input node with `waitForBluetoothInputDevice`, which polls and sleeps until the node
exists or 5 seconds have passed; the third made a D-Bus call that returns only when the connection
is up.

The `Connected` flag alone does not mean a device is usable. Four times in that log the service
reported a remote as connected although the plugin had not asked for a connection, no input node
appeared, and `Connected` went back to false 5 to 7 seconds later. Each time the plugin sat in
`waitForBluetoothInputDevice` for the full 5 seconds.

### Waiting for an input node without blocking

`InputDeviceHandler:_startNodeWait` looks for a device's input node at once and, while it does not
exist, again from a `UIManager:scheduleIn` task every `NODE_WAIT_CHECK_SECONDS` (0.5 s),
`NODE_WAIT_CHECK_COUNT` (10) times: the same five seconds as the blocking wait. One task serves all
waiting devices (`node_waits`, keyed by address). A wait ends early, without opening anything, when
the device's cached `Connected` flag turns false or when its input device has been opened by
something else (the loop, a manual connect). `closeAllIsolatedInputDevices` ends all waits.

Two callers use it:

- **Connected devices at startup.** `autoOpenConnectedDevices` runs from `initWithPlugin` and once
  an enable completes. A device is opened only on a node that `findInputNodeForDevice` matches to
  it. The fallback node is not used here: a device that is reported as connected without a matching
  node may be a stale flag, or a device that never has an input node, such as headphones, which then
  costs ten cheap looks and nothing else.
- **A device that connects** (`_handleConnection`, on the `Connected=true` signal while
  auto-detection or auto-connect is active). It calls
  `InputDeviceHandler:openIsolatedInputDeviceWhenPresent`, the non-blocking counterpart of
  `openIsolatedInputDevice` with `wait_for_device`, which finds the node by the same rules: a node
  that matches the device, else a Bluetooth input node that was not there when the wait began, and
  after the last look the auto-detected node. When the input device is open, the handler calls back
  and `_onInputDeviceAutoOpened` clears the last seen RSSI, starts key polling and applies the "stop
  after connection" settings, as before. The "Waiting 5 seconds for Bluetooth input device to
  appear..." message is not shown on this path.

"Stop auto-connect after connection" still treats a device that is reported as connected as a
connection, with or without an input node, so with the flag from the log auto-connect does not start
at startup. It starts when the `Connected=false` signal arrives (`_handleDisconnection`). This was
left as it is: a stale flag and a device that is connected but has no input cannot be told apart at
that moment.

### Connecting a device the scan has seen

`onRssiPropertyChanged` used to call `connectToDevice`, which runs `Device1.Connect` synchronously.
On MTK devices the call returns after 6 to 11 seconds (four connects in the log: 1, 6, 8 and 11
seconds), and until then nothing else runs. It now calls `_connectNearbyDevice`, which makes the
request through `DeviceManager:connectDeviceInBackground`, as the loop does for its own attempts:

- The result of the request is not reported back. The loop, which runs for as long as auto-connect
  is active, opens the input node when it exists (`_onInputNodeDetected`), shows the ready
  notification and stops auto-connect and auto-detection if the settings say so. The input is
  therefore open at most one loop run after the node appears.
- "Connected to …" and "Failed to connect to …" are no longer shown on this path. A failed request
  shows nothing, and the device is tried again on a later RSSI reading.
- The request is recorded like an attempt of the loop (`direct_connect_last_attempt_time`, attempt
  budget set to zero). For `DIRECT_CONNECT_ATTEMPT_TICKS` seconds further readings make no request,
  the loop makes no attempt of its own and a manual "Connect" waits. If the subprocess cannot be
  started, nothing is recorded and the reading is forgotten.
- Discovery keeps running during the request, as it did with the synchronous call: a device the scan
  has just reported answers at once.

### What still blocks

Connections the user asks for (scan results and paired devices menus, dispatcher action) still make
the D-Bus call synchronously (`DeviceManager:connectDevice`), show their messages and then open the
input device with `wait_for_device`.

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
  the plugin is closed (`is_closed`), nothing is started and the enable's completion callback, which
  carries a connection requested while Bluetooth was off, is kept: the next `initWithPlugin` finds
  Bluetooth on, starts the processes as usual and then runs it (`_runDeferredEnableCompletion`). If
  that `initWithPlugin` has already started the processes (`_hasBluetoothProcesses`), they are not
  started a second time.

This covers startup, auto-resume and manual enables alike.

## Measurements

Clara BW, WX02 rings, times from Bluetooth coming on to a working remote:

| Situation                                         | Before     | After                                    |
| ------------------------------------------------- | ---------- | ---------------------------------------- |
| Same ring, after wake or after enabling Bluetooth | about 30 s | about 5 s                                |
| Switching to the other paired ring                | 20 to 30 s | about 35 s (15 s attempt, scan, connect) |
| Cold start with "Enable on startup"               | by hand    | about 8 s after KOReader starts          |
