---
--- Kobo firmware version detection and comparison.
---
--- Nickel's firmware version is the third comma-separated field of the first
--- line of /mnt/onboard/.kobo/version (e.g. "4.45.23697"); KOReader's own Kobo
--- device module parses the same file in Kobo:getFirmwareVersion(), so that
--- accessor is preferred when available. Version components are compared
--- numerically, never as strings.
---
--- @module kobo_firmware

local Device = require("device")
local logger = require("logger")

local KoboFirmware = {}

--- Cached firmware version string; false means "probed, nothing found".
local cached_version = nil

---
--- Reads the firmware version string.
--- Reuses KOReader core's own accessor (Kobo:getFirmwareVersion), which parses
--- /mnt/onboard/.kobo/version and stores the version on the device object
--- (firmware_rev); this module only adds numeric parsing and comparison, which
--- core does not provide. The accessor returns nothing itself, so the stored
--- field is read back after calling it.
--- @return string|nil Version such as "4.45.23697", or nil when unknown
function KoboFirmware.getFirmwareVersion()
    if cached_version ~= nil then
        return cached_version == false and nil or cached_version
    end

    if Device.getFirmwareVersion then
        local ok, result = pcall(Device.getFirmwareVersion, Device)

        if ok and type(result) == "string" and result ~= "none" then
            cached_version = result

            return result
        end

        if type(Device.firmware_rev) == "string" and Device.firmware_rev ~= "none" then
            cached_version = Device.firmware_rev

            return cached_version
        end
    end

    logger.dbg("KoboFirmware: no firmware version accessor on the device object")

    cached_version = false

    return nil
end

---
--- Parses the leading numeric components of a version string.
--- @param version_str string Version such as "4.45.23697"
--- @return table|nil {major, minor} numbers, or nil when unparsable
function KoboFirmware.parseVersion(version_str)
    if type(version_str) ~= "string" then
        return nil
    end

    local major, minor = version_str:match("^(%d+)%.(%d+)")

    if not major then
        return nil
    end

    return { major = tonumber(major), minor = tonumber(minor) }
end

---
--- Whether the firmware is at least the given version.
--- @param major number Major version component
--- @param minor number Minor version component
--- @return boolean|nil True/false when the firmware is known, nil when unknown
function KoboFirmware.isAtLeast(major, minor)
    local version = KoboFirmware.parseVersion(KoboFirmware.getFirmwareVersion())

    if not version then
        return nil
    end

    if version.major ~= major then
        return version.major > major
    end

    return version.minor >= minor
end

---
--- Forgets the cached firmware version (tests and re-probes).
function KoboFirmware._resetCache()
    cached_version = nil
end

return KoboFirmware
