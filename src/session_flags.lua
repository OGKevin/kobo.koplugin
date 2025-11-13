-- Session flags stored in /tmp
-- These flags persist across plugin reloads during the same session
-- but are cleared on reboot (since /tmp is cleared on reboot)

local logger = require("logger")
local util = require("frontend/util")

local SessionFlags = {}

local SESSION_ID = tostring(os.time())
local FLAGS_DIR = "/tmp/kobo.koplugin/" .. SESSION_ID

---
-- Ensures the flags directory exists, creating it if necessary.
local function ensureFlagsDir()
    local lfs = require("libs/libkoreader-lfs")
    if not lfs.attributes(FLAGS_DIR, "mode") then
        util.makePath(FLAGS_DIR)
    end
end

---
-- Gets the filesystem path for a flag file.
-- @param flag_name string: Name of the flag.
-- @return string: Full path to the flag file.
local function getFlagPath(flag_name)
    return FLAGS_DIR .. "/" .. flag_name
end

---
-- Writes a flag file to disk.
-- @param flag_path string: Path to write the flag file.
-- @return boolean: True if successful, false otherwise.
local function writeFlagFile(flag_path)
    local f = io.open(flag_path, "w")
    if f then
        f:write("true")
        f:close()
        return true
    end
    return false
end

---
-- Sets a session flag by creating a marker file.
-- Flag persists across plugin reloads but not across device reboots.
-- @param flag_name string: Name of the flag to set.
function SessionFlags:setFlag(flag_name)
    ensureFlagsDir()
    local flag_path = getFlagPath(flag_name)
    if writeFlagFile(flag_path) then
        logger.dbg("KoboPlugin: Set session flag:", flag_name)

        return
    end

    logger.warn("KoboPlugin: Failed to set session flag:", flag_name)
end

---
-- Checks if a session flag is currently set.
-- @param flag_name string: Name of the flag to check.
-- @return boolean: True if flag exists, false otherwise.
function SessionFlags:isFlagSet(flag_name)
    local flag_path = getFlagPath(flag_name)
    local f = io.open(flag_path, "r")
    if f then
        f:close()
        logger.dbg("KoboPlugin: Session flag is set:", flag_name)
        return true
    end
    logger.dbg("KoboPlugin: Session flag not set:", flag_name)
    return false
end

---
-- Clears a session flag by removing its marker file.
-- @param flag_name string: Name of the flag to clear.
function SessionFlags:clearFlag(flag_name)
    local flag_path = getFlagPath(flag_name)
    os.remove(flag_path)
    logger.dbg("KoboPlugin: Cleared session flag:", flag_name)
end

---
-- Clears all session flags for this session.
-- Should be called on KOReader shutdown or when resetting the plugin.
function SessionFlags:clearAllFlags()
    local lfs = require("libs/libkoreader-lfs")
    for file in lfs.dir(FLAGS_DIR) do
        if file ~= "." and file ~= ".." then
            os.remove(getFlagPath(file))
        end
    end
    logger.dbg("KoboPlugin: Cleared all session flags")
end

return SessionFlags
