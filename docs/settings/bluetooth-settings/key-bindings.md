# Key Bindings

When you connect a Bluetooth device that has buttons (like a remote control or keyboard), you can
configure which buttons trigger which KOReader actions.

## Available Actions

The plugin automatically provides access to KOReader actions that you can bind to your Bluetooth
device buttons. These actions are organized into categories:

- **General** - Common actions like showing menus and navigation
- **Device** - Device-specific functions like toggling frontlight, WiFi, and power options
- **Screen and lights** - Adjust frontlight brightness, warmth, and screen settings
- **File browser** - Actions for managing files and folders
- **Reader** - Reading-related actions like page navigation, bookmarks, and annotations
- **Reflowable documents** - Font size, line spacing, and text formatting (for EPUBs, etc.)
- **Fixed layout documents** - Zoom, rotation, and page fitting (for PDFs, CBZ, etc.)

The full list of available actions is provided by KOReader's dispatcher system and may vary
depending on your KOReader version and installed plugins.

## Configuring Key Bindings

To set up button mappings for a connected device:

1. Navigate to **Settings → Network → Bluetooth → Paired devices**
2. Select the device you want to configure
3. Choose **"Configure key bindings"**
4. Select a category (e.g., Reader, Device, Screen and lights)
5. Select an action from the category list
6. Choose **"Register button"**
7. Press the button on your Bluetooth device you want to use for this action
8. The binding is saved automatically

Repeat steps 4-8 for each button you want to configure.

## Removing a Key Binding

To remove a button mapping:

1. Navigate to the device's key binding configuration
2. Select the action you want to unbind
3. Choose "Remove binding"

### Remove All Bindings

To clear all button mappings for a device:

1. Navigate to the device options in **Settings → Network → Bluetooth → Paired devices**
2. Select **"Reset key bindings"**

## Multiple Devices

Each Bluetooth device can have its own unique button configuration. The mappings you create for one
device won't affect other devices.

## Persistence

Key bindings are saved automatically and persist across KOReader restarts. You only need to
configure them once per device.
