# Bluetooth key bindings and custom actions

This document explains how to configure Bluetooth key bindings and add new actions to the available
actions list.

## Overview

Bluetooth key binding support allows users to map buttons on Bluetooth input devices (remotes,
keyboards, etc.) to KOReader actions. When a button is pressed, KOReader triggers the corresponding
event.

## Available actions

The list of available actions that users can bind to buttons is defined in
`src/lib/bluetooth/available_actions.lua`.

Each action entry has:

- `id`: Unique identifier for the action (used internally)
- `title`: Display name shown to users in the UI (translated with `_()`)
- `event`: KOReader event name to trigger when the button is pressed
- `args`: Optional arguments to pass to the event (e.g., `-1` for previous page, `1` for next page)
- `description`: User-friendly description of what the action does (translated)

Example action entry:

```lua
{
    id = "next_page",
    title = _("Next Page"),
    event = "GotoViewRel",
    args = 1,
    description = _("Go to next page"),
},
```

## Adding a new action

### Prerequisites

- Know the KOReader event name you want to trigger (check `apps/reader/readerui.lua` or other reader
  modules for available events)
- Understand what arguments the event accepts (if any)
- Provide localized strings using `_()` for the title and description

### Steps

1. Open `src/lib/bluetooth/available_actions.lua`
2. Add a new entry to the `AVAILABLE_ACTIONS` table following the structure above
3. **Important**: Insert the entry in alphabetical order by the `title` field to maintain UI
   consistency
4. Use descriptive names and user-friendly descriptions
5. Test the action by configuring a key binding and pressing the button on your device

Example: Adding a bookmark navigation action

```lua
{
    id = "next_bookmark",
    title = _("Next Bookmark"),
    event = "GotoNextBookmark",
    description = _("Jump to next bookmark"),
},
```

## How key bindings work internally

1. User presses a button on the Bluetooth device
2. The `InputDeviceHandler` detects the button press via the device's input event interface
3. The handler looks up the configured action id for that button
4. The corresponding KOReader event is triggered with any arguments
5. KOReader processes the event normally

## Testing custom actions

1. Add your new action to `available_actions.lua`
2. Pair a Bluetooth input device and connect to it
3. Configure a key binding to use your new action
4. Press the button and verify the expected behavior occurs

## Common KOReader events

Here are some common events you might want to bind to:

- `GotoViewRel`: Navigate pages (arg: 1 for next, -1 for previous)
- `GotoNextChapter` / `GotoPrevChapter`: Chapter navigation
- `DecreaseFontSize` / `IncreaseFontSize`: Font size control
- `ShowMenu`: Open reader menu
- `ToggleFrontlight`: Toggle screen light
- `ToggleBookmark`: Add/remove bookmark

For a complete list, refer to the KOReader source code in `apps/reader/modules/` and
`apps/reader/readerui.lua`.

## Important notes

- Keep the `AVAILABLE_ACTIONS` table sorted alphabetically by title for consistent UI ordering
- Always provide translations for titles and descriptions
- Test that the event works correctly in the reader before adding it
- Document complex arguments clearly in the action description
