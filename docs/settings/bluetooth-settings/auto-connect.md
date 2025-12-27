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
