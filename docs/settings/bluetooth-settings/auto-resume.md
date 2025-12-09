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

When Bluetooth auto-resumes after wake, the plugin needs to temporarily enable WiFi (MTK Bluetooth
requires WiFi to be on). The plugin handles WiFi restoration based on KOReader's "Auto-restore WiFi
after resume" setting:

- If KOReader's "Auto-restore WiFi" is **disabled**, WiFi will be turned back off after Bluetooth
  finishes enabling (since WiFi was only enabled temporarily for Bluetooth)
- If KOReader's "Auto-restore WiFi" is **enabled**, WiFi state will be managed by KOReader's own
  restoration logic

This ensures that enabling Bluetooth doesn't unexpectedly change your WiFi preferences.

## Battery Considerations

When auto-resume is disabled:

- Bluetooth will remain off after wake
- You'll need to manually turn Bluetooth back on using the menu or a dispatcher action
- This can help save battery if you don't need Bluetooth active all the time
