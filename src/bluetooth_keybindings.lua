---
-- Bluetooth device key binding manager.
-- Handles dynamic registration of Bluetooth device button presses to KOReader actions.
--
-- This module allows users to:
-- - Register custom key bindings from Bluetooth devices
-- - Capture key presses from connected Bluetooth devices
-- - Persist bindings across sessions
-- - Trigger KOReader events based on captured keys

local AvailableActions = require("src/lib/bluetooth/available_actions")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local ffiUtil = require("ffi/util")
local logger = require("logger")

local BluetoothKeyBindings = InputContainer:extend({
    name = "bluetooth_keybindings",
    key_events = {},
    device_bindings = {}, -- { device_mac -> { key_name -> action_name } }
    is_capturing = false,
    capture_callback = nil,
    settings = nil,
    save_callback = nil,
    capture_info_message = nil,
    input_device_handler = nil,
    poll_task = nil,
    poll_interval = 0.05, -- 50ms polling interval
})

---
-- Basic initialization (called automatically by Widget:new).
-- Does minimal setup; full initialization happens in setup().
function BluetoothKeyBindings:init()
    self.key_events = {}
    self.device_bindings = {}
end

---
-- Sets up the Bluetooth key bindings manager with callbacks.
-- Loads persisted bindings from settings.
-- @param save_callback function Function to call when settings need to be saved
-- @param input_device_handler table InputDeviceHandler instance for isolated Bluetooth input
function BluetoothKeyBindings:setup(save_callback, input_device_handler)
    self.save_callback = save_callback
    self.input_device_handler = input_device_handler

    if self.input_device_handler then
        self.input_device_handler:registerKeyEventCallback(function(key_code, key_value, time)
            self:onBluetoothKeyEvent(key_code, key_value, time)
        end)
    end

    self:loadBindings()
end

---
-- Starts polling for Bluetooth input events.
-- Should be called when Bluetooth devices are connected.
function BluetoothKeyBindings:startPolling()
    if self.poll_task then
        logger.dbg("BluetoothKeyBindings: Already polling, skipping start")

        return
    end

    if not self.input_device_handler then
        logger.warn("BluetoothKeyBindings: No input_device_handler, cannot start polling")

        return
    end

    local has_readers = self.input_device_handler:hasIsolatedReaders()
    logger.info("BluetoothKeyBindings: Starting Bluetooth input polling (has_readers:", has_readers, ")")

    local function poll()
        local has_readers = self.input_device_handler:hasIsolatedReaders()

        if has_readers then
            self.input_device_handler:pollIsolatedReaders(0)
        end

        if has_readers then
            self.poll_task = UIManager:scheduleIn(self.poll_interval, poll)
        else
            self.poll_task = nil
            logger.info("BluetoothKeyBindings: Stopped polling (no readers)")
        end
    end

    self.poll_task = UIManager:scheduleIn(self.poll_interval, poll)
    logger.info("BluetoothKeyBindings: Poll task scheduled with interval:", self.poll_interval)
end

---
-- Stops polling for Bluetooth input events.
function BluetoothKeyBindings:stopPolling()
    if self.poll_task then
        UIManager:unschedule(self.poll_task)
        self.poll_task = nil
        logger.dbg("BluetoothKeyBindings: Stopped Bluetooth input polling")
    end
end

---
-- Loads key bindings from persistent storage.
function BluetoothKeyBindings:loadBindings()
    if not self.settings then
        logger.warn("BluetoothKeyBindings: No settings provided, cannot load bindings")
        return
    end

    self.device_bindings = self.settings.bluetooth_key_bindings or {}

    logger.info("BluetoothKeyBindings: Loaded bindings for", #self.device_bindings, "devices")
end

---
-- Saves key bindings to persistent storage.
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
-- Removes a key binding.
-- @param device_mac string MAC address of the Bluetooth device
-- @param key_name string Name of the key to unbind
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
-- Gets an action definition by its ID.
-- @param action_id string ID of the action
-- @return table|nil Action definition or nil if not found
function BluetoothKeyBindings:getActionById(action_id)
    for _, action in ipairs(AvailableActions) do
        if action.id == action_id then
            return action
        end
    end

    return nil
end

---
-- Gets all bindings for a specific device.
-- @param device_mac string MAC address of the device
-- @return table Device bindings (key_name -> action_id)
function BluetoothKeyBindings:getDeviceBindings(device_mac)
    return self.device_bindings[device_mac] or {}
end

---
-- Starts capturing a key press from the user.
-- @param device_mac string MAC address of the device
-- @param action_id string ID of the action to bind
-- @param callback function Function to call when key is captured
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
-- Handles key events from the isolated Bluetooth reader.
-- This callback receives events ONLY from Bluetooth devices.
-- @param key_code number The key code
-- @param key_value number 1 for press, 0 for release, 2 for repeat
-- @param time table Event timestamp with sec and usec fields
function BluetoothKeyBindings:onBluetoothKeyEvent(key_code, key_value, time)
    -- Only handle key press events (value == 1)
    if key_value ~= 1 then
        return
    end

    local key_name = "KEY_" .. key_code

    logger.dbg("BluetoothKeyBindings: Bluetooth key event:", key_name, "code:", key_code)

    if self.is_capturing then
        logger.info("BluetoothKeyBindings: Captured Bluetooth key:", key_name)
        self:captureKey(key_name)

        return
    end

    for device_mac, bindings in pairs(self.device_bindings) do
        if bindings[key_name] then
            local action_id = bindings[key_name]
            local action = self:getActionById(action_id)

            if action then
                logger.dbg(
                    "BluetoothKeyBindings: Triggering action",
                    action_id,
                    "for key",
                    key_name,
                    "from device",
                    device_mac
                )

                if action.args then
                    UIManager:sendEvent(Event:new(action.event, action.args))
                else
                    UIManager:sendEvent(Event:new(action.event))
                end

                return
            end
        end
    end
end

---
-- Handles captured key press.
-- @param key string The key that was pressed (e.g., "KEY_16")
-- @return boolean True to consume the event
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
    }))

    if callback then
        callback(key_name, action_id)
    end

    return true
end

---
-- Stops key capture mode.
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
-- Shows the key binding configuration menu for a device.
-- @param device_info table Device information (must include 'address' field)
function BluetoothKeyBindings:showConfigMenu(device_info)
    if not device_info or not device_info.address then
        logger.warn("BluetoothKeyBindings: Invalid device_info provided")
        return
    end

    local device_mac = device_info.address
    local device_name = device_info.name ~= "" and device_info.name or device_mac
    local menu_items = {}

    table.insert(menu_items, {
        text = _("Configure buttons for:"),
        enabled = false,
    })

    table.insert(menu_items, {
        text = "  " .. device_name,
        enabled = false,
    })

    table.insert(menu_items, {
        text = "─────────────────────",
        enabled = false,
    })

    for idx, action in ipairs(AvailableActions) do -- luacheck: ignore idx
        local current_bindings = self:getDeviceBindings(device_mac)
        local bound_key = nil

        for key_name, action_id in pairs(current_bindings) do
            if action_id == action.id then
                bound_key = key_name
                break
            end
        end

        local mandatory_text = bound_key and _("Assigned") or _("Not assigned")

        table.insert(menu_items, {
            text = action.title,
            mandatory = mandatory_text,
            action_id = action.id,
            bound_key = bound_key,
            callback = function()
                self:showActionMenu(device_info, action)
            end,
        })
    end

    local menu_widget = Menu:new({
        title = _("Bluetooth Key Bindings"),
        item_table = menu_items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
    })

    UIManager:show(menu_widget)
end

---
-- Shows menu for a specific action.
-- @param device_info table Device information
-- @param action table Action definition
function BluetoothKeyBindings:showActionMenu(device_info, action)
    local device_mac = device_info.address
    local current_bindings = self:getDeviceBindings(device_mac)
    local bound_key = nil

    for key_name, action_id in pairs(current_bindings) do
        if action_id == action.id then
            bound_key = key_name
            break
        end
    end

    local menu_items = {}
    local menu_widget

    table.insert(menu_items, {
        text = bound_key and _("Re-register button") or _("Register button"),
        callback = function()
            UIManager:close(menu_widget)

            self:startKeyCapture(device_mac, action.id, function()
                ffiUtil.sleep(0.5)
                self:showConfigMenu(device_info)
            end)
        end,
    })

    if bound_key then
        table.insert(menu_items, {
            text = _("Remove binding"),
            callback = function()
                self:removeBinding(device_mac, bound_key)

                UIManager:show(InfoMessage:new({
                    text = _("Binding removed"),
                    timeout = 2,
                }))

                UIManager:close(menu_widget)
                self:showConfigMenu(device_info)
            end,
        })
    end

    menu_widget = Menu:new({
        title = action.title,
        item_table = menu_items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
    })

    UIManager:show(menu_widget)
end

---
-- Clears all bindings for a device.
-- @param device_mac string MAC address of the device
function BluetoothKeyBindings:clearDeviceBindings(device_mac)
    if not self.device_bindings[device_mac] then
        return
    end

    self.device_bindings[device_mac] = nil

    self:saveBindings()

    logger.dbg("BluetoothKeyBindings: Cleared all bindings for device", device_mac)
end

return BluetoothKeyBindings
