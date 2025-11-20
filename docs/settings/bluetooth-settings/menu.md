# Bluetooth Menu Navigation

## Accessing Bluetooth Settings

1. Open KOReader top menu
2. Navigate to Settings → Network → Bluetooth.

## Menu Hierarchy

```
Settings → Network → Bluetooth
├── Enable/Disable [Toggle]
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
└── Scan for devices [Action]
```

## Menu Item Reference

| Menu Item              | Type    | Function                                          |
| ---------------------- | ------- | ------------------------------------------------- |
| Enable/Disable         | Toggle  | Turn Bluetooth on or off                          |
| Paired devices         | Submenu | View and manage all paired Bluetooth devices      |
| Connect/Disconnect     | Action  | Connect to or disconnect from a specific device   |
| Configure key bindings | Submenu | Set up button mappings for a connected device     |
| Remove device          | Action  | Remove device from paired list                    |
| Scan for devices       | Action  | Scan for new devices to pair                      |
| Register button        | Action  | Capture a button press to bind to selected action |
| Remove binding         | Action  | Remove button mapping for selected action         |

## Important Notes

- Bluetooth menu is only visible on MTK-based Kobo devices (Libra Colour, Clara BW/Colour)
- "Configure key bindings" only appears when a device is connected
- When Bluetooth is enabled, the device will not enter standby mode
- The device will still suspend or shutdown according to your power settings
