---
--- Bluetooth device key binding manager.
--- Handles dynamic registration of Bluetooth device button presses to KOReader actions.
---
--- This module allows users to:
--- - Register custom key bindings from Bluetooth devices
--- - Capture key presses from connected Bluetooth devices
--- - Persist bindings across sessions
--- - Trigger KOReader events based on captured keys

local ButtonDialog = require("ui/widget/buttondialog")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local available_actions = require("src/lib/bluetooth/available_actions")
local logger = require("logger")

---
--- Helper to create a prefixed action ID.
--- Prefixed IDs prevent collisions between actions with the same ID in different categories.
--- Format: "category:action_id" (e.g., "Reader:next_page", "Device:toggle_frontlight")
--- @param category_name string Category name
--- @param action_id string Original action ID
--- @return string Prefixed action ID in format "category:action_id"
local function _make_prefixed_action_id(category_name, action_id)
    return category_name .. ":" .. action_id
end

local BluetoothKeyBindings = InputContainer:extend({
    name = "bluetooth_keybindings",
    key_events = {},
    device_bindings = {}, -- { device_mac -> { key_name -> prefixed_action_id } }
    device_path_to_address = {}, -- { device_path -> device_mac } for lookup during events
    is_capturing = false,
    capture_callback = nil,
    settings = nil,
    save_callback = nil,
    capture_info_message = nil,
    input_device_handler = nil,
    poll_task = nil,
    poll_interval = 0.05, -- 50ms polling interval

    --- Lookup map for efficient action retrieval.
    --- Lazily built on first access and cached.
    --- Keys are in format "category:action_id" (e.g., "Reader:next_page")
    action_lookup_map = nil,
    available_actions = available_actions,
    _is_action_registration_callback_registered = false,
})

---
--- Gets the topmost dismissable widget from the UIManager window stack.
--- Detects dismissable widgets by checking for:
---   1. Explicit dismissable flag
---   2. Tap-close gesture handlers (onTapClose, onTapCloseAllMenus, onTapCloseMenu)
--- Skips toast widgets (temporary notifications that auto-close on any event)
--- and blocklisted widgets (ReaderUI, FileManager).
--- Stops at first non-dismissable, non-toast widget.
--- @return table|nil The topmost dismissable widget, or nil if none found
function BluetoothKeyBindings:_getTopDismissableWidget()
    if not UIManager._window_stack then
        return nil
    end

    local blocklist = {
        ReaderUI = true,
        FileManager = true,
    }

    for i = #UIManager._window_stack, 1, -1 do
        local widget = UIManager._window_stack[i].widget

        if not widget.toast then
            if widget.name and blocklist[widget.name] then
                logger.dbg("BluetoothKeyBindings: Skipping blocklisted widget for dismissal:", widget.name)

                break
            end

            if widget.dismissable then
                logger.dbg("BluetoothKeyBindings: Found dismissable widget", widget.name, "(dismissable flag)")

                return widget
            end

            if widget.onTapClose or widget.onTapCloseAllMenus or widget.onTapCloseMenu then
                logger.dbg("BluetoothKeyBindings: Found dismissable widget", widget.name, "(tap-close handler)")

                return widget
            end

            break
        end
    end

    return nil
end

---
--- Basic initialization (called automatically by Widget:new).
--- Does minimal setup; full initialization happens in setup().
function BluetoothKeyBindings:init()
    self.key_events = {}
    self.device_bindings = {}
    self.device_path_to_address = {}
end

--- Build a flat lookup map of "category:action_id" -> action for O(1) lookups.
--- Action IDs are prefixed with category to prevent collisions.
--- @return table Lookup map where keys are "category:action_id" and values are action definitions
function BluetoothKeyBindings:_buildActionLookupMap()
    local map = {}
    local actions = self.available_actions.get_all_actions()

    for _, category in ipairs(actions) do
        local category_prefix = category.category

        for _, action in ipairs(category.actions) do
            local prefixed_id = category_prefix .. ":" .. action.id

            map[prefixed_id] = action
        end
    end

    return map
end

---
--- Sets up the Bluetooth key bindings manager with callbacks.
--- Loads persisted bindings from settings.
--- @param save_callback function Function to call when settings need to be saved
--- @param input_device_handler table InputDeviceHandler instance for isolated Bluetooth input
function BluetoothKeyBindings:setup(save_callback, input_device_handler)
    self.save_callback = save_callback
    self.input_device_handler = input_device_handler

    if not self._is_action_registration_callback_registered then
        self.available_actions.register_on_action_registered(function(action_id, action, category)
            if not self.action_lookup_map or not category then
                return
            end

            local prefixed_id = category .. ":" .. action_id
            self.action_lookup_map[prefixed_id] = action
            logger.dbg("BluetoothKeyBindings: Added action to lookup map:", prefixed_id)
        end)

        self._is_action_registration_callback_registered = true
    end

    if self.input_device_handler then
        self.input_device_handler:registerKeyEventCallback(function(key_code, key_value, time, device_path)
            self:onBluetoothKeyEvent(key_code, key_value, time, device_path)
        end)

        self.input_device_handler:registerDeviceOpenCallback(function(device_address, device_path)
            self:setDevicePathMapping(device_path, device_address)
        end)

        self.input_device_handler:registerDeviceCloseCallback(function(device_address, device_path)
            self:removeDevicePathMapping(device_path)
        end)
    end

    self:loadBindings()
end

---
--- Starts polling for Bluetooth input events.
--- Should be called when Bluetooth devices are connected.
function BluetoothKeyBindings:startPolling()
    if self.poll_task then
        logger.dbg("BluetoothKeyBindings: Already polling, skipping start")

        return
    end

    if not self.input_device_handler then
        logger.warn("BluetoothKeyBindings: No input_device_handler, cannot start polling")

        return
    end

    logger.info("BluetoothKeyBindings: Starting Bluetooth input polling")

    local function poll()
        local has_readers = self.input_device_handler:hasIsolatedReaders()

        if has_readers then
            self.input_device_handler:pollIsolatedReaders(0)
        end

        self.poll_task = UIManager:scheduleIn(self.poll_interval, poll)
    end

    self.poll_task = UIManager:scheduleIn(self.poll_interval, poll)
    logger.info("BluetoothKeyBindings: Poll task scheduled with interval:", self.poll_interval)
end

---
--- Stops polling for Bluetooth input events.
function BluetoothKeyBindings:stopPolling()
    if self.poll_task then
        UIManager:unschedule(self.poll_task)
        self.poll_task = nil
        logger.dbg("BluetoothKeyBindings: Stopped Bluetooth input polling")
    end
end

---
--- Loads key bindings from persistent storage.
function BluetoothKeyBindings:loadBindings()
    if not self.settings then
        logger.warn("BluetoothKeyBindings: No settings provided, cannot load bindings")
        return
    end

    self.device_bindings = self.settings.bluetooth_key_bindings or {}

    local count = 0
    for _ in pairs(self.device_bindings) do
        count = count + 1
    end

    logger.info("BluetoothKeyBindings: Loaded bindings for", count, "devices")
end

---
--- Saves key bindings to persistent storage.
function BluetoothKeyBindings:saveBindings()
    if not self.settings then
        logger.warn("BluetoothKeyBindings: No settings provided, cannot save bindings")
        return
    end

    self.settings.bluetooth_key_bindings = self.device_bindings

    if self.save_callback then
        self.save_callback()
    end

    logger.dbg("BluetoothKeyBindings: Saved bindings to persistent storage")
end

---
--- Removes a key binding.
--- @param device_mac string MAC address of the Bluetooth device
--- @param key_name string Name of the key to unbind
function BluetoothKeyBindings:removeBinding(device_mac, key_name)
    if not self.device_bindings[device_mac] then
        return
    end

    local action_id = self.device_bindings[device_mac][key_name]

    if not action_id then
        return
    end

    self.device_bindings[device_mac][key_name] = nil

    self:saveBindings()

    logger.dbg("BluetoothKeyBindings: Removed binding", key_name, "for device", device_mac)
end

---
--- Gets an action definition by its prefixed ID.
--- Lazily builds the lookup map on first access.
--- @param prefixed_action_id string Prefixed ID in format "category:action_id"
--- @return table|nil Action definition or nil if not found
function BluetoothKeyBindings:getActionById(prefixed_action_id)
    if not self.action_lookup_map then
        self.action_lookup_map = self:_buildActionLookupMap()
    end

    return self.action_lookup_map[prefixed_action_id]
end

---
--- Gets all bindings for a specific device.
--- @param device_mac string MAC address of the device
--- @return table Device bindings (key_name -> action_id)
function BluetoothKeyBindings:getDeviceBindings(device_mac)
    return self.device_bindings[device_mac] or {}
end

---
--- Sets the mapping from device path to device address.
--- This allows looking up the correct device when receiving input events.
--- @param device_path string Path to the input device (e.g., "/dev/input/event4")
--- @param device_mac string MAC address of the Bluetooth device
function BluetoothKeyBindings:setDevicePathMapping(device_path, device_mac)
    if not device_path or not device_mac then
        return
    end

    self.device_path_to_address[device_path] = device_mac
    logger.dbg("BluetoothKeyBindings: Mapped", device_path, "to", device_mac)
end

---
--- Removes the mapping for a device path.
--- Should be called when a device is disconnected.
--- @param device_path string Path to the input device
function BluetoothKeyBindings:removeDevicePathMapping(device_path)
    if not device_path then
        return
    end

    self.device_path_to_address[device_path] = nil
    logger.dbg("BluetoothKeyBindings: Removed mapping for", device_path)
end

---
--- Removes the mapping for a device by its MAC address.
--- Should be called when a device is disconnected.
--- @param device_mac string MAC address of the Bluetooth device
function BluetoothKeyBindings:removeDevicePathMappingByAddress(device_mac)
    if not device_mac then
        return
    end

    for path, mac in pairs(self.device_path_to_address) do
        if mac == device_mac then
            self.device_path_to_address[path] = nil
            logger.dbg("BluetoothKeyBindings: Removed mapping for", path, "(device:", device_mac, ")")
        end
    end
end

---
--- Gets the device path for a given MAC address.
--- @param device_mac string MAC address of the Bluetooth device
--- @return string|nil Device path or nil if not found
function BluetoothKeyBindings:getDevicePathByAddress(device_mac)
    for path, mac in pairs(self.device_path_to_address) do
        if mac == device_mac then
            return path
        end
    end

    return nil
end

---
--- Starts capturing a key press from the user.
--- @param device_mac string MAC address of the device
--- @param action_id string ID of the action to bind
--- @param callback function Function to call when key is captured
function BluetoothKeyBindings:startKeyCapture(device_mac, action_id, callback)
    self.is_capturing = true
    self.capture_callback = callback
    self.capture_device_mac = device_mac
    self.capture_action_id = action_id

    logger.dbg("BluetoothKeyBindings: Started key capture for device", device_mac, "action", action_id)

    self.capture_info_message = InfoMessage:new({
        text = _("Press a button on your Bluetooth device now...\n\nTap the screen to cancel."),
        dismissable = true,
        dismiss_callback = function()
            if self.is_capturing then
                self:stopKeyCapture()
                UIManager:scheduleIn(0.1, function()
                    UIManager:show(InfoMessage:new({
                        text = _("Key capture cancelled"),
                    }))
                end)
            end
        end,
    })

    UIManager:show(self.capture_info_message)

    self:startPolling()

    logger.info("BluetoothKeyBindings: Waiting for button press from Bluetooth device...")
end

---
--- Handles key events from the isolated Bluetooth reader.
--- This callback receives events ONLY from Bluetooth devices.
--- @param key_code number The key code
--- @param key_value number 1 for press, 0 for release, 2 for repeat
--- @param time table Event timestamp with sec and usec fields
--- @param device_path string Path to the input device (e.g., "/dev/input/event4")
function BluetoothKeyBindings:onBluetoothKeyEvent(key_code, key_value, time, device_path)
    -- Only handle key press events (value == 1)
    if key_value ~= 1 then
        return
    end

    local key_name = "KEY_" .. key_code

    logger.dbg("BluetoothKeyBindings: Bluetooth key event:", key_name, "code:", key_code, "from:", device_path)

    UIManager.event_hook:execute("InputEvent")

    if self.is_capturing then
        logger.info("BluetoothKeyBindings: Captured Bluetooth key:", key_name)
        self:captureKey(key_name)

        return
    end

    if self.settings and self.settings.dismiss_widgets_on_button then
        local widget = self:_getTopDismissableWidget()

        if widget then
            logger.dbg("BluetoothKeyBindings: Dismissing widget", widget.name, "with button press:", key_name)

            UIManager:close(widget)

            if widget.dismiss_callback then
                widget.dismiss_callback()
            end

            return
        end
    end

    local device_mac = self.device_path_to_address[device_path]

    if not device_mac then
        logger.warn("BluetoothKeyBindings: Unknown device path:", device_path, "- no mapping found")

        return
    end

    local bindings = self.device_bindings[device_mac]

    if not bindings then
        logger.dbg("BluetoothKeyBindings: No bindings for device:", device_mac)

        return
    end

    local action_id = bindings[key_name]

    if not action_id then
        logger.dbg("BluetoothKeyBindings: No binding for key:", key_name, "on device:", device_mac)

        return
    end

    local action = self:getActionById(action_id)

    if not action then
        logger.warn("BluetoothKeyBindings: Unknown action:", action_id)

        return
    end

    logger.dbg(
        "BluetoothKeyBindings: Triggering action",
        action_id,
        "for key",
        key_name,
        "from device",
        device_mac,
        "with args:",
        action.args
    )

    if action.args then
        UIManager:sendEvent(Event:new(action.event, action.args))
    else
        UIManager:sendEvent(Event:new(action.event))
    end
end

---
--- Handles captured key press.
--- @param key string The key that was pressed (e.g., "KEY_16")
--- @return boolean True to consume the event
function BluetoothKeyBindings:captureKey(key)
    logger.dbg("BluetoothKeyBindings: Processing captured key:", key)

    local device_mac = self.capture_device_mac
    local action_id = self.capture_action_id
    local callback = self.capture_callback

    self:stopKeyCapture()

    local key_name = key

    if not self.device_bindings[device_mac] then
        self.device_bindings[device_mac] = {}
    end

    self.device_bindings[device_mac][key_name] = action_id

    self:saveBindings()

    local action = self:getActionById(action_id)

    UIManager:show(InfoMessage:new({
        text = _("Button registered: ") .. key .. _(" → ") .. (action and action.title or action_id),
        timeout = 3,
        dismiss_callback = function()
            if callback then
                callback(key_name, action_id)
            end
        end,
    }))
    return true
end

---
--- Stops key capture mode.
function BluetoothKeyBindings:stopKeyCapture()
    self.is_capturing = false
    self.capture_callback = nil
    self.capture_device_mac = nil
    self.capture_action_id = nil

    if self.capture_info_message then
        UIManager:close(self.capture_info_message)
        self.capture_info_message = nil
    end

    logger.dbg("BluetoothKeyBindings: Stopped key capture")
end

---
--- Shows the key binding configuration menu for a device.
--- @param device_info table Device information (must include 'address' field)
function BluetoothKeyBindings:showConfigMenu(device_info)
    if not device_info or not device_info.address then
        logger.warn("BluetoothKeyBindings: Invalid device_info provided")
        return
    end

    if self.config_menu then
        UIManager:close(self.config_menu)
        self.config_menu = nil
    end

    local device_mac = device_info.address
    local device_name = device_info.name ~= "" and device_info.name or device_mac
    local menu_items = self:buildConfigMenuItems(device_info)

    self.config_menu = Menu:new({
        title = _("Key Bindings for: ") .. device_name,
        item_table = menu_items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
    })

    UIManager:show(self.config_menu)
end

---
--- Builds the menu items for the config menu.
--- @param device_info table Device information
--- @return table Menu items with category submenus
function BluetoothKeyBindings:buildConfigMenuItems(device_info)
    local device_mac = device_info.address
    local menu_items = {}
    local actions = self.available_actions.get_all_actions()

    for idx, category in ipairs(actions) do -- luacheck: ignore
        local category_items = {}

        for idy, action in ipairs(category.actions) do -- luacheck: ignore
            local current_bindings = self:getDeviceBindings(device_mac)
            local bound_key = nil
            local prefixed_action_id = _make_prefixed_action_id(category.category, action.id)

            for key_name, action_id in pairs(current_bindings) do
                if action_id == prefixed_action_id then
                    bound_key = key_name

                    break
                end
            end

            local mandatory_text = bound_key and _("Assigned") or _("Not assigned")

            table.insert(category_items, {
                text = action.title,
                mandatory = mandatory_text,
                action_id = prefixed_action_id,
                bound_key = bound_key,
                callback = function()
                    self:showActionMenu(device_info, action, category.category)
                end,
            })

            logger.dbg("BluetoothKeyBindings: Added menu item for action:", prefixed_action_id, "bound_key:", bound_key)
        end

        table.insert(menu_items, {
            text = category.category,
            sub_item_table = category_items,
        })
    end

    return menu_items
end

---
--- Refreshes the config menu with updated bindings.
--- Handles both the main menu and category submenus.
--- @param device_info table Device information
function BluetoothKeyBindings:refreshConfigMenu(device_info)
    if not self.config_menu then
        return
    end

    logger.dbg("BluetoothKeyBindings: Refreshing config menu for device", device_info.address)

    local menu_items = self:buildConfigMenuItems(device_info)

    local current_title = self.config_menu.title
    local device_name = device_info.name ~= "" and device_info.name or device_info.address
    local expected_main_title = _("Key Bindings for: ") .. device_name

    --- @fixme This throws you back to the main menu :(
    if current_title and current_title ~= expected_main_title then
        for _, category_item in ipairs(menu_items) do
            if category_item.text == current_title and category_item.sub_item_table then
                self.config_menu:switchItemTable(current_title, category_item.sub_item_table)

                return
            end
        end
    end

    self.config_menu:switchItemTable(nil, menu_items)
end

---
--- Shows menu for a specific action.
--- @param device_info table Device information
--- @param action table Action definition
--- @param category_name string Category name for prefixing the action ID
function BluetoothKeyBindings:showActionMenu(device_info, action, category_name)
    local device_mac = device_info.address
    local current_bindings = self:getDeviceBindings(device_mac)
    local bound_key = nil
    local prefixed_action_id = _make_prefixed_action_id(category_name, action.id)

    for key_name, action_id in pairs(current_bindings) do
        if action_id == prefixed_action_id then
            bound_key = key_name
            break
        end
    end

    local dialog
    local buttons = {}

    table.insert(buttons, {
        text = bound_key and _("Re-register button") or _("Register button"),
        callback = function()
            UIManager:close(dialog)

            self:startKeyCapture(device_mac, prefixed_action_id, function()
                self:refreshConfigMenu(device_info)
            end)
        end,
    })

    if bound_key then
        table.insert(buttons, {
            text = _("Remove binding"),
            callback = function()
                UIManager:close(dialog)
                self:removeBinding(device_mac, bound_key)

                UIManager:show(InfoMessage:new({
                    text = _("Binding removed"),
                    timeout = 2,
                    dismiss_callback = function()
                        self:refreshConfigMenu(device_info)
                    end,
                }))
            end,
        })
    end

    dialog = ButtonDialog:new({
        title = action.title,
        title_align = "center",
        buttons = { buttons },
    })

    UIManager:show(dialog)
end

---
--- Clears all bindings for a device.
--- @param device_mac string MAC address of the device
function BluetoothKeyBindings:clearDeviceBindings(device_mac)
    if not self.device_bindings[device_mac] then
        return
    end

    self.device_bindings[device_mac] = nil

    self:saveBindings()

    logger.dbg("BluetoothKeyBindings: Cleared all bindings for device", device_mac)
end

return BluetoothKeyBindings
