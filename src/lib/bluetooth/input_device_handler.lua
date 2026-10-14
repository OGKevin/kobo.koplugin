---
--- Bluetooth input device handler.
--- Manages opening and closing of Bluetooth input devices for key event handling.
---
--- Uses a dedicated BluetoothInputReader that only reads from Bluetooth devices,
--- providing clean separation from other input sources (touchscreen, built-in buttons).
--- This allows key bindings to be processed exclusively for Bluetooth input.

local BluetoothInputReader = require("src/lib/bluetooth/bluetooth_input_reader")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local InputDeviceHandler = {
    input_device_path = "/dev/input/event4",
    -- Isolated readers for Bluetooth-only input (keyed by device address)
    isolated_readers = {},
    -- Callbacks for isolated reader events
    key_event_callbacks = {},
    -- Callbacks for device open/close events
    device_open_callbacks = {},
    device_close_callbacks = {},
    -- HID devices already handed to hid-generic (see _bindUnclaimedHidDevices)
    hid_bind_attempts = {},
}

--- Directory where the kernel lists HID devices as <bus>:<vendor>:<product>.<instance>.
InputDeviceHandler.HID_DEVICES_DIR = "/sys/bus/hid/devices"

--- Bus number of Bluetooth HID devices in the kernel's HID IDs (BUS_BLUETOOTH, 0x0005).
InputDeviceHandler.HID_BUS_BLUETOOTH = "0005"

--- HID groups the kernel reserves for the hid-multitouch driver
--- (HID_GROUP_MULTITOUCH 0x0002 and HID_GROUP_MULTITOUCH_WIN_8 0x0100).
--- Kobo kernels do not ship that driver, so devices in these groups stay driverless.
InputDeviceHandler.HID_GROUPS_MULTITOUCH = { ["0002"] = true, ["0100"] = true }

--- Sysfs file that makes hid-generic claim an additional device ID.
InputDeviceHandler.HID_GENERIC_NEW_ID = "/sys/bus/hid/drivers/hid-generic/new_id"

--- Time the kernel needs to create the input node after hid-generic took a device.
InputDeviceHandler.HID_BIND_SETTLE_SECONDS = 0.3

---
--- Creates a new InputDeviceHandler instance.
--- @return table New InputDeviceHandler instance
function InputDeviceHandler:new()
    local instance = {}
    setmetatable(instance, self)
    self.__index = self

    instance.input_device_path = "/dev/input/event4"
    instance.isolated_readers = {}
    instance.key_event_callbacks = {}
    instance.device_open_callbacks = {}
    instance.device_close_callbacks = {}
    instance.hid_bind_attempts = {}

    return instance
end

---
--- Detects available Bluetooth input devices by scanning /sys/class/input/
---
--- Scans /sys/class/input/event* and checks each symlink for the "uhid" pattern,
--- which indicates a Bluetooth/USB HID device. Built-in Kobo devices use platform
--- paths that don't contain "uhid", making Bluetooth devices easy to identify.
---
--- Detection strategy:
---   - Bluetooth devices: symlink contains "uhid" (e.g., ../../devices/virtual/misc/uhid/...)
---   - Built-in devices: symlink contains "platform" (e.g., ../../devices/platform/...)
---
--- @return table Array of detected device paths (e.g., {"/dev/input/event4", "/dev/input/event5"})
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
--- Checks if an input device is a Bluetooth (uhid) device
--- @param event_path string Path to /sys/class/input/eventN
--- @return boolean True if device is Bluetooth
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
--- Hands a driverless Bluetooth HID device to hid-generic so it gets an input node.
---
--- Remotes that emulate a touch screen carry a digitizer contact ID in their HID
--- descriptor, so the kernel files them under a multitouch HID group and leaves
--- them to hid-multitouch, which Kobo kernels do not ship. The device then sits on
--- the HID bus without a driver and never gets a /dev/input/eventN node. Writing
--- its ID to hid-generic's new_id makes hid-generic claim it (dynamic IDs match
--- any HID group), which creates the node. The ID stays registered until reboot,
--- so reconnects of the same device are bound by the kernel on its own.
---
--- Only a device that meets all of these is touched: on the Bluetooth bus,
--- without a driver, in a multitouch HID group and, when an address is given,
--- carrying that address, i.e. the paired device the plugin was asked to open.
--- Everything else is left to the kernel. After a bind this waits
--- HID_BIND_SETTLE_SECONDS so the node exists when the caller looks for it.
--- @param device_address string|nil Bluetooth address of the device to bind; any matching device when nil
--- @return number Number of devices handed to hid-generic
function InputDeviceHandler:_bindUnclaimedHidDevices(device_address)
    local ok, iterator, state = pcall(lfs.dir, InputDeviceHandler.HID_DEVICES_DIR)

    if not ok then
        return 0
    end

    local bound = 0

    for entry in iterator, state do
        local hid_path = InputDeviceHandler.HID_DEVICES_DIR .. "/" .. entry

        if self:_isBindableHidDevice(entry, hid_path, device_address) and self:_bindToHidGeneric(entry, hid_path) then
            bound = bound + 1
        end
    end

    if bound > 0 then
        ffiutil.sleep(InputDeviceHandler.HID_BIND_SETTLE_SECONDS)
    end

    return bound
end

---
--- Whether a HID device is one _bindUnclaimedHidDevices should hand to hid-generic.
--- @param entry string Directory entry, <bus>:<vendor>:<product>.<instance>
--- @param hid_path string Full sysfs path of the device
--- @param device_address string|nil Required Bluetooth address, or nil for any
--- @return boolean
function InputDeviceHandler:_isBindableHidDevice(entry, hid_path, device_address)
    local bus = entry:match("^(%x%x%x%x):%x%x%x%x:%x%x%x%x%.%x+$")

    if bus ~= InputDeviceHandler.HID_BUS_BLUETOOTH or self.hid_bind_attempts[hid_path] then
        return false
    end

    if lfs.attributes(hid_path .. "/driver", "mode") then
        return false
    end

    local modalias = self:_readSysfsFile(hid_path .. "/modalias") or ""
    local group = modalias:match("^hid:b%x+g(%x%x%x%x)")

    if not InputDeviceHandler.HID_GROUPS_MULTITOUCH[group] then
        return false
    end

    if device_address then
        local uevent = self:_readSysfsFile(hid_path .. "/uevent") or ""
        local uniq = uevent:match("HID_UNIQ=([%x:]+)")

        return self:_isSameBluetoothAddress(uniq, device_address)
    end

    return true
end

---
--- Writes a HID device's ID to hid-generic's new_id and remembers the attempt.
--- @param entry string Directory entry, <bus>:<vendor>:<product>.<instance>
--- @param hid_path string Full sysfs path of the device
--- @return boolean True if the ID was written
function InputDeviceHandler:_bindToHidGeneric(entry, hid_path)
    self.hid_bind_attempts[hid_path] = true

    local bus, vendor, product = entry:match("^(%x%x%x%x):(%x%x%x%x):(%x%x%x%x)")
    local new_id = io.open(InputDeviceHandler.HID_GENERIC_NEW_ID, "w")

    if not new_id then
        logger.warn("InputDeviceHandler: Cannot write hid-generic new_id for", hid_path)

        return false
    end

    local written, err = new_id:write(string.format("%s %s %s", bus, vendor, product))
    new_id:close()

    if not written then
        logger.warn("InputDeviceHandler: hid-generic rejected the ID of", hid_path, ":", err)

        return false
    end

    logger.info("InputDeviceHandler: Bound driverless Bluetooth HID device to hid-generic:", hid_path)

    return true
end

---
--- Reads a whole sysfs file.
--- @param path string File path
--- @return string|nil Content, or nil if the file cannot be opened
function InputDeviceHandler:_readSysfsFile(path)
    local file = io.open(path, "r")

    if not file then
        return nil
    end

    local content = file:read("*a")
    file:close()

    return content
end

---
--- Compares two Bluetooth addresses, ignoring case and byte order: the HID
--- layer on MTK devices reports the address with its bytes reversed.
--- @param a string|nil
--- @param b string|nil
--- @return boolean
function InputDeviceHandler:_isSameBluetoothAddress(a, b)
    if not a or not b then
        return false
    end

    a, b = a:upper(), b:upper()

    if a == b then
        return true
    end

    local reversed = {}

    for byte in a:gmatch("%x%x") do
        table.insert(reversed, 1, byte)
    end

    return table.concat(reversed, ":") == b
end

---
--- Gets the name of an input device from sysfs
--- @param event_path string Path to /dev/input/eventN
--- @return string|nil Device name or nil if not found
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
--- Gets the unique identifier of an input device from sysfs. For Bluetooth HID
--- devices this is the remote's address (on MTK Kobos with the byte order reversed).
--- @param event_path string Path to /dev/input/eventN
--- @return string|nil Identifier, empty when the device has none, nil if unreadable
function InputDeviceHandler:_getDeviceUniq(event_path)
    local event_num = event_path:match("event(%d+)$")

    if not event_num then
        return nil
    end

    local file = io.open(string.format("/sys/class/input/event%s/device/uniq", event_num), "r")

    if not file then
        return nil
    end

    local uniq = file:read("*l")
    file:close()

    return uniq or ""
end

---
--- Compares a sysfs uniq value with a Bluetooth address, accepting reversed byte order.
--- @param uniq string Value of the sysfs uniq attribute
--- @param address string Bluetooth address (e.g. "1D:01:FF:5A:0E:F6")
--- @return boolean True if they denote the same device
local function uniq_matches_address(uniq, address)
    uniq, address = uniq:upper(), address:upper()

    if uniq == address then
        return true
    end

    local bytes = {}

    for byte in uniq:gmatch("%x%x") do
        table.insert(bytes, 1, byte)
    end

    return table.concat(bytes, ":") == address
end

---
--- Checks whether an input node is already opened by an isolated reader.
--- Two devices of the same model share a name, so a node that already belongs
--- to one of them must not be matched again for the other.
--- @param device_path string Path to /dev/input/eventN
--- @return boolean True if a reader is open on that path
function InputDeviceHandler:_isPathInUse(device_path)
    for _, reader_info in pairs(self.isolated_readers) do
        if reader_info.device_path == device_path and reader_info.reader:isOpen() then
            return true
        end
    end

    return false
end

---
--- Finds the input device path for a Bluetooth device by matching device names
---
--- Scans all Bluetooth input devices and compares their sysfs device names
--- against the provided D-Bus device name. This provides direct correlation
--- between D-Bus Bluetooth devices and kernel input devices.
---
--- Example:
---   D-Bus name: "8BitDo Micro gamepad"
---   Sysfs name: cat /sys/class/input/event4/device/name → "8BitDo Micro gamepad"
---   Match! → Returns "/dev/input/event4"
---
--- When the node carries the remote's address (sysfs uniq), that is what is matched,
--- so two devices of the same model are told apart; the name is the fallback.
--- @param device_name string Device name from D-Bus
--- @param device_address string|nil Bluetooth address of the device
--- @return string|nil Path to matching device or nil if not found
function InputDeviceHandler:findDeviceByName(device_name, device_address)
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

            local uniq = device_address and self:_getDeviceUniq(device_path)
            local matches

            if uniq and uniq ~= "" then
                matches = uniq_matches_address(uniq, device_address)
            else
                matches = sysfs_name == device_name
            end

            if matches and not self:_isPathInUse(device_path) then
                logger.info("InputDeviceHandler: Found matching device:", device_path, "for", device_name)

                return device_path
            end
        end
    end

    logger.dbg("InputDeviceHandler: No matching device found for name:", device_name)

    return nil
end

---
--- Auto-detects the appropriate input device path for a Bluetooth device
---
--- Uses intelligent fallback logic:
---   1. Single Bluetooth device detected → Auto-select it
---   2. No devices detected → Fall back to /dev/input/event4
---   3. Multiple devices detected → Fall back to /dev/input/event4 (ambiguous case)
---
--- The fallback to event4 works because on MTK Kobo devices, Bluetooth HID devices
--- typically appear as event4 (event0-3 are used by built-in hardware).
---
--- Falls back to hardcoded /dev/input/event4 if detection fails or multiple devices found
--- @return string Path to input device
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
--- Waits for a Bluetooth input device to appear in /sys/class/input/
---
--- After a Bluetooth device connects via D-Bus, there's a brief delay before the
--- kernel creates the corresponding /dev/input/eventN device node. This function
--- polls for the device to appear instead of using a fixed sleep duration.
---
--- Detects NEW devices by tracking the initial device count and waiting for an
--- increase. This handles the case where other Bluetooth devices are already connected.
---
--- Typical scenarios:
---   - Device appears in < 1 second (most cases)
---   - Timeout after 3 seconds (connection issues or non-HID device)
---
--- This replaces fixed sleep delays with event-based waiting, providing faster
--- response times while still handling edge cases.
---
--- @param timeout number Maximum time to wait in seconds (default: 3)
--- @param poll_interval number Time between checks in seconds (default: 0.2)
--- @param device_address string|nil Bluetooth address of the device being waited for, used for the hid-generic binding and to match input node identifiers
--- @param device_name string|nil Device name to match against input node names
--- @return string|nil Path to detected device or nil if timeout
function InputDeviceHandler:waitForBluetoothInputDevice(timeout, poll_interval, device_address, device_name)
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
        self:_bindUnclaimedHidDevices(device_address)

        -- The node may have appeared just before the initial snapshot, in which
        -- case it never counts as "new"; a name match finds it either way.
        local named_path = device_name and self:findDeviceByName(device_name, device_address)

        if named_path then
            return named_path
        end

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

        -- TODO(OGKevin): use UIManager:nextTick instead of sleep to avoid blocking main thread
        ffiUtil.sleep(poll_interval)
    end

    logger.warn("InputDeviceHandler: Timeout waiting for new Bluetooth input device")

    return nil
end

---
--- Automatically opens input devices for all connected paired devices.
--- @param paired_devices table Array of paired device information
function InputDeviceHandler:autoOpenConnectedDevices(paired_devices)
    logger.dbg("InputDeviceHandler: Auto-opening connected devices")

    for _, device in ipairs(paired_devices) do
        if device.connected then
            logger.info("InputDeviceHandler: Found connected device on startup:", device.name or device.address)

            local success = self:openIsolatedInputDevice(device, false, true)

            if success then
                logger.info("InputDeviceHandler: Auto-opened input device for", device.name or device.address)
            end
        end
    end
end

---
--- Opens a Bluetooth input device using the isolated reader.
--- This bypasses KOReader's main input system, providing events only from Bluetooth devices.
---
--- Device detection strategy (in order of preference):
---   1. Name matching: Match D-Bus device name with sysfs device name (if device_info.name provided)
---   2. Wait for new device: If wait_for_device=true and no match found, poll for new devices
---   3. Auto-detection: Single device auto-select, fallback to event4
---
--- Name matching is tried first to avoid waiting if the device already exists.
--- This is particularly useful when auto-opening devices on startup or when
--- the device was already connected before the connection event.
---
--- Name matching provides direct correlation between D-Bus (MAC address) and
--- kernel (/dev/input/eventN) by comparing device names:
---   D-Bus: device.name = "8BitDo Micro gamepad"
---   Sysfs: /sys/class/input/event4/device/name = "8BitDo Micro gamepad"
---
--- @param device_info table Device information with address and name
--- @param show_messages boolean Optional, whether to show UI messages (default: true)
--- @param wait_for_device boolean Optional, whether to wait for device to appear (default: false)
--- @return boolean True if successfully opened, false otherwise
function InputDeviceHandler:openIsolatedInputDevice(device_info, show_messages, wait_for_device)
    if show_messages == nil then
        show_messages = true
    end

    local detected_path

    self:_bindUnclaimedHidDevices(device_info.address)

    if device_info.name then
        detected_path = self:findDeviceByName(device_info.name, device_info.address)

        if detected_path then
            logger.info("InputDeviceHandler: Matched device by name:", detected_path)
        end
    end

    if not detected_path and wait_for_device then
        local info_msg = InfoMessage:new({
            text = _("Waiting 5 seconds for Bluetooth input device to appear..."),
            timeout = 0,
        })

        if show_messages then
            UIManager:show(info_msg)
        end

        logger.dbg("InputDeviceHandler: Waiting for input device to appear...")
        detected_path = self:waitForBluetoothInputDevice(nil, nil, device_info.address, device_info.name)

        if show_messages then
            UIManager:close(info_msg)
        end

        if detected_path then
            logger.info("InputDeviceHandler: Device appeared while waiting:", detected_path)
        end
    end

    if not detected_path then
        detected_path = self:_autoDetectInputDevice()
    end

    logger.info(
        "InputDeviceHandler: Opening isolated Bluetooth input device:",
        detected_path,
        "for",
        device_info.address
    )

    local reader = BluetoothInputReader:new()
    local success = reader:open(detected_path)

    if not success then
        logger.warn("InputDeviceHandler: Failed to open isolated reader for", detected_path)

        if show_messages then
            UIManager:show(InfoMessage:new({
                text = _("Bluetooth input device not found.\nYou may need to reconnect the device."),
                timeout = 3,
            }))
        end

        return false
    end

    for _, callback in ipairs(self.key_event_callbacks) do
        reader:registerKeyCallback(callback)
    end

    self.isolated_readers[device_info.address] = {
        reader = reader,
        device_path = detected_path,
    }

    for _, callback in ipairs(self.device_open_callbacks) do
        local ok, err = pcall(callback, device_info.address, detected_path)

        if not ok then
            logger.warn("InputDeviceHandler: Device open callback error:", err)
        end
    end

    if show_messages then
        local label = device_info.name or device_info.address or detected_path

        UIManager:show(InfoMessage:new({
            text = _("%s ready"):format(label),
            timeout = 2,
        }))
    end

    return true
end

---
--- Closes an isolated Bluetooth input device.
--- @param device_info table Device information with address
function InputDeviceHandler:closeIsolatedInputDevice(device_info)
    local reader_info = self.isolated_readers[device_info.address]

    if not reader_info then
        logger.dbg("InputDeviceHandler: No isolated reader for", device_info.address)

        return
    end

    local device_path = reader_info.device_path

    logger.info("InputDeviceHandler: Closing isolated reader for", device_info.address)

    reader_info.reader:close()
    self.isolated_readers[device_info.address] = nil

    for _, callback in ipairs(self.device_close_callbacks) do
        local ok, err = pcall(callback, device_info.address, device_path)

        if not ok then
            logger.warn("InputDeviceHandler: Device close callback error:", err)
        end
    end
end

---
--- Closes all isolated Bluetooth input devices.
--- Iterates through all open isolated readers and closes them.
--- Safe to call even if no devices are open.
function InputDeviceHandler:closeAllIsolatedInputDevices()
    logger.dbg("InputDeviceHandler: Closing all isolated input devices")

    local count = 0

    for device_address, reader_info in pairs(self.isolated_readers) do
        local device_path = reader_info.device_path

        logger.info("InputDeviceHandler: Closing isolated reader for", device_address)

        reader_info.reader:close()

        for _, callback in ipairs(self.device_close_callbacks) do
            local ok, err = pcall(callback, device_address, device_path)

            if not ok then
                logger.warn("InputDeviceHandler: Device close callback error:", err)
            end
        end

        count = count + 1
    end

    self.isolated_readers = {}

    logger.dbg("InputDeviceHandler: Closed", count, "isolated input devices")
end

---
--- Registers a callback for key events from isolated readers.
--- This callback will receive events ONLY from Bluetooth devices.
---
--- @param callback function Callback function(key_code, key_value, time, device_path) where:
---   - key_code: The key code (ev.code)
---   - key_value: 1 for press, 0 for release, 2 for repeat
---   - time: Event timestamp table with sec and usec fields
---   - device_path: Path to the input device (e.g., "/dev/input/event4")
function InputDeviceHandler:registerKeyEventCallback(callback)
    table.insert(self.key_event_callbacks, callback)

    for _, reader_info in pairs(self.isolated_readers) do
        reader_info.reader:registerKeyCallback(callback)
    end

    logger.dbg("InputDeviceHandler: Registered key event callback")
end

---
--- Registers a callback for device open events.
--- Called when an isolated input device is successfully opened.
---
--- @param callback function Callback function(device_address, device_path) where:
---   - device_address: MAC address of the Bluetooth device
---   - device_path: Path to the input device (e.g., "/dev/input/event4")
function InputDeviceHandler:registerDeviceOpenCallback(callback)
    table.insert(self.device_open_callbacks, callback)
    logger.dbg("InputDeviceHandler: Registered device open callback")
end

---
--- Registers a callback for device close events.
--- Called when an isolated input device is closed.
---
--- @param callback function Callback function(device_address, device_path) where:
---   - device_address: MAC address of the Bluetooth device
---   - device_path: Path to the input device that was closed
function InputDeviceHandler:registerDeviceCloseCallback(callback)
    table.insert(self.device_close_callbacks, callback)
    logger.dbg("InputDeviceHandler: Registered device close callback")
end

---
--- Clears all registered key event callbacks.
function InputDeviceHandler:clearKeyEventCallbacks()
    self.key_event_callbacks = {}

    for _, reader_info in pairs(self.isolated_readers) do
        reader_info.reader:clearCallbacks()
    end

    logger.dbg("InputDeviceHandler: Cleared all key event callbacks")
end

---
--- Polls all isolated readers for input events.
--- Should be called periodically (e.g., via UIManager scheduling).
--- Automatically cleans up readers that have been closed due to device disconnect.
---
--- @param timeout_ms number Optional timeout in milliseconds (default: 0 for non-blocking)
--- @return table|nil Array of all events from all Bluetooth devices, or nil if none
function InputDeviceHandler:pollIsolatedReaders(timeout_ms)
    local all_events = {}
    local disconnected_addresses = {}

    for address, reader_info in pairs(self.isolated_readers) do
        local events = reader_info.reader:poll(timeout_ms)

        if events then
            for _, ev in ipairs(events) do
                local new_ev = {}

                for k, v in pairs(ev) do
                    new_ev[k] = v
                end

                new_ev.device_address = address
                table.insert(all_events, new_ev)
            end
        end

        if not reader_info.reader:isOpen() then
            table.insert(disconnected_addresses, {
                address = address,
                device_path = reader_info.device_path,
            })
        end
    end

    for _, disconnected in ipairs(disconnected_addresses) do
        logger.info("InputDeviceHandler: Cleaning up disconnected reader for", disconnected.address)
        self.isolated_readers[disconnected.address] = nil

        for _, callback in ipairs(self.device_close_callbacks) do
            local ok, err = pcall(callback, disconnected.address, disconnected.device_path)

            if not ok then
                logger.warn("InputDeviceHandler: Device close callback error:", err)
            end
        end
    end

    if #all_events > 0 then
        return all_events
    end

    return nil
end

---
--- Gets the isolated reader for a specific device
--- @param device_address string MAC address of the device
--- @return table|nil The BluetoothInputReader instance or nil if not open
function InputDeviceHandler:getIsolatedReader(device_address)
    local reader_info = self.isolated_readers[device_address]

    if reader_info then
        return reader_info.reader
    end

    return nil
end

---
--- Checks if any isolated readers are open.
--- @return boolean True if at least one isolated reader is open
function InputDeviceHandler:hasIsolatedReaders()
    for _, reader_info in pairs(self.isolated_readers) do
        if reader_info.reader:isOpen() then
            return true
        end
    end

    return false
end

return InputDeviceHandler
