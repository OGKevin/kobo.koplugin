---
applyTo: "src/lib/bluetooth/available_actions.lua"
---

# Bluetooth Available Actions File

## Purpose

The `available_actions.lua` file defines all actions that can be bound to Bluetooth device buttons
in KOReader. It serves as a centralized registry of available keybinding actions.

## Structure

This file exports a single table array containing action definitions. Each action object has:

- `id`: Unique identifier (string)
- `title`: Translated display name (string)
- `event`: KOReader event name to trigger (string)
- `args`: Optional event arguments (any type)
- `description`: User-friendly description (string)

## Important Requirements

### Alphabetical Sorting by Title

**The actions array MUST be kept sorted alphabetically by the `title` field.**

This is critical for:

- Consistent user experience in the UI menu
- Easier maintenance and code reviews
- Predictable ordering when new actions are added

### Adding New Actions

When adding a new action:

1. Define the action object with all required fields
2. Insert it in the correct alphabetical position based on `title`
3. Ensure the `id` is unique and follows snake_case naming
4. Ensure the `event` corresponds to a valid KOReader event
5. Add a clear, concise `description`

### Example

```lua
{
    id = "zoom_in",
    title = _("Zoom In"),
    event = "ZoomIn",
    description = _("Increase zoom level"),
}
```

Insert this between "Show Menu" and other actions starting with letters after "Z".

## Testing

After modifying this file:

1. Run `luacheck src/lib/bluetooth/available_actions.lua` to check for syntax errors
2. Verify the UI menu shows actions in alphabetical order
3. Test that new actions trigger the correct events

## Notes

- All user-facing strings must be wrapped in `_()` for translation support
- The `args` field is optional and can be any type (number, table, string, etc.)
- Actions are loaded by `bluetooth_keybindings.lua` at initialization
