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
    ├── Auto-resume after wake [Toggle]
    ├── Show status in footer [Toggle]
    ├── Auto-detection [Submenu]
    │   ├── Auto-detect connecting devices [Toggle]
    │   └── Stop detection after connection [Toggle]
    │── Auto-connect [Submenu]
    │   ├── Auto-connect to nearby devices [Toggle]
    │   └── Stop auto-connect after connection [Toggle]
    ├── Show device ready notifications [Toggle]
    └── Dismiss pop-ups with button press [Toggle]
```

## Menu Item Reference

| Menu Item                         | Type    | Function                                                |
| --------------------------------- | ------- | ------------------------------------------------------- |
| Enable/Disable                    | Toggle  | Turn Bluetooth on or off                                |
| Scan for devices                  | Action  | Scan for new devices to pair                            |
| Paired devices                    | Submenu | View and manage all paired Bluetooth devices            |
| Connect/Disconnect                | Action  | Connect to or disconnect from a specific device         |
| Configure key bindings            | Submenu | Set up button mappings for a connected device           |
| Remove device                     | Action  | Remove device from paired list                          |
| Settings                          | Submenu | Bluetooth settings submenu                              |
| Auto-resume after wake            | Toggle  | Automatically re-enable Bluetooth after device wakes up |
| Show status in footer             | Toggle  | Display Bluetooth status in the reader's footer bar     |
| Show device ready notifications   | Toggle  | Show notification when input device connects and ready  |
| Dismiss pop-ups with button press | Toggle  | Allow Bluetooth buttons to close dismissable dialogs    |
| Auto-detection                    | Submenu | Auto-detection settings submenu                         |
| Auto-detect connecting devices    | Toggle  | Enable/disable polling for auto-connected devices       |
| Stop detection after connection   | Toggle  | Stop polling once a device successfully connects        |
| Auto-connect                      | Submenu | Auto-connect settings submenu                           |
| Auto-connect to nearby devices    | Toggle  | Enable/disable automatic connection to nearby devices   |
| Stop auto-connect after connect   | Toggle  | Stop scanning once a device successfully connects       |
| Register button                   | Action  | Capture a button press to bind to selected action       |
| Remove binding                    | Action  | Remove button mapping for selected action               |

## Important Notes

- Bluetooth menu is only visible on MTK-based Kobo devices (Libra Colour, Clara BW/Colour)
- "Configure key bindings" only appears when a device is connected
- When Bluetooth is enabled, the device will not enter standby mode
- The device will still suspend or shutdown according to your power settings
- "Scan for devices" scans for nearby Bluetooth devices. Use it to discover new devices to pair and
  to check whether previously paired devices are currently nearby and discoverable.
