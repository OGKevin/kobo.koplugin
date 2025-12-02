# Auto-Detection Settings

The auto-detection feature monitors for Bluetooth devices that automatically reconnect to your Kobo
device and opens their input handlers so key bindings continue to work.

## When to Use Auto-Detection

### Use Auto-Detection For

- **Devices that auto-reconnect** - Some Bluetooth devices (page turners, remotes, keyboards)
  automatically reconnect when they wake from sleep or when Bluetooth is enabled on the Kobo
- **Hands-free reconnection** - When you want your device to be ready to use without manual
  intervention after the device reconnects

### Use Dispatcher "Connect to Device" Action For

- **Devices that don't auto-connect** - If your device requires manual connection each time
- **On-demand connections** - When you want to trigger a connection with a gesture or profile
- **Power saving** - When you don't want continuous polling for device connections

See
[Using Dispatcher to Connect Bluetooth](../../scenarios/using-dispatcher-to-connect-bluetooth.md)
for details on the dispatcher approach.

## Settings

### Auto-detect connecting devices

When enabled, the plugin polls every second to check if any paired Bluetooth devices have connected.
If a connected device is found without an open input handler, it automatically opens one.

- **Default:** Disabled
- **When enabled:** Polls for connected devices every 1 second
- **Notification:** Shows a notification when a device is auto-detected (except during initial
  startup)

### Stop detection after connection

When enabled, auto-detection polling stops after the first successful device connection. This saves
resources if you typically only use one Bluetooth device at a time.

- **Default:** Enabled
- **Only active when:** "Auto-detect connecting devices" is enabled
- **Behavior:** Polling resumes when Bluetooth is toggled off and back on

## How It Works

1. When Bluetooth is enabled and auto-detection is turned on, the plugin starts polling every second
2. Each poll cycle:
   - Loads the current list of paired devices from the system
   - Checks which devices are marked as "connected" by the Bluetooth stack
   - For any connected device without an open input handler, opens one
3. When a new device is detected after startup, a notification is shown
4. If "Stop detection after connection" is enabled, polling stops after the first successful
   connection
