# Bluetooth support

The Kobo plugin provides Bluetooth management for MTK-based Kobo devices. You can enable/disable
Bluetooth, scan for nearby devices, pair and connect to devices, and manage paired devices from
KOReader.

## Supported devices

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
- Use "Scan for devices" only if you want to pair a new device that is not already in your paired
  list.

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

## Dispatcher integration

The plugin automatically registers dispatcher actions for all paired Bluetooth devices at KOReader
startup. This allows you to connect to your devices using gestures, profiles, or other
dispatcher-aware features.

These can be found in the dispatcher system under the "Device" category.

## Notes and tips

- Bluetooth is only supported on Kobo devices with MediaTek (MTK) hardware. If your device does not
  support Bluetooth, the menu will not be shown.
- When Bluetooth is enabled, KOReader prevents the device from entering standby until you disable
  Bluetooth.
- The device will still automatically suspend or shutdown according to your power settings when
  Bluetooth is enabled.
- Paired devices are remembered in the plugin settings so you can reconnect even if Bluetooth is off
  at startup.
