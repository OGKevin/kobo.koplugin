---
-- UI menus for Bluetooth device management.
-- Provides scan results, paired devices, and device options menus.

local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local UiMenus = {}

---
-- Shows the scan results in a full-screen menu.
-- Only shows devices that have a name set.
-- @param devices table Array of device information from scanForDevices
-- @param on_device_select function Callback when device is selected, receives device_info
function UiMenus.showScanResults(devices, on_device_select)
    if not devices or #devices == 0 then
        UIManager:show(InfoMessage:new({
            text = _("No Bluetooth devices found"),
            timeout = 3,
        }))

        return
    end

    local named_devices = {}

    for idx, device in ipairs(devices) do -- luacheck: ignore idx
        if device.name ~= "" then
            table.insert(named_devices, device)
        end
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

    UIManager:show(menu)
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
        title_bar_left_icon = on_refresh and "appbar.refresh" or nil,

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
--   - on_connect: function Callback for connect action
--   - on_disconnect: function Callback for disconnect action
--   - on_configure_keys: function Callback for configure keys action
-- @param on_action_complete function Optional callback when connect/disconnect completes
function UiMenus.showDeviceOptionsMenu(device_info, options, on_action_complete)
    local menu_items = {}

    if options.show_disconnect then
        table.insert(menu_items, {
            text = _("Disconnect"),
            callback = function()
                options.on_disconnect()

                if on_action_complete then
                    on_action_complete()
                end
            end,
        })
    end

    if options.show_connect then
        table.insert(menu_items, {
            text = _("Connect"),
            callback = function()
                options.on_connect()

                if on_action_complete then
                    on_action_complete()
                end
            end,
        })
    end

    if options.show_configure_keys then
        table.insert(menu_items, {
            text = _("Configure key bindings"),
            callback = options.on_configure_keys,
        })
    end

    local menu_widget = Menu:new({
        title = device_info.name ~= "" and device_info.name or device_info.address,
        item_table = menu_items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
    })

    UIManager:show(menu_widget)
    return menu_widget
end

return UiMenus
