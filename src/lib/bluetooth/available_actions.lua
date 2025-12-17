---
-- Available Bluetooth key binding actions for KOReader.
--
-- This file dynamically loads all Dispatcher actions at runtime.
-- Falls back to a minimal static list if dynamic extraction is unavailable.

local _ = require("gettext")
local dispatcher_helper = require("src/lib/bluetooth/dispatcher_helper")

---
-- Category definitions for organizing actions.
--
local CATEGORIES = {
    { key = "general", title = _("General") },
    { key = "device", title = _("Device") },
    { key = "screen", title = _("Screen and lights") },
    { key = "filemanager", title = _("File browser") },
    { key = "reader", title = _("Reader") },
    { key = "rolling", title = _("Reflowable documents") },
    { key = "paging", title = _("Fixed layout documents") },
}

---
--- Get all available actions for Bluetooth key bindings.
--- Attempts to dynamically extract from Dispatcher.
--- Falls back to a minimal static list if extraction fails.
---
--- @return table Categorized action definitions with structure:
---         {
---           {category = "General", actions = {...}},
---           {category = "Device", actions = {...}},
---           ...
---         }
---         Each action has fields:
---         - id: unique identifier
---         - title: display name (translated)
---         - event: KOReader event name
---         - args: optional arguments
---         - description: user-friendly description
---         - dispatcher_id: internal action key from Dispatcher (if dynamic)
---

---
--- Essential navigation actions that should always be available,
--- and require arguments that aren't provided by Dispatcher.
---
--- These actions are merged on top of the extracted actions
--- and override them when ID and category match.
--- They are also available if Dispatcher-extraction fails.
local function _get_essential_actions()
    return {
        {
            id = "decrease_frontlight",
            title = _("Decrease frontlight brightness"),
            event = "IncreaseFlIntensity",
            args = -1,
            description = _("Make the frontlight less bright"),
            screen = true,
        },
        {
            id = "decrease_font",
            title = _("Decrease font size"),
            event = "DecreaseFontSize",
            args = 1,
            description = _("Make text smaller"),
            rolling = true,
        },
        {
            id = "decrease_frontlight_warmth",
            title = _("Decrease frontlight warmth"),
            event = "IncreaseFlWarmth",
            args = -1,
            description = _("Make the frontlight less warm"),
            screen = true,
        },
        {
            id = "increase_frontlight",
            title = _("Increase frontlight brightness"),
            event = "IncreaseFlIntensity",
            args = 1,
            description = _("Make the frontlight brighter"),
            screen = true,
        },
        {
            id = "increase_font",
            title = _("Increase Font Size"),
            event = "IncreaseFontSize",
            args = 1,
            description = _("Make text larger"),
            rolling = true,
        },
        {
            id = "increase_frontlight_warmth",
            title = _("Increase frontlight warmth"),
            event = "IncreaseFlWarmth",
            args = 1,
            description = _("Make the frontlight warmer"),
            screen = true,
        },
        {
            id = "next_page",
            title = _("Next Page"),
            event = "GotoViewRel",
            args = 1,
            description = _("Go to next page"),
            reader = true,
        },
        {
            id = "prev_page",
            title = _("Previous Page"),
            event = "GotoViewRel",
            args = -1,
            description = _("Go to previous page"),
            reader = true,
        },
    }
end

---
--- Static fallback actions with category tags.
--- These actions do not require arguments and are only
--- loaded if dynamic extraction from Dispatcher fails.
local function _get_all_static_actions()
    local actions = {
        {
            id = "next_chapter",
            title = _("Next Chapter"),
            event = "GotoNextChapter",
            description = _("Jump to next chapter"),
            reader = true,
        },
        {
            id = "prev_chapter",
            title = _("Previous Chapter"),
            event = "GotoPrevChapter",
            description = _("Jump to previous chapter"),
            reader = true,
        },
        {
            id = "show_menu",
            title = _("Show Menu"),
            event = "ShowMenu",
            description = _("Open reader menu"),
            general = true,
        },
        {
            id = "toggle_bookmark",
            title = _("Toggle Bookmark"),
            event = "ToggleBookmark",
            description = _("Add or remove bookmark"),
            reader = true,
        },
        {
            id = "toggle_frontlight",
            title = _("Toggle Frontlight"),
            event = "ToggleFrontlight",
            description = _("Turn frontlight on/off"),
            device = true,
        },
    }

    for _, action in ipairs(_get_essential_actions()) do
        table.insert(actions, action)
    end

    return actions
end

---
--- Organize actions into categories.
--- @param flat_actions table Array of actions with category flags
--- @return table Array of category groups with actions
local function _organize_by_categories(flat_actions)
    local categorized = {}

    for _, cat_def in ipairs(CATEGORIES) do
        local cat_key = cat_def.key
        local cat_actions = {}

        for _, action in ipairs(flat_actions) do
            if action[cat_key] then
                table.insert(cat_actions, action)
            end
        end

        if #cat_actions > 0 then
            table.sort(cat_actions, function(a, b)
                return (a.title or "") < (b.title or "")
            end)

            table.insert(categorized, {
                category = cat_def.title,
                actions = cat_actions,
            })
        end
    end

    return categorized
end

local function get_all_actions()
    local ordered_actions = dispatcher_helper.get_dispatcher_actions_ordered()

    if ordered_actions then
        local actions_by_id = {}

        for _, item in ipairs(ordered_actions) do
            if type(item) == "table" and item.event then
                local action = {
                    id = item.dispatcher_id or "",
                    title = item.title or "Unknown",
                    event = item.event,
                    description = item.title or "",
                }

                if item.args ~= nil then
                    action.args = item.args
                end

                if item.args_func then
                    action.args_func = item.args_func
                end

                if item.toggle then
                    action.toggle = item.toggle
                end

                if item.category then
                    action.category = item.category
                end

                if item.general then
                    action.general = true
                end
                if item.device then
                    action.device = true
                end
                if item.screen then
                    action.screen = true
                end
                if item.filemanager then
                    action.filemanager = true
                end
                if item.reader then
                    action.reader = true
                end
                if item.rolling then
                    action.rolling = true
                end
                if item.paging then
                    action.paging = true
                end

                actions_by_id[action.id] = action
            end
        end

        if next(actions_by_id) ~= nil then
            for _, essential_action in ipairs(_get_essential_actions()) do
                actions_by_id[essential_action.id] = essential_action
            end

            local merged_actions = {}
            for _, action in pairs(actions_by_id) do
                table.insert(merged_actions, action)
            end

            return _organize_by_categories(merged_actions)
        end
    end

    return _organize_by_categories(_get_all_static_actions())
end

return get_all_actions()
