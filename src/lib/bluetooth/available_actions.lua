---
-- Available Bluetooth key binding actions for KOReader.
--
-- This file defines all actions that can be bound to Bluetooth device buttons.
-- Each action specifies the KOReader event to trigger and any required arguments.
--
-- IMPORTANT: This list MUST be kept sorted alphabetically by the 'title' field.
-- This ensures a consistent user experience in the UI menu.

local _ = require("gettext")

---
-- Available actions that can be bound to Bluetooth keys.
-- Each action has:
-- - id: Unique identifier for the action
-- - title: Display name shown in UI (translated)
-- - event: KOReader event name to trigger
-- - args: Optional arguments to pass to the event
-- - description: User-friendly description of what the action does
--
-- @return table Array of action definitions, sorted by title
local AVAILABLE_ACTIONS = {
    {
        id = "decrease_font",
        title = _("Decrease Font Size"),
        event = "DecreaseFontSize",
        description = _("Make text smaller"),
    },
    {
        id = "increase_font",
        title = _("Increase Font Size"),
        event = "IncreaseFontSize",
        description = _("Make text larger"),
    },
    {
        id = "next_chapter",
        title = _("Next Chapter"),
        event = "GotoNextChapter",
        description = _("Jump to next chapter"),
    },
    {
        id = "next_page",
        title = _("Next Page"),
        event = "GotoViewRel",
        args = 1,
        description = _("Go to next page"),
    },
    {
        id = "prev_chapter",
        title = _("Previous Chapter"),
        event = "GotoPrevChapter",
        description = _("Jump to previous chapter"),
    },
    {
        id = "prev_page",
        title = _("Previous Page"),
        event = "GotoViewRel",
        args = -1,
        description = _("Go to previous page"),
    },
    {
        id = "show_menu",
        title = _("Show Menu"),
        event = "ShowMenu",
        description = _("Open reader menu"),
    },
    {
        id = "toggle_bookmark",
        title = _("Toggle Bookmark"),
        event = "ToggleBookmark",
        description = _("Add or remove bookmark"),
    },
    {
        id = "toggle_frontlight",
        title = _("Toggle Frontlight"),
        event = "ToggleFrontlight",
        description = _("Turn frontlight on/off"),
    },
}

return AVAILABLE_ACTIONS
