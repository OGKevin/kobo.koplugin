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
local Device = require("device")
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
    input_device_handle = nil,
    settings = nil,
    save_callback = nil,
})

---
-- Initializes the Bluetooth key bindings manager.
-- Loads persisted bindings from settings.
-- @param save_callback function Function to call when settings need to be saved
-- @param parent_container table Optional parent InputContainer to notify of key_events changes
function BluetoothKeyBindings:init(save_callback, parent_container)
    self.key_events = {}
    self.device_bindings = {}
    self.save_callback = save_callback
    self.parent_container = parent_container
    self.input_device = Device.input

    self:loadBindings()
end

---
-- Loads key bindings from persistent storage.
function BluetoothKeyBindings:loadBindings()
    if not self.settings then
        logger.warn("BluetoothKeyBindings: No settings provided, cannot load bindings")
        return
    end

    self.device_bindings = self.settings.bluetooth_key_bindings or {}

    for device_mac, bindings in pairs(self.device_bindings) do
        for key_name, action_id in pairs(bindings) do
            self:applyBinding(device_mac, key_name, action_id)
        end
    end

    local count = 0

    for _ in pairs(self.device_bindings) do
        count = count + 1
    end

    logger.info("BluetoothKeyBindings: Loaded bindings for", count, "devices")
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
-- Applies a key binding to the InputContainer key_events table.
-- @param device_mac string MAC address of the Bluetooth device
-- @param key_name string Name of the key (e.g., "BTPageNext")
-- @param action_id string ID of the action to bind
function BluetoothKeyBindings:applyBinding(device_mac, key_name, action_id)
    local action = self:getActionById(action_id)

    if not action then
        logger.warn("BluetoothKeyBindings: Unknown action ID:", action_id)
        return
    end

    local event_name = "BT_" .. device_mac:gsub(":", "") .. "_" .. key_name

    self.key_events[event_name] = {
        { key_name },
        event = event_name,
    }

    local handler_name = "on" .. event_name

    self[handler_name] = function()
        logger.dbg("BluetoothKeyBindings: Triggering", action.event, "with args:", action.args, "for", event_name)

        if action.args then
            UIManager:sendEvent(Event:new(action.event, action.args))
        end

        if not action.args then
            UIManager:sendEvent(Event:new(action.event))
        end

        return true
    end

    if self.parent_container and self.parent_container.mergeKeyEvents then
        self.parent_container:mergeKeyEvents()
    end

    logger.dbg("BluetoothKeyBindings: Applied binding", key_name, "->", action_id, "for device", device_mac)
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

    local event_name = "BT_" .. device_mac:gsub(":", "") .. "_" .. key_name
    self.key_events[event_name] = nil

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
-- Starts capturing a key press from the user by intercepting input events.
-- @param device_mac string MAC address of the device
-- @param action_id string ID of the action to bind
-- @param callback function Function to call when key is captured
function BluetoothKeyBindings:startKeyCapture(device_mac, action_id, callback)
    self.is_capturing = true
    self.capture_callback = callback
    self.capture_device_mac = device_mac
    self.capture_action_id = action_id

    logger.dbg("BluetoothKeyBindings: Registering event adjust hook for key capture")

    self.input_device:registerEventAdjustHook(function(input, ev)
        self:onRawInputEvent(ev)
    end)

    UIManager:show(InfoMessage:new({
        text = _("Press a button on your Bluetooth device now...\n\nPress the back button to cancel."),
        timeout = 10,
    }))

    logger.dbg("BluetoothKeyBindings: Started key capture for device", device_mac, "action", action_id)
    logger.info("BluetoothKeyBindings: Waiting for button press from Bluetooth device...")
end

---
-- Handles raw input events from the eventAdjustHook during key capture.
-- This is called directly from the Input device before event processing.
-- @param ev table Raw input_event structure from the device
function BluetoothKeyBindings:onRawInputEvent(ev)
    if not self.is_capturing then
        return
    end

    local C = Device.input.C or {
        EV_KEY = 0x01,
    }

    if ev.type ~= C.EV_KEY or ev.value ~= 1 then
        return
    end

    local key_code = ev.code
    local key_name = nil

    if Device.input.event_map and Device.input.event_map[key_code] then
        key_name = Device.input.event_map[key_code]
    end

    if not key_name then
        key_name = ev.code_name or ("KEY_" .. key_code)
    end

    logger.info("BluetoothKeyBindings: Raw key event captured:", key_name, "code:", key_code)

    self:captureKey(key_name)
end

---
-- Handles input events during key capture.
-- Note: This is called from the event hook chain but event hooks don't pass event data.
-- Actual key capture is done via onRawInputEvent using the eventAdjustHook.
-- @param input_event table Input event structure (will be nil from event hooks)
-- @return boolean Always false to pass events through
function BluetoothKeyBindings:onInputEvent(input_event)
    return false
end

---
-- Handles captured key press.
-- @param key string The key that was pressed (e.g., "BTRight", "BTGotoNextChapter")
-- @return boolean True to consume the event
function BluetoothKeyBindings:captureKey(key)
    logger.dbg("BluetoothKeyBindings: Processing captured key:", key)

    local device_mac = self.capture_device_mac
    local action_id = self.capture_action_id
    local callback = self.capture_callback

    if key == "Back" or key == "Home" or key == "Menu" then
        self:stopKeyCapture()

        UIManager:show(InfoMessage:new({
            text = _("Key capture cancelled"),
            timeout = 2,
        }))

        return true
    end

    self:stopKeyCapture()

    local key_name = key

    if not self.device_bindings[device_mac] then
        self.device_bindings[device_mac] = {}
    end

    self.device_bindings[device_mac][key_name] = action_id

    self:applyBinding(device_mac, key_name, action_id)
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

    for key_name in pairs(self.device_bindings[device_mac]) do
        local event_name = "BT_" .. device_mac:gsub(":", "") .. "_" .. key_name
        self.key_events[event_name] = nil
    end

    self.device_bindings[device_mac] = nil

    self:saveBindings()

    logger.dbg("BluetoothKeyBindings: Cleared all bindings for device", device_mac)
end

return BluetoothKeyBindings
