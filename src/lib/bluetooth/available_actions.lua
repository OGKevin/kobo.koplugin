---
--- Available Bluetooth key binding actions for KOReader.
---
--- This file dynamically loads all Dispatcher actions at runtime.
--- Falls back to a minimal static list if dynamic extraction is unavailable.
---
--- The module patches Dispatcher.registerAction to capture actions registered
--- after initial load, ensuring the action list stays synchronized with all
--- plugins that register Dispatcher actions.

local _ = require("gettext")
local dispatcher_helper = require("src/lib/bluetooth/dispatcher_helper")
local logger = require("logger")

local M = {}

---
--- Category definitions for organizing actions.
---
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
--- Internal state for live action list and dispatcher patching.
---
local _live_actions_list = nil
local _is_dispatcher_patched = false
local _original_registerAction = nil
local _action_registered_callbacks = {}

---
--- Trigger all registered callbacks when a new action is added to live list.
--- @param action_id string The dispatcher action ID
--- @param action table The fully-formed action from live_actions_list
--- @param category string The category title
local function _trigger_action_registered_callbacks(action_id, action, category)
    for _, callback in ipairs(_action_registered_callbacks) do
        logger.dbg("available_actions: Triggering action registered callback for action:", action_id)

        local ok, err = pcall(callback, action_id, action, category)
        if not ok then
            logger.warn("available_actions: Callback error:", err)
        end
    end
end

---
--- Build an action object from a definition.
--- Consolidates common action construction logic used by both
--- initial list building and live list updates.
--- @param def table The action definition
--- @param action_id_field string|nil Field name for action ID (defaults to "dispatcher_id")
--- @param action_id string|nil Override action ID (used if provided)
--- @return table|nil Action object or nil if invalid
local function _build_action_from_def(def, action_id_field, action_id)
    if not def or not def.event then
        return nil
    end

    local id = action_id or def[action_id_field or "dispatcher_id"] or ""

    local action = {
        id = id,
        title = def.title or "Unknown",
        event = def.event,
        description = def.title or "",
    }

    if def.args ~= nil then
        action.args = def.args
    end

    if def.arg ~= nil then
        if def.args ~= nil then
            logger.warn(
                "available_actions: Both 'args' and 'arg' defined for action:",
                action.id,
                "- 'arg' takes priority"
            )
        end

        action.args = def.arg
    end

    if def.args_func then
        action.args_func = def.args_func
    end

    if def.toggle then
        action.toggle = def.toggle
    end

    if def.category then
        action.category = def.category
    end

    return action
end

---
--- Set category flags on an action from a definition.
--- Copies all category boolean flags from definition to action.
--- @param action table The action to update
--- @param def table The definition with category flags
local function _set_action_category_flags(action, def)
    action.general = def.general or false
    action.device = def.device or false
    action.screen = def.screen or false
    action.filemanager = def.filemanager or false
    action.reader = def.reader or false
    action.rolling = def.rolling or false
    action.paging = def.paging or false
end

---
--- Add a newly registered action to the live actions list.
--- This is called by the patched Dispatcher.registerAction.
--- @param action_id string The action ID
--- @param def table The action definition from registerAction
local function _add_new_action_to_live_list(action_id, def)
    if not _live_actions_list then
        return
    end

    local action = _build_action_from_def(def, nil, action_id)

    if not action then
        logger.dbg("available_actions: Skipping action without event:", action_id)

        return
    end

    _set_action_category_flags(action, def)

    local categories_by_title = {}
    for _, category_data in ipairs(_live_actions_list) do
        categories_by_title[category_data.category] = category_data
    end

    local added_to_categories = {}

    for _, cat_def in ipairs(CATEGORIES) do
        if action[cat_def.key] then
            local category_data = categories_by_title[cat_def.title]

            if not category_data then
                category_data = {
                    category = cat_def.title,
                    actions = {},
                }
                table.insert(_live_actions_list, category_data)
                categories_by_title[cat_def.title] = category_data
                logger.dbg("available_actions: Created new category:", cat_def.title)
            end

            local action_exists = false
            for i, existing_action in ipairs(category_data.actions) do
                if existing_action.id == action_id then
                    category_data.actions[i] = action
                    action_exists = true
                    logger.dbg("available_actions: Updated existing action:", action_id, "in", category_data.category)
                    break
                end
            end

            if not action_exists then
                table.insert(category_data.actions, action)
            end

            table.sort(category_data.actions, function(a, b)
                return (a.title or "") < (b.title or "")
            end)

            _trigger_action_registered_callbacks(action_id, action, cat_def.title)

            table.insert(added_to_categories, cat_def.title)
        end
    end

    if #added_to_categories > 0 then
        logger.dbg(
            "available_actions: Added action:",
            action_id,
            "to categories:",
            table.concat(added_to_categories, ", ")
        )
    else
        logger.dbg("available_actions: Action", action_id, "not added to any category")
    end
end

---
--- Patch Dispatcher.registerAction to capture future action registrations.
--- This is called once on first get_all_actions() call.
local function _patch_dispatcher()
    if _is_dispatcher_patched then
        return
    end

    local ok, Dispatcher = pcall(require, "dispatcher")

    if not ok or not Dispatcher then
        logger.dbg("available_actions: Cannot patch Dispatcher - module not available")

        return
    end

    if type(Dispatcher.registerAction) ~= "function" then
        logger.dbg("available_actions: Cannot patch Dispatcher - registerAction is not a function")

        return
    end

    _original_registerAction = Dispatcher.registerAction

    Dispatcher.registerAction = function(self, action_id, action_def)
        logger.dbg("available_actions: Intercepted Dispatcher.registerAction for action:", action_id)

        local result = _original_registerAction(self, action_id, action_def)

        _add_new_action_to_live_list(action_id, action_def)

        return result
    end

    _is_dispatcher_patched = true
    logger.info("available_actions: Successfully patched Dispatcher.registerAction")
end

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
            title = _("Increase font size"),
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
--- Initialize category structure.
--- @return table Hash table of categories by key
local function _initialize_categories()
    local by_category = {}

    for _, cat_def in ipairs(CATEGORIES) do
        by_category[cat_def.key] = {
            category = cat_def.title,
            actions = {},
        }
    end

    return by_category
end

---
--- Add action to all relevant categories based on flags.
--- @param action table Action with category flags (general, device, screen, etc.)
--- @param categories_hash table Hash table of categories
local function _add_action_to_categories(action, categories_hash)
    if action.general then
        table.insert(categories_hash.general.actions, action)
    end

    if action.device then
        table.insert(categories_hash.device.actions, action)
    end

    if action.screen then
        table.insert(categories_hash.screen.actions, action)
    end

    if action.filemanager then
        table.insert(categories_hash.filemanager.actions, action)
    end

    if action.reader then
        table.insert(categories_hash.reader.actions, action)
    end

    if action.rolling then
        table.insert(categories_hash.rolling.actions, action)
    end

    if action.paging then
        table.insert(categories_hash.paging.actions, action)
    end
end

---
--- Convert category hash to sorted array format.
--- @param categories_hash table Hash table of categories
--- @return table Array of category groups with sorted actions
local function _finalize_categories(categories_hash)
    local result = {}

    for _, cat_def in ipairs(CATEGORIES) do
        local cat_data = categories_hash[cat_def.key]

        if #cat_data.actions > 0 then
            table.sort(cat_data.actions, function(a, b)
                return (a.title or "") < (b.title or "")
            end)

            table.insert(result, cat_data)
        end
    end

    return result
end

---
--- Organize static fallback actions into categories.
--- @return table Array of category groups with sorted actions
local function _organize_static_actions()
    local categories = _initialize_categories()

    for _, action in ipairs(_get_all_static_actions()) do
        _add_action_to_categories(action, categories)
    end

    return _finalize_categories(categories)
end

---
--- Build the initial actions list from Dispatcher.
--- @return table Array of category groups with sorted actions
local function _build_initial_actions_list()
    local ordered_actions = dispatcher_helper.get_dispatcher_actions_ordered()

    if not ordered_actions then
        return _organize_static_actions()
    end

    local categories = _initialize_categories()
    local actions_by_id = {}

    for _, item in ipairs(ordered_actions) do
        if type(item) == "table" and item.event then
            local action = _build_action_from_def(item, "dispatcher_id")

            if action then
                _set_action_category_flags(action, item)
                actions_by_id[action.id] = action
            end
        end
    end

    if next(actions_by_id) == nil then
        return _organize_static_actions()
    end

    for _, essential_action in ipairs(_get_essential_actions()) do
        actions_by_id[essential_action.id] = essential_action
    end

    for _, action in pairs(actions_by_id) do
        _add_action_to_categories(action, categories)
    end

    return _finalize_categories(categories)
end

---
--- Get all available actions for Bluetooth key bindings.
--- Attempts to dynamically extract from Dispatcher.
--- Falls back to a minimal static list if extraction fails.
---
--- On first call, this function:
--- 1. Extracts currently registered Dispatcher actions
--- 2. Patches Dispatcher.registerAction to capture future registrations
--- 3. Returns the categorized action list
---
--- Subsequent calls return the cached (and potentially updated) list.
---
--- WARNING: Do not modify the returned value. The table is cached and shared
---          across all callers. Modifications will affect all consumers of this
---          data and may cause unexpected behavior.
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
function M.get_all_actions()
    if not _live_actions_list then
        logger.dbg("available_actions: Building initial actions list")
        _live_actions_list = _build_initial_actions_list()
        _patch_dispatcher()
    end

    return _live_actions_list
end

---
--- Gets the category title for an action definition.
--- Returns the first matching category based on flags.
--- @param def table Action definition with category flags
--- @return string|nil Category title or nil if no category matches
function M.get_category_from_def(def)
    for _, cat_def in ipairs(CATEGORIES) do
        if def[cat_def.key] == true then
            return cat_def.title
        end
    end

    return nil
end

---
--- Register a callback to be called when a new action is registered.
--- Callback signature: function(action_id, action, category)
--- @param callback function Function to call when action is registered
function M.register_on_action_registered(callback)
    if type(callback) == "function" then
        table.insert(_action_registered_callbacks, callback)
        logger.dbg("available_actions: Registered callback for action registration")
    end
end

return M
