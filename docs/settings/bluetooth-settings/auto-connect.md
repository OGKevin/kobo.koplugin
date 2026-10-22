# Auto-Connect Settings

The auto-connect feature monitors for nearby paired Bluetooth devices in discovery/pairing mode and
automatically initiates connections when they come within range. This is useful for devices that
don't auto-reconnect and require the Kobo to start the connection process.

## When to Use Auto-Connect

### Use Auto-Connect For

- **Devices requiring Kobo-initiated connection** - Bluetooth devices that are in discovery,
  pairing, or broadcasting mode and need the Kobo to initiate the connection
- **Devices that don't auto-reconnect** - Devices that disconnect and don't automatically reconnect
  when turned back on or when Bluetooth is re-enabled

### Use Auto-Detection For

- **Devices that auto-reconnect** - Some Bluetooth devices (page turners, remotes, keyboards)
  automatically reconnect when they wake from sleep or when Bluetooth is re-enabled
- **Already-connected devices** - If your devices already handle reconnection on their own

See [Auto-Detection](./auto-detection.md) for details on handling devices that auto-reconnect.

### Use Dispatcher "Connect to Device" Action For

- **On-demand connections** - When you want to trigger a connection with a gesture or profile
- **Power saving** - When you don't want continuous scanning for nearby devices

See
[Using Dispatcher to Connect Bluetooth](../../scenarios/using-dispatcher-to-connect-bluetooth.md)
for details on the dispatcher approach.

## Settings

### Auto-connect to nearby devices

When enabled, the plugin continuously scans for nearby paired Bluetooth devices in
discovery/pairing/broadcasting mode. When a paired device comes within range (detected via RSSI
signal strength), the plugin automatically initiates a connection to that device.

- **Default:** Disabled
- **When enabled:** Continuously scans and monitors RSSI for all paired devices
- **Connection initiation:** The Kobo (not the device) initiates the connection request
- **Notification:** Shows a notification when a device is auto-connected
- **Requirements:** Device must be paired, in discovery/broadcasting mode, and not currently
  connected

### Stop auto-connect after connection

When enabled, auto-connect scanning stops after the first successful device connection. This saves
battery and prevents unnecessary scanning if you typically only use one Bluetooth device at a time.

- **Default:** Enabled
- **Only active when:** "Auto-connect to nearby devices" is enabled
- **Behavior:** Scanning automatically resumes when a connected device disconnects or when Bluetooth
  is toggled off and back on

## How It Works

1. When Bluetooth is enabled and auto-connect is turned on, the plugin starts scanning for nearby
   paired devices in discovery/pairing/broadcasting mode
2. For each paired device, the plugin monitors the RSSI (signal strength):
   - RSSI indicates how strong the wireless signal is from the device
   - When a device's RSSI changes, it means the device has come into range or moved away
3. When a paired device with a valid RSSI is detected (in range), the plugin:
   - Checks if it's not already connected
   - Verifies it's in your paired devices list
   - Automatically initiates a connection request (the Kobo starts the connection)
4. If "Stop auto-connect after connection" is enabled:
   - Scanning stops after the first successful connection
   - Scanning resumes when that device disconnects
   - Scanning also resumes when Bluetooth is toggled off and back on

### Faster connection after Bluetooth comes on

Waiting for the scan to notice a device can take 20 to 30 seconds. While auto-connect is active, the
plugin therefore also does the following:

- Right after Bluetooth is turned on, or comes back on after standby, it asks the device that was
  connected last to connect, directly and in the background. A remote that stayed switched on is
  usually back within about 5 seconds. If only one device is paired, a second attempt follows about
  16 seconds later; then the scan takes over.
- Once a second it checks whether a paired device's input has appeared and opens it immediately,
  instead of waiting for the Bluetooth service to report the connection, which can take up to 10
  seconds. This also picks up connections started by the remote itself.

The scan is paused while a direct attempt is running and starts once the attempt has had its time.
No direct attempts are made after a device disconnects, because contacting a device that was just
switched off only keeps the Bluetooth service busy; from then on the scan and the once-a-second
check apply.

### Several paired devices

The Bluetooth service connects to one device at a time, and an attempt to reach a device that is
switched off occupies it for about 15 seconds. With several paired devices, the direct attempt
therefore goes to the device that was connected last only; the other devices are found by the scan,
which takes about 35 seconds in total. Two devices of the same model (same name) are told apart by
their address, so each is opened on its own input.

If you choose "Connect" from the paired devices list while a direct attempt is still running, the
plugin shows "Bluetooth is busy, connecting in a moment..." and connects as soon as the attempt has
finished, instead of failing with "in progress".
