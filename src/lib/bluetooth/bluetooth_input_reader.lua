---
--- Dedicated Bluetooth input reader.
--- Provides isolated input event reading from Bluetooth devices only,
--- bypassing KOReader's main input system to avoid mixing with other input sources.
---
--- This module uses FFI to directly read from the Bluetooth device's file descriptor,
--- allowing clean separation of Bluetooth input events from touchscreen, buttons, etc.

local bit = require("bit")
local ffi = require("ffi")
local logger = require("logger")

require("ffi/posix_h")
require("ffi/linux_input_h")

local C = ffi.C

local EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
local SYN_REPORT = 0
local ABS_X, ABS_Y = 0, 1
local ABS_MT_POSITION_X, ABS_MT_POSITION_Y = 53, 54
local BTN_TOUCH = 330
local BTN_DIGI_MIN, BTN_DIGI_MAX = 320, 335

local function new_touch_state()
    return { active = false, started = false, in_frame = false, x = 0, y = 0, max_coord = 0 }
end

local BluetoothInputReader = {
    fd = nil,
    device_path = nil,
    is_open = false,
    callbacks = {},
    touch = new_touch_state(),

    -- Synthetic key codes for touch gestures, above the kernel's KEY_MAX (767)
    GESTURE_TAP = 1000,
    GESTURE_SWIPE_UP = 1001,
    GESTURE_SWIPE_DOWN = 1002,
    GESTURE_SWIPE_LEFT = 1003,
    GESTURE_SWIPE_RIGHT = 1004,
}

---
--- Creates a new BluetoothInputReader instance.
--- @return table New BluetoothInputReader instance
function BluetoothInputReader:new()
    local instance = {
        fd = nil,
        device_path = nil,
        is_open = false,
        callbacks = {},
        touch = new_touch_state(),
    }
    setmetatable(instance, self)
    self.__index = self

    return instance
end

---
--- Opens a Bluetooth input device for reading.
--- @param device_path string Path to the input device (e.g., "/dev/input/event4")
--- @return boolean True if successfully opened, false otherwise
function BluetoothInputReader:open(device_path)
    if self.is_open then
        logger.warn("BluetoothInputReader: Already open, closing first")
        self:close()
    end

    local fd = C.open(device_path, bit.bor(C.O_RDONLY, C.O_NONBLOCK, C.O_CLOEXEC))

    if fd < 0 then
        logger.warn("BluetoothInputReader: Failed to open", device_path, "errno:", ffi.errno())

        return false
    end

    self.fd = fd
    self.device_path = device_path
    self.is_open = true

    logger.info("BluetoothInputReader: Opened", device_path, "fd:", fd)

    return true
end

---
--- Closes the Bluetooth input device.
function BluetoothInputReader:close()
    if not self.is_open or not self.fd then
        return
    end

    C.close(self.fd)

    logger.info("BluetoothInputReader: Closed", self.device_path)

    self.fd = nil
    self.device_path = nil
    self.is_open = false
end

---
--- Registers a callback for key events.
--- @param callback function Callback function(key_code, key_value, time, device_path) where:
---   - key_code: The key code (ev.code)
---   - key_value: 1 for press, 0 for release, 2 for repeat
---   - time: Event timestamp table with sec and usec fields
---   - device_path: Path to the input device (e.g., "/dev/input/event4")
function BluetoothInputReader:registerKeyCallback(callback)
    table.insert(self.callbacks, callback)
end

---
--- Clears all registered callbacks.
function BluetoothInputReader:clearCallbacks()
    self.callbacks = {}
end

---
--- Delivers a key event to all registered callbacks.
--- @param code number Key code
--- @param value number 1 for press, 0 for release, 2 for repeat
--- @param time table Event timestamp
function BluetoothInputReader:_emitKey(code, value, time)
    for _, callback in ipairs(self.callbacks) do
        local ok, err = pcall(callback, code, value, time, self.device_path)

        if not ok then
            logger.warn("BluetoothInputReader: Callback error:", err)
        end
    end
end

---
--- Classifies a finished touch contact as a tap or a swipe direction.
--- Movement below 10% of the largest coordinate seen so far counts as a tap.
--- @return number One of the BluetoothInputReader.GESTURE_* key codes
function BluetoothInputReader:_classifyTouch()
    local touch = self.touch
    local dx = (touch.last_x or touch.start_x or 0) - (touch.start_x or 0)
    local dy = (touch.last_y or touch.start_y or 0) - (touch.start_y or 0)
    local threshold = math.max(10, touch.max_coord * 0.1)

    if math.abs(dx) < threshold and math.abs(dy) < threshold then
        return BluetoothInputReader.GESTURE_TAP
    end

    if math.abs(dy) >= math.abs(dx) then
        return dy > 0 and BluetoothInputReader.GESTURE_SWIPE_DOWN or BluetoothInputReader.GESTURE_SWIPE_UP
    end

    return dx > 0 and BluetoothInputReader.GESTURE_SWIPE_RIGHT or BluetoothInputReader.GESTURE_SWIPE_LEFT
end

---
--- Processes one input event.
---
--- Plain key events are passed to the callbacks unchanged. Devices that present
--- themselves as a touch screen ("TikTok ring" style remotes) send every button
--- as a simulated finger gesture instead: BTN_TOUCH down, a few ABS_X/ABS_Y
--- positions, BTN_TOUCH up. Those are folded into a single synthetic key press
--- (GESTURE_TAP / GESTURE_SWIPE_*) when the contact ends, so each button can be
--- bound like a normal key. The raw touch buttons of such frames are swallowed.
--- @param ev table Event with type, code, value and time
function BluetoothInputReader:_processEvent(ev)
    local touch = self.touch

    if ev.type == EV_ABS then
        if ev.code == ABS_X or ev.code == ABS_MT_POSITION_X then
            touch.x = ev.value
        elseif ev.code == ABS_Y or ev.code == ABS_MT_POSITION_Y then
            touch.y = ev.value
        else
            return
        end

        touch.max_coord = math.max(touch.max_coord, ev.value)

        return
    end

    if ev.type == EV_SYN then
        if ev.code == SYN_REPORT then
            if touch.active and not touch.started then
                touch.start_x, touch.start_y = touch.x, touch.y
                touch.started = true
            elseif touch.active then
                touch.last_x, touch.last_y = touch.x, touch.y
            end

            touch.in_frame = false
        end

        return
    end

    if ev.type ~= EV_KEY then
        return
    end

    if ev.code == BTN_TOUCH then
        touch.in_frame = true

        if ev.value == 1 then
            touch.active = true
            touch.started = false
            touch.start_x, touch.start_y, touch.last_x, touch.last_y = nil, nil, nil, nil
        elseif ev.value == 0 and touch.active then
            touch.active = false

            local gesture = self:_classifyTouch()

            logger.dbg("BluetoothInputReader: touch gesture", gesture, "from", self.device_path)
            self:_emitKey(gesture, 1, ev.time)
            self:_emitKey(gesture, 0, ev.time)
        end

        return
    end

    -- Tool/contact buttons that accompany a touch contact are not real buttons
    if touch.in_frame or (ev.code >= BTN_DIGI_MIN and ev.code <= BTN_DIGI_MAX) then
        return
    end

    self:_emitKey(ev.code, ev.value, ev.time)
end

---
--- Polls for input events from the Bluetooth device.
--- This is non-blocking and should be called periodically.
--- @param timeout_ms number Optional timeout in milliseconds (default: 0 for non-blocking)
--- @return table|nil Array of events or nil if no events available
function BluetoothInputReader:poll(timeout_ms)
    if not self.is_open or not self.fd then
        return nil
    end

    timeout_ms = timeout_ms or 0

    local pollfd = ffi.new("struct pollfd[1]")
    pollfd[0].fd = self.fd
    pollfd[0].events = C.POLLIN
    pollfd[0].revents = 0

    local result = C.poll(pollfd, 1, timeout_ms)

    if result <= 0 then
        return nil
    end

    local has_pollerr = bit.band(pollfd[0].revents, C.POLLERR) ~= 0
    local has_pollhup = bit.band(pollfd[0].revents, C.POLLHUP) ~= 0

    if has_pollerr or has_pollhup then
        logger.warn(
            "BluetoothInputReader: Poll error or hangup detected - POLLERR:",
            has_pollerr,
            "POLLHUP:",
            has_pollhup,
            "fd:",
            self.fd,
            "device:",
            self.device_path
        )
        self:close()

        return nil
    end

    if bit.band(pollfd[0].revents, C.POLLIN) == 0 then
        return nil
    end

    local events = {}
    local input_event = ffi.new("struct input_event")
    local event_size = ffi.sizeof("struct input_event")

    while true do
        if not self.fd then
            logger.warn("BluetoothInputReader: fd became nil during read loop")

            return nil
        end

        local bytes_read = C.read(self.fd, input_event, event_size)

        if bytes_read < 0 then
            local err = ffi.errno()

            if err == C.EAGAIN then
                -- No more data available (EWOULDBLOCK is same as EAGAIN on Linux)
                break
            elseif err == C.ENODEV then
                logger.warn("BluetoothInputReader: ENODEV - Device removed, fd:", self.fd, "device:", self.device_path)
                self:close()

                break
            elseif err == C.EINTR then -- luacheck: ignore
                logger.dbg("BluetoothInputReader: EINTR - interrupted, retrying")
                -- Interrupted, retry
            else
                logger.warn("BluetoothInputReader: Read error, errno:", err, "fd:", self.fd)

                break
            end
        elseif bytes_read == 0 then
            break
        elseif bytes_read == event_size then
            local ev = {
                type = tonumber(input_event.type),
                code = tonumber(input_event.code),
                value = tonumber(input_event.value),
                time = {
                    sec = tonumber(input_event.time.tv_sec),
                    usec = tonumber(input_event.time.tv_usec),
                },
                source = "bluetooth",
                device_path = self.device_path,
            }
            table.insert(events, ev)

            logger.dbg(
                string.format(
                    "BluetoothInputReader: processing event type=%d code=%d value=%d",
                    ev.type,
                    ev.code,
                    ev.value
                )
            )

            self:_processEvent(ev)
        end
    end

    if #events > 0 then
        return events
    end

    return nil
end

---
--- Checks if the reader is currently open.
--- @return boolean True if open, false otherwise
function BluetoothInputReader:isOpen()
    return self.is_open
end

---
--- Gets the current device path.
--- @return string|nil Device path or nil if not open
function BluetoothInputReader:getDevicePath()
    return self.device_path
end

---
--- Gets the file descriptor.
--- @return number|nil File descriptor or nil if not open
function BluetoothInputReader:getFd()
    return self.fd
end

return BluetoothInputReader
