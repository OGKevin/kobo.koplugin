# Auto-resume After Wake

## Overview

The plugin includes an "Auto-resume after wake" feature that can automatically re-enable Bluetooth
when your device wakes from sleep if Bluetooth was enabled before the device was suspended.

## Enabling Auto-resume

1. Go to Settings → Network → Bluetooth → Settings
2. Toggle "Auto-resume after wake" to enable or disable the feature

## How It Works

When auto-resume is enabled:

1. When your device suspends, the plugin automatically turns off Bluetooth to save battery
2. If "Auto-resume after wake" is enabled and Bluetooth was on before suspend:
   - The plugin will automatically turn Bluetooth back on when the device wakes
   - It will attempt to reconnect to previously connected devices
   - Your key bindings will remain active
3. If the setting is disabled, Bluetooth will remain off after wake and you'll need to manually
   re-enable it

## WiFi Interaction

On MediaTek Kobos (Clara BW / Colour, Libra Colour) Bluetooth and WiFi share one radio chip. Turning
Bluetooth on powers the chip by itself, so the plugin normally does nothing with WiFi at all. Only
if Bluetooth fails to come up while WiFi is off does the plugin fall back to the chip power-on
handshake KOReader's WiFi scripts use, without starting a WiFi connection (no network association,
no DHCP lease), and it switches the WiFi function off again as soon as Bluetooth is up. Nothing
changes your WiFi preferences.

On a boot where neither Kobo's own software nor KOReader has used WiFi or Bluetooth yet, the plugin
loads the radio driver first; enabling Bluetooth then takes about ten seconds longer, once.

The plugin never turns off WiFi it did not power on itself:

- If WiFi is already on, nothing is touched.
- If KOReader's "Auto-restore WiFi after resume" is **enabled** and WiFi was on before sleep,
  KOReader is already restoring the connection after wake; the plugin waits for it and leaves it on.
- If another plugin or a KOReader feature starts a WiFi connection while Bluetooth is coming up, the
  plugin leaves WiFi to that owner.

## Starting With Bluetooth On

Auto-resume only covers waking from sleep. To have Bluetooth turned on when KOReader starts, see
[Enable on Startup](./enable-on-startup.md).

## Battery Considerations

When auto-resume is disabled:

- Bluetooth will remain off after wake
- You'll need to manually turn Bluetooth back on using the menu or a dispatcher action
- This can help save battery if you don't need Bluetooth active all the time
