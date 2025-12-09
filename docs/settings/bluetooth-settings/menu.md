# Bluetooth Menu Navigation

## Accessing Bluetooth Settings

1. Open KOReader top menu
2. Navigate to Settings → Network → Bluetooth.

## Menu Hierarchy

```
Settings → Network → Bluetooth
├── Enable/Disable [Toggle]
├── Scan for devices [Action]
├── Paired devices [Submenu]
│   ├── Device 1 [Submenu]
│   │   ├── Connect/Disconnect [Action]
│   │   ├── Configure key bindings [Submenu]
│   │   │   ├── Action 1 → Register button / Remove binding
│   │   │   ├── Action 2 → Register button / Remove binding
│   │   │   └── ...
│   │   └── Remove device [Action]
│   ├── Device 2 [Submenu]
│   └── ...
└── Settings [Submenu]
    └── Auto-resume after wake [Toggle]
```

## Menu Item Reference

| Menu Item              | Type    | Function                                                |
| ---------------------- | ------- | ------------------------------------------------------- |
| Enable/Disable         | Toggle  | Turn Bluetooth on or off                                |
| Scan for devices       | Action  | Scan for new devices to pair                            |
| Paired devices         | Submenu | View and manage all paired Bluetooth devices            |
| Connect/Disconnect     | Action  | Connect to or disconnect from a specific device         |
| Configure key bindings | Submenu | Set up button mappings for a connected device           |
| Remove device          | Action  | Remove device from paired list                          |
| Settings               | Submenu | Configure Bluetooth behavior                            |
| Auto-resume after wake | Toggle  | Automatically re-enable Bluetooth after device wakes up |
| Register button        | Action  | Capture a button press to bind to selected action       |
| Remove binding         | Action  | Remove button mapping for selected action               |

## Important Notes

- Bluetooth menu is only visible on MTK-based Kobo devices (Libra Colour, Clara BW/Colour)
- "Configure key bindings" only appears when a device is connected
- When Bluetooth is enabled, the device will not enter standby mode
- The device will still suspend or shutdown according to your power settings
- "Scan for devices" scans for nearby Bluetooth devices. Use it to discover new devices to pair and
  to check whether previously paired devices are currently nearby and discoverable.

## Auto-resume After Wake

When enabled, the "Auto-resume after wake" setting automatically re-enables Bluetooth after the
device wakes from sleep if Bluetooth was enabled before the device was suspended.

### How It Works

1. When your device suspends, the plugin automatically turns off Bluetooth to save battery
2. If "Auto-resume after wake" is enabled and Bluetooth was on before suspend:
   - The plugin will automatically turn Bluetooth back on when the device wakes
   - It will reconnect to previously connected devices
   - Your key bindings will remain active
3. If the setting is disabled, Bluetooth will remain off after wake and you'll need to manually
   re-enable it

### WiFi Interaction

When Bluetooth auto-resumes after wake, the plugin needs to temporarily enable WiFi (MTK Bluetooth
requires WiFi to be on). The plugin handles WiFi restoration based on KOReader's "Auto-restore WiFi
after resume" setting:

- If KOReader's "Auto-restore WiFi" is **disabled**, WiFi will be turned back off after Bluetooth
  finishes enabling (since WiFi was only enabled temporarily for Bluetooth)
- If KOReader's "Auto-restore WiFi" is **enabled**, WiFi state will be managed by KOReader's own
  restoration logic

This ensures that enabling Bluetooth doesn't unexpectedly change your WiFi preferences.
