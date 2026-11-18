---
--- Probes the system bus for Kobo's legacy MediaTek Bluetooth daemon.
---
--- The probe runs before any adapter is chosen: it asks the bus itself
--- (org.freedesktop.DBus.NameHasOwner and ListActivatableNames) whether the
--- com.kobo.mtk.bluedroid service is running or could be started, without
--- activating it. Queries to the bus object itself never start a service.
---
--- @module bluedroid_probe

local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local BluedroidProbe = {}

--- Name of Kobo's legacy MediaTek Bluetooth daemon on the system bus.
BluedroidProbe.SERVICE_NAME = "com.kobo.mtk.bluedroid"

--- Seconds the shell is allowed to spend on each bus query (busbox timeout).
BluedroidProbe.PROBE_TIMEOUT_SECONDS = 2

--- Probe results.
BluedroidProbe.OWNED = "owned"
BluedroidProbe.ACTIVATABLE = "activatable"
BluedroidProbe.ABSENT = "absent"
BluedroidProbe.UNKNOWN = "unknown"

--- Bus query for one well-known name; answers "boolean true" / "boolean false".
local NAME_HAS_OWNER = "dbus-send --system --print-reply --dest=org.freedesktop.DBus "
    .. "/org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner string:"

--- Bus query listing every name the bus could activate on demand.
local LIST_ACTIVATABLE = "dbus-send --system --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus "
    .. "org.freedesktop.DBus.ListActivatableNames"

---
--- Whether the shell has the timeout command, so the probe cannot hang forever
--- on a wedged bus. Detected through the filesystem, not the shell: running
--- "command -v" through os.execute would leak a shell call into every command
--- log. Checked once per query, not cached: tests replace the mocks.
--- @return boolean
local function hasTimeout()
    for _, path in ipairs({ "/bin/timeout", "/usr/bin/timeout", "/sbin/timeout", "/usr/sbin/timeout" }) do
        if lfs.attributes(path, "mode") ~= nil then
            return true
        end
    end

    return false
end

---
--- Runs one D-Bus query and returns its output.
--- The query is always wrapped in the timeout command: without it a wedged
--- dbus-daemon could hang the read forever. Without the timeout binary on the
--- device the probe cannot be bounded, so nothing is run and the caller
--- treats the result as failed - the legacy adapter is the safe default.
--- @param command string Full shell command to run
--- @return string|nil Output, or nil when nothing could be read
local function runQuery(command)
    if not hasTimeout() then
        logger.warn("BluedroidProbe: no timeout command, not probing the bus")

        return nil
    end

    local handle = io.popen(string.format("timeout %d %s", BluedroidProbe.PROBE_TIMEOUT_SECONDS, command))

    if not handle then
        return nil
    end

    local output = handle:read("*a")
    handle:close()

    return output
end

---
--- Whether the bus has the service running right now.
--- @return boolean|nil True/false, or nil when the probe failed
local function probeOwned()
    local output = runQuery(NAME_HAS_OWNER .. BluedroidProbe.SERVICE_NAME)

    if not output then
        return nil
    end

    if output:find("boolean true", 1, true) then
        return true
    end

    if output:find("boolean false", 1, true) then
        return false
    end

    return nil
end

---
--- Whether the bus could start the service on demand (exact name match).
--- @return boolean|nil True/false, or nil when the probe failed
local function probeActivatable()
    local output = runQuery(LIST_ACTIVATABLE)

    if not output then
        return nil
    end

    for name in output:gmatch('string%s+"([^"]+)"') do
        if name == BluedroidProbe.SERVICE_NAME then
            return true
        end
    end

    return false
end

---
--- Probes the system bus for the legacy service without starting it.
--- @return string One of BluedroidProbe.OWNED, ACTIVATABLE, ABSENT or UNKNOWN
function BluedroidProbe.probeService()
    local owned = probeOwned()

    if owned == nil then
        logger.warn("BluedroidProbe: could not query", BluedroidProbe.SERVICE_NAME, "owner on the system bus")

        return BluedroidProbe.UNKNOWN
    end

    if owned then
        return BluedroidProbe.OWNED
    end

    local activatable = probeActivatable()

    if activatable == nil then
        logger.warn("BluedroidProbe: could not query activatable names on the system bus")

        return BluedroidProbe.UNKNOWN
    end

    if activatable then
        return BluedroidProbe.ACTIVATABLE
    end

    return BluedroidProbe.ABSENT
end

return BluedroidProbe
