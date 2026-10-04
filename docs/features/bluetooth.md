# Bluetooth support

The Kobo plugin provides Bluetooth management for compatible Kobo devices. You can enable/disable
Bluetooth, scan for nearby devices, pair and connect to devices, and manage paired devices from
KOReader.

## Supported devices

- Kobo Libra 2
- Kobo Libra Colour
- Kobo Clara BW / Colour
- Kobo Elipsa 2E

## How to use

- Open main menu and choose Settings → Network → Bluetooth.
- Use "Enable/Disable" to toggle Bluetooth.
- Open "Paired devices" to see devices you have previously paired (including devices paired via Kobo
  Nickel). From the paired devices list you can:
  - Connect or disconnect a device
  - Open the key binding configuration (when connected) to map device events to actions
  - Forget a device to unpair it and remove it from the list

**Note:** Paired devices can only be connected when they are nearby and discoverable. Use "Scan for
devices" to detect nearby devices (including paired devices that are currently discoverable). If a
paired device appears in the scan results, you can connect to it from the Paired devices list or
directly from the scan results.

## Configuring key bindings

When you connect a Bluetooth device that supports button input (such as a remote or keyboard), you
can map its buttons to KOReader actions.

To configure key bindings for a device:

1. Go to Paired devices and select the device you want to configure.
2. Choose "Configure key bindings" from the device menu - a list of available actions will appear.
3. Select an action you want to bind to a button.
4. Choose "Register button" - the system will now listen for the next button press on your device.
5. Press a button on your Bluetooth device - the system will capture and bind it to the selected
   action.
6. Repeat from step 3 for other actions you want to configure.

The available actions are defined in
[`src/lib/bluetooth/available_actions.lua`](https://github.com/OGKevin/kobo.koplugin/blob/main/src/lib/bluetooth/available_actions.lua).
If an action you need is missing, you can contribute by adding it to this file following the same
pattern as existing actions. See the plugin development documentation for details.

For more details, see [key-bindings](../settings/bluetooth-settings/key-bindings.md).

## Touch-screen style remotes ("TikTok rings")

Some cheap page-turner rings and remotes do not send key presses. They present themselves as a touch
screen and send every button as a simulated finger gesture (a swipe or a tap), because they are made
for scrolling short videos on a phone.

Two things are done so these devices can be used like any other remote:

- **Driver binding.** The kernel classifies such a device as multitouch and leaves it to the
  `hid-multitouch` driver, which Kobo kernels do not include. The device then connects but never
  gets an input node, and "Register button" detects nothing. When a connected Bluetooth HID device
  has no kernel driver, the plugin registers it with `hid-generic` (via its `new_id` sysfs file) so
  the input node is created. This lasts until the Kobo reboots and is repeated when needed.
- **Gesture to key translation.** A touch contact (finger down, movement, finger up) is folded into
  one synthetic key press, which can be bound like a normal button. A swipe fires as soon as its
  direction is clear, without waiting for the finger to lift:

  | Gesture     | Key name   |
  | ----------- | ---------- |
  | Tap         | `KEY_1000` |
  | Swipe up    | `KEY_1001` |
  | Swipe down  | `KEY_1002` |
  | Swipe left  | `KEY_1003` |
  | Swipe right | `KEY_1004` |

Buttons can only be told apart by the direction of their gesture. Two buttons that swipe in the same
direction, or tap at different positions, register as the same key.

### Tested devices

- **WX02** ring remote (sold as "wxlj-02", three buttons, classic Bluetooth, announces itself with
  Apple's vendor ID `05AC:0220`), for example [this listing](https://www.amazon.co.uk/dp/B0GTVH33JR).
  Tested on a Kobo Clara BW. Next/previous buttons send swipe down/up (`KEY_1002` / `KEY_1001`), the
  middle button sends a tap (`KEY_1000`) and, on its first press after power-on, a power key
  (`KEY_116`).

Other remotes of this kind have not been tested. Remotes that emulate a mouse (relative movement)
instead of a touch screen are not covered.

## Dispatcher integration

The plugin registers Bluetooth actions with KOReader's dispatcher system at startup, allowing you to
control Bluetooth using gestures, profiles, or other dispatcher-aware features.

### Bluetooth Control Actions

The following control actions are registered automatically:

- **Enable Bluetooth** — Turns Bluetooth on
- **Disable Bluetooth** — Turns Bluetooth off
- **Toggle Bluetooth** — Toggles Bluetooth on/off based on current state
- **Scan for Bluetooth Devices** — Starts a device scan and shows results

### Device Connection Actions

The plugin also registers actions for each paired Bluetooth device, allowing you to connect to
specific devices directly via dispatcher actions.

All Bluetooth actions can be found in the dispatcher system under the "Device" category.

## Auto-detection of connecting devices

For Bluetooth devices that automatically reconnect (e.g., page turners that wake from sleep), you
can enable auto-detection polling. When enabled, the plugin monitors for newly connected devices and
automatically opens their input handlers so key bindings work immediately.

To enable auto-detection:

1. Open Settings → Network → Bluetooth → Settings → Auto-detection.
2. Enable "Auto-detect connecting devices" — this starts polling and will automatically open input
   handlers for devices that reconnect (for example, page turners that wake from sleep).
3. (Optional) Enable "Stop detection after connection" to stop polling once a device successfully
   connects; leave it disabled to continue detecting additional devices.

For devices that don't auto-connect, use the dispatcher "Connect to device" action instead. See the
[auto-detection settings documentation](../settings/bluetooth-settings/auto-detection.md) for
details on when to use each approach.

## Auto-connecting to nearby devices

For Bluetooth devices that require the Kobo to initiate the connection (devices in
discovery/pairing/broadcasting mode), you can enable auto-connect. When enabled, the plugin scans
for nearby paired devices and automatically connects to them when they come into range.

To enable auto-connect:

1. Open Settings → Network → Bluetooth → Settings → Auto-connect.
2. Enable "Auto-connect to nearby devices" — this starts scanning and will automatically connect to
   paired devices that come within range.
3. (Optional) Enable "Stop auto-connect after connection" to stop scanning once a device
   successfully connects; leave it disabled to continue scanning for additional devices.

For devices that auto-reconnect on their own, use auto-detection instead. See the
[auto-connect settings documentation](../settings/bluetooth-settings/auto-connect.md) for details on
when to use each approach.

## Notes and tips

- Bluetooth is only supported on compatible Kobo devices (see list above). If your device does not
  support Bluetooth, the menu will not be shown.
- When Bluetooth is enabled, KOReader prevents the device from entering standby until you disable
  Bluetooth.
- The device will still automatically suspend or shutdown according to your power settings when
  Bluetooth is enabled.
- Paired devices are remembered in the plugin settings so you can reconnect even if Bluetooth is off
  at startup.
