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

--- Polls before enabling Bluetooth, when KOReader is restoring Wi-Fi after a
--- wake-up: how often to check that Wi-Fi is up, and for how many checks.
MTKBluetooth.WIFI_RESTORE_POLL_SECONDS = 0.25
MTKBluetooth.WIFI_RESTORE_MAX_POLLS = 40

--- Polls after enabling Bluetooth: the number of 100 ms checks to wait for the
--- adapter to report Powered. When the subprocess may fall back to the chip
--- power-on handshake (about 2.5 s) and a second On(), the plugin waits longer.
MTKBluetooth.BLUETOOTH_ENABLE_MAX_POLLS = 30
MTKBluetooth.BLUETOOTH_ENABLE_MAX_POLLS_WITH_FALLBACK = 80

--- Polls after enabling Bluetooth on a boot where the radio driver had to be
--- loaded first: loader, firmware daemon, handshake and On() take about 12 s.
MTKBluetooth.BLUETOOTH_ENABLE_MAX_POLLS_COLD_BOOT = 200

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
--- Plans the Bluetooth enable: which bring-up path applies and whether the
--- legacy Wi-Fi handshake is involved. The BlueZ adapter powers the Bluetooth
--- half of the combo chip itself (via /dev/wmtBluetooth) and needs no Wi-Fi
--- handling; only the radio driver has to be loaded for the control node to
--- exist. The legacy bluedroid backend either rides an already powered chip
--- (Wi-Fi on, or being restored by KOReader) or powers the chip itself and
--- keeps the Wi-Fi handshake as a fallback.
--- @param is_resume boolean True when called from the resume path
--- @param initial_wifi_was_on boolean Whether Wi-Fi was on before the enable
--- @return table Plan with cold_boot, may_power_chip, wait_for_wifi, is_bluez
function MTKBluetooth:_planBluetoothEnable(is_resume, initial_wifi_was_on)
    local plan = {
        cold_boot = false,
        may_power_chip = false,
        wait_for_wifi = false,
        is_bluez = DbusAdapter.getBackend() == "mtk-bluez",
    }

    if plan.is_bluez then
        if not WmtPower.isStackLoaded() then
            logger.info("MTKBluetooth: radio driver not loaded (first use since boot), bringing it up first")
            plan.cold_boot = true
            WmtPower.bringing_up = true
        end

        return plan
    end

    if not WmtPower.isStackLoaded() then
        logger.info("MTKBluetooth: radio driver not loaded (first use since boot), bringing it up first")
        plan.cold_boot = true
        plan.may_power_chip = true
        WmtPower.bringing_up = true
    elseif initial_wifi_was_on then
        logger.dbg("MTKBluetooth: Wi-Fi is on, the chip is powered")
    elseif self:_isWifiBeingRestored(is_resume) then
        logger.dbg("MTKBluetooth: KOReader is bringing Wi-Fi up, waiting for it")
        plan.wait_for_wifi = true
    elseif WmtPower.isAvailable() then
        logger.dbg("MTKBluetooth: Wi-Fi is off, On() powers the chip; handshake kept as fallback")
        plan.may_power_chip = true
    else
        logger.dbg("MTKBluetooth: no WMT Wi-Fi control device, no fallback available")
    end

    return plan
end

---
--- The subprocess body for the enable: loads the radio driver on a cold boot,
--- then asks the adapter to turn Bluetooth on. For the legacy bluedroid
--- backend only, a failed On() with a cold chip retries after powering the
--- Wi-Fi function (the chip handshake); the BlueZ adapter powers the radio
--- itself and reports its own failures, so it never retries.
--- @param plan table Plan from _planBluetoothEnable
function MTKBluetooth:_enableBluetoothInSubprocess(plan)
    ffiutil.runInSubProcess(function()
        Subprocess.detachFromStorage()

        if plan.cold_boot then
            if not WmtPower.loadStack() or not (plan.is_bluez or WmtPower.powerOn()) then
                logger.warn("MTKBluetooth: radio bring-up failed, not starting the Bluetooth daemon")

                return
            end

            WmtPower.markStackReady()
            logger.info("MTKBluetooth: turning on Bluetooth via dbus adapter")
            DbusAdapter.turnOn()

            return
        end

        logger.info("MTKBluetooth: turning on Bluetooth via dbus adapter")

        if DbusAdapter.turnOn() or not plan.may_power_chip then
            return
        end

        logger.warn("MTKBluetooth: On() failed with the chip cold, powering the Wi-Fi function and retrying")
        WmtPower.powerOn()
        DbusAdapter.turnOn()
    end, false, true)
end

---
--- How long to poll for the enable: longer on a cold boot (driver load) and
--- for the legacy path with the Wi-Fi handshake fallback; the BlueZ adapter
--- bring-up is bounded by its own waits.
--- @param plan table Plan from _planBluetoothEnable
--- @return number Maximum number of 100 ms polls
function MTKBluetooth:_bluetoothEnableMaxPolls(plan)
    if plan.cold_boot then
        return MTKBluetooth.BLUETOOTH_ENABLE_MAX_POLLS_COLD_BOOT
    end

    if plan.may_power_chip then
        return MTKBluetooth.BLUETOOTH_ENABLE_MAX_POLLS_WITH_FALLBACK
    end

    return MTKBluetooth.BLUETOOTH_ENABLE_MAX_POLLS
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
---
--- On a boot where nothing has used the radio yet (Wi-Fi and Bluetooth off in
--- Nickel, KOReader launched straight away) the driver is not even loaded. The
--- subprocess then brings it up the way Nickel does (WmtPower.loadStack), runs
--- the handshake, marks the stack ready, and only then calls On(); the Wi-Fi
--- function is released afterwards as above. Nothing talks to the Bluetooth
--- daemon before the mark, not even this process's own Powered polling, and
--- if the bring-up fails the daemon is not started at all: started on a chip
--- without its driver, it crashes the kernel at the next power-on.
--- Uses async subprocess + polling pattern to avoid blocking.
--- While the attempt runs with Wi-Fi off, self.wifi_hold_for_bluetooth and
--- KoboBluetooth.wifi_borrowed are set, so _restoreWifiState knows it has to
--- release the Wi-Fi function and other plugins know to wait. A second call
--- while an attempt is running (the adapter reports "off" until it is up) is
--- ignored: two subprocesses would run two bring-ups and two handshakes at
--- once, which is the race that crashes the kernel.
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

    if self.enable_in_progress then
        logger.warn("MTKBluetooth: Bluetooth enable already in progress, ignoring")

        return
    end

    logger.info("MTKBluetooth: Turning Bluetooth ON (is_resume:", is_resume, ")")

    local initial_wifi_was_on = NetworkMgr:isWifiOn()
    logger.dbg("MTKBluetooth: initial_wifi_was_on:", initial_wifi_was_on)

    local plan = self:_planBluetoothEnable(is_resume, initial_wifi_was_on)

    self.wifi_hold_for_bluetooth = plan.may_power_chip

    if plan.may_power_chip then
        WmtPower.clearPoweredForBluetooth()
        KoboBluetooth.setWifiBorrowed(true)
    end

    self.enable_in_progress = true

    logger.dbg("MTKBluetooth: preventing standby")
    UIManager:preventStandby()
    self.bluetooth_standby_prevented = true

    local function enable()
        logger.dbg("MTKBluetooth: spawning subprocess to enable Bluetooth")
        self:_enableBluetoothInSubprocess(plan)
        self:_pollForBluetoothEnabledAndRestoreWifi(
            0,
            self:_bluetoothEnableMaxPolls(plan),
            100,
            is_resume,
            initial_wifi_was_on,
            on_complete
        )
    end

    if plan.wait_for_wifi then
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

    UIManager:scheduleIn(MTKBluetooth.WIFI_RESTORE_POLL_SECONDS, function()
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
    WmtPower.bringing_up = false
    self.enable_in_progress = false

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

    self.enable_in_progress = false

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
