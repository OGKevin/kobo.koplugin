---
-- UI menus for Bluetooth device management.
-- Provides scan results, paired devices, and device options menus.

local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local UiMenus = {}

---
-- Filters out unreachable devices (RSSI -127 indicates out of range).
-- @param devices table Array of device information
-- @return table Filtered array excluding unreachable devices
local function _filterReachableDevices(devices)
    local reachable = {}

    for idx, device in ipairs(devices) do -- luacheck: ignore idx
        if not device.rssi or device.rssi > -127 then
            table.insert(reachable, device)
        end
    end

    return reachable
end

---
-- Filters out devices with empty names.
-- @param devices table Array of device information
-- @return table Filtered array excluding devices with empty names
local function _filterNamedDevices(devices)
    local named = {}

    for idx, device in ipairs(devices) do -- luacheck: ignore idx
        if device.name ~= "" then
            table.insert(named, device)
        end
    end

    return named
end

---
-- Shows the scan results in a full-screen menu.
-- Only shows devices that have a name set and are reachable (RSSI != -127).
-- Devices are sorted by signal strength (strongest first).
-- @param devices table Array of device information from scanForDevices
-- @param on_device_select function Callback when device is selected, receives device_info
-- @param on_refresh function Optional callback when refresh button is tapped, receives menu_widget
-- @return table The created menu widget, or nil if no devices to show
function UiMenus.showScanResults(devices, on_device_select, on_refresh)
    local reachable_devices = _filterReachableDevices(devices)
    local named_devices = _filterNamedDevices(reachable_devices)

    if not reachable_devices or #reachable_devices == 0 then
        UIManager:show(InfoMessage:new({
            text = _("No Bluetooth devices found"),
            timeout = 3,
        }))

        return
    end

    if #named_devices == 0 then
        UIManager:show(InfoMessage:new({
            text = _("No named Bluetooth devices found"),
            timeout = 3,
        }))

        return
    end

    local menu_items = {}

    for idx, device in ipairs(named_devices) do -- luacheck: ignore idx
        local status_text

        if device.connected then
            status_text = _("Connected")
        elseif device.paired then
            status_text = _("Paired")
        else
            status_text = _("Not paired")
        end

        table.insert(menu_items, {
            text = device.name,
            mandatory = status_text,
            device_info = device,
        })
    end

    local menu
    menu = Menu:new({
        subtitle = _("Select a device"),
        item_table = menu_items,
        items_per_page = 10,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_left_icon = on_refresh and "cre.render.reload" or nil,

        onMenuChoice = function(menu_self, item) -- luacheck: ignore menu_self
            if on_device_select then
                on_device_select(item.device_info)
            end
        end,

        onMenuHold = function(menu_self, item) -- luacheck: ignore menu_self item
            return true
        end,

        close_callback = function()
            UIManager:close(menu)
        end,
    })

    if on_refresh then
        menu.onLeftButtonTap = function()
            on_refresh(menu)
        end
    end

    UIManager:show(menu)
    return menu
end

---
-- Shows a menu of paired devices.
-- @param paired_devices table Array of paired device information
-- @param on_device_select function Callback when device is selected, receives device_info
-- @param on_device_hold function Optional callback when device is long-pressed, receives device_info
-- @param on_refresh function Optional callback when refresh button is tapped, receives menu_widget
function UiMenus.showPairedDevices(paired_devices, on_device_select, on_device_hold, on_refresh)
    if #paired_devices == 0 then
        UIManager:show(InfoMessage:new({
            text = _("No paired devices found"),
            timeout = 2,
        }))

        return
    end

    local menu_items = {}

    for idx, device in ipairs(paired_devices) do -- luacheck: ignore idx
        local status_text = device.connected and _("Connected") or _("Not connected")

        table.insert(menu_items, {
            text = device.name ~= "" and device.name or device.address,
            mandatory = status_text,
            device_info = device,
        })
    end

    local menu_widget = Menu:new({
        title = _("Paired Devices"),
        item_table = menu_items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_left_icon = on_refresh and "cre.render.reload" or nil,

        onMenuChoice = function(menu, item)
            if item.device_info and on_device_select then
                on_device_select(item.device_info)
            end
        end,

        onMenuHold = function(menu, item)
            if item.device_info and on_device_hold then
                UIManager:close(menu)
                on_device_hold(item.device_info)

                return true
            end

            return true
        end,
    })

    if on_refresh then
        menu_widget.onLeftButtonTap = function()
            on_refresh(menu_widget)
        end
    end
    UIManager:show(menu_widget)
    return menu_widget
end

---
-- Shows device options menu.
-- @param device_info table Device information
-- @param options table Table with menu options:
--   - show_connect: boolean Whether to show connect option
--   - show_disconnect: boolean Whether to show disconnect option
--   - show_configure_keys: boolean Whether to show configure keys option
--   - show_forget: boolean Whether to show forget/unpair option
--   - on_connect: function Callback for connect action
--   - on_disconnect: function Callback for disconnect action
--   - on_configure_keys: function Callback for configure keys action
--   - on_forget: function Callback for forget action
-- @param on_action_complete function Optional callback when connect/disconnect/forget completes
function UiMenus.showDeviceOptionsMenu(device_info, options, on_action_complete)
    local dialog
    local button_rows = {}

    if options.show_disconnect then
        table.insert(button_rows, {
            {
                text = _("Disconnect"),
                callback = function()
                    UIManager:close(dialog)
                    options.on_disconnect()

                    if on_action_complete then
                        on_action_complete()
                    end
                end,
            },
        })
    end

    if options.show_connect then
        table.insert(button_rows, {
            {
                text = _("Connect"),
                callback = function()
                    UIManager:close(dialog)
                    options.on_connect()

                    if on_action_complete then
                        on_action_complete()
                    end
                end,
            },
        })
    end

    if options.show_configure_keys then
        table.insert(button_rows, {
            {
                text = _("Configure key bindings"),
                callback = function()
                    UIManager:close(dialog)
                    options.on_configure_keys()
                end,
            },
        })
    end

    if options.show_forget then
        table.insert(button_rows, {
            {
                text = _("Forget"),
                callback = function()
                    UIManager:close(dialog)
                    options.on_forget()

                    if on_action_complete then
                        on_action_complete()
                    end
                end,
            },
        })
    end

    dialog = ButtonDialog:new({
        title = device_info.name ~= "" and device_info.name or device_info.address,
        title_align = "center",
        buttons = button_rows,
    })

    UIManager:show(dialog)
    return dialog
end

return UiMenus
