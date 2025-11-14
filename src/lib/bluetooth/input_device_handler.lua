---
-- Bluetooth input device handler.
-- Manages opening and closing of Bluetooth input devices for key event handling.

local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local logger = require("logger")

local InputDeviceHandler = {
    bt_input_devices = {},
    input_device_path = "/dev/input/event4",
}

---
-- Creates a new InputDeviceHandler instance.
-- @return table New InputDeviceHandler instance
function InputDeviceHandler:new()
    local instance = {}
    setmetatable(instance, self)
    self.__index = self

    instance.bt_input_devices = {}
    instance.input_device_path = "/dev/input/event4"

    return instance
end

---
-- Detects available Bluetooth input devices by scanning /sys/class/input/
--
-- Scans /sys/class/input/event* and checks each symlink for the "uhid" pattern,
-- which indicates a Bluetooth/USB HID device. Built-in Kobo devices use platform
-- paths that don't contain "uhid", making Bluetooth devices easy to identify.
--
-- Detection strategy:
--   - Bluetooth devices: symlink contains "uhid" (e.g., ../../devices/virtual/misc/uhid/...)
--   - Built-in devices: symlink contains "platform" (e.g., ../../devices/platform/...)
--
-- @return table Array of detected device paths (e.g., {"/dev/input/event4", "/dev/input/event5"})
function InputDeviceHandler:detectBluetoothInputDevices()
    local devices = {}
    local handle = io.popen("ls -1d /sys/class/input/event* 2>/dev/null")

    if not handle then
        logger.warn("InputDeviceHandler: Cannot access /sys/class/input/")

        return devices
    end

    local success, result = pcall(function()
        for event_path in handle:lines() do
            if self:_isBluetoothDevice(event_path) then
                local event_num = event_path:match("event(%d+)$")

                if event_num then
                    local device_path = "/dev/input/event" .. event_num
                    table.insert(devices, device_path)
                    logger.dbg("InputDeviceHandler: Found Bluetooth input device:", device_path)
                end
            end
        end
    end)

    if not success then
        logger.warn("InputDeviceHandler: Error scanning for Bluetooth devices:", result)
    end

    handle:close()

    return devices
end

---
-- Checks if an input device is a Bluetooth (uhid) device
-- @param event_path string Path to /sys/class/input/eventN
-- @return boolean True if device is Bluetooth
function InputDeviceHandler:_isBluetoothDevice(event_path)
    local handle = io.popen("readlink " .. event_path .. " 2>/dev/null")

    if not handle then
        return false
    end

    local target = handle:read("*l")
    handle:close()

    return target and target:match("uhid") ~= nil
end

---
-- Gets the name of an input device from sysfs
-- @param event_path string Path to /dev/input/eventN
-- @return string|nil Device name or nil if not found
function InputDeviceHandler:_getDeviceName(event_path)
    local event_num = event_path:match("event(%d+)$")

    if not event_num then
        return nil
    end

    local name_path = string.format("/sys/class/input/event%s/device/name", event_num)
    local file = io.open(name_path, "r")

    if not file then
        return nil
    end

    local name = file:read("*l")
    file:close()

    return name
end

---
-- Finds the input device path for a Bluetooth device by matching device names
--
-- Scans all Bluetooth input devices and compares their sysfs device names
-- against the provided D-Bus device name. This provides direct correlation
-- between D-Bus Bluetooth devices and kernel input devices.
--
-- Example:
--   D-Bus name: "8BitDo Micro gamepad"
--   Sysfs name: cat /sys/class/input/event4/device/name → "8BitDo Micro gamepad"
--   Match! → Returns "/dev/input/event4"
--
-- @param device_name string Device name from D-Bus
-- @return string|nil Path to matching device or nil if not found
function InputDeviceHandler:findDeviceByName(device_name)
    if not device_name or device_name == "" then
        logger.dbg("InputDeviceHandler: No device name provided for matching")

        return nil
    end

    logger.dbg("InputDeviceHandler: Searching for device with name:", device_name)

    local detected_devices = self:detectBluetoothInputDevices()

    for _, device_path in ipairs(detected_devices) do
        local sysfs_name = self:_getDeviceName(device_path)

        if sysfs_name then
            logger.dbg("InputDeviceHandler: Checking", device_path, "name:", sysfs_name)

            if sysfs_name == device_name then
                logger.info("InputDeviceHandler: Found matching device:", device_path, "for", device_name)

                return device_path
            end
        end
    end

    logger.dbg("InputDeviceHandler: No matching device found for name:", device_name)

    return nil
end

---
-- Auto-detects the appropriate input device path for a Bluetooth device
--
-- Uses intelligent fallback logic:
--   1. Single Bluetooth device detected → Auto-select it
--   2. No devices detected → Fall back to /dev/input/event4
--   3. Multiple devices detected → Fall back to /dev/input/event4 (ambiguous case)
--
-- The fallback to event4 works because on MTK Kobo devices, Bluetooth HID devices
-- typically appear as event4 (event0-3 are used by built-in hardware).
--
-- Falls back to hardcoded /dev/input/event4 if detection fails or multiple devices found
-- @return string Path to input device
function InputDeviceHandler:_autoDetectInputDevice()
    logger.dbg("InputDeviceHandler: Auto-detecting Bluetooth input device")

    local detected_devices = self:detectBluetoothInputDevices()

    if #detected_devices == 0 then
        logger.warn("InputDeviceHandler: No Bluetooth input devices detected, using fallback")

        return self.input_device_path
    end

    if #detected_devices == 1 then
        logger.info("InputDeviceHandler: Auto-detected single Bluetooth device:", detected_devices[1])

        return detected_devices[1]
    end

    logger.warn("InputDeviceHandler: Multiple Bluetooth devices detected (", #detected_devices, "), using fallback")

    return self.input_device_path
end

---
-- Waits for a Bluetooth input device to appear in /sys/class/input/
--
-- After a Bluetooth device connects via D-Bus, there's a brief delay before the
-- kernel creates the corresponding /dev/input/eventN device node. This function
-- polls for the device to appear instead of using a fixed sleep duration.
--
-- Detects NEW devices by tracking the initial device count and waiting for an
-- increase. This handles the case where other Bluetooth devices are already connected.
--
-- Typical scenarios:
--   - Device appears in < 1 second (most cases)
--   - Timeout after 3 seconds (connection issues or non-HID device)
--
-- This replaces fixed sleep delays with event-based waiting, providing faster
-- response times while still handling edge cases.
--
-- @param timeout number Maximum time to wait in seconds (default: 3)
-- @param poll_interval number Time between checks in seconds (default: 0.2)
-- @return string|nil Path to detected device or nil if timeout
function InputDeviceHandler:waitForBluetoothInputDevice(timeout, poll_interval)
    timeout = timeout or 5
    poll_interval = poll_interval or 0.2

    local ffiUtil = require("ffi/util")
    local start_time = os.time()

    -- Get initial device count to detect new devices
    local initial_devices = self:detectBluetoothInputDevices()
    local initial_count = #initial_devices

    logger.dbg(
        "InputDeviceHandler: Waiting for NEW Bluetooth input device (initial count:",
        initial_count,
        "timeout:",
        timeout,
        "s)"
    )

    while os.time() - start_time < timeout do
        logger.dbg("InputDeviceHandler: Polling for Bluetooth input devices...")
        local detected_devices = self:detectBluetoothInputDevices()
        logger.dbg("InputDeviceHandler: Detected", #detected_devices, "Bluetooth input devices")

        -- Check if device count increased
        if #detected_devices > initial_count then
            -- Find the new device (one that wasn't in initial list)
            for _, device_path in ipairs(detected_devices) do
                local is_new = true

                for _, initial_path in ipairs(initial_devices) do
                    if device_path == initial_path then
                        is_new = false

                        break
                    end
                end

                if is_new then
                    logger.info("InputDeviceHandler: New Bluetooth input device appeared:", device_path)

                    return device_path
                end
            end
        end

        ffiUtil.sleep(poll_interval)
    end

    logger.warn("InputDeviceHandler: Timeout waiting for new Bluetooth input device")

    return nil
end

---
-- Opens the Bluetooth input device for reading key events.
--
-- This function integrates the device with KOReader's input system, allowing
-- key events from Bluetooth devices to be processed by the application.
--
-- Device detection strategy (in order of preference):
--   1. Wait for new device: If wait_for_device=true, poll for new devices first
--   2. Name matching: Match D-Bus device name with sysfs device name
--   3. Auto-detection: Single device auto-select, fallback to event4
--
-- The wait-first approach ensures that when connecting a new device, we detect
-- the newly appeared device rather than trying to match against devices that
-- may not have appeared yet in the kernel.
--
-- Name matching provides direct correlation between D-Bus (MAC address) and
-- kernel (/dev/input/eventN) by comparing device names:
--   D-Bus: device.name = "8BitDo Micro gamepad"
--   Sysfs: /sys/class/input/event4/device/name = "8BitDo Micro gamepad"
--
-- @param device_info table Device information with address and name
-- @param show_messages boolean Optional, whether to show UI messages (default: true)
-- @param wait_for_device boolean Optional, whether to wait for device to appear (default: false)
-- @return boolean True if successfully opened, false otherwise
function InputDeviceHandler:openInputDevice(device_info, show_messages, wait_for_device)
    if show_messages == nil then
        show_messages = true
    end

    local detected_path

    -- Strategy 1: Wait for new device if requested
    if wait_for_device then
        logger.dbg("InputDeviceHandler: Waiting for input device to appear...")
        detected_path = self:waitForBluetoothInputDevice()

        if detected_path then
            logger.info("InputDeviceHandler: Device appeared while waiting:", detected_path)
        end
    end

    -- Strategy 2: Try name matching if we don't have a path yet
    if not detected_path and device_info.name then
        detected_path = self:findDeviceByName(device_info.name)

        if detected_path then
            logger.info("InputDeviceHandler: Matched device by name:", detected_path)
        end
    end

    -- Strategy 3: Fall back to auto-detection
    if not detected_path then
        detected_path = self:_autoDetectInputDevice()
    end

    logger.info("InputDeviceHandler: Opening Bluetooth input device:", detected_path, "for", device_info.address)

    local f = io.open(detected_path, "r")

    if not f then
        logger.warn("InputDeviceHandler: Input device", detected_path, "not found")

        if show_messages then
            UIManager:show(InfoMessage:new({
                text = _("Bluetooth input device not found.\nYou may need to reconnect the device."),
                timeout = 3,
            }))
        end

        return false
    end

    f:close()

    local status, err = pcall(function()
        if not Device.input then
            error("Device.input not available")
        end

        Device.input:close(detected_path)
        Device.input:open(detected_path)

        logger.info("InputDeviceHandler: Successfully opened", detected_path)
    end)

    if not status then
        logger.warn("InputDeviceHandler: Failed to open input device:", err)

        if show_messages then
            UIManager:show(InfoMessage:new({
                text = _("Failed to open Bluetooth input device: ") .. tostring(err),
                timeout = 3,
            }))
        end

        return false
    end

    self.bt_input_devices[device_info.address] = detected_path

    if show_messages then
        UIManager:show(InfoMessage:new({
            text = _("Bluetooth input device ready at ") .. detected_path,
            timeout = 2,
        }))
    end

    return true
end

---
-- Closes the Bluetooth input device.
-- @param device_info table Device information with address
function InputDeviceHandler:closeInputDevice(device_info)
    local input_device_path = self.bt_input_devices[device_info.address]

    if not input_device_path then
        logger.dbg("InputDeviceHandler: No opened input device for", device_info.address)

        return
    end

    logger.info("InputDeviceHandler: Closing Bluetooth input device:", input_device_path)

    local status, err = pcall(function()
        if Device.input then
            Device.input:close(input_device_path)
        end
    end)

    if not status then
        logger.warn("InputDeviceHandler: Failed to close input device:", err)
    end

    self.bt_input_devices[device_info.address] = nil

    logger.dbg("InputDeviceHandler: Bluetooth input device closed")
end

---
-- Automatically opens input devices for all connected paired devices.
-- @param paired_devices table Array of paired device information
function InputDeviceHandler:autoOpenConnectedDevices(paired_devices)
    logger.dbg("InputDeviceHandler: Auto-opening connected devices")

    for _, device in ipairs(paired_devices) do
        if device.connected then
            logger.info("InputDeviceHandler: Found connected device on startup:", device.name or device.address)

            local success = self:openInputDevice(device, false, false)

            if success then
                logger.info("InputDeviceHandler: Auto-opened input device for", device.name or device.address)
            end
        end
    end
end

return InputDeviceHandler
