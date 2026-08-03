---
--- BlueZ Bluetooth implementation for devices using standard org.bluez.
--- Extends KoboBluetooth base class and overrides device-specific methods.
--- Chip bring-up differences live in per-device D-Bus adapters.

local DbusAdapter = require("src/lib/bluetooth/dbus_adapter")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local KoboBluetooth = require("src/kobo_bluetooth")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local logger = require("logger")

local BlueZBluetooth = KoboBluetooth:extend({})

---
--- BlueZ-based Kobo devices are supported (Libra 2, Sage).
--- @return boolean True for supported BlueZ Kobo devices
function BlueZBluetooth:isDeviceSupported()
    return Device:isKobo() and (Device.model == "Kobo_io" or Device.model == "Kobo_cadmus")
end

---
--- BlueZ Bluetooth power-on logic.
--- Uses standard BlueZ without WiFi dependency.
--- @param is_resume boolean True if called from resume context, false for manual turn-on (unused)
--- @param on_complete function Optional callback executed after Bluetooth enables
function BlueZBluetooth:turnBluetoothOn(is_resume, on_complete)
    if is_resume == nil then
        is_resume = false -- luacheck: ignore
    end

    if not self:isDeviceSupported() then
        logger.warn("BlueZBluetooth: Device not supported, cannot turn Bluetooth ON")

        UIManager:show(InfoMessage:new({
            text = _("Bluetooth not supported on this device"),
            timeout = 3,
        }))

        return
    end

    if self:isBluetoothEnabled() then
        logger.warn("BlueZBluetooth: turn on Bluetooth was called while already on.")

        return
    end

    logger.info("BlueZBluetooth: Turning Bluetooth ON")

    if not DbusAdapter.turnOn() then
        logger.warn("BlueZBluetooth: Failed to turn ON")

        UIManager:show(InfoMessage:new({
            text = _("Failed to enable Bluetooth. Check device logs."),
            timeout = 3,
        }))

        return
    end

    logger.dbg("BlueZBluetooth: preventing standby")
    UIManager:preventStandby()
    self.bluetooth_standby_prevented = true

    logger.info("BlueZBluetooth: Turned ON, standby prevented")

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
--- BlueZ Bluetooth power-off logic.
--- @param show_popup boolean Whether to show UI popup messages
function BlueZBluetooth:turnBluetoothOff(show_popup)
    if show_popup == nil then
        show_popup = true
    end

    if not self:isDeviceSupported() then
        logger.warn("BlueZBluetooth: Device not supported, cannot turn Bluetooth OFF")

        if show_popup then
            UIManager:show(InfoMessage:new({
                text = _("Bluetooth not supported on this device"),
                timeout = 3,
            }))
        end

        return
    end

    if not self:isBluetoothEnabled() then
        logger.warn("BlueZBluetooth: turn off Bluetooth was called while already off.")

        return
    end

    logger.info("BlueZBluetooth: Turning Bluetooth OFF")

    self:_cleanup(true)

    logger.dbg("BlueZBluetooth: turning off Bluetooth via dbus adapter")

    if not DbusAdapter.turnOff() then
        logger.warn("BlueZBluetooth: Failed to turn OFF, leaving standby prevented")

        if show_popup then
            UIManager:show(InfoMessage:new({
                text = _("Failed to disable Bluetooth. Check device logs."),
                timeout = 3,
            }))
        end

        return
    end

    if self.bluetooth_standby_prevented then
        logger.dbg("BlueZBluetooth: allow standby")
        UIManager:allowStandby()
        self.bluetooth_standby_prevented = false
    end

    logger.info("BlueZBluetooth: Turned OFF, standby allowed")

    if show_popup then
        UIManager:show(InfoMessage:new({
            text = _("Bluetooth disabled"),
            timeout = 2,
        }))
    end

    self:emitBluetoothStateChangedEvent(false)

    logger.dbg("BlueZBluetooth: finished turnBluetoothOff")
end

return BlueZBluetooth
