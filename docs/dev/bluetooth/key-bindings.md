# Bluetooth key bindings and custom actions

This document explains how Bluetooth key bindings work with the dynamic dispatcher system and how
actions are provided to users.

## Overview

Bluetooth key binding support allows users to map buttons on Bluetooth input devices (remotes,
keyboards, etc.) to KOReader actions. The system dynamically extracts all available actions from
KOReader's dispatcher at runtime, providing users with access to hundreds of actions without manual
maintenance.

## Architecture

The key binding system consists of several components:

### 1. `bluetooth_keybindings.lua`

The main module that:

- Manages button press event handling from Bluetooth devices
- Stores and retrieves key bindings per device (MAC address)
- Triggers the appropriate KOReader events when buttons are pressed
- Provides UI for users to configure bindings

### 2. `lib/bluetooth/available_actions.lua`

Dynamically loads all available actions at runtime by:

- Extracting actions from KOReader's dispatcher using `dispatcher_helper`
- Organizing actions into categories (General, Device, Screen, Reader, etc.)
- Providing fallback static actions if dynamic extraction fails
- Merging essential actions that require specific arguments (e.g., `args = 1` or `args = -1`)

### 3. `lib/bluetooth/dispatcher_helper.lua`

Helper module that extracts dispatcher actions using introspection:

- Uses `debug.getupvalue()` to access dispatcher's internal `settingsList` and
  `dispatcher_menu_order`
- Returns actions organized by category with metadata (event names, titles, arguments, etc.)
- Caches results for performance
- Returns `nil` if extraction fails (triggering static fallback)

## How Actions Are Loaded

### Dynamic Loading (Primary Method)

1. `available_actions.lua` calls `dispatcher_helper.get_dispatcher_actions_ordered()`
2. The helper introspects KOReader's dispatcher module to extract all registered actions
3. Actions are organized into categories based on their category flags
4. Essential actions with custom arguments are merged on top (overriding extracted versions)
5. The final categorized list is returned

### Static Fallback (Backup Method)

If dynamic extraction fails:

1. A minimal static list of core navigation and UI actions is used
2. Essential actions are merged with static fallback actions
3. Actions are organized into the same category structure

### Essential Actions

Certain actions require specific arguments that aren't provided by the dispatcher (e.g., `args = 1`
for next page vs `args = -1` for previous page). These are defined in `_get_essential_actions()` and
always override extracted actions:

- `next_page` / `prev_page` - Page navigation with direction
- `increase_font` / `decrease_font` - Font size adjustment
- `increase_frontlight` / `decrease_frontlight` - Brightness control
- `increase_frontlight_warmth` / `decrease_frontlight_warmth` - Warmth control

## Action Structure

Each action extracted from the dispatcher has the following structure:

- `id`: Unique identifier for the action (from dispatcher)
- `title`: Display name shown to users in the UI (translated)
- `event`: KOReader event name to trigger when the button is pressed
- `args`: Optional arguments to pass to the event
- `args_func`: Optional function to generate arguments dynamically
- `toggle`: Optional toggle state for toggle-type actions
- `category`: String category name (for logging/debugging)
- Category flags: `general`, `device`, `screen`, `filemanager`, `reader`, `rolling`, `paging`

Example action from dispatcher:

```lua
{
    id = "show_menu",
    title = "Show menu",
    event = "ShowMenu",
    description = "Show menu",
    general = true,
    reader = true,
}
```

## Adding New Actions

### Using KOReader's Dispatcher

**Preferred method**: Register your action with KOReader's dispatcher system. The Bluetooth key
binding system will automatically detect and expose it to users.

In your plugin or KOReader module:

```lua
local Dispatcher = require("dispatcher")

Dispatcher:registerAction("my_custom_action", {
    category = "none",
    event = "MyCustomEvent",
    title = _("My Custom Action"),
    general = true,  -- Shows in General category
    reader = true,   -- Shows in Reader category
})
```

The action will automatically appear in the Bluetooth key binding configuration UI once registered.

### Adding Essential Actions

If your action requires specific arguments that the dispatcher doesn't provide (e.g., directional
arguments like `1` vs `-1`), add it to `_get_essential_actions()` in
`src/lib/bluetooth/available_actions.lua`:

```lua
{
    id = "my_directional_action",
    title = _("My Action (Forward)"),
    event = "MyEvent",
    args = 1,  -- Custom argument
    description = _("Description of what this does"),
    reader = true,  -- Category flag
},
```

Essential actions override any dispatcher-provided actions with the same ID and category.

## How Key Bindings Work Internally

1. User presses a button on the Bluetooth device
2. The `InputDeviceHandler` detects the button press via the device's input event interface
3. **CRITICAL**: The handler executes `UIManager.event_hook:execute("InputEvent")` to notify other
   components of user activity
4. The handler looks up the configured action ID for that button (format: `"category:action_id"`)
5. The action is retrieved from the action lookup map (pre-built at module load time)
6. The corresponding KOReader event is triggered with any arguments or argument functions
7. KOReader processes the event normally

### InputEvent Hook for Autosuspend Integration

When a Bluetooth key event is received, the code **must** execute the InputEvent hook:

```lua
UIManager.event_hook:execute("InputEvent")
```

This is essential for KOReader's autosuspend plugin to work correctly with Bluetooth input. The
autosuspend plugin relies on this hook to detect user activity and reset its standby timer. Without
this call, the device would go into standby even while the user is actively using Bluetooth
controls.

The hook is called in `BluetoothKeyBindings:onBluetoothKeyEvent()` immediately when a key press
event is received, before processing the key binding. This ensures timely notification of user
activity to all interested components.

**When implementing new input handlers or modifying key event processing, always ensure this hook is
called to maintain proper autosuspend behavior.**
