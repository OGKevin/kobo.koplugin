---
--- Helpers for code that runs inside a forked subprocess.

local ffi = require("ffi")
local logger = require("logger")

require("ffi/posix_h")

pcall(ffi.cdef, "int chdir(const char *path);")
pcall(ffi.cdef, "long sysconf(int name);")

local C = ffi.C

local Subprocess = {}

--- Directory the subprocess moves to: on tmpfs, so it holds nothing on the
--- onboard partition.
Subprocess.WORKING_DIRECTORY = "/tmp"

--- sysconf name for the per-process limit on open files (_SC_OPEN_MAX on Linux).
Subprocess.SC_OPEN_MAX = 4

--- Fallback for the open-file limit when sysconf cannot tell.
Subprocess.DEFAULT_OPEN_MAX = 1024

---
--- Highest file descriptor number a process can have open, plus one.
--- @return number
function Subprocess.openFileLimit()
    local limit = tonumber(C.sysconf(Subprocess.SC_OPEN_MAX))

    if not limit or limit <= 0 then
        return Subprocess.DEFAULT_OPEN_MAX
    end

    return limit
end

---
--- Releases everything the subprocess inherited that pins the onboard storage:
--- the working directory (KOReader runs from /mnt/onboard/.adds/koreader) and
--- the open files (book, settings, databases). A child that keeps those while
--- it waits for D-Bus makes the storage impossible to unmount, so plugging in
--- the USB cable fails with a busy filesystem until the child has exited.
--- This is what KOReader's own Kobo scripts do for the same reason
--- (platform/kobo/koreader.sh relocates itself off the onboard partition for
--- USB mass storage, platform/kobo/enable-wifi.sh closes every inherited fd).
--- stdin/stdout/stderr are kept so the child can still log.
function Subprocess.detachFromStorage()
    if C.chdir(Subprocess.WORKING_DIRECTORY) ~= 0 then
        logger.warn("Subprocess: chdir", Subprocess.WORKING_DIRECTORY, "failed, errno:", ffi.errno())
    end

    for fd = 3, Subprocess.openFileLimit() - 1 do
        C.close(fd)
    end
end

return Subprocess
