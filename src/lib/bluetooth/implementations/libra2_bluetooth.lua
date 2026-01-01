---
--- Libra 2-specific Bluetooth implementation.
--- Extends KoboBluetooth base class and overrides device-specific methods.
--- Uses standard BlueZ stack without WiFi dependency (to be determined through testing).

local DbusAdapter = require("src/lib/bluetooth/dbus_adapter")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local KoboBluetooth = require("src/kobo_bluetooth")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local logger = require("logger")

local Libra2Bluetooth = KoboBluetooth:extend({})

---
--- Libra 2 devices are supported.
--- @return boolean True for Kobo Libra 2 devices
function Libra2Bluetooth:isDeviceSupported()
    return Device:isKobo() and Device.model == "Kobo_io"
end

---
--- Libra 2-specific Bluetooth power-on logic.
--- Uses standard BlueZ without WiFi dependency.
--- @param is_resume boolean True if called from resume context, false for manual turn-on (unused for Libra 2)
--- @param on_complete function Optional callback executed after Bluetooth enables
function Libra2Bluetooth:turnBluetoothOn(is_resume, on_complete)
    if is_resume == nil then
        is_resume = false -- luacheck: ignore
    end

    if not self:isDeviceSupported() then
        logger.warn("Libra2Bluetooth: Device not supported, cannot turn Bluetooth ON")

        UIManager:show(InfoMessage:new({
            text = _("Bluetooth not supported on this device"),
            timeout = 3,
        }))

        return
    end

    if self:isBluetoothEnabled() then
        logger.warn("Libra2Bluetooth: turn on Bluetooth was called while already on.")

        return
    end

    logger.info("Libra2Bluetooth: Turning Bluetooth ON")

    if not DbusAdapter.turnOn() then
        logger.warn("Libra2Bluetooth: Failed to turn ON")

        UIManager:show(InfoMessage:new({
            text = _("Failed to enable Bluetooth. Check device logs."),
            timeout = 3,
        }))

        return
    end

    logger.dbg("Libra2Bluetooth: preventing standby")
    UIManager:preventStandby()
    self.bluetooth_standby_prevented = true

    logger.info("Libra2Bluetooth: Turned ON, standby prevented")

    UIManager:show(InfoMessage:new({
        text = _("Bluetooth enabled"),
        timeout = 2,
    }))

    self:emitBluetoothStateChangedEvent(true)
    self:_startBluetoothProcesses()

    if on_complete then
        on_complete()
    end
end

---
--- Libra 2-specific Bluetooth power-off logic.
--- @param show_popup boolean Whether to show UI popup messages
function Libra2Bluetooth:turnBluetoothOff(show_popup)
    if show_popup == nil then
        show_popup = true
    end

    if not self:isDeviceSupported() then
        logger.warn("Libra2Bluetooth: Device not supported, cannot turn Bluetooth OFF")

        if show_popup then
            UIManager:show(InfoMessage:new({
                text = _("Bluetooth not supported on this device"),
                timeout = 3,
            }))
        end

        return
    end

    if not self:isBluetoothEnabled() then
        logger.warn("Libra2Bluetooth: turn off Bluetooth was called while already off.")

        return
    end

    logger.info("Libra2Bluetooth: Turning Bluetooth OFF")

    self:_cleanup(true)

    logger.dbg("Libra2Bluetooth: turning off Bluetooth via dbus adapter")

    if not DbusAdapter.turnOff() then
        logger.warn("Libra2Bluetooth: Failed to turn OFF, leaving standby prevented")

        if show_popup then
            UIManager:show(InfoMessage:new({
                text = _("Failed to disable Bluetooth. Check device logs."),
                timeout = 3,
            }))
        end

        return
    end

    if self.bluetooth_standby_prevented then
        logger.dbg("Libra2Bluetooth: allow standby")
        UIManager:allowStandby()
        self.bluetooth_standby_prevented = false
    end

    logger.info("Libra2Bluetooth: Turned OFF, standby allowed")

    if show_popup then
        UIManager:show(InfoMessage:new({
            text = _("Bluetooth disabled"),
            timeout = 2,
        }))
    end

    self:emitBluetoothStateChangedEvent(false)

    logger.dbg("Libra2Bluetooth: finished turnBluetoothOff")
end

return Libra2Bluetooth
