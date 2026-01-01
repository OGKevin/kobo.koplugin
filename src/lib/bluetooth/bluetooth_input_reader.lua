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

local BluetoothInputReader = {
    fd = nil,
    device_path = nil,
    is_open = false,
    callbacks = {},
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

            if ev.type == 1 then
                for _, callback in ipairs(self.callbacks) do
                    local ok, err = pcall(callback, ev.code, ev.value, ev.time, self.device_path)

                    if not ok then
                        logger.warn("BluetoothInputReader: Callback error:", err)
                    end
                end
            end
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
