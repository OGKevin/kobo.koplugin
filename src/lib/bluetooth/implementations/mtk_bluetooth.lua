---
--- MTK-specific Bluetooth implementation.
--- Extends KoboBluetooth base class and overrides device-specific methods.

local DbusAdapter = require("src/lib/bluetooth/dbus_adapter")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local KoboBluetooth = require("src/kobo_bluetooth")
local NetworkMgr = require("ui/network/manager")
local Subprocess = require("src/lib/bluetooth/subprocess")
local UIManager = require("ui/uimanager")
local WmtPower = require("src/lib/bluetooth/wmt_power")
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

--- Polls before enabling Bluetooth: the number of 250 ms checks to wait for
--- Wi-Fi to come up when KOReader is restoring it after a wake-up.
MTKBluetooth.WIFI_RESTORE_MAX_POLLS = 40

--- Polls after enabling Bluetooth: the number of 100 ms checks to wait for the
--- adapter to report Powered. When the subprocess may fall back to the chip
--- power-on handshake (about 2.5 s) and a second On(), the plugin waits longer.
MTKBluetooth.BLUETOOTH_ENABLE_MAX_POLLS = 30
MTKBluetooth.BLUETOOTH_ENABLE_MAX_POLLS_WITH_FALLBACK = 80

---
--- Whether KOReader itself is bringing Wi-Fi up right now, so the plugin must
--- neither power the chip nor turn anything off afterwards.
--- NetworkListener:onResume runs restoreWifiAsync() plus a connectivity check
--- when "auto restore Wi-Fi" is on; a pending connection means someone used
--- NetworkMgr:enableWifi() / turnOnWifi().
--- @param is_resume boolean True when called from the resume path
--- @return boolean
function MTKBluetooth:_isWifiBeingRestored(is_resume)
    if NetworkMgr.pending_connection or NetworkMgr.pending_connectivity_check then
        return true
    end

    return is_resume == true and NetworkMgr.wifi_was_on == true and G_reader_settings:isTrue("auto_restore_wifi")
end

---
--- MTK-specific Bluetooth power-on logic.
--- Bluetooth and Wi-Fi share the MediaTek combo chip, but On() powers it by
--- itself (measured: about 1 s from cold on a Clara BW). The plugin therefore
--- calls On() with no Wi-Fi handling at all. Only if On() fails while Wi-Fi is
--- off and nobody is bringing it up does the same subprocess fall back to the
--- chip power-on handshake (WmtPower.powerOn, no connection) and retry; the
--- Wi-Fi function is then powered off again once the adapter is up, unless
--- something else started using Wi-Fi in the meantime (see _restoreWifiState).
--- Wi-Fi brought up through NetworkMgr is never touched: its owner tears it down.
--- Uses async subprocess + polling pattern to avoid blocking.
--- @param is_resume boolean True if called from resume context, false for manual turn-on
--- @param on_complete function Optional callback executed after Bluetooth enables and WiFi is released
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

    local may_power_chip = false
    local wait_for_wifi = false

    if initial_wifi_was_on then
        logger.dbg("MTKBluetooth: Wi-Fi is on, the chip is powered")
    elseif self:_isWifiBeingRestored(is_resume) then
        logger.dbg("MTKBluetooth: KOReader is bringing Wi-Fi up, waiting for it")
        wait_for_wifi = true
    elseif WmtPower.isAvailable() then
        logger.dbg("MTKBluetooth: Wi-Fi is off, On() powers the chip; handshake kept as fallback")
        may_power_chip = true
    else
        logger.dbg("MTKBluetooth: no WMT Wi-Fi control device, no fallback available")
    end

    -- While this holds, the plugin may power the Wi-Fi function (and will
    -- release it); other plugins wait for BluetoothWifiReleased.
    self.wifi_hold_for_bluetooth = may_power_chip

    if may_power_chip then
        WmtPower.clearPoweredForBluetooth()
        KoboBluetooth.setWifiBorrowed(true)
    end

    logger.dbg("MTKBluetooth: preventing standby")
    UIManager:preventStandby()
    self.bluetooth_standby_prevented = true

    local max_polls = may_power_chip and MTKBluetooth.BLUETOOTH_ENABLE_MAX_POLLS_WITH_FALLBACK
        or MTKBluetooth.BLUETOOTH_ENABLE_MAX_POLLS

    local function enable()
        logger.dbg("MTKBluetooth: spawning subprocess to enable Bluetooth")

        ffiutil.runInSubProcess(function()
            Subprocess.detachFromStorage()

            logger.info("MTKBluetooth: turning on Bluetooth via dbus adapter")

            if DbusAdapter.turnOn() or not may_power_chip then
                return
            end

            logger.warn("MTKBluetooth: On() failed with the chip cold, powering the Wi-Fi function and retrying")
            WmtPower.powerOn()
            DbusAdapter.turnOn()
        end, false, true)

        self:_pollForBluetoothEnabledAndRestoreWifi(0, max_polls, 100, is_resume, initial_wifi_was_on, on_complete)
    end

    if wait_for_wifi then
        UIManager:tickAfterNext(function()
            self:_waitForWifiThen(0, enable)
        end)
    else
        UIManager:tickAfterNext(enable)
    end

    logger.info("MTKBluetooth: Bluetooth enable initiated (async)")

    UIManager:show(InfoMessage:new({
        text = _("Bluetooth enabled"),
        timeout = 2,
    }))

    self:emitBluetoothStateChangedEvent(true)
end

---
--- Waits (polling) until KOReader's Wi-Fi restore has powered the chip, then
--- runs the callback. Gives up waiting after WIFI_RESTORE_MAX_POLLS and runs
--- it anyway: the restore may have failed, and On() can still succeed.
--- @param poll_count number Polls done so far
--- @param callback function Run once Wi-Fi is up or the wait is over
function MTKBluetooth:_waitForWifiThen(poll_count, callback)
    if NetworkMgr:isWifiOn() then
        logger.dbg("MTKBluetooth: Wi-Fi is up after", poll_count, "polls")
        callback()

        return
    end

    if poll_count >= MTKBluetooth.WIFI_RESTORE_MAX_POLLS then
        logger.warn("MTKBluetooth: Wi-Fi did not come up, enabling Bluetooth anyway")
        callback()

        return
    end

    UIManager:scheduleIn(0.25, function()
        self:_waitForWifiThen(poll_count + 1, callback)
    end)
end

---
--- Releases the Wi-Fi function after the enable attempt (success or timeout).
--- Powers it off only when the enable subprocess powered it on (fallback
--- path, marker present) and nobody else has started using Wi-Fi since;
--- otherwise it belongs to whoever brought it up. Wi-Fi started through
--- NetworkMgr is never turned off here, in either the resume or the manual path.
--- @param is_resume boolean Unused; kept for the base-class signature
--- @param initial_wifi_was_on boolean Unused; the instance remembers whether it holds Wi-Fi
function MTKBluetooth:_restoreWifiState(is_resume, initial_wifi_was_on)
    if not self.wifi_hold_for_bluetooth then
        logger.dbg("MTKBluetooth: Wi-Fi was not held by the plugin, leaving it alone")

        return
    end

    self.wifi_hold_for_bluetooth = false

    if WmtPower.wasPoweredForBluetooth() then
        WmtPower.clearPoweredForBluetooth()

        local in_use, reason = WmtPower.isWifiInUse()

        if in_use then
            logger.info("MTKBluetooth: leaving the Wi-Fi function on:", reason)
        else
            WmtPower.powerOff()
        end
    else
        logger.dbg("MTKBluetooth: On() powered the chip itself, nothing to release")
    end

    KoboBluetooth.setWifiBorrowed(false)
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
