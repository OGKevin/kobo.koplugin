---
--- MTK-specific Bluetooth implementation.
--- Extends KoboBluetooth base class and overrides device-specific methods.

local DbusAdapter = require("src/lib/bluetooth/dbus_adapter")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local KoboBluetooth = require("src/kobo_bluetooth")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local ffiutil = require("ffi/util")
local logger = require("logger")

local MTKBluetooth = KoboBluetooth:extend({})

---
--- MTK devices are supported.
--- @return boolean True for MTK-based Kobo devices
function MTKBluetooth:isDeviceSupported()
    return Device:isKobo() and Device.isMTK()
end

---
--- MTK-specific Bluetooth power-on logic.
--- Handles WiFi restoration intelligently:
--- - During resume: respects auto_restore_wifi setting
--- - During manual turn-on: restores to original state
--- Uses async subprocess + polling pattern to avoid blocking.
--- @param is_resume boolean True if called from resume context, false for manual turn-on
--- @param on_complete function Optional callback executed after Bluetooth enables and WiFi restores
function MTKBluetooth:turnBluetoothOn(is_resume, on_complete)
    if is_resume == nil then
        is_resume = false
    end

    if not self:isDeviceSupported() then
        logger.warn("MTKBluetooth: Device not supported, cannot turn Bluetooth ON")

        UIManager:show(InfoMessage:new({
            text = _("Bluetooth not supported on this device"),
            timeout = 3,
        }))

        return
    end

    if self:isBluetoothEnabled() then
        logger.warn("MTKBluetooth: turn on Bluetooth was called while already on.")

        return
    end

    logger.info("MTKBluetooth: Turning Bluetooth ON (is_resume:", is_resume, ")")

    local initial_wifi_was_on = NetworkMgr:isWifiOn()
    logger.dbg("MTKBluetooth: initial_wifi_was_on:", initial_wifi_was_on)

    if not initial_wifi_was_on then
        logger.dbg("MTKBluetooth: WiFi is off, turning it on async for Bluetooth")
        NetworkMgr:restoreWifiAsync()
    end

    logger.dbg("MTKBluetooth: spawning subprocess to enable Bluetooth")

    logger.dbg("MTKBluetooth: preventing standby")
    UIManager:preventStandby()
    self.bluetooth_standby_prevented = true

    UIManager:tickAfterNext(function()
        ffiutil.runInSubProcess(function()
            logger.info("MTKBluetooth: turning on Bluetooth via dbus adapter")
            DbusAdapter.turnOn()
        end, false, true)

        self:_pollForBluetoothEnabledAndRestoreWifi(0, 30, 100, is_resume, initial_wifi_was_on, on_complete)
    end)

    logger.info("MTKBluetooth: Bluetooth enable initiated (async)")

    UIManager:show(InfoMessage:new({
        text = _("Bluetooth enabled"),
        timeout = 2,
    }))

    self:emitBluetoothStateChangedEvent(true)
end

---
--- MTK-specific Bluetooth power-off logic.
--- @param show_popup boolean Whether to show UI popup messages
function MTKBluetooth:turnBluetoothOff(show_popup)
    if show_popup == nil then
        show_popup = true
    end

    if not self:isDeviceSupported() then
        logger.warn("MTKBluetooth: Device not supported, cannot turn Bluetooth OFF")

        if show_popup then
            UIManager:show(InfoMessage:new({
                text = _("Bluetooth not supported on this device"),
                timeout = 3,
            }))
        end

        return
    end

    if not self:isBluetoothEnabled() then
        logger.warn("MTKBluetooth: turn off Bluetooth was called while already off.")

        return
    end

    logger.info("MTKBluetooth: Turning Bluetooth OFF")

    self:_cleanup(true)

    logger.dbg("MTKBluetooth: turning off Bluetooth via dbus adapter")

    if not DbusAdapter.turnOff() then
        logger.warn("MTKBluetooth: Failed to turn OFF, leaving standby prevented")

        if show_popup then
            UIManager:show(InfoMessage:new({
                text = _("Failed to disable Bluetooth. Check device logs."),
                timeout = 3,
            }))
        end

        return
    end

    if self.bluetooth_standby_prevented then
        logger.dbg("MTKBluetooth: allow standby")
        UIManager:allowStandby()
        self.bluetooth_standby_prevented = false
    end

    logger.info("MTKBluetooth: Turned OFF, standby allowed")

    if show_popup then
        UIManager:show(InfoMessage:new({
            text = _("Bluetooth disabled"),
            timeout = 2,
        }))
    end

    self:emitBluetoothStateChangedEvent(false)

    logger.dbg("MTKBluetooth: finished turnBluetoothOff")
end

return MTKBluetooth
